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
    @ObservationIgnored private var vpnStartHandler: (() -> Void)?
    @ObservationIgnored private var vpnStopHandler: (() -> Void)?
    @ObservationIgnored private var vpnStatusProvider: (() -> NEVPNStatus)?
    @ObservationIgnored private var streakEligibilityHandler: ((String) -> Void)?
    @ObservationIgnored private var vpnStartInFlight = false
    @ObservationIgnored private var vpnStopInFlight = false
    @ObservationIgnored private var pendingVPNSyncTask: Task<Void, Never>?
    @ObservationIgnored private let sharedDefaults = UserDefaults(suiteName: BubbleConstants.appGroupID)

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
        startVPN: @escaping () -> Void,
        stopVPN: @escaping () -> Void,
        vpnStatus: @escaping () -> NEVPNStatus,
        markStreakIfEligible: @escaping (String) -> Void = { _ in }
    ) {
        vpnStartHandler = startVPN
        vpnStopHandler = stopVPN
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
        pendingVPNSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                self?.reconcileVPNState(triggerSource: triggerSource)
            }
        }
    }

    private func reconcileVPNState(triggerSource: String) {
        guard let vpnStartHandler, let vpnStopHandler, let vpnStatusProvider else { return }
        let status = vpnStatusProvider()
        let isConnectedLike = status == .connected || status == .connecting || status == .reasserting
        let shouldVPNBeOn = shouldVPNBeOnFromPolicy()

        if shouldVPNBeOn {
            if isConnectedLike {
                streakEligibilityHandler?(triggerSource)
            }
            AppDiagnosticsLogger.log(
                "VPN_SYNC action=converge_on status=\(status.rawValue) should_vpn_be_on=true source=\(triggerSource)"
            )
            guard !isConnectedLike, !vpnStartInFlight else { return }
            vpnStartInFlight = true
            vpnStopInFlight = false
            vpnStartHandler()
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    vpnStartInFlight = false
                }
            }
            return
        }

        AppDiagnosticsLogger.log(
            "VPN_SYNC action=converge_off status=\(status.rawValue) should_vpn_be_on=false source=\(triggerSource)"
        )
        let isDisconnectedLike = status == .disconnected || status == .disconnecting || status == .invalid
        guard !isDisconnectedLike, !vpnStopInFlight else { return }
        vpnStopInFlight = true
        vpnStartInFlight = false
        vpnStopHandler()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.vpnStopInFlight = false
            }
        }
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
