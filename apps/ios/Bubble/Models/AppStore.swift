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
    @ObservationIgnored private var vpnStopHandler: (() -> Void)?
    @ObservationIgnored private var vpnStatusProvider: (() -> NEVPNStatus)?
    @ObservationIgnored private var vpnStartInFlight = false
    @ObservationIgnored private var vpnStopInFlight = false
    @ObservationIgnored private var pendingVPNStopTask: Task<Void, Never>?
    @ObservationIgnored private var pendingVPNStopToken = UUID()
    @ObservationIgnored private var pendingVPNStopAt: Date?
    @ObservationIgnored private let vpnStopDelayNanoseconds: UInt64 = 10_000_000_000

    init() {
        refreshFromOptionsService()
    }

    func app(for id: String) -> BlockedApp? {
        apps.first { $0.id == id }
    }

    func toggleOption(appId: String, optionId: String) {
        optionsService.toggleOption(appId: appId, optionId: optionId)
        refreshFromOptionsService()
        syncVPNAfterToggle()
    }

    func configureVPNAutostart(startVPN: @escaping () -> Void, stopVPN: @escaping () -> Void, vpnStatus: @escaping () -> NEVPNStatus) {
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

    private func syncVPNAfterToggle() {
        guard let vpnStartHandler, let vpnStopHandler, let vpnStatusProvider else { return }
        let status = vpnStatusProvider()
        let isConnectedLike = status == .connected || status == .connecting || status == .reasserting
        let isDisconnecting = status == .disconnecting

        if hasAnyEnabledBlockingOption {
            cancelPendingVPNStop()
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

        guard isConnectedLike || isDisconnecting else {
            cancelPendingVPNStop()
            return
        }
        scheduleDelayedVPNStop(vpnStopHandler: vpnStopHandler, vpnStatusProvider: vpnStatusProvider)
    }

    private func scheduleDelayedVPNStop(vpnStopHandler: @escaping () -> Void, vpnStatusProvider: @escaping () -> NEVPNStatus) {
        if pendingVPNStopTask != nil {
            return
        }
        let token = UUID()
        pendingVPNStopToken = token
        pendingVPNStopAt = Date().addingTimeInterval(Double(vpnStopDelayNanoseconds) / 1_000_000_000.0)
        pendingVPNStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.vpnStopDelayNanoseconds ?? 0)
            await MainActor.run {
                guard let self else { return }
                guard self.pendingVPNStopToken == token else { return }
                self.pendingVPNStopTask = nil
                self.pendingVPNStopAt = nil
                guard !self.hasAnyEnabledBlockingOption else { return }
                let status = vpnStatusProvider()
                if status == .disconnecting || status == .disconnected || status == .invalid {
                    return
                }
                guard !self.vpnStopInFlight else { return }
                self.vpnStopInFlight = true
                self.vpnStartInFlight = false
                vpnStopHandler()
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        self.vpnStopInFlight = false
                    }
                }
            }
        }
    }

    private func cancelPendingVPNStop() {
        pendingVPNStopToken = UUID()
        pendingVPNStopTask?.cancel()
        pendingVPNStopTask = nil
        pendingVPNStopAt = nil
    }

    private var hasAnyEnabledBlockingOption: Bool {
        apps.contains { app in
            app.options.contains { $0.isEnabled }
        }
    }
}
