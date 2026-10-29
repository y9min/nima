import Foundation
import Observation
import UIKit

@Observable
final class TimeWindowStore {
    var windows: [TimeWindow] = []
    var pauseAll = false
    var pauseExpiresAt: Date?
    var homeFocusRequestID: UUID?
    private(set) var activeWindowIDs: Set<String> = []
    private(set) var scheduledAppIDs: Set<String> = []
    private(set) var endedWindowUntilByID: [String: Date] = [:]
    private(set) var activationPrompt: TimeWindowActivationPrompt?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let notificationScheduler: any TimeWindowNotificationScheduling
    @ObservationIgnored private var applyScheduledApps: ((Set<String>, String) -> Void)?
    @ObservationIgnored private var applyInstagramProtection: ((Bool, String) -> Void)?
    @ObservationIgnored private var applyTikTokProtection: ((Bool, String) -> Void)?
    @ObservationIgnored private var startProtection: ((String) -> Void)?
    @ObservationIgnored private var requestHomeFocus: (() -> Void)?
    @ObservationIgnored private var manuallyBlockedAppIDs: (() -> Set<String>)?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var scheduleTimer: Timer?
    @ObservationIgnored private var lastAppliedScheduledAppIDs: Set<String>?
    @ObservationIgnored private var occurrenceDecisions: [String: PersistedTimeWindowOccurrenceDecision] = [:]

    static let minimumActivationRemainingTime: TimeInterval = 5 * 60

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        notificationScheduler: any TimeWindowNotificationScheduling = TimeWindowNotificationScheduler(),
        shouldRegisterLifecycleObservers: Bool = true,
        startForegroundTimer: Bool = true
    ) {
        self.defaults = defaults
        self.notificationScheduler = notificationScheduler
        load()
        if shouldRegisterLifecycleObservers {
            registerLifecycleObservers()
        }
        if startForegroundTimer {
            startForegroundScheduleTimer()
        }
    }

    deinit {
        scheduleTimer?.invalidate()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func configure(
        applyScheduledApps: @escaping (Set<String>, String) -> Void,
        applyInstagramProtection: @escaping (Bool, String) -> Void = { _, _ in },
        applyTikTokProtection: @escaping (Bool, String) -> Void = { _, _ in },
        startProtection: @escaping (String) -> Void,
        manuallyBlockedAppIDs: @escaping () -> Set<String> = { [] },
        requestHomeFocus: @escaping () -> Void = {}
    ) {
        self.applyScheduledApps = applyScheduledApps
        self.applyInstagramProtection = applyInstagramProtection
        self.applyTikTokProtection = applyTikTokProtection
        self.startProtection = startProtection
        self.manuallyBlockedAppIDs = manuallyBlockedAppIDs
        self.requestHomeFocus = requestHomeFocus
        TimeWindowNotificationCoordinator.shared.setActionHandler { [weak self] action in
            switch action {
            case .windowStart(let windowID):
                self?.handleNotificationActivation(windowID: windowID)
            case .pauseReminder:
                self?.handlePauseReminderActivation()
            }
        }
        InstagramScheduleMonitor.sync(windows: windows)
        evaluateSchedules(source: "time_windows.configure", forceApply: true)
        refreshActivationPrompt(source: "time_windows.configure")
        rescheduleNotifications(requestAuthorizationIfNeeded: false)
        if pauseAll {
            schedulePauseReminders(requestAuthorizationIfNeeded: false)
        }
    }

    func addWindow(_ window: TimeWindow) {
        var newWindow = window
        newWindow.updatedAt = Date()
        windows.append(newWindow)
        persistAndRefresh(source: "time_windows.add", requestNotificationAuthorization: newWindow.enabled)
    }

    func updateWindow(_ window: TimeWindow) {
        guard let index = windows.firstIndex(where: { $0.id == window.id }) else { return }
        var updatedWindow = window
        updatedWindow.updatedAt = Date()
        windows[index] = updatedWindow
        persistAndRefresh(source: "time_windows.update", requestNotificationAuthorization: updatedWindow.enabled)
    }

    func deleteWindow(id: String) {
        windows.removeAll { $0.id == id }
        persistAndRefresh(source: "time_windows.delete", requestNotificationAuthorization: false)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].enabled = enabled
        windows[index].updatedAt = Date()
        persistAndRefresh(source: "time_windows.toggle", requestNotificationAuthorization: enabled)
    }

    func setPauseAll(_ value: Bool, now: Date = Date()) {
        if value {
            pauseWindows(now: now)
        } else {
            resumePausedWindows(source: "time_windows.pause_all.manual_resume", focusHome: false)
        }
    }

    func setPauseIntervalMinutes(_ minutes: Int, now: Date = Date()) {
        let normalized = AppSettingsStore.normalizedPauseInterval(minutes)
        defaults?.set(normalized, forKey: NimaConstants.pauseIntervalMinutesKey)

        guard pauseAll else { return }
        pauseExpiresAt = now.addingTimeInterval(TimeInterval(normalized * 60))
        savePauseState()
        schedulePauseReminders(requestAuthorizationIfNeeded: false)
    }

    func setWindowsNotificationsEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: NimaConstants.windowsNotificationsEnabledKey)
        if enabled {
            rescheduleNotifications(requestAuthorizationIfNeeded: true)
            if pauseAll {
                schedulePauseReminders(requestAuthorizationIfNeeded: true)
            }
        } else {
            notificationScheduler.cancelStartNotifications()
            notificationScheduler.cancelPauseReminderNotifications()
        }
    }

    func resetForAccountDeletion() {
        windows = []
        pauseAll = false
        pauseExpiresAt = nil
        homeFocusRequestID = nil
        activeWindowIDs = []
        scheduledAppIDs = []
        endedWindowUntilByID = [:]
        activationPrompt = nil
        occurrenceDecisions = [:]
        lastAppliedScheduledAppIDs = nil

        defaults?.removeObject(forKey: NimaConstants.timeWindowsKey)
        defaults?.removeObject(forKey: NimaConstants.timeWindowsPauseAllKey)
        defaults?.removeObject(forKey: NimaConstants.timeWindowsPauseExpiresAtKey)
        defaults?.removeObject(forKey: NimaConstants.timeWindowsEndedUntilKey)
        defaults?.removeObject(forKey: NimaConstants.timeWindowOccurrenceDecisionsKey)
        ScheduledProtectionStateStore.persistScheduleEvaluation(
            appIDs: [],
            windowIDs: [],
            desiredUntil: nil,
            source: "account_deletion.local_reset",
            defaults: defaults
        )
        notificationScheduler.cancelStartNotifications()
        notificationScheduler.cancelPauseReminderNotifications()
        applyScheduledApps?([], "account_deletion.local_reset")
        applyInstagramProtection?(false, "account_deletion.local_reset")
        applyTikTokProtection?(false, "account_deletion.local_reset")
        InstagramScheduleMonitor.sync(windows: [])
    }

    func status(for window: TimeWindow, now: Date = Date()) -> TimeWindowStatus {
        TimeWindowScheduleEvaluator.status(
            for: window,
            now: now,
            pauseAll: pauseAll,
            endedWindowIDs: activeEndedWindowIDs(now: now)
        )
    }

    func activeWindows(now: Date = Date()) -> [TimeWindow] {
        confirmedActiveWindows(now: now)
    }

    func soonestActiveWindowEndDate(now: Date = Date()) -> Date? {
        confirmedActiveWindows(now: now)
            .compactMap { TimeWindowScheduleEvaluator.activeEndDate(for: $0, now: now, pauseAll: pauseAll) }
            .min()
    }

    func soonestActiveWindowEndDateIgnoringPause(now: Date = Date()) -> Date? {
        TimeWindowScheduleEvaluator.soonestActiveEndDate(from: windows, now: now, pauseAll: false)
    }

    func isAppScheduled(_ appID: String) -> Bool {
        scheduledAppIDs.contains(appID)
    }

    @discardableResult
    func endActiveWindow(for appID: String, now: Date = Date()) -> Bool {
        purgeEndedWindows(now: now)
        let activeWindows = confirmedActiveWindows(now: now)
        let windowsToEnd = activeWindows.filter { $0.apps.contains(appID) }
        guard !windowsToEnd.isEmpty else { return false }

        for window in windowsToEnd {
            if let endDate = TimeWindowScheduleEvaluator.activeEndDate(for: window, now: now, pauseAll: pauseAll) {
                endedWindowUntilByID[window.id] = endDate
            }
        }
        saveEndedWindows()
        evaluateSchedules(source: "time_windows.end_current_window", now: now)
        return true
    }

    var activeSummary: String? {
        let active = windows.filter { activeWindowIDs.contains($0.id) }
        if active.count == 1, let window = active.first {
            return "\(window.name) is active"
        }
        if active.count > 1 {
            return "\(active.count) time windows active"
        }
        return nil
    }

    func evaluateSchedules(
        source: String = "time_windows.evaluate",
        forceApply: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        purgeEndedWindows(now: now)
        purgeOccurrenceDecisions(now: now)
        let active = confirmedActiveWindows(now: now, calendar: calendar)
        activeWindowIDs = Set(active.map(\.id))
        let nextScheduledApps = Set(active.flatMap(\.apps))
        for appID in nextScheduledApps.subtracting(scheduledAppIDs) {
            PauseModeState.exclude(appID, defaults: defaults)
        }
        let activeEndDates = active.compactMap {
            TimeWindowScheduleEvaluator.activeEndDate(for: $0, now: now, calendar: calendar)
        }
        var clientScheduleEndDates: [String: Date] = [:]
        for window in active {
            guard let endDate = TimeWindowScheduleEvaluator.activeEndDate(for: window, now: now, calendar: calendar) else { continue }
            for appID in window.apps where appID == "instagram" || appID == "tiktok" {
                clientScheduleEndDates[appID] = max(clientScheduleEndDates[appID] ?? .distantPast, endDate)
            }
        }
        defaults?.set(clientScheduleEndDates, forKey: NimaConstants.clientScheduleEndDatesKey)
        ScheduledProtectionStateStore.persistScheduleEvaluation(
            // This shared snapshot drives VPN recovery. Instagram and TikTok are
            // enforced by their controlled clients and must not make the tunnel desired.
            appIDs: nextScheduledApps.intersection(["x"]),
            windowIDs: activeWindowIDs,
            desiredUntil: activeEndDates.max(),
            source: source,
            defaults: defaults,
            now: now
        )
        let didChange = nextScheduledApps != scheduledAppIDs
        scheduledAppIDs = nextScheduledApps
        applyInstagramProtection?(nextScheduledApps.contains("instagram"), source)
        applyTikTokProtection?(nextScheduledApps.contains("tiktok"), source)
        guard didChange || forceApply || lastAppliedScheduledAppIDs != nextScheduledApps else { return }
        guard let applyScheduledApps else { return }
        applyScheduledApps(nextScheduledApps, source)
        lastAppliedScheduledAppIDs = nextScheduledApps
    }

    func handleNotificationActivation(windowID: String) {
        focusHome()
        refreshActivationPrompt(source: "time_windows.notification_tap", preferredWindowID: windowID)
    }

    func refreshActivationPrompt(
        source: String = "time_windows.activation_prompt",
        preferredWindowID: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        purgeEndedWindows(now: now)
        purgeOccurrenceDecisions(now: now)

        let manualApps = manuallyBlockedAppIDs?() ?? []
        var promptItems: [TimeWindowActivationItem] = []
        var didChangeDecisions = false

        for window in eligibleWindows(now: now, calendar: calendar) {
            guard let occurrence = TimeWindowScheduleEvaluator.activeOccurrence(
                for: window,
                now: now,
                calendar: calendar,
                pauseAll: pauseAll,
                endedWindowIDs: activeEndedWindowIDs(now: now)
            ) else { continue }

            let existingDecision = occurrenceDecision(for: occurrence)
            guard existingDecision == nil || existingDecision == .pending else { continue }

            let normalizedApps = Set(window.apps).intersection(["instagram", "tiktok"])
            let needsScheduledBlocking = !normalizedApps.subtracting(manualApps).isEmpty
            let hasEnoughTime = occurrence.endDate.timeIntervalSince(now) >= Self.minimumActivationRemainingTime

            guard needsScheduledBlocking, hasEnoughTime else {
                occurrenceDecisions[occurrence.id] = PersistedTimeWindowOccurrenceDecision(
                    occurrence: occurrence,
                    decision: .declined
                )
                didChangeDecisions = true
                continue
            }

            if existingDecision == nil {
                occurrenceDecisions[occurrence.id] = PersistedTimeWindowOccurrenceDecision(
                    occurrence: occurrence,
                    decision: .pending
                )
                didChangeDecisions = true
            }
            promptItems.append(TimeWindowActivationItem(window: window, occurrence: occurrence))
        }

        promptItems.sort { lhs, rhs in
            if let preferredWindowID {
                if lhs.window.id == preferredWindowID { return true }
                if rhs.window.id == preferredWindowID { return false }
            }
            if lhs.occurrence.startDate != rhs.occurrence.startDate {
                return lhs.occurrence.startDate < rhs.occurrence.startDate
            }
            return lhs.window.id < rhs.window.id
        }

        if didChangeDecisions {
            saveOccurrenceDecisions()
        }

        activationPrompt = promptItems.isEmpty ? nil : TimeWindowActivationPrompt(items: promptItems)
        AppDiagnosticsLogger.log("TIME_WINDOW_PROMPT count=\(promptItems.count) source=\(source)")
    }

    func activatePromptedWindows(now: Date = Date(), calendar: Calendar = .current) {
        guard let prompt = activationPrompt else { return }
        let eligibleOccurrenceIDs = Set(eligibleWindows(now: now, calendar: calendar).compactMap { window in
            TimeWindowScheduleEvaluator.activeOccurrence(
                for: window,
                now: now,
                calendar: calendar,
                pauseAll: pauseAll,
                endedWindowIDs: activeEndedWindowIDs(now: now)
            )?.id
        })

        var didActivate = false
        for item in prompt.items where eligibleOccurrenceIDs.contains(item.occurrence.id) {
            guard item.occurrence.endDate.timeIntervalSince(now) >= Self.minimumActivationRemainingTime else { continue }
            occurrenceDecisions[item.occurrence.id] = PersistedTimeWindowOccurrenceDecision(
                occurrence: item.occurrence,
                decision: .activated
            )
            didActivate = true
        }

        activationPrompt = nil
        saveOccurrenceDecisions()
        evaluateSchedules(
            source: "time_windows.activation_confirmed",
            forceApply: true,
            now: now,
            calendar: calendar
        )
        if didActivate, hasTunnelBackedScheduledApps {
            startProtection?("time_windows.activation_confirmed")
        }
    }

    func declinePromptedWindows(now: Date = Date()) {
        guard let prompt = activationPrompt else { return }
        for item in prompt.items where item.occurrence.endDate > now {
            occurrenceDecisions[item.occurrence.id] = PersistedTimeWindowOccurrenceDecision(
                occurrence: item.occurrence,
                decision: .declined
            )
        }
        activationPrompt = nil
        saveOccurrenceDecisions()
        evaluateSchedules(source: "time_windows.activation_declined", forceApply: true, now: now)
    }

    func handlePauseReminderActivation() {
        resumePausedWindows(source: "time_windows.pause_reminder_tap", focusHome: true)
    }

    private func persistAndRefresh(source: String, requestNotificationAuthorization: Bool) {
        save()
        InstagramScheduleMonitor.sync(windows: windows)
        evaluateSchedules(source: source)
        rescheduleNotifications(requestAuthorizationIfNeeded: requestNotificationAuthorization)
        if pauseAll {
            schedulePauseReminders(requestAuthorizationIfNeeded: false)
        }
    }

    private func load() {
        pauseAll = defaults?.bool(forKey: NimaConstants.timeWindowsPauseAllKey) ?? false
        pauseExpiresAt = defaults?.object(forKey: NimaConstants.timeWindowsPauseExpiresAtKey) as? Date
        loadEndedWindows()
        if let data = defaults?.data(forKey: NimaConstants.timeWindowsKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([TimeWindow].self, from: data) {
                windows = decoded
            }
        }
        loadOccurrenceDecisions()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(windows) else { return }
        defaults?.set(data, forKey: NimaConstants.timeWindowsKey)
    }

    private func rescheduleNotifications(requestAuthorizationIfNeeded: Bool) {
        guard windowsNotificationsEnabled else {
            notificationScheduler.cancelStartNotifications()
            return
        }
        notificationScheduler.rescheduleStartNotifications(
            for: windows,
            pauseAll: pauseAll,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private func pauseWindows(now: Date) {
        guard pauseAll == false else { return }
        pauseAll = true
        pauseExpiresAt = now.addingTimeInterval(TimeInterval(pauseIntervalMinutes * 60))
        savePauseState()
        evaluateSchedules(source: "time_windows.pause_all.pause", now: now)
        activationPrompt = nil
        rescheduleNotifications(requestAuthorizationIfNeeded: false)
        schedulePauseReminders(requestAuthorizationIfNeeded: true)
    }

    private func resumePausedWindows(source: String, focusHome: Bool) {
        guard pauseAll else { return }
        pauseAll = false
        pauseExpiresAt = nil
        savePauseState()
        notificationScheduler.cancelPauseReminderNotifications()
        evaluateSchedules(source: source)
        rescheduleNotifications(requestAuthorizationIfNeeded: false)
        if hasTunnelBackedScheduledApps {
            startProtection?(source)
        }
        refreshActivationPrompt(source: source)
        if focusHome {
            self.focusHome()
        }
    }

    private func schedulePauseReminders(requestAuthorizationIfNeeded: Bool) {
        guard windowsNotificationsEnabled else {
            notificationScheduler.cancelPauseReminderNotifications()
            return
        }
        guard pauseAll, let pauseExpiresAt else {
            notificationScheduler.cancelPauseReminderNotifications()
            return
        }
        notificationScheduler.schedulePauseReminderNotifications(
            firstReminderAt: pauseExpiresAt,
            windowEndDate: soonestActiveWindowEndDateIgnoringPause(),
            reminderInterval: TimeInterval(pauseIntervalMinutes * 60),
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private func savePauseState() {
        defaults?.set(pauseAll, forKey: NimaConstants.timeWindowsPauseAllKey)
        if let pauseExpiresAt {
            defaults?.set(pauseExpiresAt, forKey: NimaConstants.timeWindowsPauseExpiresAtKey)
        } else {
            defaults?.removeObject(forKey: NimaConstants.timeWindowsPauseExpiresAtKey)
        }
    }

    private func loadEndedWindows(now: Date = Date()) {
        guard let stored = defaults?.dictionary(forKey: NimaConstants.timeWindowsEndedUntilKey) as? [String: TimeInterval] else {
            endedWindowUntilByID = [:]
            return
        }
        endedWindowUntilByID = stored.reduce(into: [:]) { partialResult, item in
            let endDate = Date(timeIntervalSince1970: item.value)
            if endDate > now {
                partialResult[item.key] = endDate
            }
        }
        saveEndedWindows()
    }

    private func saveEndedWindows() {
        let stored = endedWindowUntilByID.reduce(into: [String: TimeInterval]()) { partialResult, item in
            partialResult[item.key] = item.value.timeIntervalSince1970
        }
        if stored.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.timeWindowsEndedUntilKey)
        } else {
            defaults?.set(stored, forKey: NimaConstants.timeWindowsEndedUntilKey)
        }
    }

    private func purgeEndedWindows(now: Date = Date()) {
        let current = endedWindowUntilByID
        endedWindowUntilByID = current.filter { $0.value > now }
        if endedWindowUntilByID != current {
            saveEndedWindows()
        }
    }

    private func activeEndedWindowIDs(now: Date) -> Set<String> {
        Set(endedWindowUntilByID.filter { $0.value > now }.keys)
    }

    private func focusHome() {
        homeFocusRequestID = UUID()
        requestHomeFocus?()
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification,
            UIApplication.willEnterForegroundNotification,
            UIApplication.significantTimeChangeNotification,
            NSNotification.Name.NSSystemTimeZoneDidChange
        ]
        lifecycleObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.evaluateSchedules(source: "time_windows.lifecycle")
                self?.refreshActivationPrompt(source: "time_windows.lifecycle")
                self?.rescheduleNotifications(requestAuthorizationIfNeeded: false)
            }
        }
    }

    private func startForegroundScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluateSchedules(source: "time_windows.timer")
        }
        scheduleTimer?.tolerance = 5
    }

    private var windowsNotificationsEnabled: Bool {
        AppSettingsStore.windowsNotificationsEnabled(defaults: defaults)
    }

    private var pauseIntervalMinutes: Int {
        AppSettingsStore.pauseIntervalMinutes(defaults: defaults)
    }

    private var hasTunnelBackedScheduledApps: Bool {
        scheduledAppIDs.contains("x")
    }

    private func eligibleWindows(now: Date, calendar: Calendar) -> [TimeWindow] {
        TimeWindowScheduleEvaluator.activeWindows(
            from: windows,
            now: now,
            calendar: calendar,
            pauseAll: pauseAll,
            endedWindowIDs: activeEndedWindowIDs(now: now)
        )
    }

    private func confirmedActiveWindows(now: Date, calendar: Calendar = .current) -> [TimeWindow] {
        eligibleWindows(now: now, calendar: calendar).filter { window in
            guard let occurrence = TimeWindowScheduleEvaluator.activeOccurrence(
                for: window,
                now: now,
                calendar: calendar,
                pauseAll: pauseAll,
                endedWindowIDs: activeEndedWindowIDs(now: now)
            ) else { return false }
            return occurrenceDecision(for: occurrence) == .activated
        }
    }

    private func occurrenceDecision(for occurrence: TimeWindowOccurrence) -> TimeWindowOccurrenceDecision? {
        if let exact = occurrenceDecisions[occurrence.id]?.decision {
            return exact
        }
        guard let matching = occurrenceDecisions.values.first(where: { record in
            record.occurrence.windowID == occurrence.windowID &&
                record.occurrence.startDate < occurrence.endDate &&
                occurrence.startDate < record.occurrence.endDate
        }) else {
            return nil
        }

        occurrenceDecisions.removeValue(forKey: matching.occurrence.id)
        occurrenceDecisions[occurrence.id] = PersistedTimeWindowOccurrenceDecision(
            occurrence: occurrence,
            decision: matching.decision
        )
        saveOccurrenceDecisions()
        return matching.decision
    }

    private func loadOccurrenceDecisions() {
        guard let data = defaults?.data(forKey: NimaConstants.timeWindowOccurrenceDecisionsKey),
              let records = try? JSONDecoder().decode([PersistedTimeWindowOccurrenceDecision].self, from: data) else {
            occurrenceDecisions = [:]
            return
        }
        occurrenceDecisions = Dictionary(uniqueKeysWithValues: records.map { ($0.occurrence.id, $0) })
        purgeOccurrenceDecisions()
    }

    private func saveOccurrenceDecisions() {
        let records = occurrenceDecisions.values.sorted { $0.occurrence.id < $1.occurrence.id }
        if records.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.timeWindowOccurrenceDecisionsKey)
        } else if let data = try? JSONEncoder().encode(records) {
            defaults?.set(data, forKey: NimaConstants.timeWindowOccurrenceDecisionsKey)
        }
    }

    private func purgeOccurrenceDecisions(now: Date = Date()) {
        let knownWindowIDs = Set(windows.map(\.id))
        let current = occurrenceDecisions
        occurrenceDecisions = current.filter {
            $0.value.occurrence.endDate > now && knownWindowIDs.contains($0.value.occurrence.windowID)
        }
        if occurrenceDecisions != current {
            saveOccurrenceDecisions()
        }
        if let activationPrompt {
            let liveItems = activationPrompt.items.filter { $0.occurrence.endDate > now }
            self.activationPrompt = liveItems.isEmpty ? nil : TimeWindowActivationPrompt(items: liveItems)
        }
    }
}

struct TimeWindowActivationItem: Identifiable, Equatable {
    let window: TimeWindow
    let occurrence: TimeWindowOccurrence

    var id: String { occurrence.id }
}

struct TimeWindowActivationPrompt: Identifiable, Equatable {
    let items: [TimeWindowActivationItem]

    var id: String { items.map(\.id).sorted().joined(separator: ",") }
    var soonestEndDate: Date? { items.map(\.occurrence.endDate).min() }
}

enum ScheduledProtectionStateStore {
    typealias Snapshot = ScheduledProtectionSnapshot

    static func snapshot(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) -> Snapshot {
        ScheduledProtectionSnapshotReader.snapshot(defaults: defaults)
    }

    static func persistScheduleEvaluation(
        appIDs: Set<String>,
        windowIDs: Set<String>,
        desiredUntil: Date?,
        source: String,
        defaults: UserDefaults?,
        now: Date = Date()
    ) {
        purgeExpiredManualOverride(defaults: defaults, now: now)
        let normalizedApps = appIDs.intersection(["instagram", "tiktok"])
        guard !normalizedApps.isEmpty, let desiredUntil, desiredUntil > now else {
            defaults?.set(false, forKey: NimaConstants.scheduleDesiredVPNOnKey)
            defaults?.removeObject(forKey: NimaConstants.scheduleDesiredReasonKey)
            defaults?.set(source, forKey: NimaConstants.scheduleDesiredSourceKey)
            defaults?.removeObject(forKey: NimaConstants.scheduleDesiredUntilTSKey)
            defaults?.set([String](), forKey: NimaConstants.scheduleActiveAppIDsKey)
            defaults?.set([String](), forKey: NimaConstants.scheduleActiveWindowIDsKey)
            AppDiagnosticsLogger.log(
                "SCHEDULE_PROTECTION_STATE desired_on=false apps=[] windows=[] source=\(source)"
            )
            return
        }

        defaults?.set(true, forKey: NimaConstants.scheduleDesiredVPNOnKey)
        defaults?.set("schedule", forKey: NimaConstants.scheduleDesiredReasonKey)
        defaults?.set(source, forKey: NimaConstants.scheduleDesiredSourceKey)
        defaults?.set(desiredUntil.timeIntervalSince1970, forKey: NimaConstants.scheduleDesiredUntilTSKey)
        defaults?.set(normalizedApps.sorted(), forKey: NimaConstants.scheduleActiveAppIDsKey)
        defaults?.set(windowIDs.sorted(), forKey: NimaConstants.scheduleActiveWindowIDsKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_STATE desired_on=true apps=\(normalizedApps.sorted()) windows=\(windowIDs.sorted()) desired_until=\(format(desiredUntil.timeIntervalSince1970)) source=\(source)"
        )
    }

    static func suppressCurrentScheduleWindow(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        source: String,
        now: Date = Date()
    ) {
        let current = snapshot(defaults: defaults)
        guard current.desiredVPNOn, current.desiredUntil > now.timeIntervalSince1970 else { return }
        defaults?.set(current.desiredUntil, forKey: NimaConstants.scheduleManualOffUntilTSKey)
        defaults?.set("manual_off_current_window source=\(source)", forKey: NimaConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_MANUAL_OFF until=\(format(current.desiredUntil)) source=\(source) apps=\(current.activeAppIDs.sorted()) windows=\(current.activeWindowIDs.sorted())"
        )
    }

    static func recordInterruption(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        result: String,
        now: Date = Date()
    ) {
        defaults?.set(now.timeIntervalSince1970, forKey: NimaConstants.scheduleLastInterruptionTSKey)
        defaults?.set(result, forKey: NimaConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_INTERRUPTION at=\(format(now.timeIntervalSince1970)) result=\(result)"
        )
    }

    static func recordRepairResult(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        result: String
    ) {
        defaults?.set(result, forKey: NimaConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log("SCHEDULE_PROTECTION_REPAIR_RESULT result=\(result)")
    }

    private static func purgeExpiredManualOverride(defaults: UserDefaults?, now: Date) {
        let manualOffUntil = defaults?.double(forKey: NimaConstants.scheduleManualOffUntilTSKey) ?? 0
        guard manualOffUntil > 0, manualOffUntil <= now.timeIntervalSince1970 else { return }
        defaults?.removeObject(forKey: NimaConstants.scheduleManualOffUntilTSKey)
        AppDiagnosticsLogger.log("SCHEDULE_PROTECTION_MANUAL_OFF_EXPIRED at=\(format(now.timeIntervalSince1970))")
    }

    private static func format(_ ts: TimeInterval) -> String {
        guard ts > 0 else { return "unknown" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ts))
    }
}
