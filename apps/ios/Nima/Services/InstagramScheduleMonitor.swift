import DeviceActivity
import Foundation

enum InstagramScheduleMonitor {
    private static let activityPrefix = "nima.instagram."

    static func sync(windows: [TimeWindow]) {
        let center = DeviceActivityCenter()
        let existing = center.activities.filter { $0.rawValue.hasPrefix(activityPrefix) }
        if !existing.isEmpty {
            center.stopMonitoring(existing)
        }

        for window in windows where window.enabled && window.instagramMode != nil {
            guard let startMinutes = TimeWindowScheduleEvaluator.minutes(from: window.startTime),
                  let endMinutes = TimeWindowScheduleEvaluator.minutes(from: window.endTime),
                  startMinutes != endMinutes else { continue }

            for day in window.repeatDays {
                let name = DeviceActivityName(
                    "\(activityPrefix)\(window.id).\(day.rawValue).\(window.instagramMode?.rawValue ?? "clean")"
                )
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
                        "INSTAGRAM_DEVICE_ACTIVITY_REGISTER_FAILED window=\(window.id) error=\(error.localizedDescription)"
                    )
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
