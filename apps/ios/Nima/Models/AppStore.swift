import Foundation
import Observation
import NetworkExtension

@Observable
final class AppStore {
    var apps: [BlockedApp] = [
        BlockedApp(
            id: "instagram",
            name: "INSTAGRAM",
            iconName: "camera.fill",
            platform: "instagram",
            options: [
                BlockingOption(id: "strict_reels", label: "reels", isEnabled: false)
            ]
        ),
        BlockedApp(
            id: "tiktok",
            name: "TIKTOK",
            iconName: "music.note",
            platform: "tiktok",
            options: [
                BlockingOption(id: "video_block", label: "video_block", isEnabled: false)
            ]
        )
    ]

    private let optionsService = AppOptionsService.shared
    @ObservationIgnored private var vpnReconcileHandler: ((ProtectionIntent) async -> Void)?
    @ObservationIgnored private var vpnStatusProvider: (() -> NEVPNStatus)?
    @ObservationIgnored private var streakEligibilityHandler: ((String) -> Void)?
    @ObservationIgnored private var pendingVPNSyncTask: Task<Void, Never>?
    @ObservationIgnored private let sharedDefaults = UserDefaults(suiteName: NimaConstants.appGroupID)
    @ObservationIgnored private var protectionIntentRevision = Int(Date().timeIntervalSince1970 * 1_000)

    init() {
        refreshFromOptionsService()
    }

    func app(for id: String) -> BlockedApp? {
        apps.first { $0.id == id }
    }

    func toggleOption(appId: String, optionId: String, source: String = "unknown") {
        optionsService.toggleOption(appId: appId, optionId: optionId, source: source)
        refreshFromOptionsService()
        scheduleVPNReconciliation(triggerSource: source)
    }

    func setScheduledBlockedAppIDs(_ appIDs: Set<String>, source: String = "time_windows") {
        let didChange = optionsService.setScheduledBlockedAppIDs(appIDs, source: source)
        refreshFromOptionsService()
        if didChange {
            scheduleVPNReconciliation(triggerSource: source)
        }
    }

    func isAppScheduled(_ appId: String) -> Bool {
        optionsService.isAppScheduled(appId)
    }

    func configureVPNAutostart(
        reconcileProtection: @escaping (ProtectionIntent) async -> Void,
        vpnStatus: @escaping () -> NEVPNStatus,
        markStreakIfEligible: @escaping (String) -> Void = { _ in }
    ) {
        vpnReconcileHandler = reconcileProtection
        vpnStatusProvider = vpnStatus
        streakEligibilityHandler = markStreakIfEligible
        scheduleVPNReconciliation(triggerSource: "app_store.configure")
    }

    func syncVPNState(source: String = "app_store.sync") {
        refreshFromOptionsService()
        scheduleVPNReconciliation(triggerSource: source)
    }

    func resetAllBlockingOptions(source: String = "app_store.reset") {
        optionsService.resetAllOptions(source: source)
        refreshFromOptionsService()
        scheduleVPNReconciliation(triggerSource: source)
    }

    func disableAllManualBlockingOptions(source: String) {
        optionsService.disableAllManualOptions(source: source)
        refreshFromOptionsService()
        scheduleVPNReconciliation(triggerSource: source)
    }

    private func refreshFromOptionsService() {
        for appIndex in apps.indices {
            let appId = apps[appIndex].id
            for optIndex in apps[appIndex].options.indices {
                let optId = apps[appIndex].options[optIndex].id
                apps[appIndex].options[optIndex].isEnabled = optionsService.isOptionSelected(appId: appId, optionId: optId)
            }
        }
    }

    private func scheduleVPNReconciliation(triggerSource: String) {
        pendingVPNSyncTask?.cancel()
        pendingVPNSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.reconcileVPNState(triggerSource: triggerSource)
        }
    }

    private func reconcileVPNState(triggerSource: String) {
        guard let vpnReconcileHandler, let vpnStatusProvider else { return }
        let status = vpnStatusProvider()
        let isConnectedLike = status == .connected || status == .connecting || status == .reasserting
        let manualRecoveryRequired = hasAnyManuallyEnabledBlockingOption
        let shouldVPNBeOn = shouldVPNBeOnFromPolicy()
        protectionIntentRevision = max(
            protectionIntentRevision + 1,
            Int(Date().timeIntervalSince1970 * 1_000)
        )
        let intent = ProtectionIntent(
            vpnRequired: shouldVPNBeOn,
            manualRecoveryRequired: manualRecoveryRequired,
            source: triggerSource,
            revision: protectionIntentRevision
        )

        if shouldVPNBeOn {
            if isConnectedLike {
                streakEligibilityHandler?(triggerSource)
            }
            AppDiagnosticsLogger.log(
                "VPN_SYNC action=converge_on status=\(status.rawValue) should_vpn_be_on=true source=\(triggerSource)"
            )
            Task { await vpnReconcileHandler(intent) }
            return
        }

        AppDiagnosticsLogger.log(
            "VPN_SYNC action=converge_off status=\(status.rawValue) should_vpn_be_on=false source=\(triggerSource)"
        )
        Task { await vpnReconcileHandler(intent) }
    }

    var hasAnyEnabledBlockingOption: Bool {
        optionsService.hasAnyEnabledBlockingOption
    }

    var hasAnyManuallyEnabledBlockingOption: Bool {
        optionsService.hasAnyManuallyEnabledBlockingOption
    }

    var firstEnabledBlockerSource: String? {
        optionsService.firstEnabledBlockerSource
    }

    private func shouldVPNBeOnFromPolicy(now: Date = Date()) -> Bool {
        hasAnyManuallyEnabledBlockingOption ||
            ScheduledProtectionStateStore.snapshot(defaults: sharedDefaults).isDesiredProtectionActive(now: now)
    }
}
