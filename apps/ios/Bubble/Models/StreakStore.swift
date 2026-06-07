import Foundation
import Observation

struct StreakDayRecord: Codable, Equatable, Identifiable {
    var id: String { date }

    let date: String
    let earned: Bool
    let earnedAt: Date
    let timezone: String
    let source: String
}

enum StreakWeekDayStatus: String, Equatable {
    case earned
    case missed
    case todayPending
    case future
    case beforeTrackingStarted
}

struct StreakWeekDayState: Equatable, Identifiable {
    var id: String { date }

    let date: String
    let label: String
    let status: StreakWeekDayStatus
    let isToday: Bool
}

@Observable
final class StreakStore {
    private(set) var records: [StreakDayRecord] = []

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let storageKey: String

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID),
        storageKey: String = BubbleConstants.streakDaysKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    @discardableResult
    func markTodayEarned(
        source: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let calendar = Self.normalizedCalendar(calendar)
        let today = Self.localDateString(for: now, calendar: calendar)

        if records.contains(where: { $0.date == today && $0.earned }) {
            return false
        }

        let record = StreakDayRecord(
            date: today,
            earned: true,
            earnedAt: now,
            timezone: calendar.timeZone.identifier,
            source: source
        )

        if let existingIndex = records.firstIndex(where: { $0.date == today }) {
            records[existingIndex] = record
        } else {
            records.append(record)
        }

        records.sort { $0.date < $1.date }
        save()
        return true
    }

    func hasEarnedToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let calendar = Self.normalizedCalendar(calendar)
        return earnedDateSet.contains(Self.localDateString(for: now, calendar: calendar))
    }

    func currentStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let calendar = Self.normalizedCalendar(calendar)
        let earnedDates = earnedDateSet
        let todayStart = calendar.startOfDay(for: now)
        let today = Self.localDateString(for: todayStart, calendar: calendar)
        let startDate = earnedDates.contains(today)
            ? todayStart
            : calendar.date(byAdding: .day, value: -1, to: todayStart)

        guard var cursor = startDate else { return 0 }

        var count = 0
        while earnedDates.contains(Self.localDateString(for: cursor, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }
        return count
    }

    func weekStates(now: Date = Date(), calendar: Calendar = .current) -> [StreakWeekDayState] {
        let calendar = Self.normalizedCalendar(calendar)
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        let earnedDates = earnedDateSet
        let todayStart = calendar.startOfDay(for: now)
        let today = Self.localDateString(for: todayStart, calendar: calendar)
        let firstTrackingDate = records
            .filter(\.earned)
            .map(\.date)
            .sorted()
            .first
        let monday = Self.startOfWeek(containing: now, calendar: calendar)

        return labels.indices.compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: monday) else {
                return nil
            }

            let dateString = Self.localDateString(for: date, calendar: calendar)
            let isToday = dateString == today
            let isFuture = calendar.startOfDay(for: date) > todayStart
            let isBeforeTrackingStarted = firstTrackingDate.map { dateString < $0 } ?? (dateString < today)

            let status: StreakWeekDayStatus
            if isFuture {
                status = .future
            } else if earnedDates.contains(dateString) {
                status = .earned
            } else if isToday {
                status = .todayPending
            } else if isBeforeTrackingStarted {
                status = .beforeTrackingStarted
            } else {
                status = .missed
            }

            return StreakWeekDayState(
                date: dateString,
                label: labels[index],
                status: status,
                isToday: isToday
            )
        }
    }

    private var earnedDateSet: Set<String> {
        Set(records.filter(\.earned).map(\.date))
    }

    private func load() {
        guard let data = defaults?.data(forKey: storageKey) else {
            records = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([StreakDayRecord].self, from: data)) ?? []
        records.sort { $0.date < $1.date }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    private static func normalizedCalendar(_ calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    private static func localDateString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
