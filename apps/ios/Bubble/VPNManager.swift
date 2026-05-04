import Foundation
import Combine
import NetworkExtension
import SwiftUI

@MainActor
final class VPNManager: ObservableObject {
    @Published var vpnStatus: NEVPNStatus = .disconnected
    @Published private(set) var statusLog: [String] = []
    @Published var tunnelLog: String = "(no diagnostic report yet)"

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var autoConnect = false
    private let sharedDefaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let reconnectMaxAttempts = 6
    private var previousVPNStatus: NEVPNStatus = .invalid
    private var reconnectBreakerLastSuppressed = false
    private var lastProbeReconnectAt: Date?
    private var lastResolvedStopClass = "unknown"

    deinit {
        reconnectTask?.cancel()
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    func setup() {
        appendLog("App launched")
        loadVPNPreferences()
    }

    // MARK: - Status Log (bounded)

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        statusLog.append(line)
        if statusLog.count > BubbleConstants.maxStatusLogEntries {
            statusLog.removeFirst(statusLog.count - BubbleConstants.maxStatusLogEntries)
        }
        AppDiagnosticsLogger.log(msg)
    }

    // MARK: - Tunnel Extension Log

    func refreshTunnelLog() {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BubbleConstants.appGroupID
        ) else {
            tunnelLog = "ERROR: Can't access app group container"
            appendLog("ERROR: No app group container")
            return
        }
        tunnelLog = buildDiagnosticReport(container: container)
    }

    // MARK: - VPN Lifecycle

    private func loadVPNPreferences() {
        appendLog("Loading VPN preferences...")
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    self.appendLog("ERROR loading prefs: \(error.localizedDescription)")
                    return
                }

                if let existingManagers = managers, !existingManagers.isEmpty {
                    let matchingManager = existingManagers.first { manager in
                        let providerBundleID = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
                            .providerBundleIdentifier
                        return providerBundleID == BubbleConstants.tunnelBundleID
                    }

                    guard let mgr = matchingManager else {
                        self.appendLog("Found \(existingManagers.count) VPN profile(s), but none match \(BubbleConstants.tunnelBundleID)")
                        self.appendLog("Creating a fresh profile for current extension ID")
                        self.createVPNProfile()
                        return
                    }

                    self.manager = mgr
                    self.vpnStatus = mgr.connection.status
                    self.appendLog("Found existing profile. Status: \(self.statusString)")
                    self.appendLog("Bundle ID: \((mgr.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ?? "nil")")
                    self.observeStatusChanges(for: mgr)
                    if self.autoConnect && mgr.connection.status != .connected && mgr.connection.status != .connecting {
                        self.startVPN()
                    }
                } else {
                    self.createVPNProfile()
                }
            }
        }
    }

    private func observeStatusChanges(for mgr: NETunnelProviderManager) {
        if let existing = statusObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: mgr.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let newStatus = mgr.connection.status
            let oldStatus = self.previousVPNStatus
            self.previousVPNStatus = newStatus
            self.vpnStatus = newStatus
            self.appendLog("VPN status \(Self.statusString(for: oldStatus)) -> \(self.statusString) (raw=\(newStatus.rawValue))")
            if newStatus == .disconnected {
                let connectedDate = mgr.connection.connectedDate?.ISO8601Format() ?? "nil"
                self.appendLog("Disconnect context connected_date=\(connectedDate) manager_enabled=\(mgr.isEnabled)")
            }
            self.handleStatusTransition(newStatus)

            if newStatus == .connected || newStatus == .disconnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.refreshTunnelLog()
                }
            }
        }
    }

    private func createVPNProfile() {
        appendLog("No VPN profile found, creating one...")
        let newManager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = BubbleConstants.tunnelBundleID
        proto.serverAddress = BubbleConstants.vpnServerAddress
        newManager.protocolConfiguration = proto
        newManager.localizedDescription = BubbleConstants.vpnDescription
        newManager.isEnabled = true

        newManager.saveToPreferences { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.appendLog("ERROR saving profile: \(error.localizedDescription)")
                    return
                }
                self.appendLog("Profile saved. Reloading...")
                self.loadVPNPreferences()
            }
        }
    }

    func toggleVPN() {
        guard let manager = self.manager else {
            appendLog("ERROR: Manager not ready")
            return
        }

        if manager.connection.status == .connected || manager.connection.status == .connecting {
            stopVPN(source: "settings.toggle_button")
        } else {
            startVPN(source: "settings.toggle_button")
        }
    }

    func startVPN(source: String = "unknown") {
        guard let manager = self.manager else {
            appendLog("ERROR: Manager not ready")
            return
        }
        setManualOffRequested(false)
        reconnectTask?.cancel()
        reconnectTask = nil

        appendLog("Starting VPN... source=\(source)")

        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.appendLog("ERROR loading: \(error.localizedDescription)")
                    return
                }

                manager.isEnabled = true
                manager.saveToPreferences { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if let error = error {
                            self.appendLog("ERROR saving: \(error.localizedDescription)")
                            return
                        }

                        manager.loadFromPreferences { [weak self] reloadError in
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                if let reloadError = reloadError {
                                    self.appendLog("ERROR reloading after save: \(reloadError.localizedDescription)")
                                    return
                                }

                                do {
                                    self.appendLog("Starting VPN tunnel... source=\(source)")
                                    try manager.connection.startVPNTunnel()
                                    self.appendLog("startVPNTunnel() called successfully")
                                } catch {
                                    let nsError = error as NSError
                                    self.appendLog("ERROR starting: \(error.localizedDescription)")
                                    self.appendLog("Error details: \(nsError.domain) code \(nsError.code)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func stopVPN(source: String = "unknown") {
        guard let manager = self.manager else {
            appendLog("ERROR: Manager not ready")
            return
        }
        setManualOffRequested(source == "settings.toggle_button")
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        appendLog("Stopping VPN tunnel... source=\(source)")
        manager.connection.stopVPNTunnel()
    }

    private func handleStatusTransition(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            reconnectAttempts = 0
            reconnectTask?.cancel()
            reconnectTask = nil
            recoverReconnectBreakerIfNeeded()
        case .disconnected:
            scheduleAutoReconnectForUnexpectedStop()
        default:
            break
        }
    }

    private func scheduleAutoReconnectForUnexpectedStop() {
        guard reconnectTask == nil else { return }
        guard reconnectAttempts < reconnectMaxAttempts else {
            appendLog("Auto-reconnect skipped: retry cap reached")
            return
        }
        var stopReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonKey) ?? "unknown"
        var stopSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSourceKey) ?? "unknown"
        var stopReasonRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonRawKey) ?? ""
        var unexpectedExit = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey) ?? false
        var inferredCrash = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleInferredCrashKey) ?? false
        let runningMarker = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleRunningMarkerKey) ?? false
        let lastHeartbeatTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        let stopResolution = resolveStopClassification(
            stopSource: stopSource,
            stopReason: stopReason,
            stopReasonRaw: stopReasonRaw,
            runningMarker: runningMarker,
            lastHeartbeatTS: lastHeartbeatTS
        )
        if stopResolution.didPersistFallback {
            stopSource = stopResolution.stopSource
            stopReason = stopResolution.stopReason
            stopReasonRaw = stopResolution.stopReasonRaw
            unexpectedExit = true
            inferredCrash = true
        }
        lastResolvedStopClass = stopResolution.resolvedClass.rawValue
        let pathStatus = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathStatusKey) ?? "unknown"
        let pathReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey) ?? "none"
        let pathInterfaces = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey) ?? "unknown"
        let pathExpensive = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey) ?? false
        let pathConstrained = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey) ?? false
        let pathTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey) ?? 0
        let sessionDurationSeconds = currentSessionDurationSeconds()
        let shortLivedSession = sessionDurationSeconds > 0 && sessionDurationSeconds < BubbleConstants.reconnectBreakerShortSessionSeconds
        let policyDesiredOn = shouldVPNBeOnFromPolicy()
        let expectedDisconnect = !policyDesiredOn || manualOffRequested
        let isCrashLikeStop = (stopSource == "tun2socks_exit" || stopSource == "cancelTunnelWithError" || stopSource == "inferred_crash") && (unexpectedExit || inferredCrash)
        appendLog(
            "Disconnect classified resolved_stop_class=\(stopResolution.resolvedClass.rawValue) expected_disconnect=\(expectedDisconnect) crash_like=\(isCrashLikeStop) short_lived_session=\(shortLivedSession) session_duration_seconds=\(Int(sessionDurationSeconds)) policy_desired_on=\(policyDesiredOn) manual_off_requested=\(manualOffRequested) source=\(stopSource) reason=\(stopReason) reason_raw=\(stopReasonRaw) unexpected_exit=\(unexpectedExit) inferred_crash=\(inferredCrash) path_status=\(pathStatus) path_reason=\(pathReason) path_interfaces=\(pathInterfaces) path_expensive=\(pathExpensive) path_constrained=\(pathConstrained) path_observed_at=\(formatUnixTS(pathTS))"
        )
        guard policyDesiredOn else {
            appendLog("Unexpected stop observed, but policy_desired_on=false. Skipping reconnect.")
            return
        }
        recordUnexpectedDisconnectAndTripBreakerIfNeeded(shortLivedSession: shortLivedSession)
        if let cooldownRemaining = reconnectBreakerRemainingCooldownSeconds(), cooldownRemaining > 0 {
            if !reconnectBreakerLastSuppressed {
                appendLog("Reconnect breaker tripped: healthy -> tripped -> cooldown (\(cooldownRemaining)s remaining)")
            } else {
                appendLog("Reconnect breaker cooldown active (\(cooldownRemaining)s remaining), skipping auto-reconnect")
            }
            incrementReconnectSuppressedByBreaker()
            reconnectBreakerLastSuppressed = true
            return
        }
        let transportDegraded = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleTransportDegradedKey) ?? false
        let transportDegradedReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleTransportDegradedReasonKey) ?? ""
        let transportDegradedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleTransportDegradedTSKey) ?? 0
        appendLog("Reconnect decision path resolved_stop_class=\(stopResolution.resolvedClass.rawValue) policy_desired_on=\(policyDesiredOn) expected_disconnect=\(expectedDisconnect) breaker_cooldown_active=\(reconnectBreakerRemainingCooldownSeconds() != nil) transport_degraded=\(transportDegraded) transport_reason=\(transportDegradedReason)")
        if transportDegraded && transportDegradedReason == "tripped_overload_guard" {
            if shouldScheduleProbeReconnect(lastTransportSignalTS: transportDegradedTS) {
                appendLog("Transport is tripped_overload_guard; scheduling bounded probe reconnect")
                scheduleProbeReconnect()
            } else {
                appendLog("Transport is tripped_overload_guard; suppressing auto-reconnect until recovered")
            }
            incrementReconnectSuppressedByBreaker()
            reconnectBreakerLastSuppressed = true
            return
        }
        reconnectBreakerLastSuppressed = false
        appendLog("Unexpected stop detected with policy_desired_on=true. Attempting reconnect...")

        reconnectAttempts += 1
        let backoffSeconds = reconnectAttemptBackoffSeconds()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                if self.vpnStatus == .disconnected && self.shouldVPNBeOnFromPolicy() {
                    self.appendLog("Auto-reconnect attempt \(self.reconnectAttempts)/\(self.reconnectMaxAttempts)")
                    self.startVPN(source: "auto_reconnect")
                }
            }
        }
    }

    private func shouldVPNBeOnFromPolicy() -> Bool {
        guard let data = sharedDefaults?.data(forKey: BubbleConstants.featurePolicyKey),
              let policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return false
        }
        let instagramOn = policy.appToggles["instagram"]?["reels"] == true
        let tiktokOn = policy.appToggles["tiktok"]?["video_block"] == true
        return instagramOn || tiktokOn
    }

    private var manualOffRequested: Bool {
        sharedDefaults?.bool(forKey: BubbleConstants.manualOffRequestedKey) ?? false
    }

    private func setManualOffRequested(_ value: Bool) {
        sharedDefaults?.set(value, forKey: BubbleConstants.manualOffRequestedKey)
    }

    private func reconnectBreakerRemainingCooldownSeconds(now: Date = Date()) -> Int? {
        let until = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey) ?? 0
        guard until > now.timeIntervalSince1970 else { return nil }
        return Int(ceil(until - now.timeIntervalSince1970))
    }

    private func recordUnexpectedDisconnectAndTripBreakerIfNeeded(shortLivedSession: Bool, now: Date = Date()) {
        guard shortLivedSession else { return }
        let scoreKey = BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey
        let stepKey = BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey
        let score = (sharedDefaults?.integer(forKey: scoreKey) ?? 0) + 1
        sharedDefaults?.set(score, forKey: scoreKey)
        guard score >= BubbleConstants.reconnectBreakerFailureScoreThreshold else { return }

        let oldStep = sharedDefaults?.integer(forKey: stepKey) ?? 0
        let nextStep = min(oldStep + 1, 6)
        sharedDefaults?.set(nextStep, forKey: stepKey)
        let exponential = BubbleConstants.reconnectBreakerBaseCooldownSeconds * pow(2.0, Double(max(0, nextStep - 1)))
        let capped = min(exponential, BubbleConstants.reconnectBreakerMaxCooldownSeconds)
        let jitter = capped * BubbleConstants.reconnectBreakerJitterFraction
        let cooldown = max(1.0, capped + Double.random(in: -jitter...jitter))
        let until = now.timeIntervalSince1970 + cooldown
        sharedDefaults?.set(until, forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        let trips = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey) ?? 0
        sharedDefaults?.set(trips + 1, forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey)
        appendLog("Reconnect breaker trip: short-lived failures score=\(score) backoff_step=\(nextStep) cooldown=\(Int(cooldown))s")
    }

    private func recoverReconnectBreakerIfNeeded(now: Date = Date()) {
        let sessionDuration = currentSessionDurationSeconds(now: now)
        if sessionDuration >= BubbleConstants.reconnectBreakerHealthySessionResetSeconds {
            sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
            sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey)
        }
        guard reconnectBreakerLastSuppressed || reconnectBreakerRemainingCooldownSeconds(now: now) != nil else { return }
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
        reconnectBreakerLastSuppressed = false
        appendLog("Reconnect breaker recovered: cooldown -> healthy")
    }

    private func reconnectAttemptBackoffSeconds() -> Double {
        let exp = min(reconnectAttempts - 1, 5)
        let base = min(60.0, pow(2.0, Double(exp)))
        let jitter = base * 0.25
        return max(1.0, base + Double.random(in: -jitter...jitter))
    }

    private func currentSessionDurationSeconds(now: Date = Date()) -> TimeInterval {
        let lastStartTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastStartTSKey) ?? 0
        guard lastStartTS > 0 else { return 0 }
        return max(0, now.timeIntervalSince1970 - lastStartTS)
    }

    private enum ResolvedStopClass: String {
        case cleanStop = "clean_stop"
        case inferredCrash = "inferred_crash"
        case transportDegraded = "transport_degraded"
        case unknown
    }

    private struct StopResolution {
        let resolvedClass: ResolvedStopClass
        let stopSource: String
        let stopReason: String
        let stopReasonRaw: String
        let didPersistFallback: Bool
    }

    private func resolveStopClassification(
        stopSource: String,
        stopReason: String,
        stopReasonRaw: String,
        runningMarker: Bool,
        lastHeartbeatTS: TimeInterval,
        now: Date = Date()
    ) -> StopResolution {
        if stopSource == "stopTunnel" {
            sharedDefaults?.set(ResolvedStopClass.cleanStop.rawValue, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
            return StopResolution(resolvedClass: .cleanStop, stopSource: stopSource, stopReason: stopReason, stopReasonRaw: stopReasonRaw, didPersistFallback: false)
        }
        if stopSource == "tun2socks_exit" || stopSource == "cancelTunnelWithError" || stopSource == "inferred_crash" {
            let inferredReason = stopReasonRaw.isEmpty ? "running_marker_unknown_stop" : stopReasonRaw
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey)
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleInferredCrashKey)
            sharedDefaults?.set(inferredReason, forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey)
            sharedDefaults?.set(ResolvedStopClass.inferredCrash.rawValue, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
            return StopResolution(resolvedClass: .inferredCrash, stopSource: stopSource, stopReason: stopReason, stopReasonRaw: inferredReason, didPersistFallback: false)
        }

        let heartbeatAge = lastHeartbeatTS > 0 ? now.timeIntervalSince1970 - lastHeartbeatTS : .greatestFiniteMagnitude
        if runningMarker && (stopSource == "unknown" || stopReason == "unknown") {
            let inferredReason = heartbeatAge >= BubbleConstants.lifecycleHeartbeatStaleSeconds
                ? "running_marker_stale_heartbeat"
                : "running_marker_unknown_stop"
            sharedDefaults?.set("inferred_crash", forKey: BubbleConstants.vpnLifecycleStopSourceKey)
            sharedDefaults?.set("inferred_crash_unknown_stop", forKey: BubbleConstants.vpnLifecycleStopReasonKey)
            sharedDefaults?.set(inferredReason, forKey: BubbleConstants.vpnLifecycleStopReasonRawKey)
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey)
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleInferredCrashKey)
            sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleRunningMarkerKey)
            sharedDefaults?.set(ResolvedStopClass.inferredCrash.rawValue, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
            sharedDefaults?.set(inferredReason, forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey)
            return StopResolution(
                resolvedClass: .inferredCrash,
                stopSource: "inferred_crash",
                stopReason: "inferred_crash_unknown_stop",
                stopReasonRaw: inferredReason,
                didPersistFallback: true
            )
        }

        sharedDefaults?.set(ResolvedStopClass.unknown.rawValue, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
        return StopResolution(resolvedClass: .unknown, stopSource: stopSource, stopReason: stopReason, stopReasonRaw: stopReasonRaw, didPersistFallback: false)
    }

    private func incrementReconnectSuppressedByBreaker() {
        let key = BubbleConstants.vpnLifecycleReconnectSuppressedByBreakerKey
        let current = sharedDefaults?.integer(forKey: key) ?? 0
        sharedDefaults?.set(current + 1, forKey: key)
    }

    private func shouldScheduleProbeReconnect(lastTransportSignalTS: TimeInterval) -> Bool {
        if reconnectTask != nil {
            return false
        }
        if let lastProbeReconnectAt,
           Date().timeIntervalSince(lastProbeReconnectAt) < BubbleConstants.transportProbeReconnectMinIntervalSeconds {
            return false
        }
        if lastTransportSignalTS > 0 {
            let signalAge = Date().timeIntervalSince1970 - lastTransportSignalTS
            if signalAge < BubbleConstants.transportProbeReconnectDelaySeconds {
                return false
            }
        }
        return shouldVPNBeOnFromPolicy() && vpnStatus == .disconnected
    }

    private func scheduleProbeReconnect() {
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(BubbleConstants.transportProbeReconnectDelaySeconds * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                guard self.vpnStatus == .disconnected, self.shouldVPNBeOnFromPolicy() else { return }
                self.lastProbeReconnectAt = Date()
                self.appendLog("Probe reconnect attempt after transport trip")
                self.startVPN(source: "probe_reconnect")
            }
        }
    }

    private func buildDiagnosticReport(container: URL) -> String {
        let tunnelFileURL = container.appendingPathComponent(BubbleConstants.logFileName)
        let statsFileURL = container.appendingPathComponent(BubbleConstants.statsFileName)

        let tunnelContent = (try? String(contentsOf: tunnelFileURL, encoding: .utf8)) ?? "(no extension logs found at \(tunnelFileURL.path))"
        let appContent = AppDiagnosticsLogger.readLog()
        let lifecycleSummary = renderLifecycleSummary()
        let policySummary = renderPolicySummary()
        let statsSummary = renderTrafficSummary(statsFileURL: statsFileURL)

        return [
            "=== DIAGNOSTIC REPORT ===",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "What this means:",
            "This report combines app decisions, VPN lifecycle state, traffic stats, and raw tunnel output in one place.",
            "",
            "=== LIFECYCLE ===",
            lifecycleSummary,
            "",
            "=== FEATURE POLICY ===",
            policySummary,
            "",
            "=== TRAFFIC SNAPSHOT ===",
            statsSummary,
            "",
            "=== APP DIAGNOSTIC LOG ===",
            appContent,
            "",
            "=== TUNNEL LOG ===",
            tunnelContent
        ].joined(separator: "\n")
    }

    private func renderLifecycleSummary() -> String {
        let lastStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastStartTSKey) ?? 0
        let lastStop = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastStopTSKey) ?? 0
        let lastHeartbeat = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        let stopReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonKey) ?? "unknown"
        let stopSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSourceKey) ?? "unknown"
        let stopReasonRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonRawKey) ?? ""
        let unexpectedExit = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey) ?? false
        let inferredCrash = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleInferredCrashKey) ?? false
        let runningMarker = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleRunningMarkerKey) ?? false
        let resolvedStopClass = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey) ?? lastResolvedStopClass
        let inferredCrashReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey) ?? ""
        let lastExitCode = sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleLastExitCodeKey) as? Int
        let heartbeatAge = lastHeartbeat > 0 ? Int(Date().timeIntervalSince1970 - lastHeartbeat) : -1
        let pathStatus = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathStatusKey) ?? "unknown"
        let pathReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey) ?? "none"
        let pathInterfaces = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey) ?? "unknown"
        let pathExpensive = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey) ?? false
        let pathConstrained = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey) ?? false
        let pathUpdate = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey) ?? 0
        let reconnectSuppressedByBreaker = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectSuppressedByBreakerKey) ?? 0

        return [
            "status=\(statusString)",
            "tunnel_operational=\(vpnStatus == .connected)",
            "policy_enabled=\(shouldVPNBeOnFromPolicy())",
            "manual_off_requested=\(manualOffRequested)",
            "last_start=\(formatUnixTS(lastStart))",
            "last_stop=\(formatUnixTS(lastStop))",
            "last_stop_source=\(stopSource)",
            "last_stop_reason=\(stopReason)",
            "last_stop_reason_raw=\(stopReasonRaw)",
            "unexpected_exit=\(unexpectedExit)",
            "inferred_crash=\(inferredCrash)",
            "resolved_stop_class=\(resolvedStopClass)",
            "inferred_crash_reason=\(inferredCrashReason)",
            "running_marker=\(runningMarker)",
            "last_exit_code=\(lastExitCode.map(String.init) ?? "nil")",
            "last_heartbeat=\(formatUnixTS(lastHeartbeat))",
            "heartbeat_age_seconds=\(heartbeatAge >= 0 ? String(heartbeatAge) : "unknown")",
            "last_path_status=\(pathStatus)",
            "last_path_unsatisfied_reason=\(pathReason)",
            "last_path_interfaces=\(pathInterfaces)",
            "last_path_is_expensive=\(pathExpensive)",
            "last_path_is_constrained=\(pathConstrained)",
            "last_path_updated_at=\(formatUnixTS(pathUpdate))",
            "reconnect_suppressed_by_breaker=\(reconnectSuppressedByBreaker)"
        ].joined(separator: "\n")
    }

    private func renderPolicySummary() -> String {
        guard let data = sharedDefaults?.data(forKey: BubbleConstants.featurePolicyKey),
              let policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return "featurePolicyV1 missing"
        }

        return [
            "revision=\(policy.revision)",
            "updated_by=\(policy.updatedBy)",
            "updated_at=\(formatUnixTS(policy.updatedAt))",
            "toggles=\(policy.appToggles)"
        ].joined(separator: "\n")
    }

    private func renderTrafficSummary(statsFileURL: URL) -> String {
        guard let data = try? Data(contentsOf: statsFileURL),
              let trafficData = try? JSONDecoder().decode(TrafficData.self, from: data),
              let snapshot = trafficData.snapshots.last else {
            return "traffic stats unavailable"
        }

        let stats = snapshot.stats
        return [
            "snapshot_at=\(snapshot.timestamp.ISO8601Format())",
            "total_conns=\(stats.totalConns)",
            "tcp_allowed=\(stats.tcpAllowed)",
            "tcp_blocked=\(stats.tcpBlocked)",
            "udp_relayed=\(stats.udpRelayed)",
            "udp_active=\(stats.udpActiveStreams)",
            "udp_opened=\(stats.udpStreamsOpened)",
            "udp_closed=\(stats.udpStreamsClosed)",
            "udp_peak=\(stats.udpActivePeak)",
            "udp_timeout_rate=\(String(format: "%.2f", stats.udpTimeoutRate))",
            "bad_len_rate=\(String(format: "%.2f", stats.badLenRate))",
            "recent_bad_len_hard_fails=\(stats.recentBadLenHardFails)",
            "decoder_error_rate=\(String(format: "%.2f", stats.decoderErrorRate))",
            "dns_inflight=\(stats.dnsInflight)",
            "reconnect_suppressed_by_breaker=\(stats.reconnectSuppressedByBreaker)",
            "reconnect_breaker_backoff_step=\(stats.reconnectBreakerBackoffStep)",
            "storm_mode_active_seconds=\(Int(stats.stormModeActiveSeconds))",
            "maintenance_reclaim_budget_exhausted=\(stats.maintenanceReclaimBudgetExhaustedCount)",
            "dns_reserved_slots_in_use=\(stats.dnsReservedSlotsInUse)",
            "decoder_soft_discards=\(stats.decoderSoftDiscards)",
            "decoder_error_density_closes=\(stats.decoderErrorDensityCloses)",
            "close_reasons=\(stats.streamCloseReasonCounts)"
        ].joined(separator: "\n")
    }

    private func formatUnixTS(_ value: TimeInterval) -> String {
        guard value > 0 else { return "unknown" }
        return Date(timeIntervalSince1970: value).ISO8601Format()
    }

    // MARK: - Display Helpers

    var statusString: String {
        Self.statusString(for: vpnStatus)
    }

    static func statusString(for status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reasserting: return "Reasserting..."
        case .disconnecting: return "Disconnecting..."
        @unknown default: return "Unknown"
        }
    }

    static func statusColor(for status: NEVPNStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting, .reasserting: return .orange
        case .disconnecting: return .yellow
        default: return .red
        }
    }
}
