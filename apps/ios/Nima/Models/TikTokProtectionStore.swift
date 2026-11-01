import FamilyControls
import Foundation
import ManagedSettings
import Observation
import WebKit

enum TikTokShieldStatus: Equatable {
    case permissionRequired
    case selectionRequired
    case unprotected
    case protected
}

@MainActor
@Observable
final class TikTokProtectionStore {
    static let protectionEnabledKey = NimaConstants.tiktokProtectionEnabledKey
    static let manualModeKey = "tiktok.client.manual_mode"
    static let familySelectionKey = NimaConstants.tiktokFamilySelectionKey

    var protectionEnabled: Bool
    var manualMode: TikTokMode
    private(set) var isScheduled = false
    private(set) var filteringHealth: TikTokFilteringHealth = .checking
    private(set) var authorizationStatus: AuthorizationStatus
    var familySelection: FamilyActivitySelection {
        didSet {
            persistSelection()
            applyShield()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let managedSettings = ManagedSettingsStore(named: .init("nima.tiktok"))

    init(defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)) {
        self.defaults = defaults
        protectionEnabled = defaults?.bool(forKey: Self.protectionEnabledKey) ?? false
        manualMode = TikTokMode(rawValue: defaults?.string(forKey: Self.manualModeKey) ?? "") ?? .clean
        if let data = defaults?.data(forKey: Self.familySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            familySelection = selection
        } else if let connected = ScreenTimeAppConnections.load(defaults: defaults).selection(for: "tiktok") {
            familySelection = connected
            // Existing guided-onboarding connections predate the dedicated TikTok
            // store. Copy the selection so the shield extension can identify which
            // controlled client to open.
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
            "tiktok",
            scheduled: isScheduled,
            defaults: defaults
        )
    }

    var effectiveMode: TikTokMode {
        filteringHealth == .limited ? .dmOnly : manualMode
    }

    var shieldStatus: TikTokShieldStatus {
        guard authorizationStatus == .approved else { return .permissionRequired }
        guard !familySelection.applicationTokens.isEmpty else { return .selectionRequired }
        return isActive ? .protected : .unprotected
    }

    func setProtectionEnabled(_ enabled: Bool, source: String) {
        if enabled {
            PauseModeState.exclude("tiktok", defaults: defaults)
            HardModeProtectionState.markProtectionOn("tiktok", defaults: defaults)
        }
        protectionEnabled = enabled
        defaults?.set(enabled, forKey: Self.protectionEnabledKey)
        applyShield()
        AppDiagnosticsLogger.log("TIKTOK_PROTECTION enabled=\(enabled) source=\(source)")
    }

    func setManualMode(_ mode: TikTokMode, source: String) {
        manualMode = mode
        defaults?.set(mode.rawValue, forKey: Self.manualModeKey)
        AppDiagnosticsLogger.log("TIKTOK_MODE mode=\(mode.rawValue) source=\(source)")
    }

    func setScheduled(_ scheduled: Bool, source: String) {
        guard isScheduled != scheduled else { return }
        isScheduled = scheduled
        applyShield()
        AppDiagnosticsLogger.log("TIKTOK_SCHEDULE enabled=\(scheduled) source=\(source)")
    }

    func setFilteringHealth(_ health: TikTokFilteringHealth) {
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

    func clearTikTokData() async {
        await removeTikTokData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        filteringHealth = .checking
    }

    func logOutTikTok() async {
        await removeTikTokData(ofTypes: [WKWebsiteDataTypeCookies])
        filteringHealth = .checking
    }

    private func removeTikTokData(ofTypes types: Set<String>) async {
        let store = WKWebsiteDataStore.default()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
        let tiktokRecords = records.filter {
            let name = $0.displayName.lowercased()
            return name.contains("tiktok") || name.contains("byteoversea") || name.contains("tiktokv")
        }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: tiktokRecords) { continuation.resume() }
        }
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

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(familySelection) else { return }
        defaults?.set(data, forKey: Self.familySelectionKey)
    }

    private func applyShield() {
        ClientShieldPolicy.reconcile(
            for: ClientShieldAppID.tiktok.rawValue,
            defaults: defaults,
            selection: familySelection
        )
    }

    func refreshPauseMode() { applyShield() }
}
