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
        case legacyExperience = "legacy_experience"
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

        if ExperienceModeState.isLegacy(defaults: defaults) {
            return .unshield(.legacyExperience)
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

        if defaults?.bool(forKey: NimaConstants.timeWindowsPauseAllKey) == true {
            return .unshield(.pauseAllWindows)
        }

        let windows = loadWindows(defaults: defaults)
        let endedWindowIDs = activeEndedWindowIDs(defaults: defaults, now: now)
        let activeWindows = TimeWindowScheduleEvaluator.activeWindows(
            from: windows,
            now: now,
            calendar: calendar,
            endedWindowIDs: endedWindowIDs
        ).filter { $0.apps.contains(app.rawValue) }

        if activeWindows.isEmpty { return .unshield(.noActiveTimeWindow) }
        let hasUnsuppressedWindow = activeWindows.contains {
            !HardModeProtectionState.isOccurrenceSuppressed(
                app.rawValue, window: $0, defaults: defaults, now: now, calendar: calendar
            )
        }

        return hasUnsuppressedWindow
            ? .shield(.timeWindow)
            : .unshield(.hardModeScheduleOff)
    }

    @discardableResult
    static func reconcile(
        for appID: String,
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        now: Date = Date(),
        calendar: Calendar = .current,
        selection: FamilyActivitySelection? = nil,
        checkProcessAuthorization: Bool = true
    ) -> ClientShieldDecision {
        let decision = decision(
            for: appID,
            defaults: defaults,
            now: now,
            calendar: calendar
        )
        guard let app = ClientShieldAppID(rawValue: appID) else { return decision }

        let store = ManagedSettingsStore(named: .init(app.managedSettingsStoreName))
        guard decision.shouldShield else {
            store.shield.applications = nil
            return decision
        }

        // AuthorizationCenter's status starts as notDetermined in the monitor
        // extension, which does not request authorization itself. The app
        // checks authorization when configuring the schedule; the extension
        // uses its Family Controls entitlement and the saved app selection.
        if checkProcessAuthorization && AuthorizationCenter.shared.authorizationStatus != .approved {
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

enum ScheduleMonitorDiagnostics {
    private static let registrationKey = "schedule_monitor.last_registration_v1"
    private static let callbackKey = "schedule_monitor.last_callback_v1"

    static func recordRegistration(
        requested: Int,
        installed: Int,
        unchanged: Int,
        failures: [String],
        nextStart: Date?,
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) {
        var entry: [String: Any] = [
            "at": Date().timeIntervalSince1970,
            "requested": requested,
            "installed": installed,
            "unchanged": unchanged,
            "failures": failures
        ]
        if let nextStart { entry["next_start"] = nextStart.timeIntervalSince1970 }
        defaults?.set(entry, forKey: registrationKey)
    }

    static func recordCallback(
        activity: String,
        event: String,
        appID: String? = nil,
        decision: ClientShieldDecision? = nil,
        shieldCount: Int? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) {
        var entry: [String: Any] = [
            "at": Date().timeIntervalSince1970,
            "activity": activity,
            "event": event
        ]
        if let appID { entry["app"] = appID }
        if let decision { entry["decision"] = decision.reason.rawValue }
        if let shieldCount { entry["shield_count"] = shieldCount }
        defaults?.set(entry, forKey: appID.map { "\(callbackKey).\($0)" } ?? callbackKey)
    }
}
