import FamilyControls
import Foundation
import ManagedSettings
import Observation
import WebKit

enum XShieldStatus: Equatable {
    case unavailable
    case permissionRequired
    case selectionRequired
    case unprotected
    case protected

    var title: String {
        switch self {
        case .unavailable: return "Screen Time unavailable"
        case .permissionRequired: return "Permission required"
        case .selectionRequired: return "Select X"
        case .unprotected: return "Official app not protected"
        case .protected: return "Official app protected"
        }
    }
}

@MainActor
@Observable
final class XProtectionStore {
    static let protectionEnabledKey = NimaConstants.xProtectionEnabledKey
    static let manualModeKey = "x.client.manual_mode"
    static let familySelectionKey = NimaConstants.xFamilySelectionKey

    var protectionEnabled: Bool
    var manualMode: XMode
    private(set) var isScheduled = false
    private(set) var filteringHealth: XFilteringHealth = .checking
    private(set) var authorizationStatus: AuthorizationStatus
    var familySelection: FamilyActivitySelection {
        didSet {
            persistSelection()
            applyShield()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let managedSettings = ManagedSettingsStore(named: .init("nima.x"))

    init(defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)) {
        self.defaults = defaults
        protectionEnabled = Self.loadProtectionEnabled(defaults: defaults)

        if defaults?.object(forKey: Self.manualModeKey) == nil {
            let migratedMode: XMode
            if let data = defaults?.data(forKey: NimaConstants.manualFeaturePolicyKey),
               let policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data),
               policy.appToggles["x"]?["strict_feed_block"] == true {
                migratedMode = .clean
            } else {
                migratedMode = .clean
            }
            defaults?.set(migratedMode.rawValue, forKey: Self.manualModeKey)
        }
        manualMode = XMode(rawValue: defaults?.string(forKey: Self.manualModeKey) ?? "") ?? .clean

        if let data = defaults?.data(forKey: Self.familySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            familySelection = selection
        } else if let connected = ScreenTimeAppConnections.load(defaults: defaults).selection(for: "x") {
            familySelection = connected
            if let data = try? JSONEncoder().encode(connected) {
                defaults?.set(data, forKey: Self.familySelectionKey)
            }
        } else {
            familySelection = FamilyActivitySelection()
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        applyShield()
    }

    var isActive: Bool {
        protectionEnabled || HardModeProtectionState.effectivelyScheduled(
            "x",
            scheduled: isScheduled,
            defaults: defaults
        )
    }

    var effectiveMode: XMode {
        filteringHealth == .limited ? .dmOnly : manualMode
    }

    var shieldStatus: XShieldStatus {
        guard authorizationStatus == .approved else {
            return authorizationStatus == .denied ? .unavailable : .permissionRequired
        }
        guard !familySelection.applicationTokens.isEmpty else { return .selectionRequired }
        return isActive ? .protected : .unprotected
    }

    func setProtectionEnabled(_ enabled: Bool, source: String) {
        if enabled {
            PauseModeState.exclude("x", defaults: defaults)
            HardModeProtectionState.markProtectionOn("x", defaults: defaults)
        }
        protectionEnabled = enabled
        defaults?.set(enabled, forKey: Self.protectionEnabledKey)
        applyShield()
        AppDiagnosticsLogger.log("X_PROTECTION enabled=\(enabled) source=\(source)")
    }

    func setManualMode(_ mode: XMode, source: String) {
        manualMode = mode
        defaults?.set(mode.rawValue, forKey: Self.manualModeKey)
        AppDiagnosticsLogger.log("X_MODE mode=\(mode.rawValue) source=\(source)")
    }

    func setScheduled(_ scheduled: Bool, source: String) {
        guard isScheduled != scheduled else { return }
        isScheduled = scheduled
        applyShield()
        AppDiagnosticsLogger.log("X_SCHEDULE enabled=\(scheduled) source=\(source)")
    }

    func setFilteringHealth(_ health: XFilteringHealth) {
        guard filteringHealth != health else { return }
        filteringHealth = health
        AppDiagnosticsLogger.log("X_HEALTH status=\(health.rawValue)")
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        applyShield()
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refreshAuthorizationStatus()
    }

    func clearXData() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let xRecords = records.filter {
            let name = $0.displayName.lowercased()
            return name.contains("x.com") || name.contains("twitter")
                || name.contains("twimg") || name.contains("t.co")
        }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: xRecords) { continuation.resume() }
        }
        filteringHealth = .checking
    }

    func logOutX() async {
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        let store = WKWebsiteDataStore.default()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let xRecords = records.filter {
            let name = $0.displayName.lowercased()
            return name.contains("x.com") || name.contains("twitter")
        }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: xRecords) { continuation.resume() }
        }
        filteringHealth = .checking
    }

    func resetForAccountDeletion() {
        protectionEnabled = false
        manualMode = .clean
        isScheduled = false
        familySelection = FamilyActivitySelection()
        defaults?.removeObject(forKey: Self.protectionEnabledKey)
        defaults?.removeObject(forKey: Self.manualModeKey)
        defaults?.removeObject(forKey: Self.familySelectionKey)
        managedSettings.shield.applications = nil
    }

    static func loadProtectionEnabled(defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        if defaults.object(forKey: protectionEnabledKey) != nil {
            return defaults.bool(forKey: protectionEnabledKey)
        }

        for key in [NimaConstants.manualFeaturePolicyKey, NimaConstants.featurePolicyKey] {
            guard let data = defaults.data(forKey: key),
                  let policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
                continue
            }
            let enabled = policy.appToggles["x"]?["feed_block"] == true
                || policy.appToggles["x"]?["strict_feed_block"] == true
            defaults.set(enabled, forKey: protectionEnabledKey)
            return enabled
        }
        defaults.set(false, forKey: protectionEnabledKey)
        return false
    }

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(familySelection) else { return }
        defaults?.set(data, forKey: Self.familySelectionKey)
    }

    private func applyShield() {
        ClientShieldPolicy.reconcile(
            for: ClientShieldAppID.x.rawValue,
            defaults: defaults,
            selection: familySelection
        )
    }

    func refreshPauseMode() { applyShield() }
}
