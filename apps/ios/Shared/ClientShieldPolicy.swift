import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum ClientShieldAppID: String, CaseIterable {
    case instagram
    case tiktok
    case x

    var manualProtectionKey: String {
        switch self {
        case .instagram: return NimaConstants.instagramProtectionEnabledKey
        case .tiktok: return NimaConstants.tiktokProtectionEnabledKey
        case .x: return NimaConstants.xProtectionEnabledKey
        }
    }

    var familySelectionKey: String {
        switch self {
        case .instagram: return NimaConstants.instagramFamilySelectionKey
        case .tiktok: return NimaConstants.tiktokFamilySelectionKey
        case .x: return NimaConstants.xFamilySelectionKey
        }
    }

    var managedSettingsStoreName: String {
        "nima.\(rawValue)"
    }
}

enum ClientShieldDecision: Equatable {
    enum Reason: String, Equatable {
        case manualProtection = "manual_protection"
        case timeWindow = "time_window"
        case noActiveTimeWindow = "no_active_time_window"
        case pauseMode = "pause_mode"
        case hardMode = "hard_mode"
        case hardModeScheduleOff = "hard_mode_schedule_off"
        case pauseAllWindows = "pause_all_windows"
        case paywall = "paywall"
        case unsupportedApp = "unsupported_app"
    }

    case shield(Reason)
    case unshield(Reason)

    var shouldShield: Bool {
        if case .shield = self { return true }
        return false
    }

    var reason: Reason {
        switch self {
        case .shield(let reason), .unshield(let reason):
            return reason
        }
    }
}

enum ClientShieldPolicy {
    static func decision(
        for appID: String,
        defaults: UserDefaults?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ClientShieldDecision {
        guard let app = ClientShieldAppID(rawValue: appID) else {
            return .unshield(.unsupportedApp)
        }

        if PaywallBlockingState.isActive(defaults: defaults) {
            return .unshield(.paywall)
        }
        if PauseModeState.isPaused(app.rawValue, defaults: defaults, now: now) {
            return .unshield(.pauseMode)
        }
        if HardModeProtectionState.isPaused(app.rawValue, defaults: defaults, now: now) {
            return .unshield(.hardMode)
        }

        if defaults?.bool(forKey: app.manualProtectionKey) == true {
            return .shield(.manualProtection)
        }

        if HardModeProtectionState.isScheduleSuppressed(app.rawValue, defaults: defaults) {
            return .unshield(.hardModeScheduleOff)
        }

        if defaults?.bool(forKey: NimaConstants.timeWindowsPauseAllKey) == true {
            return .unshield(.pauseAllWindows)
        }

        let windows = loadWindows(defaults: defaults)
        let endedWindowIDs = activeEndedWindowIDs(defaults: defaults, now: now)
        let hasActiveWindow = TimeWindowScheduleEvaluator.activeWindows(
            from: windows,
            now: now,
            calendar: calendar,
            endedWindowIDs: endedWindowIDs
        ).contains { $0.apps.contains(app.rawValue) }

        return hasActiveWindow
            ? .shield(.timeWindow)
            : .unshield(.noActiveTimeWindow)
    }

    @discardableResult
    static func reconcile(
        for appID: String,
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        now: Date = Date(),
        calendar: Calendar = .current,
        selection: FamilyActivitySelection? = nil
    ) -> ClientShieldDecision {
        let decision = decision(
            for: appID,
            defaults: defaults,
            now: now,
            calendar: calendar
        )
        guard let app = ClientShieldAppID(rawValue: appID) else { return decision }

        let store = ManagedSettingsStore(named: .init(app.managedSettingsStoreName))
        guard decision.shouldShield,
              AuthorizationCenter.shared.authorizationStatus == .approved else {
            store.shield.applications = nil
            return decision
        }

        let resolvedSelection = selection ?? loadSelection(
            key: app.familySelectionKey,
            defaults: defaults
        )
        guard !resolvedSelection.applicationTokens.isEmpty else {
            store.shield.applications = nil
            return decision
        }

        store.shield.applications = resolvedSelection.applicationTokens
        return decision
    }

    static func clearLegacyWindowActivityShields(
        for appIDs: Set<String> = Set(ClientShieldAppID.allCases.map(\.rawValue))
    ) {
        let prefixes = appIDs.map { "nima.\($0)." }
        for activity in DeviceActivityCenter().activities where
            prefixes.contains(where: { activity.rawValue.hasPrefix($0) }) {
            ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        }
    }

    private static func loadWindows(defaults: UserDefaults?) -> [TimeWindow] {
        guard let data = defaults?.data(forKey: NimaConstants.timeWindowsKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TimeWindow].self, from: data)) ?? []
    }

    private static func activeEndedWindowIDs(
        defaults: UserDefaults?,
        now: Date
    ) -> Set<String> {
        guard let stored = defaults?.dictionary(
            forKey: NimaConstants.timeWindowsEndedUntilKey
        ) as? [String: TimeInterval] else {
            return []
        }
        return Set(stored.compactMap { id, timestamp in
            timestamp > now.timeIntervalSince1970 ? id : nil
        })
    }

    private static func loadSelection(
        key: String,
        defaults: UserDefaults?
    ) -> FamilyActivitySelection {
        guard let data = defaults?.data(forKey: key),
              let selection = try? JSONDecoder().decode(
                FamilyActivitySelection.self,
                from: data
              ) else {
            return FamilyActivitySelection()
        }
        return selection
    }
}
