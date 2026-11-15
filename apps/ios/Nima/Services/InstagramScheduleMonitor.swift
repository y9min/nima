import DeviceActivity
import Foundation
import ManagedSettings

enum InstagramScheduleMonitor {
    private static let activityPrefixes = ["nima.window.", "nima.instagram.", "nima.tiktok.", "nima.x."]

    static func sync(windows: [TimeWindow]) {
        let center = DeviceActivityCenter()
        let existing = Set(center.activities.filter { activity in
            activityPrefixes.contains { activity.rawValue.hasPrefix($0) }
        })
        let desired = activityDefinitions(windows: windows)
        var failed: [String] = []
        var unchanged = 0

        // Keep the old monitor until a replacement is installed. A failed
        // registration must not leave an otherwise working schedule empty.
        for (name, schedule) in desired.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if center.schedule(for: name) == schedule {
                unchanged += 1
                continue
            }
            do {
                try center.startMonitoring(name, during: schedule)
            } catch {
                failed.append("\(name.rawValue): \(error.localizedDescription)")
                AppDiagnosticsLogger.log(
                    "FEED_DEVICE_ACTIVITY_REGISTER_FAILED activity=\(name.rawValue) error=\(error.localizedDescription)"
                )
            }
        }

        // Old per-app monitors can continue to drive reconciliation if the
        // replacement could not be installed.
        let installed = Set(center.activities)
        let missing = Set(desired.keys).subtracting(installed)
        let stale = existing.subtracting(desired.keys)
        // An empty stopMonitoring list cancels ALL activities, including limits
        // and pause expiry. Only stop explicitly obsolete schedules.
        if !stale.isEmpty && missing.isEmpty && failed.isEmpty {
            for activity in stale {
                ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
            }
            center.stopMonitoring(Array(stale))
        }
        let remaining = Set(center.activities)
        for name in Set(desired.keys).subtracting(remaining) {
            failed.append("\(name.rawValue): missing after registration cleanup")
        }
        ScheduleMonitorDiagnostics.recordRegistration(
            requested: desired.count,
            installed: desired.keys.filter { remaining.contains($0) }.count,
            unchanged: unchanged,
            failures: failed,
            nextStart: desired.values.compactMap { $0.nextInterval?.start }.min()
        )
    }

    static func activityDefinitions(windows: [TimeWindow]) -> [DeviceActivityName: DeviceActivitySchedule] {
        var definitions: [DeviceActivityName: DeviceActivitySchedule] = [:]
        for window in windows where window.enabled && window.apps.contains(where: { ["instagram", "tiktok", "x"].contains($0) }) {
            guard let startMinutes = TimeWindowScheduleEvaluator.minutes(from: window.startTime),
                  let endMinutes = TimeWindowScheduleEvaluator.minutes(from: window.endTime),
                  startMinutes != endMinutes else { continue }

            let everyDay = Set(window.repeatDays) == Set(TimeWindowWeekday.allCases)
            let days: [TimeWindowWeekday?] = everyDay ? [nil] : window.repeatDays.map(Optional.some)
            for day in days {
                let name = DeviceActivityName("nima.window.\(window.id).\(day?.rawValue ?? "daily")")
                definitions[name] = DeviceActivitySchedule(
                    intervalStart: DateComponents(
                        hour: startMinutes / 60,
                        minute: startMinutes % 60,
                        weekday: day?.calendarWeekday
                    ),
                    intervalEnd: DateComponents(
                        hour: endMinutes / 60,
                        minute: endMinutes % 60,
                        weekday: day.map {
                            endWeekday(for: $0, startMinutes: startMinutes, endMinutes: endMinutes).calendarWeekday
                        }
                    ),
                    repeats: true
                )
            }
        }
        return definitions
    }

    private static func endWeekday(
        for startDay: TimeWindowWeekday,
        startMinutes: Int,
        endMinutes: Int
    ) -> TimeWindowWeekday {
        guard endMinutes <= startMinutes else { return startDay }
        let ordered: [TimeWindowWeekday] = [
            .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
        ]
        guard let index = ordered.firstIndex(of: startDay) else { return startDay }
        return ordered[(index + 1) % ordered.count]
    }
}

enum PauseModeMonitor {
    static let activity = DeviceActivityName("nima.pause_mode")

    @discardableResult
    static func schedule(until expiresAt: Date, now: Date = Date()) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        let schedule = definition(until: expiresAt, now: now)
        guard let nextInterval = schedule.nextInterval,
              abs(nextInterval.end.timeIntervalSince(expiresAt)) < 5 else {
            AppDiagnosticsLogger.log("PAUSE_MODE_MONITOR_FAILED invalid_interval")
            return false
        }
        do {
            try center.startMonitoring(activity, during: schedule)
            return true
        } catch {
            AppDiagnosticsLogger.log("PAUSE_MODE_MONITOR_FAILED error=\(error.localizedDescription)")
            return false
        }
    }

    static func definition(until expiresAt: Date, now: Date = Date()) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        // DeviceActivity requires a minimum 15-minute interval. For a 5 or 10
        // minute pause, begin the monitored interval before the pause starts;
        // only its end callback restores the shields.
        let intervalStart = min(now, expiresAt.addingTimeInterval(-15 * 60))
        let start = calendar.dateComponents([.hour, .minute, .second], from: intervalStart)
        let end = calendar.dateComponents([.hour, .minute, .second], from: expiresAt)
        return DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)
    }

    static func clearClientScheduleShields() {
        for activity in DeviceActivityCenter().activities where ["nima.instagram.", "nima.tiktok.", "nima.x."].contains(where: { activity.rawValue.hasPrefix($0) }) {
            ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        }
    }
}

enum HardModePauseMonitor {
    static let activity = DeviceActivityName("nima.hard_mode_pause")

    @discardableResult
    static func schedule(
        until expiresAt: Date,
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        now: Date = Date()
    ) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        let intervalStart = min(now, expiresAt.addingTimeInterval(-15 * 60))
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: intervalStart),
            intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: expiresAt),
            repeats: false
        )
        guard schedule.nextInterval != nil else { return false }
        do {
            try center.startMonitoring(activity, during: schedule)
            return true
        } catch {
            AppDiagnosticsLogger.log(
                "HARD_MODE_PAUSE_MONITOR_FAILED error=\(error.localizedDescription)"
            )
            return false
        }
    }

    static func clearScheduleShields(for appIDs: Set<String>) {
        for activity in DeviceActivityCenter().activities {
            guard appIDs.contains(where: { activity.rawValue.hasPrefix("nima.\($0).") }) else {
                continue
            }
            ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        }
    }
}
