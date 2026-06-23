import Foundation
import Observation
import UserNotifications

protocol StreakReminderScheduling {
    func scheduleStreakReminders(
        at dates: [Date],
        requestAuthorizationIfNeeded: Bool
    )
    func cancelStreakReminder()
}

struct StreakReminderScheduler: StreakReminderScheduling {
    static let identifierPrefix = "streak-reminder"
    static let notificationTitle = "Don't lose your streak 🔥"
    static let notificationBody = "Activate Nima and protect your focus"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduleStreakReminders(
        at dates: [Date],
        requestAuthorizationIfNeeded: Bool
    ) {
        cancelExistingStreakReminders {
            guard !dates.isEmpty else { return }

            scheduleWhenAuthorized(requestIfNeeded: requestAuthorizationIfNeeded) {
                dates.enumerated().forEach { index, date in
                    scheduleStreakReminder(at: date, index: index)
                }
            }
        }
    }

    func cancelStreakReminder() {
        cancelExistingStreakReminders()
    }

    private func scheduleStreakReminder(at date: Date, index: Int) {
        let content = UNMutableNotificationContent()
        content.title = Self.notificationTitle
        content.body = Self.notificationBody
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationID(index: index),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private static func notificationID(index: Int) -> String {
        "\(identifierPrefix)-\(index)"
    }

    private func cancelExistingStreakReminders(completion: (() -> Void)? = nil) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
            completion?()
        }
    }

    private func scheduleWhenAuthorized(requestIfNeeded: Bool, schedule: @escaping () -> Void) {
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule()
            case .notDetermined where requestIfNeeded:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        schedule()
                    }
                }
            default:
                break
            }
        }
    }
}

@Observable
final class AppSettingsStore {
    static let allowedPauseIntervals = [5, 10, 15, 20, 25, 30]
    static let defaultPauseIntervalMinutes = 5
    static let defaultStreakRemindersEnabled = true
    static let defaultStreakReminderHour = 20
    static let defaultStreakReminderMinute = 0
    static let scheduledStreakReminderDayCount = 14

    var displayName: String = ""
    var windowsNotificationsEnabled: Bool = true
    var streakRemindersEnabled: Bool = defaultStreakRemindersEnabled
    var streakReminderHour: Int = defaultStreakReminderHour
    var streakReminderMinute: Int = defaultStreakReminderMinute
    var pauseIntervalMinutes: Int = defaultPauseIntervalMinutes

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let streakReminderScheduler: any StreakReminderScheduling
    @ObservationIgnored private var hasEarnedStreakToday = false

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        streakReminderScheduler: any StreakReminderScheduling = StreakReminderScheduler()
    ) {
        self.defaults = defaults
        self.streakReminderScheduler = streakReminderScheduler
        load()
        syncStreakReminder(
            hasEarnedToday: StreakStore(defaults: defaults).hasEarnedToday(),
            requestAuthorizationIfNeeded: false
        )
    }

    var normalizedDisplayName: String? {
        Self.normalizedDisplayName(displayName)
    }

    var streakReminderDateComponents: DateComponents {
        DateComponents(hour: streakReminderHour, minute: streakReminderMinute)
    }

    func setDisplayName(_ value: String) {
        let normalized = Self.normalizedDisplayName(value) ?? ""
        displayName = normalized
        if normalized.isEmpty {
            defaults?.removeObject(forKey: NimaConstants.displayNameKey)
        } else {
            defaults?.set(normalized, forKey: NimaConstants.displayNameKey)
        }
    }

    func setWindowsNotificationsEnabled(_ enabled: Bool) {
        windowsNotificationsEnabled = enabled
        defaults?.set(enabled, forKey: NimaConstants.windowsNotificationsEnabledKey)
    }

    func setStreakRemindersEnabled(
        _ enabled: Bool,
        hasEarnedToday: Bool? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        streakRemindersEnabled = enabled
        defaults?.set(enabled, forKey: NimaConstants.streakRemindersEnabledKey)
        if let hasEarnedToday {
            hasEarnedStreakToday = hasEarnedToday
        }
        rescheduleStreakReminder(
            requestAuthorizationIfNeeded: enabled,
            now: now,
            calendar: calendar
        )
    }

    func setStreakReminderTime(
        hour: Int,
        minute: Int,
        hasEarnedToday: Bool? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        streakReminderHour = min(23, max(0, hour))
        streakReminderMinute = min(59, max(0, minute))
        defaults?.set(streakReminderHour, forKey: NimaConstants.streakReminderHourKey)
        defaults?.set(streakReminderMinute, forKey: NimaConstants.streakReminderMinuteKey)
        if let hasEarnedToday {
            hasEarnedStreakToday = hasEarnedToday
        }
        rescheduleStreakReminder(
            requestAuthorizationIfNeeded: streakRemindersEnabled,
            now: now,
            calendar: calendar
        )
    }

    func setPauseIntervalMinutes(_ minutes: Int) {
        let normalized = Self.normalizedPauseInterval(minutes)
        pauseIntervalMinutes = normalized
        defaults?.set(normalized, forKey: NimaConstants.pauseIntervalMinutesKey)
    }

    func resetAdvancedDefaults() {
        Self.resetAdvancedDefaults(defaults: defaults)
    }

    func resetForAccountDeletion() {
        displayName = ""
        windowsNotificationsEnabled = true
        streakRemindersEnabled = Self.defaultStreakRemindersEnabled
        streakReminderHour = Self.defaultStreakReminderHour
        streakReminderMinute = Self.defaultStreakReminderMinute
        pauseIntervalMinutes = Self.defaultPauseIntervalMinutes

        defaults?.removeObject(forKey: NimaConstants.displayNameKey)
        defaults?.set(windowsNotificationsEnabled, forKey: NimaConstants.windowsNotificationsEnabledKey)
        defaults?.set(streakRemindersEnabled, forKey: NimaConstants.streakRemindersEnabledKey)
        defaults?.set(streakReminderHour, forKey: NimaConstants.streakReminderHourKey)
        defaults?.set(streakReminderMinute, forKey: NimaConstants.streakReminderMinuteKey)
        defaults?.set(pauseIntervalMinutes, forKey: NimaConstants.pauseIntervalMinutesKey)
        streakReminderScheduler.cancelStreakReminder()
    }

    func syncStreakReminder(
        hasEarnedToday: Bool,
        now: Date = Date(),
        calendar: Calendar = .current,
        requestAuthorizationIfNeeded: Bool = false
    ) {
        hasEarnedStreakToday = hasEarnedToday
        rescheduleStreakReminder(
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded,
            now: now,
            calendar: calendar
        )
    }

    static func resetAdvancedDefaults(defaults: UserDefaults?) {
        defaults?.set(true, forKey: NimaConstants.udpSelectiveSafeModeEnabledKey)
        defaults?.set(false, forKey: NimaConstants.udpDisabledFastRejectEnabledKey)
        defaults?.set(
            NimaConstants.tun2socksStartupModeStagedAfterConnect,
            forKey: NimaConstants.tun2socksStartupModeKey
        )
    }

    static func normalizedDisplayName(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func resolvedDisplayName(localOverride: String?, userEmail: String) -> String {
        if let localOverride = localOverride.flatMap(normalizedDisplayName) {
            return localOverride
        }

        let localPart = userEmail
            .split(separator: "@")
            .first?
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .first

        guard let localPart, !localPart.isEmpty else {
            return "emily"
        }

        return String(localPart).lowercased()
    }

    static func windowsNotificationsEnabled(defaults: UserDefaults?) -> Bool {
        if let stored = defaults?.object(forKey: NimaConstants.windowsNotificationsEnabledKey) as? Bool {
            return stored
        }
        return true
    }

    static func pauseIntervalMinutes(defaults: UserDefaults?) -> Int {
        let stored = defaults?.integer(forKey: NimaConstants.pauseIntervalMinutesKey) ?? defaultPauseIntervalMinutes
        return normalizedPauseInterval(stored)
    }

    static func normalizedPauseInterval(_ minutes: Int) -> Int {
        allowedPauseIntervals.contains(minutes) ? minutes : defaultPauseIntervalMinutes
    }

    static func streakReminderDates(
        hour: Int,
        minute: Int,
        hasEarnedToday: Bool,
        now: Date,
        calendar: Calendar = .current,
        dayCount: Int = scheduledStreakReminderDayCount
    ) -> [Date] {
        guard dayCount > 0 else { return [] }

        let calendar = normalizedCalendar(calendar)
        let todayStart = calendar.startOfDay(for: now)
        guard let todayReminder = reminderDate(
            dayOffset: 0,
            hour: hour,
            minute: minute,
            todayStart: todayStart,
            calendar: calendar
        ) else {
            return []
        }

        let firstDayOffset = hasEarnedToday || todayReminder <= now ? 1 : 0
        return (firstDayOffset..<(firstDayOffset + dayCount)).compactMap { dayOffset in
            reminderDate(
                dayOffset: dayOffset,
                hour: hour,
                minute: minute,
                todayStart: todayStart,
                calendar: calendar
            )
        }
    }

    private func load() {
        displayName = defaults?.string(forKey: NimaConstants.displayNameKey) ?? ""
        windowsNotificationsEnabled = Self.windowsNotificationsEnabled(defaults: defaults)
        if let storedStreakReminders = defaults?.object(forKey: NimaConstants.streakRemindersEnabledKey) as? Bool {
            streakRemindersEnabled = storedStreakReminders
        } else {
            streakRemindersEnabled = Self.defaultStreakRemindersEnabled
        }

        let storedHour = defaults?.object(forKey: NimaConstants.streakReminderHourKey) as? Int
        let storedMinute = defaults?.object(forKey: NimaConstants.streakReminderMinuteKey) as? Int
        streakReminderHour = min(23, max(0, storedHour ?? Self.defaultStreakReminderHour))
        streakReminderMinute = min(59, max(0, storedMinute ?? Self.defaultStreakReminderMinute))
        pauseIntervalMinutes = Self.pauseIntervalMinutes(defaults: defaults)
    }

    private func rescheduleStreakReminder(
        requestAuthorizationIfNeeded: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard streakRemindersEnabled else {
            streakReminderScheduler.cancelStreakReminder()
            return
        }
        let dates = Self.streakReminderDates(
            hour: streakReminderHour,
            minute: streakReminderMinute,
            hasEarnedToday: hasEarnedStreakToday,
            now: now,
            calendar: calendar
        )
        streakReminderScheduler.scheduleStreakReminders(
            at: dates,
            requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
        )
    }

    private static func reminderDate(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        todayStart: Date,
        calendar: Calendar
    ) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    private static func normalizedCalendar(_ calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }
}
