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
        )
    ]

    private let optionsService = AppOptionsService.shared
    @ObservationIgnored private var vpnStartHandler: (() -> Void)?
    @ObservationIgnored private var vpnStatusProvider: (() -> NEVPNStatus)?
    @ObservationIgnored private var vpnStartInFlight = false

    init() {
        refreshFromOptionsService()
    }

    func app(for id: String) -> BlockedApp? {
        apps.first { $0.id == id }
    }

    func toggleOption(appId: String, optionId: String) {
        optionsService.toggleOption(appId: appId, optionId: optionId)
        refreshFromOptionsService()
        maybeAutoStartVPNAfterToggle()
    }

    func configureVPNAutostart(startVPN: @escaping () -> Void, vpnStatus: @escaping () -> NEVPNStatus) {
        vpnStartHandler = startVPN
        vpnStatusProvider = vpnStatus
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

    private func maybeAutoStartVPNAfterToggle() {
        guard hasAnyEnabledBlockingOption else { return }
        guard let vpnStartHandler, let vpnStatusProvider else { return }

        let status = vpnStatusProvider()
        let isAlreadyConnected = status == .connected || status == .connecting || status == .reasserting
        if isAlreadyConnected || vpnStartInFlight {
            return
        }

        vpnStartInFlight = true
        vpnStartHandler()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                let latestStatus = vpnStatusProvider()
                let stillConnecting = latestStatus == .connected || latestStatus == .connecting || latestStatus == .reasserting
                if !stillConnecting {
                    vpnStartInFlight = false
                }
            }
        }
    }

    private var hasAnyEnabledBlockingOption: Bool {
        apps.contains { app in
            app.options.contains { $0.isEnabled }
        }
    }
}
