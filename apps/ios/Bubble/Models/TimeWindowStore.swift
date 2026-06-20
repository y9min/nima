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

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let notificationScheduler: any TimeWindowNotificationScheduling
    @ObservationIgnored private var applyScheduledApps: ((Set<String>, String) -> Void)?
    @ObservationIgnored private var startProtection: ((String) -> Void)?
    @ObservationIgnored private var requestHomeFocus: (() -> Void)?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var scheduleTimer: Timer?
    @ObservationIgnored private var lastAppliedScheduledAppIDs: Set<String>?

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID),
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
        startProtection: @escaping (String) -> Void,
        requestHomeFocus: @escaping () -> Void = {}
    ) {
        self.applyScheduledApps = applyScheduledApps
        self.startProtection = startProtection
        self.requestHomeFocus = requestHomeFocus
        TimeWindowNotificationCoordinator.shared.setActionHandler { [weak self] action in
            switch action {
            case .windowStart(let windowID):
                self?.handleNotificationActivation(windowID: windowID)
            case .pauseReminder:
                self?.handlePauseReminderActivation()
            }
        }
        evaluateSchedules(source: "time_windows.configure", forceApply: true)
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
        defaults?.set(normalized, forKey: BubbleConstants.pauseIntervalMinutesKey)

        guard pauseAll else { return }
        pauseExpiresAt = now.addingTimeInterval(TimeInterval(normalized * 60))
        savePauseState()
        schedulePauseReminders(requestAuthorizationIfNeeded: false)
    }

    func setWindowsNotificationsEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: BubbleConstants.windowsNotificationsEnabledKey)
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
        lastAppliedScheduledAppIDs = nil

        defaults?.removeObject(forKey: BubbleConstants.timeWindowsKey)
        defaults?.removeObject(forKey: BubbleConstants.timeWindowsPauseAllKey)
        defaults?.removeObject(forKey: BubbleConstants.timeWindowsPauseExpiresAtKey)
        defaults?.removeObject(forKey: BubbleConstants.timeWindowsEndedUntilKey)
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
        TimeWindowScheduleEvaluator.activeWindows(
            from: windows,
            now: now,
            pauseAll: pauseAll,
            endedWindowIDs: activeEndedWindowIDs(now: now)
        )
    }

    func soonestActiveWindowEndDate(now: Date = Date()) -> Date? {
        TimeWindowScheduleEvaluator.soonestActiveEndDate(
            from: windows,
            now: now,
            pauseAll: pauseAll,
            endedWindowIDs: activeEndedWindowIDs(now: now)
        )
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
        let alreadyEndedIDs = activeEndedWindowIDs(now: now)
        let activeWindows = TimeWindowScheduleEvaluator.activeWindows(
            from: windows,
            now: now,
            pauseAll: pauseAll,
            endedWindowIDs: alreadyEndedIDs
        )
        let windowsToEnd = activeWindows.filter { $0.apps.contains(appID) }
        guard !windowsToEnd.isEmpty else { return false }

        for window in windowsToEnd {
            if let endDate = TimeWindowScheduleEvaluator.activeEndDate(for: window, now: now, pauseAll: pauseAll) {
                endedWindowUntilByID[window.id] = endDate
            }
        }
        saveEndedWindows()
        evaluateSchedules(source: "time_windows.end_current_window")
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

    func evaluateSchedules(source: String = "time_windows.evaluate", forceApply: Bool = false) {
        purgeEndedWindows()
        let active = activeWindows()
        activeWindowIDs = Set(active.map(\.id))
        let nextScheduledApps = Set(active.flatMap(\.apps))
        let activeEndDates = active.compactMap { TimeWindowScheduleEvaluator.activeEndDate(for: $0) }
        ScheduledProtectionStateStore.persistScheduleEvaluation(
            appIDs: nextScheduledApps,
            windowIDs: activeWindowIDs,
            desiredUntil: activeEndDates.max(),
            source: source,
            defaults: defaults
        )
        let didChange = nextScheduledApps != scheduledAppIDs
        scheduledAppIDs = nextScheduledApps
        guard didChange || forceApply || lastAppliedScheduledAppIDs != nextScheduledApps else { return }
        guard let applyScheduledApps else { return }
        applyScheduledApps(nextScheduledApps, source)
        lastAppliedScheduledAppIDs = nextScheduledApps
    }

    func handleNotificationActivation(windowID: String) {
        evaluateSchedules(source: "time_windows.notification_tap", forceApply: true)
        focusHome()
        guard activeWindowIDs.contains(windowID), !scheduledAppIDs.isEmpty else { return }
        startProtection?("time_windows.notification_tap")
    }

    func handlePauseReminderActivation() {
        resumePausedWindows(source: "time_windows.pause_reminder_tap", focusHome: true)
    }

    private func persistAndRefresh(source: String, requestNotificationAuthorization: Bool) {
        save()
        evaluateSchedules(source: source)
        rescheduleNotifications(requestAuthorizationIfNeeded: requestNotificationAuthorization)
        if pauseAll {
            schedulePauseReminders(requestAuthorizationIfNeeded: false)
        }
    }

    private func load() {
        pauseAll = defaults?.bool(forKey: BubbleConstants.timeWindowsPauseAllKey) ?? false
        pauseExpiresAt = defaults?.object(forKey: BubbleConstants.timeWindowsPauseExpiresAtKey) as? Date
        loadEndedWindows()
        guard let data = defaults?.data(forKey: BubbleConstants.timeWindowsKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TimeWindow].self, from: data) {
            windows = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(windows) else { return }
        defaults?.set(data, forKey: BubbleConstants.timeWindowsKey)
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
        evaluateSchedules(source: "time_windows.pause_all.pause")
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
        if !scheduledAppIDs.isEmpty {
            startProtection?(source)
        }
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
        defaults?.set(pauseAll, forKey: BubbleConstants.timeWindowsPauseAllKey)
        if let pauseExpiresAt {
            defaults?.set(pauseExpiresAt, forKey: BubbleConstants.timeWindowsPauseExpiresAtKey)
        } else {
            defaults?.removeObject(forKey: BubbleConstants.timeWindowsPauseExpiresAtKey)
        }
    }

    private func loadEndedWindows(now: Date = Date()) {
        guard let stored = defaults?.dictionary(forKey: BubbleConstants.timeWindowsEndedUntilKey) as? [String: TimeInterval] else {
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
            defaults?.removeObject(forKey: BubbleConstants.timeWindowsEndedUntilKey)
        } else {
            defaults?.set(stored, forKey: BubbleConstants.timeWindowsEndedUntilKey)
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
}

enum ScheduledProtectionStateStore {
    typealias Snapshot = ScheduledProtectionSnapshot

    static func snapshot(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID)
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
            defaults?.set(false, forKey: BubbleConstants.scheduleDesiredVPNOnKey)
            defaults?.removeObject(forKey: BubbleConstants.scheduleDesiredReasonKey)
            defaults?.set(source, forKey: BubbleConstants.scheduleDesiredSourceKey)
            defaults?.removeObject(forKey: BubbleConstants.scheduleDesiredUntilTSKey)
            defaults?.set([String](), forKey: BubbleConstants.scheduleActiveAppIDsKey)
            defaults?.set([String](), forKey: BubbleConstants.scheduleActiveWindowIDsKey)
            AppDiagnosticsLogger.log(
                "SCHEDULE_PROTECTION_STATE desired_on=false apps=[] windows=[] source=\(source)"
            )
            return
        }

        defaults?.set(true, forKey: BubbleConstants.scheduleDesiredVPNOnKey)
        defaults?.set("schedule", forKey: BubbleConstants.scheduleDesiredReasonKey)
        defaults?.set(source, forKey: BubbleConstants.scheduleDesiredSourceKey)
        defaults?.set(desiredUntil.timeIntervalSince1970, forKey: BubbleConstants.scheduleDesiredUntilTSKey)
        defaults?.set(normalizedApps.sorted(), forKey: BubbleConstants.scheduleActiveAppIDsKey)
        defaults?.set(windowIDs.sorted(), forKey: BubbleConstants.scheduleActiveWindowIDsKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_STATE desired_on=true apps=\(normalizedApps.sorted()) windows=\(windowIDs.sorted()) desired_until=\(format(desiredUntil.timeIntervalSince1970)) source=\(source)"
        )
    }

    static func suppressCurrentScheduleWindow(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID),
        source: String,
        now: Date = Date()
    ) {
        let current = snapshot(defaults: defaults)
        guard current.desiredVPNOn, current.desiredUntil > now.timeIntervalSince1970 else { return }
        defaults?.set(current.desiredUntil, forKey: BubbleConstants.scheduleManualOffUntilTSKey)
        defaults?.set("manual_off_current_window source=\(source)", forKey: BubbleConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_MANUAL_OFF until=\(format(current.desiredUntil)) source=\(source) apps=\(current.activeAppIDs.sorted()) windows=\(current.activeWindowIDs.sorted())"
        )
    }

    static func recordInterruption(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID),
        result: String,
        now: Date = Date()
    ) {
        defaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.scheduleLastInterruptionTSKey)
        defaults?.set(result, forKey: BubbleConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log(
            "SCHEDULE_PROTECTION_INTERRUPTION at=\(format(now.timeIntervalSince1970)) result=\(result)"
        )
    }

    static func recordRepairResult(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID),
        result: String
    ) {
        defaults?.set(result, forKey: BubbleConstants.scheduleLastRepairResultKey)
        AppDiagnosticsLogger.log("SCHEDULE_PROTECTION_REPAIR_RESULT result=\(result)")
    }

    private static func purgeExpiredManualOverride(defaults: UserDefaults?, now: Date) {
        let manualOffUntil = defaults?.double(forKey: BubbleConstants.scheduleManualOffUntilTSKey) ?? 0
        guard manualOffUntil > 0, manualOffUntil <= now.timeIntervalSince1970 else { return }
        defaults?.removeObject(forKey: BubbleConstants.scheduleManualOffUntilTSKey)
        AppDiagnosticsLogger.log("SCHEDULE_PROTECTION_MANUAL_OFF_EXPIRED at=\(format(now.timeIntervalSince1970))")
    }

    private static func format(_ ts: TimeInterval) -> String {
        guard ts > 0 else { return "unknown" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ts))
    }
}
