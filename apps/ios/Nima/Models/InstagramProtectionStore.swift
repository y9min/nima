import FamilyControls
import Foundation
import ManagedSettings
import Observation
import WebKit

enum InstagramShieldStatus: Equatable {
    case unavailable
    case permissionRequired
    case selectionRequired
    case unprotected
    case protected

    var title: String {
        switch self {
        case .unavailable: return "Screen Time unavailable"
        case .permissionRequired: return "Permission required"
        case .selectionRequired: return "Select Instagram"
        case .unprotected: return "Official app not protected"
        case .protected: return "Official app protected"
        }
    }
}

@MainActor
@Observable
final class InstagramProtectionStore {
    static let protectionEnabledKey = "instagram.client.protection_enabled"
    static let manualModeKey = "instagram.client.manual_mode"
    static let familySelectionKey = NimaConstants.instagramFamilySelectionKey

    var protectionEnabled: Bool
    var manualMode: InstagramMode
    private(set) var scheduledMode: InstagramMode?
    private(set) var filteringHealth: InstagramFilteringHealth = .checking
    private(set) var authorizationStatus: AuthorizationStatus
    var familySelection: FamilyActivitySelection {
        didSet {
            persistSelection()
            applyShield()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let managedSettings = ManagedSettingsStore(named: .init("nima.instagram"))

    init(defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)) {
        self.defaults = defaults
        let loadedProtectionEnabled: Bool
        if defaults?.object(forKey: Self.protectionEnabledKey) != nil {
            loadedProtectionEnabled = defaults?.bool(forKey: Self.protectionEnabledKey) ?? false
        } else if let data = defaults?.data(forKey: NimaConstants.manualFeaturePolicyKey),
                  let legacyPolicy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) {
            loadedProtectionEnabled = legacyPolicy.appToggles["instagram"]?["strict_reels"] == true
                || legacyPolicy.appToggles["instagram"]?["reels"] == true
            defaults?.set(loadedProtectionEnabled, forKey: Self.protectionEnabledKey)
        } else {
            loadedProtectionEnabled = false
        }
        protectionEnabled = loadedProtectionEnabled
        manualMode = InstagramMode(
            rawValue: defaults?.string(forKey: Self.manualModeKey) ?? ""
        ) ?? .clean
        if let data = defaults?.data(forKey: Self.familySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            familySelection = selection
        } else {
            familySelection = FamilyActivitySelection()
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        applyShield()
    }

    var effectiveMode: InstagramMode {
        if scheduledMode == .dmOnly { return .dmOnly }
        if filteringHealth == .limited { return .dmOnly }
        return scheduledMode ?? manualMode
    }

    var shieldStatus: InstagramShieldStatus {
        guard authorizationStatus == .approved else {
            return authorizationStatus == .denied ? .unavailable : .permissionRequired
        }
        guard !familySelection.applicationTokens.isEmpty else { return .selectionRequired }
        return (protectionEnabled || scheduledMode != nil) ? .protected : .unprotected
    }

    func setProtectionEnabled(_ enabled: Bool, source: String) {
        protectionEnabled = enabled
        defaults?.set(enabled, forKey: Self.protectionEnabledKey)
        if enabled {
            manualMode = .clean
            defaults?.set(InstagramMode.clean.rawValue, forKey: Self.manualModeKey)
        }
        applyShield()
        AppDiagnosticsLogger.log(
            "INSTAGRAM_PROTECTION enabled=\(enabled) mode=\(effectiveMode.rawValue) source=\(source)"
        )
    }

    func setManualMode(_ mode: InstagramMode, source: String) {
        manualMode = mode
        defaults?.set(mode.rawValue, forKey: Self.manualModeKey)
        AppDiagnosticsLogger.log("INSTAGRAM_MODE mode=\(mode.rawValue) source=\(source)")
    }

    func setScheduledMode(_ mode: InstagramMode?, source: String) {
        guard scheduledMode != mode else { return }
        scheduledMode = mode
        applyShield()
        AppDiagnosticsLogger.log(
            "INSTAGRAM_SCHEDULE mode=\(mode?.rawValue ?? "none") source=\(source)"
        )
    }

    func setFilteringHealth(_ health: InstagramFilteringHealth) {
        filteringHealth = health
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        applyShield()
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refreshAuthorizationStatus()
    }

    func clearInstagramData() async {
        await removeInstagramData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        filteringHealth = .checking
    }

    func logOutInstagram() async {
        await removeInstagramData(ofTypes: [WKWebsiteDataTypeCookies])
        filteringHealth = .checking
    }

    private func removeInstagramData(ofTypes types: Set<String>) async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: types)
        let instagramRecords = records.filter { record in
            let name = record.displayName.lowercased()
            return name.contains("instagram") || name.contains("facebook") || name.contains("meta")
        }
        await store.removeData(ofTypes: types, for: instagramRecords)
    }

    func resetForAccountDeletion() {
        protectionEnabled = false
        manualMode = .clean
        scheduledMode = nil
        familySelection = FamilyActivitySelection()
        defaults?.removeObject(forKey: Self.protectionEnabledKey)
        defaults?.removeObject(forKey: Self.manualModeKey)
        defaults?.removeObject(forKey: Self.familySelectionKey)
        managedSettings.shield.applications = nil
    }

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(familySelection) else { return }
        defaults?.set(data, forKey: Self.familySelectionKey)
    }

    private func applyShield() {
        let scheduleRequiresProtection = scheduledMode != nil
        guard authorizationStatus == .approved,
              protectionEnabled || scheduleRequiresProtection,
              !familySelection.applicationTokens.isEmpty else {
            managedSettings.shield.applications = nil
            return
        }
        managedSettings.shield.applications = familySelection.applicationTokens
    }
}

private extension WKWebsiteDataStore {
    func dataRecords(ofTypes types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
    }

    func removeData(ofTypes types: Set<String>, for records: [WKWebsiteDataRecord]) async {
        await withCheckedContinuation { continuation in
            removeData(ofTypes: types, for: records) { continuation.resume() }
        }
    }
}
