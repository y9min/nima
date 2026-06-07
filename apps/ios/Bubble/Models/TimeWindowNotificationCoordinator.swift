import Foundation
import UserNotifications

enum TimeWindowNotificationAction: Equatable {
    case windowStart(windowID: String)
    case pauseReminder
}

enum TimeWindowNotificationKind: String {
    case windowStart = "window_start"
    case pauseReminder = "pause_reminder"
}

final class TimeWindowNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TimeWindowNotificationCoordinator()

    private var actionHandler: ((TimeWindowNotificationAction) -> Void)?
    private var pendingActions: [TimeWindowNotificationAction] = []

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func setActionHandler(_ handler: @escaping (TimeWindowNotificationAction) -> Void) {
        actionHandler = handler
        let pending = pendingActions
        pendingActions.removeAll()
        pending.forEach { handler($0) }
    }

    static func action(from userInfo: [AnyHashable: Any]) -> TimeWindowNotificationAction? {
        let kind = (userInfo[TimeWindowNotificationScheduler.notificationKindUserInfoKey] as? String)
            .flatMap(TimeWindowNotificationKind.init(rawValue:))

        switch kind {
        case .pauseReminder:
            return .pauseReminder
        case .windowStart, nil:
            guard let windowID = userInfo[TimeWindowNotificationScheduler.windowIDUserInfoKey] as? String else {
                return nil
            }
            return .windowStart(windowID: windowID)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let action = Self.action(from: userInfo) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let actionHandler = self.actionHandler {
                    actionHandler(action)
                } else {
                    self.pendingActions.append(action)
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

protocol TimeWindowNotificationScheduling {
    func rescheduleStartNotifications(
        for windows: [TimeWindow],
        pauseAll: Bool,
        requestAuthorizationIfNeeded: Bool
    )
    func schedulePauseReminderNotifications(
        firstReminderAt: Date,
        windowEndDate: Date?,
        requestAuthorizationIfNeeded: Bool
    )
    func cancelPauseReminderNotifications()
}

struct TimeWindowNotificationScheduler {
    static let categoryIdentifier = "TIME_WINDOW_START"
    static let pauseReminderCategoryIdentifier = "TIME_WINDOW_PAUSE_REMINDER"
    static let notificationKindUserInfoKey = "timeWindowNotificationKind"
    static let windowIDUserInfoKey = "timeWindowID"
    static let pauseReminderIdentifierPrefix = "time-window-pause-reminder"
    static let pauseReminderInterval: TimeInterval = 10 * 60

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func rescheduleStartNotifications(
        for windows: [TimeWindow],
        pauseAll: Bool,
        requestAuthorizationIfNeeded: Bool
    ) {
        let allIdentifiers = windows.flatMap(Self.startNotificationIDs(for:))
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers)

        guard !pauseAll else { return }
        let enabledWindows = windows.filter { $0.enabled }
        guard !enabledWindows.isEmpty else { return }

        scheduleWhenAuthorized(requestIfNeeded: requestAuthorizationIfNeeded) {
            enabledWindows.forEach { scheduleStartNotifications(for: $0) }
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

    private func scheduleStartNotifications(for window: TimeWindow) {
        guard let startMinutes = TimeWindowScheduleEvaluator.minutes(from: window.startTime) else { return }
        let hour = startMinutes / 60
        let minute = startMinutes % 60

        for day in TimeWindowScheduleEvaluator.orderedUniqueDays(window.repeatDays) {
            var components = DateComponents()
            components.weekday = day.calendarWeekday
            components.hour = hour
            components.minute = minute

            let content = UNMutableNotificationContent()
            content.title = "\(window.name) has started"
            content.body = "Tap to activate."
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [
                Self.notificationKindUserInfoKey: TimeWindowNotificationKind.windowStart.rawValue,
                Self.windowIDUserInfoKey: window.id
            ]

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.startNotificationID(windowID: window.id, weekday: day),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    static func startNotificationIDs(for window: TimeWindow) -> [String] {
        TimeWindowWeekday.allCases.map { startNotificationID(windowID: window.id, weekday: $0) }
    }

    static func startNotificationID(windowID: String, weekday: TimeWindowWeekday) -> String {
        "time-window-start-\(windowID)-\(weekday.rawValue)"
    }
}

extension TimeWindowNotificationScheduler: TimeWindowNotificationScheduling {
    func schedulePauseReminderNotifications(
        firstReminderAt: Date,
        windowEndDate: Date?,
        requestAuthorizationIfNeeded: Bool
    ) {
        let dates = Self.pauseReminderDates(firstReminderAt: firstReminderAt, windowEndDate: windowEndDate)
        guard !dates.isEmpty else {
            cancelPauseReminderNotifications()
            return
        }

        cancelExistingPauseReminders {
            scheduleWhenAuthorized(requestIfNeeded: requestAuthorizationIfNeeded) {
                dates.enumerated().forEach { index, date in
                    schedulePauseReminder(at: date, index: index)
                }
            }
        }
    }

    func cancelPauseReminderNotifications() {
        cancelExistingPauseReminders()
    }

    static func pauseReminderDates(
        firstReminderAt: Date,
        windowEndDate: Date?,
        reminderInterval: TimeInterval = pauseReminderInterval
    ) -> [Date] {
        if let windowEndDate, firstReminderAt >= windowEndDate {
            return []
        }

        guard let windowEndDate else {
            return [firstReminderAt]
        }

        var dates: [Date] = []
        var nextDate = firstReminderAt
        while nextDate < windowEndDate {
            dates.append(nextDate)
            nextDate = nextDate.addingTimeInterval(reminderInterval)
        }
        return dates
    }

    static func pauseReminderNotificationID(index: Int) -> String {
        "\(pauseReminderIdentifierPrefix)-\(index)"
    }

    private func schedulePauseReminder(at date: Date, index: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "Tap to block again."
        content.sound = .default
        content.categoryIdentifier = Self.pauseReminderCategoryIdentifier
        content.userInfo = [
            Self.notificationKindUserInfoKey: TimeWindowNotificationKind.pauseReminder.rawValue
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.pauseReminderNotificationID(index: index),
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func cancelExistingPauseReminders(completion: (() -> Void)? = nil) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.pauseReminderIdentifierPrefix) }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
            completion?()
        }
    }
}
