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
                BlockingOption(id: "reels", label: "reels", isEnabled: false)
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
    @ObservationIgnored private var vpnStartInFlight = false
    @ObservationIgnored private var vpnStopInFlight = false
    @ObservationIgnored private var pendingVPNSyncTask: Task<Void, Never>?

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

    func configureVPNAutostart(startVPN: @escaping () -> Void, stopVPN: @escaping () -> Void, vpnStatus: @escaping () -> NEVPNStatus) {
        vpnStartHandler = startVPN
        vpnStopHandler = stopVPN
        vpnStatusProvider = vpnStatus
        scheduleVPNReconciliation(triggerSource: "app_store.configure")
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
        let shouldVPNBeOn = hasAnyEnabledBlockingOption

        if shouldVPNBeOn {
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

    private var hasAnyEnabledBlockingOption: Bool {
        apps.contains { app in
            app.options.contains { $0.isEnabled }
        }
    }
}
