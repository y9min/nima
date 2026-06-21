import Foundation

enum TimeWindowWeekday: String, Codable, CaseIterable, Hashable, Identifiable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    var fullRepeatLabel: String {
        switch self {
        case .monday: return "Every Monday"
        case .tuesday: return "Every Tuesday"
        case .wednesday: return "Every Wednesday"
        case .thursday: return "Every Thursday"
        case .friday: return "Every Friday"
        case .saturday: return "Every Saturday"
        case .sunday: return "Every Sunday"
        }
    }

    var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    static func from(calendarWeekday: Int) -> TimeWindowWeekday {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    static let weekdays: [TimeWindowWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: [TimeWindowWeekday] = [.saturday, .sunday]
}

struct ScheduledProtectionSnapshot: Equatable {
    let hasPersistedState: Bool
    let desiredVPNOn: Bool
    let reason: String
    let source: String
    let desiredUntil: TimeInterval
    let activeAppIDs: Set<String>
    let activeWindowIDs: Set<String>
    let manualOffUntil: TimeInterval
    let lastInterruptionAt: TimeInterval
    let lastRepairResult: String

    func isActive(now: Date = Date()) -> Bool {
        desiredVPNOn &&
            desiredUntil > now.timeIntervalSince1970 &&
            manualOffUntil <= now.timeIntervalSince1970 &&
            !activeAppIDs.isEmpty
    }

    func isDesiredProtectionActive(now: Date = Date()) -> Bool {
        isActive(now: now)
    }

    func isManualOverrideActive(now: Date = Date()) -> Bool {
        manualOffUntil > now.timeIntervalSince1970
    }
}

enum ScheduledProtectionSnapshotReader {
    static func snapshot(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) -> ScheduledProtectionSnapshot {
        ScheduledProtectionSnapshot(
            hasPersistedState: defaults?.object(forKey: NimaConstants.scheduleDesiredVPNOnKey) != nil,
            desiredVPNOn: defaults?.bool(forKey: NimaConstants.scheduleDesiredVPNOnKey) ?? false,
            reason: defaults?.string(forKey: NimaConstants.scheduleDesiredReasonKey) ?? "",
            source: defaults?.string(forKey: NimaConstants.scheduleDesiredSourceKey) ?? "",
            desiredUntil: defaults?.double(forKey: NimaConstants.scheduleDesiredUntilTSKey) ?? 0,
            activeAppIDs: Set(defaults?.stringArray(forKey: NimaConstants.scheduleActiveAppIDsKey) ?? []),
            activeWindowIDs: Set(defaults?.stringArray(forKey: NimaConstants.scheduleActiveWindowIDsKey) ?? []),
            manualOffUntil: defaults?.double(forKey: NimaConstants.scheduleManualOffUntilTSKey) ?? 0,
            lastInterruptionAt: defaults?.double(forKey: NimaConstants.scheduleLastInterruptionTSKey) ?? 0,
            lastRepairResult: defaults?.string(forKey: NimaConstants.scheduleLastRepairResultKey) ?? ""
        )
    }
}

struct TimeWindow: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var emoji: String
    var startTime: String
    var endTime: String
    var repeatDays: [TimeWindowWeekday]
    var apps: [String]
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "tw_\(UUID().uuidString)",
        name: String = "Focus Time",
        emoji: String = "⏰",
        startTime: String = "09:00",
        endTime: String = "17:00",
        repeatDays: [TimeWindowWeekday] = TimeWindowWeekday.weekdays,
        apps: [String] = [],
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.startTime = startTime
        self.endTime = endTime
        self.repeatDays = repeatDays
        self.apps = apps
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum TimeWindowStatus: Equatable {
    case activeNow
    case upcoming
    case off

    var label: String {
        switch self {
        case .activeNow: return "Active now"
        case .upcoming: return "Upcoming"
        case .off: return "Off"
        }
    }
}

enum TimeWindowScheduleEvaluator {
    static func minutes(from time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    static func timeString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    static func isActive(
        _ window: TimeWindow,
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> Bool {
        guard window.enabled, !pauseAll else { return false }
        guard !endedWindowIDs.contains(window.id) else { return false }
        guard let start = minutes(from: window.startTime),
              let end = minutes(from: window.endTime),
              start != end else {
            return false
        }

        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let today = TimeWindowWeekday.from(calendarWeekday: components.weekday ?? 2)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let selectedDays = Set(window.repeatDays)

        if start < end {
            return selectedDays.contains(today) && currentMinute >= start && currentMinute < end
        }

        let previousDay = previousWeekday(before: today)
        return (selectedDays.contains(today) && currentMinute >= start)
            || (selectedDays.contains(previousDay) && currentMinute < end)
    }

    static func status(
        for window: TimeWindow,
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> TimeWindowStatus {
        guard window.enabled, !pauseAll else { return .off }
        return isActive(window, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs) ? .activeNow : .upcoming
    }

    static func activeWindows(
        from windows: [TimeWindow],
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> [TimeWindow] {
        windows.filter { isActive($0, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs) }
    }

    static func scheduledAppIDs(
        from windows: [TimeWindow],
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> Set<String> {
        Set(activeWindows(from: windows, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs).flatMap(\.apps))
    }

    static func activeEndDate(
        for window: TimeWindow,
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> Date? {
        guard isActive(window, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs),
              let start = minutes(from: window.startTime),
              let end = minutes(from: window.endTime),
              start != end else {
            return nil
        }

        if start < end {
            return date(onDayOffset: 0, minuteOfDay: end, from: now, calendar: calendar)
        }

        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let today = TimeWindowWeekday.from(calendarWeekday: components.weekday ?? 2)
        let previousDay = previousWeekday(before: today)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let selectedDays = Set(window.repeatDays)

        if selectedDays.contains(previousDay), currentMinute < end {
            return date(onDayOffset: 0, minuteOfDay: end, from: now, calendar: calendar)
        }
        if selectedDays.contains(today), currentMinute >= start {
            return date(onDayOffset: 1, minuteOfDay: end, from: now, calendar: calendar)
        }
        return nil
    }

    static func soonestActiveEndDate(
        from windows: [TimeWindow],
        now: Date = Date(),
        calendar: Calendar = .current,
        pauseAll: Bool = false,
        endedWindowIDs: Set<String> = []
    ) -> Date? {
        activeWindows(from: windows, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs)
            .compactMap { activeEndDate(for: $0, now: now, calendar: calendar, pauseAll: pauseAll, endedWindowIDs: endedWindowIDs) }
            .min()
    }

    static func repeatSummary(for days: [TimeWindowWeekday]) -> String {
        let uniqueDays = orderedUniqueDays(days)
        let selected = Set(uniqueDays)

        if uniqueDays.count == TimeWindowWeekday.allCases.count {
            return "Every day"
        }
        if selected == Set(TimeWindowWeekday.weekdays) {
            return "Mon-Fri"
        }
        if selected == Set(TimeWindowWeekday.weekend) {
            return "Weekends"
        }
        if uniqueDays.count == 1, let day = uniqueDays.first {
            return day.fullRepeatLabel
        }
        return uniqueDays.map(\.shortLabel).joined(separator: ", ")
    }

    static func timeRangeSummary(startTime: String, endTime: String) -> String {
        "\(displayTime(startTime)) - \(displayTime(endTime))"
    }

    static func displayTime(_ time: String) -> String {
        guard let minutes = minutes(from: time) else { return time }
        let hour24 = minutes / 60
        let minute = minutes % 60
        let suffix = hour24 >= 12 ? "PM" : "AM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return minute == 0
            ? "\(hour12) \(suffix)"
            : String(format: "%d:%02d %@", hour12, minute, suffix)
    }

    static func orderedUniqueDays(_ days: [TimeWindowWeekday]) -> [TimeWindowWeekday] {
        let selected = Set(days)
        return TimeWindowWeekday.allCases.filter { selected.contains($0) }
    }

    static func previousWeekday(before day: TimeWindowWeekday) -> TimeWindowWeekday {
        let days = TimeWindowWeekday.allCases
        guard let index = days.firstIndex(of: day) else { return .sunday }
        return days[(index + days.count - 1) % days.count]
    }

    private static func date(
        onDayOffset dayOffset: Int,
        minuteOfDay: Int,
        from date: Date,
        calendar: Calendar
    ) -> Date? {
        guard let day = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: date)
        ) else {
            return nil
        }
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: day)
    }
}
