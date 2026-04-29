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
            id: "facebook",
            name: "FACEBOOK",
            iconName: "shield.fill",
            platform: "facebook",
            options: [
                BlockingOption(id: "reels", label: "reels", isEnabled: false)
            ]
        )
    ]

    private let optionsService = AppOptionsService.shared
    @ObservationIgnored private var vpnStartHandler: (() -> Void)?
    @ObservationIgnored private var vpnStopHandler: (() -> Void)?
    @ObservationIgnored private var vpnStatusProvider: (() -> NEVPNStatus)?
    @ObservationIgnored private var vpnStartInFlight = false
    @ObservationIgnored private var pendingVPNStopTask: Task<Void, Never>?
    @ObservationIgnored private let vpnAutoStopDebounceNanoseconds: UInt64 = 10_000_000_000

    init() {
        refreshFromOptionsService()
    }

    func app(for id: String) -> BlockedApp? {
        apps.first { $0.id == id }
    }

    func toggleOption(appId: String, optionId: String) {
        optionsService.toggleOption(appId: appId, optionId: optionId)
        refreshFromOptionsService()
        maybeAutoManageVPNAfterToggle()
    }

    func configureVPNAutostart(
        startVPN: @escaping () -> Void,
        stopVPN: @escaping () -> Void,
        vpnStatus: @escaping () -> NEVPNStatus
    ) {
        vpnStartHandler = startVPN
        vpnStopHandler = stopVPN
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

    private func maybeAutoManageVPNAfterToggle() {
        if hasAnyEnabledBlockingOption {
            pendingVPNStopTask?.cancel()
            pendingVPNStopTask = nil
            maybeAutoStartVPNAfterToggle()
            return
        }
        scheduleAutoStopVPNAfterDebounce()
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

    private func scheduleAutoStopVPNAfterDebounce() {
        guard let vpnStopHandler, let vpnStatusProvider else { return }
        pendingVPNStopTask?.cancel()

        pendingVPNStopTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: vpnAutoStopDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !self.hasAnyEnabledBlockingOption else {
                    self.pendingVPNStopTask = nil
                    return
                }

                let status = vpnStatusProvider()
                let shouldStop = status == .connected || status == .connecting || status == .reasserting
                if shouldStop {
                    self.vpnStartInFlight = false
                    vpnStopHandler()
                }
                self.pendingVPNStopTask = nil
            }
        }
    }

    private var hasAnyEnabledBlockingOption: Bool {
        apps.contains { app in
            app.options.contains { $0.isEnabled }
        }
    }
}
