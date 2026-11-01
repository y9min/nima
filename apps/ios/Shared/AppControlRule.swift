import FamilyControls
import Foundation
import ManagedSettings

enum AppControlKind: String, Codable {
    case limit
    case blocked
}

struct AppControlRule: Codable, Equatable, Identifiable {
    let id: String
    let applicationToken: ApplicationToken
    let kind: AppControlKind
    let dailyMinutes: Int?

    init(id: String = UUID().uuidString, applicationToken: ApplicationToken, kind: AppControlKind, dailyMinutes: Int? = nil) {
        self.id = id
        self.applicationToken = applicationToken
        self.kind = kind
        self.dailyMinutes = dailyMinutes
    }
}

enum ShieldActionAvailability {
    // iOS 26.5 introduced ShieldActionResponse.openParentalControlsApp.
    // Earlier releases cannot launch the containing app from a shield action.
    static var canOpenParentApp: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
        )
    }
}

enum AppControlRuleState {
    static let appGroupID = "group.so.nima.app"
    static let rulesKey = "app_controls.rules_v1"
    static let reachedLimitIDsKey = "app_controls.reached_limit_ids_v1"
    static let reachedDayKey = "app_controls.reached_day_v1"
    static let limitActivityName = "nima.controls.daily_limits"
    static let limitEventPrefix = "nima.controls.limit."

    static func rules(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> [AppControlRule] {
        guard let data = defaults?.data(forKey: rulesKey) else { return [] }
        return (try? JSONDecoder().decode([AppControlRule].self, from: data)) ?? []
    }

    static func save(_ rules: [AppControlRule], defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults?.set(data, forKey: rulesKey)
    }

    static func dayStart(_ date: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        calendar.startOfDay(for: date).timeIntervalSince1970
    }

    static func reachedLimitIDs(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID), now: Date = Date()) -> Set<String> {
        guard defaults?.double(forKey: reachedDayKey) == dayStart(now) else { return [] }
        return Set(defaults?.stringArray(forKey: reachedLimitIDsKey) ?? [])
    }

    static func saveReachedLimitIDs(_ ids: Set<String>, defaults: UserDefaults? = UserDefaults(suiteName: appGroupID), now: Date = Date()) {
        defaults?.set(dayStart(now), forKey: reachedDayKey)
        defaults?.set(Array(ids), forKey: reachedLimitIDsKey)
    }

    static func activeKind(for token: ApplicationToken, defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> AppControlKind? {
        let rules = rules(defaults: defaults)
        if rules.contains(where: { $0.applicationToken == token && $0.kind == .blocked }) { return .blocked }
        let reached = reachedLimitIDs(defaults: defaults)
        if rules.contains(where: { $0.applicationToken == token && $0.kind == .limit && reached.contains($0.id) }) { return .limit }
        return nil
    }
}
