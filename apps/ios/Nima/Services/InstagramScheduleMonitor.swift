import DeviceActivity
import Foundation
import ManagedSettings

enum InstagramScheduleMonitor {
    private static let activityPrefixes = ["nima.instagram.", "nima.tiktok."]

    static func sync(windows: [TimeWindow]) {
        let center = DeviceActivityCenter()
        let existing = center.activities.filter { activity in
            activityPrefixes.contains { activity.rawValue.hasPrefix($0) }
        }
        if !existing.isEmpty {
            center.stopMonitoring(existing)
        }

        for window in windows where window.enabled {
            guard let startMinutes = TimeWindowScheduleEvaluator.minutes(from: window.startTime),
                  let endMinutes = TimeWindowScheduleEvaluator.minutes(from: window.endTime),
                  startMinutes != endMinutes else { continue }

            for appID in window.apps where appID == "instagram" || appID == "tiktok" {
                for day in window.repeatDays {
                    let name = DeviceActivityName("nima.\(appID).\(window.id).\(day.rawValue)")
                    let schedule = DeviceActivitySchedule(
                        intervalStart: DateComponents(
                            hour: startMinutes / 60,
                            minute: startMinutes % 60,
                            weekday: day.calendarWeekday
                        ),
                        intervalEnd: DateComponents(
                            hour: endMinutes / 60,
                            minute: endMinutes % 60,
                            weekday: endWeekday(for: day, startMinutes: startMinutes, endMinutes: endMinutes).calendarWeekday
                        ),
                        repeats: true
                    )
                    do {
                        try center.startMonitoring(name, during: schedule)
                    } catch {
                        AppDiagnosticsLogger.log(
                            "FEED_DEVICE_ACTIVITY_REGISTER_FAILED app=\(appID) window=\(window.id) error=\(error.localizedDescription)"
                        )
                    }
                }
            }
        }
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
        for activity in DeviceActivityCenter().activities where ["nima.instagram.", "nima.tiktok."].contains(where: { activity.rawValue.hasPrefix($0) }) {
            ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        }
    }
}
