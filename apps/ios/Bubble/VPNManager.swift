import Foundation
import Combine
import NetworkExtension
import SwiftUI
import UIKit

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
    private let reconnectMaxAttempts = 3
    private var previousVPNStatus: NEVPNStatus = .invalid
    private var reconnectBreakerLastSuppressed = false
    private var lastProbeReconnectAt: Date?
    private var lastResolvedStopClass = "unknown"
    private var pendingTunnelIntent: PendingTunnelIntent?
    private var preferencesLoadInFlight = false
    private var startInFlight = false
    private var stopInFlight = false
    private var managerReadyAt: Date?
    private var attributionFinalizeTask: Task<Void, Never>?
    private var lastPolicyReconcileAttemptAt: Date?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var lifecycleObserversRegistered = false

    private enum PendingTunnelIntent {
        case start(source: String)
        case stop(source: String)
    }

    private enum ExternalKillSignatureTier: String {
        case strong = "external_kill_signature_strong"
        case probable = "external_kill_signature_probable"
        case none = "external_kill_signature_none"
    }

    deinit {
        reconnectTask?.cancel()
        attributionFinalizeTask?.cancel()
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    func setup() {
        registerAppLifecycleObserversIfNeeded()
        recordCurrentAppLifecycleSnapshot(source: "setup")
        applyDiagnosticProfileConfiguration()
        appendLog("App launched")
        loadVPNPreferences(
            createProfileIfMissing: false,
            reconcilePolicyAfterLoad: false
        )
    }

    private func applyDiagnosticProfileConfiguration() {
        let enabled = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDiagnosticProfileEnabledKey) ?? false
        if enabled {
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldEnabledKey)
            sharedDefaults?.set(BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldSecondsKey)
            sharedDefaults?.set("manual_profile", forKey: BubbleConstants.vpnLifecycleDiagnosticModeSourceKey)
        } else {
            let autoUntil = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDiagnosticAutoEnabledUntilTSKey) ?? 0
            if autoUntil > Date().timeIntervalSince1970 {
                sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldEnabledKey)
                sharedDefaults?.set(BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldSecondsKey)
                sharedDefaults?.set("auto_escalation", forKey: BubbleConstants.vpnLifecycleDiagnosticModeSourceKey)
            }
        }
        appendLog(
            "Diagnostic profile effective: profile_enabled=\(enabled) hold_enabled=\(diagnosticHoldEnabled()) hold_seconds=\(String(format: "%.2f", diagnosticHoldSeconds())) mode_source=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDiagnosticModeSourceKey) ?? "default_off")"
        )
    }

    private func registerAppLifecycleObserversIfNeeded() {
        guard !lifecycleObserversRegistered else { return }
        lifecycleObserversRegistered = true
        let center = NotificationCenter.default
        let mappings: [(Notification.Name, String)] = [
            (UIApplication.didBecomeActiveNotification, "active"),
            (UIApplication.willResignActiveNotification, "inactive"),
            (UIApplication.didEnterBackgroundNotification, "background"),
            (UIApplication.willEnterForegroundNotification, "foreground"),
            (UIApplication.significantTimeChangeNotification, "significant_time_change"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "protected_data_available"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "protected_data_unavailable"),
            (UIApplication.didReceiveMemoryWarningNotification, "memory_warning"),
            (ProcessInfo.thermalStateDidChangeNotification, "thermal_state_changed")
        ]
        lifecycleObservers = mappings.map { name, event in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordAppLifecycleEvent(event)
                }
            }
        }
    }

    private func recordCurrentAppLifecycleSnapshot(source: String) {
        recordAppLifecycleEvent("snapshot_\(source)", shouldLog: false)
    }

    private func recordAppLifecycleEvent(_ event: String, shouldLog: Bool = true, now: Date = Date()) {
        let state = currentApplicationStateString()
        let protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
        let thermalState = currentThermalStateString()
        let ts = now.timeIntervalSince1970

        sharedDefaults?.set(state, forKey: BubbleConstants.vpnLifecycleAppStateKey)
        sharedDefaults?.set(event, forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventKey)
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventTSKey)
        sharedDefaults?.set(protectedDataAvailable, forKey: BubbleConstants.vpnLifecycleProtectedDataAvailableKey)
        sharedDefaults?.set(thermalState, forKey: BubbleConstants.vpnLifecycleAppThermalStateKey)
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppThermalStateTSKey)

        switch event {
        case "active":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppLastActiveTSKey)
        case "inactive":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppLastInactiveTSKey)
        case "background":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppLastBackgroundTSKey)
        case "foreground":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppLastForegroundTSKey)
        case "protected_data_available":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleProtectedDataAvailableTSKey)
        case "protected_data_unavailable":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleProtectedDataUnavailableTSKey)
        case "memory_warning":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleAppMemoryWarningTSKey)
        default:
            break
        }

        if shouldLog {
            appendLog("APP_LIFECYCLE event=\(event) state=\(state) protected_data_available=\(protectedDataAvailable) thermal=\(thermalState)")
        }
        if event == "active" || event == "foreground" || event == "significant_time_change" {
            repairScheduledProtectionIfNeeded(source: "app_lifecycle.\(event)")
        }
    }

    private func currentApplicationStateString() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private func currentThermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
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

    private func loadVPNPreferences(
        createProfileIfMissing: Bool = true,
        reconcilePolicyAfterLoad: Bool = true
    ) {
        guard !preferencesLoadInFlight else {
            appendLog("VPN preferences load already in flight")
            return
        }
        preferencesLoadInFlight = true
        appendLog("Loading VPN preferences...")
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    self.preferencesLoadInFlight = false
                    self.appendLog("ERROR loading prefs: \(error.localizedDescription)")
                    return
                }
                self.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleProfileLoadAllTSKey)
                self.appendLog("VPN profile operation: load_all_from_preferences complete count=\(managers?.count ?? 0)")

                if let existingManagers = managers, !existingManagers.isEmpty {
                    let matchingManager = existingManagers.first { manager in
                        let providerBundleID = (manager.protocolConfiguration as? NETunnelProviderProtocol)?
                            .providerBundleIdentifier
                        return providerBundleID == BubbleConstants.tunnelBundleID
                    }

                    guard let mgr = matchingManager else {
                        self.preferencesLoadInFlight = false
                        self.appendLog("Found \(existingManagers.count) VPN profile(s), but none match \(BubbleConstants.tunnelBundleID)")
                        guard createProfileIfMissing || self.pendingTunnelIntent != nil else {
                            self.appendLog("Profile creation deferred until explicit VPN start")
                            return
                        }
                        self.appendLog("Creating a fresh profile for current extension ID")
                        self.createVPNProfile()
                        return
                    }

                    self.manager = mgr
                    self.vpnStatus = mgr.connection.status
                    self.previousVPNStatus = mgr.connection.status
                    self.managerReadyAt = Date()
                    self.preferencesLoadInFlight = false
                    self.appendLog("Found existing profile. Status: \(self.statusString)")
                    self.appendLog("Bundle ID: \((mgr.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ?? "nil")")
                    self.observeStatusChanges(for: mgr)
                    if reconcilePolicyAfterLoad && self.autoConnect && mgr.connection.status != .connected && mgr.connection.status != .connecting {
                        self.startVPN()
                    }
                    if self.pendingTunnelIntent != nil || reconcilePolicyAfterLoad {
                        self.applyPendingTunnelIntentOrPolicy(source: "preferences_loaded")
                    }
                } else {
                    self.preferencesLoadInFlight = false
                    guard createProfileIfMissing || self.pendingTunnelIntent != nil else {
                        self.appendLog("No VPN profile found; profile creation deferred until explicit VPN start")
                        return
                    }
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
            self.observeStopEventTransition(oldStatus: oldStatus, newStatus: newStatus)
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

    private func ensureVPNPreferencesLoaded(
        createProfileIfMissing: Bool = true,
        reconcilePolicyAfterLoad: Bool = true
    ) {
        guard manager == nil else { return }
        loadVPNPreferences(
            createProfileIfMissing: createProfileIfMissing,
            reconcilePolicyAfterLoad: reconcilePolicyAfterLoad
        )
    }

    private func applyPendingTunnelIntentOrPolicy(source: String) {
        if let intent = pendingTunnelIntent {
            pendingTunnelIntent = nil
            switch intent {
            case .start(let queuedSource):
                startVPN(source: queuedSource)
            case .stop(let queuedSource):
                stopVPN(source: queuedSource)
            }
            return
        }

        guard shouldVPNBeOnFromPolicy(), !manualOffRequested, let manager else { return }
        guard !Self.isConnectedLike(manager.connection.status) else { return }
        let now = Date()
        if let lastPolicyReconcileAttemptAt, now.timeIntervalSince(lastPolicyReconcileAttemptAt) < BubbleConstants.vpnLifecyclePolicyReconcileDebounceSeconds {
            appendLog("Policy reconcile debounced")
            return
        }
        lastPolicyReconcileAttemptAt = now
        startVPN(source: "\(source).policy_reconcile")
    }

    func toggleVPN() {
        guard let manager = self.manager else {
            appendLog("VPN manager not ready; loading preferences before settings toggle")
            ensureVPNPreferencesLoaded()
            return
        }

        if Self.isConnectedLike(manager.connection.status) {
            stopVPN(source: "settings.toggle_button")
        } else {
            startVPN(source: "settings.toggle_button")
        }
    }

    func startVPN(source: String = "unknown") {
        if isManualStartSource(source) {
            bypassExternalKillReconnectCapOnce(source: source)
            clearReconnectBreakerForManualStart(source: source)
        }
        guard let manager = self.manager else {
            pendingTunnelIntent = .start(source: source)
            setManualOffRequested(false)
            appendLog("VPN manager not ready; queued start source=\(source)")
            ensureVPNPreferencesLoaded()
            return
        }
        if stopInFlight || manager.connection.status == .disconnecting {
            pendingTunnelIntent = .start(source: source)
            setManualOffRequested(false)
            appendLog("VPN stop in flight; queued start source=\(source)")
            return
        }
        if startInFlight {
            pendingTunnelIntent = .start(source: source)
            appendLog("VPN start already in flight; coalesced source=\(source)")
            return
        }
        guard !Self.isConnectedLike(manager.connection.status) else {
            setManualOffRequested(false)
            appendLog("VPN start no-op status=\(Self.statusString(for: manager.connection.status)) source=\(source)")
            return
        }
        setManualOffRequested(false)
        reconnectTask?.cancel()
        reconnectTask = nil
        startInFlight = true
        stopInFlight = false
        resetStopAttributionForNewSession()

        appendLog("Starting VPN... source=\(source)")

        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let error = error {
                    self.startInFlight = false
                    self.appendLog("ERROR loading: \(error.localizedDescription)")
                    return
                }
                self.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleProfileLoadTSKey)
                self.appendLog("VPN profile operation: load_from_preferences complete source=\(source)")

                let desiredSignature = self.desiredProfileSignature(for: manager)
                let lastSignature = self.sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProfileConfigSignatureKey) ?? ""
                let needsMutation = self.profileNeedsMutation(manager: manager) || desiredSignature != lastSignature
                if !needsMutation {
                    self.appendLog("VPN profile operation: mutation skipped source=\(source)")
                    self.startTunnelIfNeeded(manager: manager, source: source)
                    return
                }

                if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
                    proto.providerBundleIdentifier = BubbleConstants.tunnelBundleID
                    proto.serverAddress = BubbleConstants.vpnServerAddress
                    manager.protocolConfiguration = proto
                }
                manager.localizedDescription = BubbleConstants.vpnDescription
                manager.isEnabled = true
                manager.saveToPreferences { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if let error = error {
                            self.startInFlight = false
                            self.appendLog("ERROR saving: \(error.localizedDescription)")
                            return
                        }
                        self.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleProfileSaveTSKey)
                        self.sharedDefaults?.set(desiredSignature, forKey: BubbleConstants.vpnLifecycleProfileConfigSignatureKey)
                        self.appendLog("VPN profile operation: save_to_preferences complete source=\(source)")

                        manager.loadFromPreferences { [weak self] reloadError in
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                if let reloadError = reloadError {
                                    self.startInFlight = false
                                    self.appendLog("ERROR reloading after save: \(reloadError.localizedDescription)")
                                    return
                                }
                                self.sharedDefaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleProfileReloadTSKey)
                                self.appendLog("VPN profile operation: reload_after_save complete source=\(source)")
                                self.startTunnelIfNeeded(manager: manager, source: source)
                            }
                        }
                    }
                }
            }
        }
    }

    private func startTunnelIfNeeded(manager: NETunnelProviderManager, source: String) {
        if Self.isConnectedLike(manager.connection.status) {
            startInFlight = false
            appendLog("VPN start no-op status=\(Self.statusString(for: manager.connection.status)) source=\(source)")
            return
        }

        do {
            appendLog("Starting VPN tunnel... source=\(source)")
            try manager.connection.startVPNTunnel()
            appendLog("startVPNTunnel() called successfully")
            if source.hasPrefix("schedule.") {
                ScheduledProtectionStateStore.recordRepairResult(defaults: sharedDefaults, result: "\(source)_start_called")
            }
        } catch {
            let nsError = error as NSError
            appendLog("ERROR starting: \(error.localizedDescription)")
            appendLog("Error details: \(nsError.domain) code \(nsError.code)")
            if source.hasPrefix("schedule.") {
                ScheduledProtectionStateStore.recordRepairResult(defaults: sharedDefaults, result: "\(source)_start_failed_code_\(nsError.code)")
            }
        }
        startInFlight = false
    }

    private func desiredProfileSignature(for manager: NETunnelProviderManager) -> String {
        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        let provider = proto?.providerBundleIdentifier ?? "nil"
        let server = proto?.serverAddress ?? "nil"
        return "provider=\(provider)|server=\(server)|enabled=true|description=\(BubbleConstants.vpnDescription)"
    }

    private func profileNeedsMutation(manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return true }
        if !manager.isEnabled { return true }
        if proto.providerBundleIdentifier != BubbleConstants.tunnelBundleID { return true }
        if proto.serverAddress != BubbleConstants.vpnServerAddress { return true }
        if manager.localizedDescription != BubbleConstants.vpnDescription { return true }
        return false
    }

    func stopVPN(source: String = "unknown") {
        if source == "settings.toggle_button" {
            ScheduledProtectionStateStore.suppressCurrentScheduleWindow(defaults: sharedDefaults, source: source)
        }
        guard let manager = self.manager else {
            pendingTunnelIntent = .stop(source: source)
            appendLog("VPN manager not ready; queued stop source=\(source)")
            ensureVPNPreferencesLoaded()
            return
        }
        if startInFlight {
            pendingTunnelIntent = .stop(source: source)
            appendLog("VPN start in flight; queued stop source=\(source)")
            return
        }
        if stopInFlight || Self.isDisconnectedLike(manager.connection.status) {
            setManualOffRequested(source == "settings.toggle_button")
            appendLog("VPN stop no-op status=\(Self.statusString(for: manager.connection.status)) source=\(source)")
            return
        }
        setManualOffRequested(source == "settings.toggle_button")
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        stopInFlight = true
        startInFlight = false
        persistPendingStopIntent(source: source)
        appendLog("Stopping VPN tunnel... source=\(source)")
        manager.connection.stopVPNTunnel()
        stopInFlight = false
    }

    private func persistPendingStopIntent(source: String, now: Date = Date()) {
        let stopID = UUID().uuidString
        sharedDefaults?.set(stopID, forKey: BubbleConstants.vpnLifecyclePendingStopIDKey)
        sharedDefaults?.set(source, forKey: BubbleConstants.vpnLifecyclePendingStopSourceKey)
        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecyclePendingStopTSKey)
        ensureStopEventExists(now: now)
        upsertStopSignal(candidate: "app_requested_stop", ts: now.timeIntervalSince1970)
        appendLog("STOP_INTENT id=\(stopID) source=\(source)")
    }

    private func observeStopEventTransition(oldStatus: NEVPNStatus, newStatus: NEVPNStatus, now: Date = Date()) {
        let oldConnectedLike = Self.isConnectedLike(oldStatus)
        let enteringDropPath = oldConnectedLike && (newStatus == .disconnecting || newStatus == .disconnected)
        if enteringDropPath {
            ensureStopEventExists(now: now)
            recordStatusDropTimestamp(now: now)
        }
        if enteringDropPath || newStatus == .disconnected {
            upsertStopSignal(candidate: "status_drop_without_stop_callback", ts: now.timeIntervalSince1970)
            captureDropBoundaryContext(now: now)
            scheduleStopAttributionFinalization(eventID: currentStopEventID(), delaySeconds: attributionWindowSeconds())
        }
    }

    private func scheduleStopAttributionFinalization(eventID: String, delaySeconds: TimeInterval) {
        guard !eventID.isEmpty else { return }
        attributionFinalizeTask?.cancel()
        attributionFinalizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.finalizeStopAttributionIfNeeded(eventID: eventID)
            }
        }
    }

    private func handleStatusTransition(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            startInFlight = false
            reconnectAttempts = 0
            reconnectTask?.cancel()
            reconnectTask = nil
            recoverReconnectBreakerIfNeeded()
            if case .stop = pendingTunnelIntent {
                applyPendingTunnelIntentOrPolicy(source: "status_connected")
            }
        case .disconnected:
            stopInFlight = false
            if case .start = pendingTunnelIntent {
                applyPendingTunnelIntentOrPolicy(source: "status_disconnected")
            } else {
                scheduleAutoReconnectForUnexpectedStop()
            }
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
        let policyDesiredOn = shouldVPNBeOnFromPolicy()
        let scheduleSnapshot = ScheduledProtectionStateStore.snapshot(defaults: sharedDefaults)
        if scheduleSnapshot.isDesiredProtectionActive(), !manualOffRequested {
            scheduleScheduledProtectionReconnect(source: "schedule.drop_reconnect")
            return
        }
        if policyDesiredOn, isWithinManagerReadyGraceWindow() {
            appendLog("Disconnect during manager readiness grace; deferring reconnect without crash classification")
            scheduleDeferredPolicyReconnect(source: "manager_ready_grace")
            return
        }
        var stopReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonKey) ?? "unknown"
        var stopSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSourceKey) ?? "unknown"
        var stopReasonRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonRawKey) ?? ""
        var unexpectedExit = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey) ?? false
        var inferredCrash = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleInferredCrashKey) ?? false
        let runningMarker = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleRunningMarkerKey) ?? false
        let lastHeartbeatTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        let expectedDisconnect = !policyDesiredOn || manualOffRequested
        let stopResolution = resolveStopClassification(
            stopSource: stopSource,
            stopReason: stopReason,
            stopReasonRaw: stopReasonRaw,
            runningMarker: runningMarker,
            lastHeartbeatTS: lastHeartbeatTS,
            expectedDisconnect: expectedDisconnect
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
        let isCrashLikeStop = (stopSource == "tun2socks_exit" || stopSource == "cancelTunnelWithError" || stopSource == "inferred_crash") && (unexpectedExit || inferredCrash)
        appendLog(
            "Disconnect classified resolved_stop_class=\(stopResolution.resolvedClass.rawValue) expected_disconnect=\(expectedDisconnect) crash_like=\(isCrashLikeStop) short_lived_session=\(shortLivedSession) session_duration_seconds=\(Int(sessionDurationSeconds)) policy_desired_on=\(policyDesiredOn) manual_off_requested=\(manualOffRequested) source=\(stopSource) reason=\(stopReason) reason_raw=\(stopReasonRaw) unexpected_exit=\(unexpectedExit) inferred_crash=\(inferredCrash) path_status=\(pathStatus) path_reason=\(pathReason) path_interfaces=\(pathInterfaces) path_expensive=\(pathExpensive) path_constrained=\(pathConstrained) path_observed_at=\(formatUnixTS(pathTS))"
        )
        let effectiveFinalCause = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ??
            sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let providerLastPhase = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey) ?? "unknown"
        let heartbeatSnapshotJSON = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProviderHeartbeatSnapshotJSONKey) ?? "{}"
        let lastDecoderEventJSON = sharedDefaults?.string(forKey: BubbleConstants.udpLastDecoderEventJSONKey) ?? "{}"
        let transportCause = classifyDisconnectTransportCause(
            finalCause: effectiveFinalCause,
            providerLastPhase: providerLastPhase,
            tun2socksExitObserved: stopSource == "tun2socks_exit" ||
                (sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey) ?? 0) > 0,
            lastDecoderEventJSON: lastDecoderEventJSON,
            lastHeartbeatSnapshotJSON: heartbeatSnapshotJSON
        )
        let lifecycleCategory = disconnectLifecycleCategory(
            finalCause: effectiveFinalCause,
            externalKillTier: sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        )
        appendLog(
            "Disconnect attribution transport_cause=\(transportCause) lifecycle_category=\(lifecycleCategory) provider_phase=\(providerLastPhase)"
        )
        if transportCause != "unknown" {
            sharedDefaults?.set(transportCause, forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey)
        }
        guard policyDesiredOn else {
            appendLog("Unexpected stop observed, but policy_desired_on=false. Skipping reconnect.")
            return
        }
        guard !expectedDisconnect else {
            appendLog("Disconnect was expected. Skipping reconnect.")
            return
        }
        resetReconnectBreakerAfterHealthySessionIfNeeded(sessionDurationSeconds: sessionDurationSeconds)
        recordUnexpectedDisconnectAndTripBreakerIfNeeded(
            shortLivedSession: shortLivedSession,
            finalCause: effectiveFinalCause
        )
        recordDropLoopAndAutoEscalateIfNeeded(now: Date())
        if let cooldownRemaining = reconnectBreakerRemainingCooldownSeconds(), cooldownRemaining > 0 {
            if !reconnectBreakerLastSuppressed {
                appendLog("Reconnect breaker tripped: healthy -> tripped -> cooldown (\(cooldownRemaining)s remaining)")
            } else {
                appendLog("Reconnect breaker cooldown active (\(cooldownRemaining)s remaining), skipping auto-reconnect")
            }
            incrementReconnectSuppressedByBreaker(reason: "reconnect_breaker_cooldown")
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
            incrementReconnectSuppressedByBreaker(reason: "tripped_overload_guard")
            reconnectBreakerLastSuppressed = true
            return
        }
        if let suppressionReason = externalKillReconnectSuppressionReason() {
            appendLog("External-kill reconnect suppressed: \(suppressionReason)")
            incrementReconnectSuppressedByBreaker(reason: "external_kill_\(suppressionReason)")
            reconnectBreakerLastSuppressed = true
            return
        }
        reconnectBreakerLastSuppressed = false
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        appendLog("Unexpected stop detected with policy_desired_on=true. Attempting reconnect...")

        reconnectAttempts += 1
        let backoffSeconds = reconnectAttemptBackoffSeconds()
        let resilienceDelay = resilienceModeDelaySecondsIfNeeded()
        let externalKillDelay = externalKillReconnectDelaySecondsIfNeeded()
        let reconnectDelay: TimeInterval
        if externalKillDelay > 0 {
            reconnectDelay = max(backoffSeconds, resilienceDelay, externalKillDelay)
        } else {
            reconnectDelay = min(
                BubbleConstants.autoReconnectFastPathMaxDelaySeconds,
                max(backoffSeconds, resilienceDelay)
            )
        }
        sharedDefaults?.set(reconnectDelay, forKey: BubbleConstants.vpnLifecycleLastReconnectDelaySecondsKey)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                if self.vpnStatus == .disconnected && self.shouldVPNBeOnFromPolicy() {
                    guard self.registerExternalKillReconnectAttemptIfAllowed() else { return }
                    self.appendLog("Auto-reconnect attempt \(self.reconnectAttempts)/\(self.reconnectMaxAttempts) delay=\(String(format: "%.2f", reconnectDelay))s")
                    self.startVPN(source: "auto_reconnect")
                }
            }
        }
    }

    func repairScheduledProtectionIfNeeded(source: String) {
        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: sharedDefaults)
        guard snapshot.isDesiredProtectionActive() else { return }
        if manualOffRequested {
            setManualOffRequested(false)
            appendLog("Schedule protection cleared stale manual_off_requested source=\(source)")
        }
        guard let manager else {
            appendLog("SCHEDULE_PROTECTION_REPAIR desired_on=true status=manager_not_ready action=start source=\(source)")
            ScheduledProtectionStateStore.recordRepairResult(defaults: sharedDefaults, result: "manager_not_ready_start_queued")
            startVPN(source: "schedule.repair")
            return
        }

        manager.loadFromPreferences { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.appendLog("SCHEDULE_PROTECTION_REPAIR desired_on=true status=load_failed action=none source=\(source) error=\(error.localizedDescription)")
                    ScheduledProtectionStateStore.recordRepairResult(defaults: self.sharedDefaults, result: "repair_load_failed")
                    return
                }
                let status = manager.connection.status
                self.vpnStatus = status
                self.previousVPNStatus = status
                if Self.isConnectedLike(status) {
                    self.appendLog("SCHEDULE_PROTECTION_REPAIR desired_on=true status=\(Self.statusString(for: status)) action=none source=\(source)")
                    ScheduledProtectionStateStore.recordRepairResult(defaults: self.sharedDefaults, result: "already_connected")
                    return
                }
                self.appendLog("SCHEDULE_PROTECTION_REPAIR desired_on=true status=\(Self.statusString(for: status)) action=start source=\(source)")
                ScheduledProtectionStateStore.recordRepairResult(defaults: self.sharedDefaults, result: "repair_starting")
                self.startVPN(source: "schedule.repair")
            }
        }
    }

    private func diagnosticHoldEnabled() -> Bool {
        sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDiagnosticHoldEnabledKey) ?? false
    }

    private func diagnosticHoldSeconds() -> TimeInterval {
        let configured = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDiagnosticHoldSecondsKey) ?? 0
        if configured > 0 { return configured }
        return diagnosticHoldEnabled() ? BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds : 0
    }

    private func attributionWindowSeconds() -> TimeInterval {
        max(BubbleConstants.vpnLifecycleAttributionWindowSeconds, diagnosticHoldSeconds())
    }

    private func recordDropLoopAndAutoEscalateIfNeeded(now: Date) {
        let windowStartKey = BubbleConstants.vpnLifecycleDropLoopWindowStartTSKey
        let countKey = BubbleConstants.vpnLifecycleDropLoopCountKey
        let windowSeconds = BubbleConstants.vpnLifecycleDiagnosticAutoEnableWindowSeconds

        let currentWindowStart = sharedDefaults?.double(forKey: windowStartKey) ?? 0
        let currentCount = sharedDefaults?.integer(forKey: countKey) ?? 0
        let start: TimeInterval
        let nextCount: Int
        if currentWindowStart <= 0 || (now.timeIntervalSince1970 - currentWindowStart) > windowSeconds {
            start = now.timeIntervalSince1970
            nextCount = 1
        } else {
            start = currentWindowStart
            nextCount = currentCount + 1
        }
        sharedDefaults?.set(start, forKey: windowStartKey)
        sharedDefaults?.set(nextCount, forKey: countKey)

        guard nextCount >= BubbleConstants.vpnLifecycleDiagnosticAutoEnableMinDrops else { return }
        let profileEnabled = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDiagnosticProfileEnabledKey) ?? false
        guard !profileEnabled else { return }
        let until = now.timeIntervalSince1970 + BubbleConstants.vpnLifecycleDiagnosticAutoEnableWindowSeconds
        sharedDefaults?.set(until, forKey: BubbleConstants.vpnLifecycleDiagnosticAutoEnabledUntilTSKey)
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldEnabledKey)
        sharedDefaults?.set(BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldSecondsKey)
        sharedDefaults?.set("auto_escalation", forKey: BubbleConstants.vpnLifecycleDiagnosticModeSourceKey)
        appendLog(
            "Auto-escalation enabled full diagnostics: drop_count=\(nextCount) window_seconds=\(Int(windowSeconds)) hold_seconds=\(String(format: "%.2f", BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds)) active_until=\(formatUnixTS(until))"
        )
    }

    private func resilienceModeDelaySecondsIfNeeded() -> TimeInterval {
        guard diagnosticHoldEnabled() else { return 0 }
        guard diagnosticHoldSeconds() >= BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds else { return 0 }
        let lastFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ?? ""
        let evidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseEvidenceKey) ?? ""
        guard lastFinal == "status_drop_without_stop_callback", evidence.contains("terminal_callback_observed=false") else {
            return 0
        }
        let base: TimeInterval = 1.0
        let jitter = Double.random(in: 0...0.5)
        let delay = base + jitter
        appendLog("Resilience mode active for external kill class delay_seconds=\(String(format: "%.2f", delay))")
        return delay
    }

    private func externalKillReconnectDelaySecondsIfNeeded() -> TimeInterval {
        let signatureTier = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        let lastExternal = signatureTier != ExternalKillSignatureTier.none.rawValue
        let currentDropTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey) ?? 0
        let currentFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let currentExternalCandidate = diagnosticHoldEnabled() && currentDropTS > 0 && currentFinal.isEmpty
        guard lastExternal || currentExternalCandidate else { return 0 }
        let delay = Double.random(
            in: BubbleConstants.vpnLifecycleExternalKillReconnectMinDelaySeconds...BubbleConstants.vpnLifecycleExternalKillReconnectMaxDelaySeconds
        )
        appendLog("External-kill reconnect policy active delay_seconds=\(String(format: "%.2f", delay)) signature_tier=\(signatureTier) in_flight_candidate=\(currentExternalCandidate)")
        return delay
    }

    private func externalKillReconnectSuppressionReason(now: Date = Date()) -> String? {
        let signatureTier = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        guard signatureTier != ExternalKillSignatureTier.none.rawValue else {
            refreshExternalKillReconnectWindow(now: now)
            sharedDefaults?.set("inactive", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
            return nil
        }
        let attempts = filteredExternalKillReconnectAttempts(now: now)
        if attempts.count >= BubbleConstants.vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow {
            let nextAllowed = (attempts.first ?? now.timeIntervalSince1970) + BubbleConstants.vpnLifecycleExternalKillReconnectWindowSeconds
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
            sharedDefaults?.set(nextAllowed, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
            sharedDefaults?.set(attempts.count, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey)
            sharedDefaults?.set("suppressed_cooldown", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
            return "cap_active attempts=\(attempts.count) next_allowed_at=\(formatUnixTS(nextAllowed))"
        }
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
        sharedDefaults?.set(attempts.count, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey)
        sharedDefaults?.set("active", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
        return nil
    }

    private func registerExternalKillReconnectAttemptIfAllowed(now: Date = Date()) -> Bool {
        let signatureTier = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        guard signatureTier != ExternalKillSignatureTier.none.rawValue else {
            refreshExternalKillReconnectWindow(now: now)
            return true
        }
        var attempts = filteredExternalKillReconnectAttempts(now: now)
        if attempts.count >= BubbleConstants.vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow {
            let nextAllowed = (attempts.first ?? now.timeIntervalSince1970) + BubbleConstants.vpnLifecycleExternalKillReconnectWindowSeconds
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
            sharedDefaults?.set(nextAllowed, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
            sharedDefaults?.set(attempts.count, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey)
            sharedDefaults?.set("suppressed_cooldown", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
            appendLog("External-kill reconnect cap blocked attempt attempts=\(attempts.count) next_allowed_at=\(formatUnixTS(nextAllowed))")
            incrementReconnectSuppressedByBreaker(reason: "external_kill_reconnect_cap")
            reconnectBreakerLastSuppressed = true
            return false
        }
        attempts.append(now.timeIntervalSince1970)
        sharedDefaults?.set(attempts, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptTSKey)
        sharedDefaults?.set(attempts.count, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
        sharedDefaults?.set("active", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
        appendLog("External-kill reconnect attempt admitted attempts_in_window=\(attempts.count)")
        return true
    }

    private func refreshExternalKillReconnectWindow(now: Date = Date()) {
        let attempts = filteredExternalKillReconnectAttempts(now: now)
        sharedDefaults?.set(attempts.count, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey)
        if attempts.count < BubbleConstants.vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow {
            sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
            sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
        }
    }

    private func filteredExternalKillReconnectAttempts(now: Date = Date()) -> [TimeInterval] {
        let raw = sharedDefaults?.array(forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptTSKey) as? [TimeInterval] ?? []
        let filtered = raw
            .filter { $0 > 0 && now.timeIntervalSince1970 - $0 <= BubbleConstants.vpnLifecycleExternalKillReconnectWindowSeconds }
            .sorted()
        sharedDefaults?.set(filtered, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptTSKey)
        return filtered
    }

    private func isManualStartSource(_ source: String) -> Bool {
        source == "settings.toggle_button"
    }

    private func bypassExternalKillReconnectCapOnce(source: String) {
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey)
        sharedDefaults?.set("manual_bypass_once", forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey)
        appendLog("Manual start bypassed external-kill reconnect cap source=\(source)")
    }

    private func clearReconnectBreakerForManualStart(source: String) {
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerRecentDisconnectsKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        reconnectBreakerLastSuppressed = false
        appendLog("Manual start cleared reconnect breaker source=\(source)")
    }

    private func isWithinManagerReadyGraceWindow(now: Date = Date()) -> Bool {
        guard let managerReadyAt else { return false }
        return now.timeIntervalSince(managerReadyAt) <= 6.0
    }

    private func scheduleDeferredPolicyReconnect(source: String) {
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                guard self.vpnStatus == .disconnected, self.shouldVPNBeOnFromPolicy(), !self.manualOffRequested else { return }
                self.startVPN(source: source)
            }
        }
    }

    private func scheduleScheduledProtectionReconnect(source: String) {
        guard reconnectAttempts < reconnectMaxAttempts else {
            appendLog("SCHEDULE_PROTECTION_REPAIR desired_on=true status=disconnected action=skip_retry_cap source=\(source)")
            ScheduledProtectionStateStore.recordRepairResult(defaults: sharedDefaults, result: "retry_cap_reached")
            return
        }
        let attempt = reconnectAttempts + 1
        let delay = reconnectAttempts == 0 ? 0 : reconnectAttemptBackoffSeconds()
        reconnectAttempts = attempt
        ScheduledProtectionStateStore.recordInterruption(
            defaults: sharedDefaults,
            result: "unexpected_drop_reconnect_attempt_\(attempt)"
        )
        appendLog(
            "SCHEDULE_PROTECTION_REPAIR desired_on=true status=disconnected action=start attempt=\(attempt)/\(reconnectMaxAttempts) delay=\(String(format: "%.2f", delay)) source=\(source)"
        )
        reconnectTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                guard self.vpnStatus == .disconnected,
                      ScheduledProtectionStateStore.snapshot(defaults: self.sharedDefaults).isDesiredProtectionActive(),
                      !self.manualOffRequested else {
                    return
                }
                self.startVPN(source: source)
            }
        }
    }

    private func resetStopAttributionForNewSession(now: Date = Date()) {
        finalizeInFlightStopEventBeforeReset(now: now)
        let sessionID = UUID().uuidString
        sharedDefaults?.set(sessionID, forKey: BubbleConstants.vpnLifecycleSessionIDKey)
        clearStopAttributionState(preserveSession: true)
        sharedDefaults?.set(sessionID, forKey: BubbleConstants.vpnLifecycleSessionIDKey)
        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleLastStartTSKey)
    }

    private func finalizeInFlightStopEventBeforeReset(now: Date = Date()) {
        let eventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        guard !eventID.isEmpty else { return }
        let hasFinal = !(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? "").isEmpty
        if !hasFinal {
            finalizeStopAttributionIfNeeded(eventID: eventID, now: now)
        }
        if !(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? "").isEmpty {
            persistLastCompletedStopSnapshot(now: now)
        }
    }

    private func clearStopAttributionState(preserveSession: Bool) {
        let keys = [
            BubbleConstants.vpnLifecycleStopEventIDKey,
            BubbleConstants.vpnLifecycleStopEventStartTSKey,
            BubbleConstants.vpnLifecycleStopCauseFinalKey,
            BubbleConstants.vpnLifecycleStopCauseConfidenceKey,
            BubbleConstants.vpnLifecycleStopCauseEvidenceKey,
            BubbleConstants.vpnLifecycleStopCauseSignalOrderKey,
            BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey,
            BubbleConstants.vpnLifecycleStopSignalAppRequestedTSKey,
            BubbleConstants.vpnLifecycleStopSignalOSStopTSKey,
            BubbleConstants.vpnLifecycleStopSignalOSStopReasonRawKey,
            BubbleConstants.vpnLifecycleStopSignalOSStopReasonNameKey,
            BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey,
            BubbleConstants.vpnLifecycleStopSignalTun2SocksExitCodeKey,
            BubbleConstants.vpnLifecycleStopSignalProviderDeinitTSKey,
            BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey,
            BubbleConstants.vpnLifecycleDiagnosticHoldElapsedMSKey,
            BubbleConstants.vpnLifecycleDiagnosticHoldCompletedKey,
            BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey,
            BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey,
            BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey,
            BubbleConstants.vpnLifecyclePendingStopIDKey,
            BubbleConstants.vpnLifecyclePendingStopSourceKey,
            BubbleConstants.vpnLifecyclePendingStopTSKey
        ]
        keys.forEach { sharedDefaults?.removeObject(forKey: $0) }
        if !preserveSession {
            sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleSessionIDKey)
        }
    }

    private func currentStopEventID() -> String {
        sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
    }

    private func ensureStopEventExists(now: Date = Date()) {
        let current = currentStopEventID()
        if !current.isEmpty { return }
        let eventID = UUID().uuidString
        sharedDefaults?.set(eventID, forKey: BubbleConstants.vpnLifecycleStopEventIDKey)
        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldElapsedMSKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldCompletedKey)
    }

    private func upsertStopSignal(candidate: String, ts: TimeInterval) {
        switch candidate {
        case "app_requested_stop":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopSignalAppRequestedTSKey)
        case "status_drop_without_stop_callback":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey)
        default:
            break
        }
    }

    private func finalizeStopAttributionIfNeeded(eventID: String, now: Date = Date()) {
        guard (sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? "") == eventID else { return }
        let existingFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        if !existingFinal.isEmpty { return }

        let eventStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey) ?? 0
        let appTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalAppRequestedTSKey) ?? 0
        let osTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopTSKey) ?? 0
        let tunTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey) ?? 0
        let deinitTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalProviderDeinitTSKey) ?? 0
        let dropTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey) ?? 0
        let seenStopTunnelTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey) ?? 0
        let seenTun2SocksTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey) ?? 0
        let seenProviderDeinitTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey) ?? 0
        let osRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonRawKey) ?? ""
        let osName = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonNameKey) ?? ""
        let tunExit = sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitCodeKey) as? Int
        let holdSeconds = diagnosticHoldSeconds()
        let elapsed = max(0, now.timeIntervalSince1970 - eventStart)
        let holdCompleted = holdSeconds <= 0 || elapsed >= holdSeconds
        sharedDefaults?.set(Int(elapsed * 1000), forKey: BubbleConstants.vpnLifecycleDiagnosticHoldElapsedMSKey)
        sharedDefaults?.set(holdCompleted, forKey: BubbleConstants.vpnLifecycleDiagnosticHoldCompletedKey)
        if !holdCompleted {
            return
        }

        let appIntentFresh: Bool
        if appTS <= 0 {
            appIntentFresh = false
        } else if eventStart > 0 {
            appIntentFresh = abs(appTS - eventStart) <= 20
        } else {
            appIntentFresh = true
        }

        let final: String
        let confidence: String
        if appIntentFresh {
            final = "app_requested_stop"
            confidence = "high"
        } else if osTS > 0 {
            final = osRaw.isEmpty ? "os_stop_reason_unknown" : "os_stop_reason_\(osRaw)"
            confidence = "high"
        } else if tunTS > 0 {
            final = "tun2socks_exit"
            confidence = "high"
        } else if deinitTS > 0 {
            final = "provider_deinit_without_stop"
            confidence = "medium"
        } else if dropTS > 0 {
            final = "status_drop_without_stop_callback"
            confidence = "low"
        } else {
            final = "unknown"
            confidence = "low"
        }

        var entries: [(String, TimeInterval)] = []
        if appIntentFresh { entries.append(("app_requested_stop", appTS)) }
        if osTS > 0 { entries.append(("os_stop_reason", osTS)) }
        if tunTS > 0 { entries.append(("tun2socks_exit", tunTS)) }
        if deinitTS > 0 { entries.append(("provider_deinit_without_stop", deinitTS)) }
        if dropTS > 0 { entries.append(("status_drop_without_stop_callback", dropTS)) }
        entries.sort { $0.1 < $1.1 }
        let baseTS = eventStart > 0 ? eventStart : entries.first?.1 ?? now.timeIntervalSince1970
        let signalOrder = entries.map { (name, ts) in
            let deltaMS = Int(max(0, (ts - baseTS) * 1000))
            return "\(name)+\(deltaMS)ms"
        }.joined(separator: " -> ")

        var evidence: [String] = []
        if !osRaw.isEmpty || !osName.isEmpty {
            evidence.append("ne_stop_reason_raw=\(osRaw.isEmpty ? "unknown" : osRaw)")
            evidence.append("ne_stop_reason_name=\(osName.isEmpty ? "unknown" : osName)")
        }
        if let tunExit { evidence.append("tun2socks_exit_code=\(tunExit)") }
        if !signalOrder.isEmpty { evidence.append("signal_order=\(signalOrder)") }
        let terminalObserved = seenStopTunnelTS > 0 || seenTun2SocksTS > 0 || seenProviderDeinitTS > 0
        evidence.append("terminal_callback_observed=\(terminalObserved)")
        if !terminalObserved {
            let holdElapsedMS = Int(elapsed * 1000)
            evidence.append("hold_window_elapsed_ms=\(holdElapsedMS)")
            evidence.append("hold_window_completed=true")
        }
        let nearestProfileOpDeltaMS = nearestProfileOpDeltaMS(nowTS: now.timeIntervalSince1970, eventStartTS: eventStart)
        if let nearestProfileOpDeltaMS {
            evidence.append("profile_op_to_drop_ms=\(nearestProfileOpDeltaMS)")
        }

        sharedDefaults?.set(final, forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey)
        sharedDefaults?.set(confidence, forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey)
        sharedDefaults?.set(evidence.joined(separator: ";"), forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey)
        sharedDefaults?.set(signalOrder, forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey)
        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey)
        persistExternalKillAssessment(finalCause: final, evidence: evidence.joined(separator: ";"), now: now)
        persistLastCompletedStopSnapshot(now: now)
    }

    private func persistLastCompletedStopSnapshot(now: Date = Date()) {
        let eventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        let final = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let signalOrder = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey) ?? ""
        guard !eventID.isEmpty, !final.isEmpty, !signalOrder.isEmpty else { return }
        let confidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey) ?? ""
        let evidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey) ?? ""
        let finalizedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey) ?? now.timeIntervalSince1970
        let previousCompletedEventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopEventIDKey) ?? ""
        let currentSeq = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSeqKey) ?? 0
        sharedDefaults?.set(eventID, forKey: BubbleConstants.vpnLifecycleLastCompletedStopEventIDKey)
        sharedDefaults?.set(final, forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey)
        sharedDefaults?.set(confidence, forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseConfidenceKey)
        sharedDefaults?.set(evidence, forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseEvidenceKey)
        sharedDefaults?.set(signalOrder, forKey: BubbleConstants.vpnLifecycleLastCompletedStopSignalOrderKey)
        sharedDefaults?.set(finalizedTS, forKey: BubbleConstants.vpnLifecycleLastCompletedStopFinalizedTSKey)
        if previousCompletedEventID != eventID {
            sharedDefaults?.set(currentSeq + 1, forKey: BubbleConstants.vpnLifecycleLastCompletedStopSeqKey)
        }
        let remediationPath = remediationPath(for: final)
        let nextAction = nextActionForRemediationPath(remediationPath)
        sharedDefaults?.set(remediationPath, forKey: BubbleConstants.vpnLifecycleRemediationPathKey)
        sharedDefaults?.set(nextAction, forKey: BubbleConstants.vpnLifecycleNextActionKey)
        sharedDefaults?.set(isDiagnosticComplete(), forKey: BubbleConstants.vpnLifecycleDiagnosticCompletenessKey)
        persistExternalKillAssessment(finalCause: final, evidence: evidence, now: now)
    }

    private func nearestProfileOpDeltaMS(nowTS: TimeInterval, eventStartTS: TimeInterval) -> Int? {
        let dropTS = eventStartTS > 0 ? eventStartTS : nowTS
        let ops = [
            sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProfileLoadAllTSKey) ?? 0,
            sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProfileLoadTSKey) ?? 0,
            sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProfileSaveTSKey) ?? 0,
            sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProfileReloadTSKey) ?? 0
        ].filter { $0 > 0 }
        guard !ops.isEmpty else { return nil }
        let nearest = ops.map { Int(abs($0 - dropTS) * 1000) }.min()
        return nearest
    }

    private func pressureCriticalDurationSeconds(now: Date = Date()) -> Double {
        let level = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureLevelKey) ?? "unknown"
        guard level == "critical" else { return 0 }
        let runtime = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExtensionPressureRuntimeSecondsKey) ?? 0
        return max(0, runtime - BubbleConstants.extensionPressureSamplerStartSeconds)
    }

    private func reclaimBlockedCountLastWindow(now: Date = Date()) -> Int {
        let ts = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExtensionPressureLastSampleTSKey) ?? 0
        guard ts > 0, now.timeIntervalSince1970 - ts <= BubbleConstants.vpnLifecycleExternalKillSupportSignalWindowSeconds else {
            return 0
        }
        return sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleExtensionPressureReclaimBlockedCountKey) ?? 0
    }

    private func recordStatusDropTimestamp(now: Date) {
        let nowTS = now.timeIntervalSince1970
        var history = statusDropHistory(now: now)
        if let last = history.last, abs(nowTS - last) < 1.0 {
            return
        }
        history.append(nowTS)
        history = history
            .filter { nowTS - $0 <= BubbleConstants.vpnLifecycleExternalKillDropHistoryWindowSeconds }
            .sorted()
        sharedDefaults?.set(history, forKey: BubbleConstants.vpnLifecycleStatusDropHistoryTSKey)
    }

    private func statusDropHistory(now: Date = Date()) -> [TimeInterval] {
        let nowTS = now.timeIntervalSince1970
        let raw = sharedDefaults?.array(forKey: BubbleConstants.vpnLifecycleStatusDropHistoryTSKey) as? [TimeInterval] ?? []
        let filtered = raw
            .filter { $0 > 0 && nowTS - $0 <= BubbleConstants.vpnLifecycleExternalKillDropHistoryWindowSeconds }
            .sorted()
        sharedDefaults?.set(filtered, forKey: BubbleConstants.vpnLifecycleStatusDropHistoryTSKey)
        return filtered
    }

    private func dropCadenceSeconds(now: Date = Date()) -> TimeInterval? {
        let history = statusDropHistory(now: now)
        guard history.count >= 2 else { return nil }
        let intervals = zip(history.dropFirst(), history).map { max(0, $0 - $1) }
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        return sorted[sorted.count / 2]
    }

    private func externalKillSignatureTier(finalCause: String, evidence: String, now: Date = Date()) -> ExternalKillSignatureTier {
        guard finalCause == "status_drop_without_stop_callback" else { return .none }
        guard evidence.contains("terminal_callback_observed=false") else { return .none }

        let heartbeatAgeSeconds = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillHeartbeatStaleSecondsAtDropKey) ?? 0
        let staleHeartbeat = heartbeatAgeSeconds >= BubbleConstants.vpnLifecycleExternalKillStaleHeartbeatSeconds
        let cadence = dropCadenceSeconds(now: now)
        let cadenceSupport = cadence != nil &&
            cadence! >= BubbleConstants.vpnLifecycleExternalKillCadenceMinSeconds &&
            cadence! <= BubbleConstants.vpnLifecycleExternalKillCadenceMaxSeconds
        let historyCount = statusDropHistory(now: now).count
        let repeatedSupport = historyCount >= BubbleConstants.vpnLifecycleExternalKillMinDropCountForSupportSignal
        let appStateAtDrop = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryAppStateKey) ?? "unknown"
        let protectedDataAtDrop = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDropBoundaryProtectedDataAvailableKey) ?? true
        let lifecycleSupport = appStateAtDrop == "background" || !protectedDataAtDrop

        if staleHeartbeat && (cadenceSupport || repeatedSupport || lifecycleSupport) {
            return .strong
        }
        if staleHeartbeat || cadenceSupport || repeatedSupport || lifecycleSupport {
            return .probable
        }
        return .none
    }

    private func persistExternalKillAssessment(finalCause: String, evidence: String, now: Date = Date()) {
        let cadence = dropCadenceSeconds(now: now)
        let tier = externalKillSignatureTier(finalCause: finalCause, evidence: evidence, now: now)
        let isSignature = tier != .none
        sharedDefaults?.set(isSignature, forKey: BubbleConstants.vpnLifecycleExternalKillSignatureKey)
        sharedDefaults?.set(tier.rawValue, forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey)
        if let cadence {
            sharedDefaults?.set(cadence, forKey: BubbleConstants.vpnLifecycleExternalKillCadenceSecondsKey)
        }
        sharedDefaults?.set(statusDropHistory(now: now).count, forKey: BubbleConstants.vpnLifecycleExternalKillDropCadenceWindowCountKey)
        sharedDefaults?.set(pressureCriticalDurationSeconds(now: now), forKey: BubbleConstants.vpnLifecycleExternalKillPressureCriticalDurationSecondsKey)
        sharedDefaults?.set(reclaimBlockedCountLastWindow(now: now), forKey: BubbleConstants.vpnLifecycleExternalKillReclaimBlockedCountLastWindowKey)
        if isSignature {
            sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleExternalKillDetectedTSKey)
            appendLog("External kill signature detected tier=\(tier.rawValue) cadence_seconds=\(cadence.map { String(format: "%.2f", $0) } ?? "unknown")")
        }
    }

    private func shouldVPNBeOnFromPolicy() -> Bool {
        let scheduleSnapshot = ScheduledProtectionStateStore.snapshot(defaults: sharedDefaults)
        if scheduleSnapshot.isDesiredProtectionActive() {
            if manualOffRequested {
                setManualOffRequested(false)
                appendLog("Schedule protection desired; clearing stale manual_off_requested")
            }
            return true
        }
        guard let data = sharedDefaults?.data(forKey: BubbleConstants.manualFeaturePolicyKey),
              var policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return false
        }
        policy.mergeDefaults()
        let instagramOn = policy.appToggles["instagram"]?["strict_reels"] == true ||
            policy.appToggles["instagram"]?["reels"] == true
        let tiktokOn = policy.appToggles["tiktok"]?["video_block"] == true
        let xOn = policy.appToggles["x"]?["feed_block"] == true ||
            policy.appToggles["x"]?["strict_feed_block"] == true
        return instagramOn || tiktokOn || xOn
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

    private func resetReconnectBreakerAfterHealthySessionIfNeeded(sessionDurationSeconds: TimeInterval, now: Date = Date()) {
        guard sessionDurationSeconds >= BubbleConstants.reconnectBreakerHealthySessionResetSeconds else { return }
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerRecentDisconnectsKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        reconnectBreakerLastSuppressed = false
        appendLog("Reconnect breaker reset after healthy session duration_seconds=\(Int(sessionDurationSeconds)) at=\(formatUnixTS(now.timeIntervalSince1970))")
    }

    private func recordUnexpectedDisconnectAndTripBreakerIfNeeded(
        shortLivedSession: Bool,
        finalCause: String,
        now: Date = Date()
    ) {
        guard shortLivedSession else { return }
        if isShortUnknownStatusDrop(finalCause: finalCause) {
            let decision = shortUnknownDropDecision(finalCause: finalCause, now: now)
            sharedDefaults?.set(decision.recentDropTimestamps, forKey: BubbleConstants.vpnLifecycleReconnectBreakerRecentDisconnectsKey)
            if decision.shouldSuppress {
                tripReconnectBreaker(
                    cooldown: Double.random(
                        in: BubbleConstants.reconnectBreakerMinCooldownSeconds...BubbleConstants.reconnectBreakerMaxCooldownSeconds
                    ),
                    now: now,
                    reason: "short_unknown_status_drop_breaker",
                    details: "recent_short_unknown_drops=\(decision.recentDropTimestamps.count)"
                )
                return
            }
        }

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
        let cooldown = max(
            BubbleConstants.reconnectBreakerMinCooldownSeconds,
            capped + Double.random(in: -jitter...jitter)
        )
        tripReconnectBreaker(
            cooldown: cooldown,
            now: now,
            reason: "short_lived_failure_score",
            details: "score=\(score) backoff_step=\(nextStep)"
        )
    }

    private func shortUnknownDropDecision(finalCause: String, now: Date = Date()) -> (shouldSuppress: Bool, recentDropTimestamps: [TimeInterval]) {
        let recent = sharedDefaults?.array(forKey: BubbleConstants.vpnLifecycleReconnectBreakerRecentDisconnectsKey) as? [TimeInterval] ?? []
        let nowTS = now.timeIntervalSince1970
        guard finalCause == "status_drop_without_stop_callback" else {
            let filtered = recent
                .filter { $0 > 0 && nowTS - $0 <= BubbleConstants.reconnectBreakerShortUnknownDropWindowSeconds }
                .sorted()
            return (false, filtered)
        }
        var filtered = recent
            .filter { $0 > 0 && nowTS - $0 <= BubbleConstants.reconnectBreakerShortUnknownDropWindowSeconds }
            .sorted()
        filtered.append(nowTS)
        return (filtered.count >= BubbleConstants.reconnectBreakerShortUnknownDropThreshold, filtered)
    }

    private func isShortUnknownStatusDrop(finalCause: String) -> Bool {
        if finalCause == "status_drop_without_stop_callback" {
            return true
        }
        let statusDropTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey) ?? 0
        guard statusDropTS > 0 else { return false }
        let terminalStopTunnelTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey) ?? 0
        let terminalTun2SocksTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey) ?? 0
        let signalTun2SocksTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey) ?? 0
        let terminalDeinitTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey) ?? 0
        return terminalStopTunnelTS <= 0 && terminalTun2SocksTS <= 0 && signalTun2SocksTS <= 0 && terminalDeinitTS <= 0
    }

    private func tripReconnectBreaker(
        cooldown: TimeInterval,
        now: Date,
        reason: String,
        details: String
    ) {
        let boundedCooldown = min(
            BubbleConstants.reconnectBreakerMaxCooldownSeconds,
            max(BubbleConstants.reconnectBreakerMinCooldownSeconds, cooldown)
        )
        let until = now.timeIntervalSince1970 + boundedCooldown
        sharedDefaults?.set(until, forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        let trips = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey) ?? 0
        sharedDefaults?.set(trips + 1, forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey)
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        sharedDefaults?.set(reason, forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey)
        appendLog("Reconnect breaker trip: \(reason) \(details) cooldown=\(Int(boundedCooldown))s")
    }

    private func recoverReconnectBreakerIfNeeded(now: Date = Date()) {
        let sessionDuration = currentSessionDurationSeconds(now: now)
        if sessionDuration >= BubbleConstants.reconnectBreakerHealthySessionResetSeconds {
            sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
            sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey)
            sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerRecentDisconnectsKey)
            sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        }
        guard reconnectBreakerLastSuppressed || reconnectBreakerRemainingCooldownSeconds(now: now) != nil else { return }
        sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleReconnectBreakerFailureScoreKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        reconnectBreakerLastSuppressed = false
        appendLog("Reconnect breaker recovered: cooldown -> healthy")
    }

    private func reconnectAttemptBackoffSeconds() -> Double {
        switch reconnectAttempts {
        case ..<2:
            return 1.0
        case 2:
            return 2.0
        default:
            return 4.0
        }
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
        expectedDisconnect: Bool = true,
        now: Date = Date()
    ) -> StopResolution {
        if stopSource == "stopTunnel" {
            guard expectedDisconnect else {
                let inferredReason = stopReasonRaw.isEmpty ? "unexpected_stop_tunnel_while_policy_desired_on" : stopReasonRaw
                sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey)
                sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleInferredCrashKey)
                sharedDefaults?.set(inferredReason, forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey)
                sharedDefaults?.set(ResolvedStopClass.inferredCrash.rawValue, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
                return StopResolution(resolvedClass: .inferredCrash, stopSource: "inferred_crash", stopReason: "unexpected_stop_tunnel_while_policy_desired_on", stopReasonRaw: inferredReason, didPersistFallback: true)
            }
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

    private func incrementReconnectSuppressedByBreaker(reason: String = "reconnect_suppressed") {
        let key = BubbleConstants.vpnLifecycleReconnectSuppressedByBreakerKey
        let current = sharedDefaults?.integer(forKey: key) ?? 0
        sharedDefaults?.set(current + 1, forKey: key)
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        sharedDefaults?.set(reason, forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey)
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

        let tunnelContent = Self.tailForDisplay(
            (try? String(contentsOf: tunnelFileURL, encoding: .utf8)) ?? "(no extension logs found at \(tunnelFileURL.path))",
            maxLines: 600
        )
        let appContent = Self.tailForDisplay(AppDiagnosticsLogger.readLog(), maxLines: 400)
        let lifecycleSummary = renderLifecycleSummary()
        let runbookSummary = renderRunbookSummary()
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
            "=== RUNBOOK ===",
            runbookSummary,
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

    private static func tailForDisplay(_ content: String, maxLines: Int) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return content }
        let omitted = lines.count - maxLines
        return "...\(omitted) older lines omitted from UI; full logs remain in the app-group artifacts.\n" +
            lines.suffix(maxLines).joined(separator: "\n")
    }

    private func renderLifecycleSummary() -> String {
        let eventIDForRender = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        let eventStartForRender = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey) ?? 0
        let hasFinal = !(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? "").isEmpty
        if !eventIDForRender.isEmpty,
           !hasFinal,
           eventStartForRender > 0,
           Date().timeIntervalSince1970 - eventStartForRender >= attributionWindowSeconds() {
            finalizeStopAttributionIfNeeded(eventID: eventIDForRender)
        }

        let lastStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastStartTSKey) ?? 0
        let lastStop = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastStopTSKey) ?? 0
        let lastHeartbeat = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        let stopReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonKey) ?? "unknown"
        let stopSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSourceKey) ?? "unknown"
        let stopReasonRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopReasonRawKey) ?? ""
        let stopOrigin = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastStopOriginKey) ?? "unknown"
        let observedPendingStopID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastStopObservedPendingIDKey) ?? ""
        let pendingStopID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecyclePendingStopIDKey) ?? ""
        let pendingStopSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecyclePendingStopSourceKey) ?? ""
        let pendingStopTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecyclePendingStopTSKey) ?? 0
        let sessionID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleSessionIDKey) ?? ""
        let stopEventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        let stopEventStartTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey) ?? 0
        let stopCauseFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let stopCauseConfidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey) ?? ""
        let stopCauseEvidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey) ?? ""
        let stopSignalOrder = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey) ?? ""
        let stopCauseFinalizedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey) ?? 0
        let lastCompletedStopEventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopEventIDKey) ?? ""
        let lastCompletedStopCauseFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ?? ""
        let lastCompletedStopCauseConfidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseConfidenceKey) ?? ""
        let lastCompletedStopCauseEvidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseEvidenceKey) ?? ""
        let lastCompletedStopSignalOrder = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSignalOrderKey) ?? ""
        let lastCompletedStopFinalizedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastCompletedStopFinalizedTSKey) ?? 0
        let lastCompletedStopSeq = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSeqKey) ?? 0
        let diagnosticHoldEnabled = diagnosticHoldEnabled()
        let diagnosticHoldSeconds = diagnosticHoldSeconds()
        let terminalSeenStopTunnelTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey) ?? 0
        let terminalSeenTun2SocksTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey) ?? 0
        let terminalSeenProviderDeinitTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey) ?? 0
        let remediationPath = remediationPath(for: lastCompletedStopCauseFinal)
        let neStopRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonRawKey) ?? ""
        let neStopName = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonNameKey) ?? ""
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
        let diagnosticModeSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDiagnosticModeSourceKey) ?? "default_off"
        let diagnosticAutoEnabledUntil = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDiagnosticAutoEnabledUntilTSKey) ?? 0
        let dropLoopCount = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDropLoopCountKey) ?? 0
        let dropLoopWindowStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDropLoopWindowStartTSKey) ?? 0
        let diagnosticComplete = isDiagnosticComplete()
        let nextAction = nextActionForRemediationPath(remediationPath)
        let externalKillSignature = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureKey) ?? false
        let externalKillSignatureTier = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        let externalKillDetectedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillDetectedTSKey) ?? 0
        let externalKillCadence = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillCadenceSecondsKey) ?? 0
        let externalKillCadenceWindowCount = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleExternalKillDropCadenceWindowCountKey) ?? 0
        let externalKillHeartbeatStaleAtDrop = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillHeartbeatStaleSecondsAtDropKey) ?? -1
        let externalKillReclaimBlocked = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleExternalKillReclaimBlockedCountLastWindowKey) ?? 0
        let externalKillCriticalDuration = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillPressureCriticalDurationSecondsKey) ?? 0
        let externalKillReconnectAttempts = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleExternalKillReconnectAttemptsInWindowKey) ?? 0
        let externalKillReconnectCapActive = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleExternalKillReconnectCapActiveKey) ?? false
        let externalKillReconnectNextAllowed = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExternalKillReconnectNextAllowedTSKey) ?? 0
        let externalKillReconnectSuppressionState = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillReconnectSuppressionStateKey) ?? "inactive"
        let lastReconnectDelay = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastReconnectDelaySecondsKey) ?? 0
        let startupStabilityPhase = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStartupStabilityPhaseKey) ?? "unknown"
        let startupProbeCompleted = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedKey) ?? false
        let startupProbeCompletedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedTSKey) ?? 0
        let tun2socksStartupMode = sharedDefaults?.string(forKey: BubbleConstants.tun2socksStartupModeKey) ??
            BubbleConstants.tun2socksStartupModeStagedAfterConnect
        let transportReady = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleTransportReadyKey) ?? false
        let transportReadyTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleTransportReadyTSKey) ?? 0
        let dnsStartupDrainActive = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDNSStartupDrainActiveKey) ?? false
        let dnsStartupDrainCloses = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDNSStartupDrainClosesKey) ?? 0
        let dnsStartupDrainFramesProcessed = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDNSStartupDrainFramesProcessedKey) ?? 0
        let earlyReconnectSuppressed = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey) ?? false
        let iosSafeModeReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey) ?? ""
        let holdElapsedMS = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDiagnosticHoldElapsedMSKey) ?? 0
        let holdCompleted = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDiagnosticHoldCompletedKey) ?? false
        let appLifecycleEvent = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventKey) ?? "unknown"
        let appLifecycleEventTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventTSKey) ?? 0
        let lastBreadcrumb = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastBreadcrumbKey) ?? "unknown"
        let lastBreadcrumbTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastBreadcrumbTSKey) ?? 0
        let lastBreadcrumbDetails = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastBreadcrumbDetailsKey) ?? ""
        let providerLastPhase = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey) ?? "unknown"
        let providerLastPhaseTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseTSKey) ?? 0
        let providerPhaseRingJSON = sharedDefaults?.string(forKey: BubbleConstants.providerPhaseRingJSONKey) ?? "[]"
        let providerHeartbeatSnapshotJSON = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProviderHeartbeatSnapshotJSONKey) ?? "{}"
        let providerHeartbeatFields = providerHeartbeatSnapshotFields(providerHeartbeatSnapshotJSON)
        let udpLastControlStreamJSON = sharedDefaults?.string(forKey: BubbleConstants.udpLastControlStreamJSONKey) ?? "{}"
        let udpLastDNSCloseJSON = sharedDefaults?.string(forKey: BubbleConstants.udpLastDNSCloseJSONKey) ?? "{}"
        let udpLastDecoderEventJSON = sharedDefaults?.string(forKey: BubbleConstants.udpLastDecoderEventJSONKey) ?? "{}"
        let tun2socksLastStatsJSON = sharedDefaults?.string(forKey: BubbleConstants.tun2socksLastStatsJSONKey) ?? "{}"
        let udpCrashGuardUntil = sharedDefaults?.double(forKey: BubbleConstants.udpCrashGuardUntilKey) ?? 0
        let udpCrashGuardReason = sharedDefaults?.string(forKey: BubbleConstants.udpCrashGuardReasonKey) ?? ""
        let udpCrashGuardHits = sharedDefaults?.integer(forKey: BubbleConstants.udpCrashGuardHitsKey) ?? 0
        let appState = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppStateKey) ?? "unknown"
        let protectedDataAvailable = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleProtectedDataAvailableKey) ?? false
        let thermalState = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppThermalStateKey) ?? "unknown"
        let memoryWarningTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppMemoryWarningTSKey) ?? 0
        let extensionPressureSampleTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExtensionPressureLastSampleTSKey) ?? 0
        let extensionPressureRuntime = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExtensionPressureRuntimeSecondsKey) ?? 0
        let extensionPressureMemory = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleExtensionPressureMemoryMBKey) ?? -1
        let scheduleSnapshot = ScheduledProtectionStateStore.snapshot(defaults: sharedDefaults)
        let integrityMissing: [String] = [
            stopEventStartTS > 0 ? nil : "stop_event_start",
            (sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryLifecycleEventKey)?.isEmpty == false) ? nil : "drop_boundary_lifecycle",
            (sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryThermalStateKey)?.isEmpty == false) ? nil : "drop_boundary_thermal",
            extensionPressureSampleTS > 0 ? nil : "extension_pressure_sample"
        ].compactMap { $0 }
        let reportIntegrityState = integrityMissing.isEmpty ? "ok" : "missing_\(integrityMissing.joined(separator: ","))"
        let effectiveFinalCause = lastCompletedStopCauseFinal.isEmpty ? stopCauseFinal : lastCompletedStopCauseFinal
        let disconnectTransportCause = classifyDisconnectTransportCause(
            finalCause: effectiveFinalCause,
            providerLastPhase: providerLastPhase,
            tun2socksExitObserved: effectiveFinalCause == "tun2socks_exit" || terminalSeenTun2SocksTS > 0,
            lastDecoderEventJSON: udpLastDecoderEventJSON,
            lastHeartbeatSnapshotJSON: providerHeartbeatSnapshotJSON
        )
        let lifecycleCategory = disconnectLifecycleCategory(
            finalCause: effectiveFinalCause,
            externalKillTier: externalKillSignatureTier
        )
        sharedDefaults?.set(diagnosticComplete, forKey: BubbleConstants.vpnLifecycleDiagnosticCompletenessKey)
        sharedDefaults?.set(remediationPath, forKey: BubbleConstants.vpnLifecycleRemediationPathKey)
        sharedDefaults?.set(nextAction, forKey: BubbleConstants.vpnLifecycleNextActionKey)

        return [
            "status=\(statusString)",
            "tunnel_operational=\(vpnStatus == .connected)",
            "policy_enabled=\(shouldVPNBeOnFromPolicy())",
            "manual_off_requested=\(manualOffRequested)",
            "schedule_desired_vpn_on=\(scheduleSnapshot.isDesiredProtectionActive())",
            "schedule_desired_vpn_on_raw=\(scheduleSnapshot.desiredVPNOn)",
            "schedule_desired_until=\(formatUnixTS(scheduleSnapshot.desiredUntil))",
            "schedule_manual_off_until=\(formatUnixTS(scheduleSnapshot.manualOffUntil))",
            "schedule_active_app_ids=\(scheduleSnapshot.activeAppIDs.sorted().joined(separator: ","))",
            "schedule_active_window_ids=\(scheduleSnapshot.activeWindowIDs.sorted().joined(separator: ","))",
            "schedule_last_interruption_at=\(formatUnixTS(scheduleSnapshot.lastInterruptionAt))",
            "schedule_last_repair_result=\(scheduleSnapshot.lastRepairResult.isEmpty ? "none" : scheduleSnapshot.lastRepairResult)",
            "last_start=\(formatUnixTS(lastStart))",
            "last_stop=\(formatUnixTS(lastStop))",
            "last_stop_source=\(stopSource)",
            "last_stop_reason=\(stopReason)",
            "last_stop_reason_raw=\(stopReasonRaw)",
            "last_stop_origin=\(stopOrigin)",
            "last_stop_observed_pending_id=\(observedPendingStopID)",
            "pending_stop_id=\(pendingStopID)",
            "pending_stop_source=\(pendingStopSource)",
            "pending_stop_ts=\(formatUnixTS(pendingStopTS))",
            "session_id=\(sessionID)",
            "stop_event_id=\(stopEventID)",
            "stop_event_start=\(formatUnixTS(stopEventStartTS))",
            "stop_cause_final=\(stopCauseFinal)",
            "stop_cause_confidence=\(stopCauseConfidence)",
            "stop_cause_evidence=\(stopCauseEvidence)",
            "stop_signal_order=\(stopSignalOrder)",
            "stop_cause_finalized_at=\(formatUnixTS(stopCauseFinalizedTS))",
            "last_completed_stop_event_id=\(lastCompletedStopEventID)",
            "last_completed_stop_cause_final=\(lastCompletedStopCauseFinal)",
            "last_completed_stop_cause_confidence=\(lastCompletedStopCauseConfidence)",
            "last_completed_stop_cause_evidence=\(lastCompletedStopCauseEvidence)",
            "last_completed_stop_signal_order=\(lastCompletedStopSignalOrder)",
            "last_completed_stop_finalized_at=\(formatUnixTS(lastCompletedStopFinalizedTS))",
            "last_completed_stop_seq=\(lastCompletedStopSeq)",
            "disconnect_transport_suspected_cause=\(disconnectTransportCause)",
            "disconnect_lifecycle_category=\(lifecycleCategory)",
            "diagnostic_complete=\(diagnosticComplete)",
            "diagnostic_hold_enabled=\(diagnosticHoldEnabled)",
            "diagnostic_hold_seconds=\(String(format: "%.2f", diagnosticHoldSeconds))",
            "diagnostic_mode_source=\(diagnosticModeSource)",
            "diagnostic_auto_enabled_until=\(formatUnixTS(diagnosticAutoEnabledUntil))",
            "drop_loop_count_in_window=\(dropLoopCount)",
            "drop_loop_window_start=\(formatUnixTS(dropLoopWindowStart))",
            "external_kill_signature=\(externalKillSignature)",
            "external_kill_signature_tier=\(externalKillSignatureTier)",
            "external_kill_detected_at=\(formatUnixTS(externalKillDetectedTS))",
            "external_kill_drop_cadence_seconds=\(externalKillCadence > 0 ? String(format: "%.2f", externalKillCadence) : "unknown")",
            "drop_cadence_window_count=\(externalKillCadenceWindowCount)",
            "heartbeat_stale_seconds_at_drop=\(externalKillHeartbeatStaleAtDrop >= 0 ? String(Int(externalKillHeartbeatStaleAtDrop)) : "unknown")",
            "reclaim_blocked_count_last_window=\(externalKillReclaimBlocked)",
            "pressure_critical_duration_seconds=\(externalKillCriticalDuration > 0 ? String(Int(externalKillCriticalDuration)) : "0")",
            "external_kill_reconnect_attempts_in_window=\(externalKillReconnectAttempts)",
            "external_kill_reconnect_cap_active=\(externalKillReconnectCapActive)",
            "external_kill_reconnect_next_allowed_at=\(formatUnixTS(externalKillReconnectNextAllowed))",
            "external_kill_reconnect_suppression_state=\(externalKillReconnectSuppressionState)",
            "last_reconnect_delay_seconds=\(lastReconnectDelay > 0 ? String(format: "%.2f", lastReconnectDelay) : "unknown")",
            "startup_stability_phase=\(startupStabilityPhase)",
            "startup_probe_completed=\(startupProbeCompleted)",
            "startup_probe_completed_at=\(formatUnixTS(startupProbeCompletedTS))",
            "tun2socks_startup_mode=\(tun2socksStartupMode)",
            "tun2socks_launch_delay_seconds=\(String(format: "%.2f", BubbleConstants.tun2socksPostConnectLaunchDelaySeconds))",
            "transport_ready=\(transportReady)",
            "transport_ready_at=\(formatUnixTS(transportReadyTS))",
            "dns_startup_drain_active=\(dnsStartupDrainActive)",
            "dns_startup_drain_closes=\(dnsStartupDrainCloses)",
            "dns_startup_drain_frames_processed=\(dnsStartupDrainFramesProcessed)",
            "early_reconnect_suppressed=\(earlyReconnectSuppressed)",
            "ios_safe_mode_reason=\(iosSafeModeReason.isEmpty ? "none" : iosSafeModeReason)",
            "diagnostic_hold_elapsed_ms=\(holdElapsedMS)",
            "diagnostic_hold_completed=\(holdCompleted)",
            "app_lifecycle_last_event=\(appLifecycleEvent)",
            "app_lifecycle_last_event_at=\(formatUnixTS(appLifecycleEventTS))",
            "last_breadcrumb_before_death=\(lastBreadcrumb)",
            "last_breadcrumb_at=\(formatUnixTS(lastBreadcrumbTS))",
            "last_breadcrumb_details=\(lastBreadcrumbDetails)",
            "provider_last_phase=\(providerLastPhase)",
            "provider_last_phase_at=\(formatUnixTS(providerLastPhaseTS))",
            "provider_phase_ring_json=\(providerPhaseRingJSON)",
            "provider_last_heartbeat_snapshot_json=\(providerHeartbeatSnapshotJSON)",
            "provider_heartbeat_provider_phase=\(providerHeartbeatFields["provider_phase"] ?? "unknown")",
            "provider_heartbeat_memory_mb=\(providerHeartbeatFields["memory_mb"] ?? "unknown")",
            "provider_heartbeat_tun2socks_up_packets=\(providerHeartbeatFields["tun2socks_up_packets"] ?? "unknown")",
            "provider_heartbeat_tun2socks_down_packets=\(providerHeartbeatFields["tun2socks_down_packets"] ?? "unknown")",
            "provider_heartbeat_active_udp=\(providerHeartbeatFields["active_udp"] ?? "unknown")",
            "provider_heartbeat_queued_udp=\(providerHeartbeatFields["queued_udp"] ?? "unknown")",
            "provider_heartbeat_last_udp_close_phase=\(providerHeartbeatFields["last_udp_close_phase"] ?? "unknown")",
            "provider_heartbeat_last_decoder_event=\(providerHeartbeatFields["last_decoder_event"] ?? "{}")",
            "provider_heartbeat_last_dns_close=\(providerHeartbeatFields["last_dns_close"] ?? "{}")",
            "provider_heartbeat_app_lifecycle=\(providerHeartbeatFields["app_lifecycle"] ?? "unknown")",
            "provider_heartbeat_path_status=\(providerHeartbeatFields["path_status"] ?? "unknown")",
            "provider_heartbeat_path_unsatisfied_reason=\(providerHeartbeatFields["path_unsatisfied_reason"] ?? "unknown")",
            "provider_heartbeat_startup_stability_phase=\(providerHeartbeatFields["startup_stability_phase"] ?? "unknown")",
            "provider_heartbeat_startup_probe_completed=\(providerHeartbeatFields["startup_probe_completed"] ?? "false")",
            "provider_heartbeat_proxy_ready=\(providerHeartbeatFields["proxy_ready"] ?? "false")",
            "provider_heartbeat_dns_startup_drain_active=\(providerHeartbeatFields["dns_startup_drain_active"] ?? "false")",
            "provider_heartbeat_dns_startup_drain_closes=\(providerHeartbeatFields["dns_startup_drain_closes"] ?? "0")",
            "provider_heartbeat_dns_startup_drain_frames_processed=\(providerHeartbeatFields["dns_startup_drain_frames_processed"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_requests=\(providerHeartbeatFields["dns_fast_lane_requests"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_responses=\(providerHeartbeatFields["dns_fast_lane_responses"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_failures=\(providerHeartbeatFields["dns_fast_lane_failures"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_parse_failed=\(providerHeartbeatFields["dns_fast_lane_parse_failed"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_close=\(providerHeartbeatFields["dns_fast_lane_close"] ?? "0")",
            "provider_heartbeat_dns_fast_lane_disabled=\(providerHeartbeatFields["dns_fast_lane_disabled"] ?? "false")",
            "provider_heartbeat_dns_fast_lane_disabled_reason=\(providerHeartbeatFields["dns_fast_lane_disabled_reason"] ?? "none")",
            "provider_heartbeat_udp_non_dns_rejects=\(providerHeartbeatFields["udp_non_dns_rejects"] ?? "0")",
            "provider_heartbeat_udp_quic_rejects=\(providerHeartbeatFields["udp_quic_rejects"] ?? "0")",
            "provider_heartbeat_early_reconnect_suppressed=\(providerHeartbeatFields["early_reconnect_suppressed"] ?? "false")",
            "provider_heartbeat_ios_safe_mode_reason=\(providerHeartbeatFields["ios_safe_mode_reason"] ?? "none")",
            "udp_last_control_stream_json=\(udpLastControlStreamJSON)",
            "udp_last_dns_close_json=\(udpLastDNSCloseJSON)",
            "udp_last_decoder_event_json=\(udpLastDecoderEventJSON)",
            "tun2socks_last_stats_json=\(tun2socksLastStatsJSON)",
            "udp_crash_guard_until=\(formatUnixTS(udpCrashGuardUntil))",
            "udp_crash_guard_reason=\(udpCrashGuardReason.isEmpty ? "none" : udpCrashGuardReason)",
            "udp_crash_guard_hits=\(udpCrashGuardHits)",
            "app_lifecycle_current_state=\(appState)",
            "app_last_foreground_at=\(formatUnixTS(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppLastForegroundTSKey) ?? 0))",
            "app_last_background_at=\(formatUnixTS(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppLastBackgroundTSKey) ?? 0))",
            "app_last_inactive_at=\(formatUnixTS(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppLastInactiveTSKey) ?? 0))",
            "app_last_protected_data_unavailable_at=\(formatUnixTS(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleProtectedDataUnavailableTSKey) ?? 0))",
            "protected_data_available=\(protectedDataAvailable)",
            "app_thermal_state=\(thermalState)",
            "app_last_memory_warning_at=\(formatUnixTS(memoryWarningTS))",
            "stop_terminal_seen_stop_tunnel_at=\(formatUnixTS(terminalSeenStopTunnelTS))",
            "stop_terminal_seen_tun2socks_exit_at=\(formatUnixTS(terminalSeenTun2SocksTS))",
            "stop_terminal_seen_provider_deinit_at=\(formatUnixTS(terminalSeenProviderDeinitTS))",
            "remediation_path=\(remediationPath)",
            "next_action=\(nextAction)",
            "ne_stop_reason_mapping=raw=\(neStopRaw),name=\(neStopName)",
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
            "reconnect_suppressed_by_breaker=\(reconnectSuppressedByBreaker)",
            "drop_boundary_app_state=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryAppStateKey) ?? "unknown")",
            "app_lifecycle_at_drop=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryLifecycleEventKey) ?? "unknown")",
            "protected_data_available_at_drop=\(sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleDropBoundaryProtectedDataAvailableKey) ?? false)",
            "thermal_state_at_drop=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryThermalStateKey) ?? "unknown")",
            "memory_warning_age_seconds=\((sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDropBoundaryMemoryWarningAgeSecondsKey) ?? -1) >= 0 ? String(Int(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDropBoundaryMemoryWarningAgeSecondsKey) ?? -1)) : "unknown")",
            "drop_boundary_profile_op_delta_ms=\((sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleDropBoundaryProfileOpDeltaMSKey) as? Int).map(String.init) ?? "unknown")",
            "drop_boundary_lock_sleep_hint=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleDropBoundaryLockSleepHintKey) ?? "unknown")",
            "drop_boundary_ts=\(formatUnixTS(sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleDropBoundaryTSKey) ?? 0))",
            "extension_pressure_last_sample_at=\(formatUnixTS(extensionPressureSampleTS))",
            "extension_pressure_runtime_seconds=\(extensionPressureRuntime > 0 ? String(Int(extensionPressureRuntime)) : "unknown")",
            "extension_pressure_level=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureLevelKey) ?? "unknown")",
            "extension_memory_mb=\(extensionPressureMemory >= 0 ? String(format: "%.1f", extensionPressureMemory) : "unknown")",
            "extension_cpu_percent=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureCPUPercentKey) ?? "unknown")",
            "extension_udp_active=\(sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleExtensionPressureUDPActiveKey).map { "\($0)" } ?? "unknown")",
            "extension_udp_queued=\(sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleExtensionPressureUDPQueuedKey).map { "\($0)" } ?? "unknown")",
            "extension_degraded_state=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureDegradedStateKey) ?? "unknown")",
            "extension_pressure_action=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureActionKey) ?? "unknown")",
            "extension_pressure_app_lifecycle=\(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExtensionPressureAppLifecycleKey) ?? "unknown")",
            "report_integrity=\(reportIntegrityState)"
        ].joined(separator: "\n")
    }

    private func classifyDisconnectTransportCause(
        finalCause: String,
        providerLastPhase: String,
        tun2socksExitObserved: Bool,
        lastDecoderEventJSON: String,
        lastHeartbeatSnapshotJSON: String
    ) -> String {
        _ = lastDecoderEventJSON
        if finalCause == "tun2socks_exit" || tun2socksExitObserved {
            return "tun2socks_native_exit"
        }
        guard finalCause == "status_drop_without_stop_callback" else {
            return finalCause.isEmpty ? "unknown" : finalCause
        }
        let heartbeatFields = providerHeartbeatSnapshotFields(lastHeartbeatSnapshotJSON)
        let snapshotPhaseField = heartbeatFields["provider_phase"] ?? "unknown"
        let snapshotPhase = snapshotPhaseField == "unknown" ? providerLastPhase : snapshotPhaseField
        let queueDepth = heartbeatFields["queued_udp"].flatMap(Int.init) ?? -1
        let lastUDPClosePhase = heartbeatFields["last_udp_close_phase"] ?? ""
        if queueDepth >= BubbleConstants.safeModeMaxQueuedUDPControlStreams &&
            lastUDPClosePhase == "grace_close_blocked" {
            return "suspected_udp_startup_guard_saturation"
        }
        let dnsChurnPhases: Set<String> = [
            "dns_one_shot_close",
            "dns_startup_drain_close",
            "dns_response_send",
            "dns_fast_lane_response_send_start",
            "dns_fast_lane_response_sent",
            "dns_fast_lane_close",
            "decoder_recovery",
        ]
        if dnsChurnPhases.contains(snapshotPhase) || dnsChurnPhases.contains(providerLastPhase) {
            return "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn"
        }
        return "suspected_provider_silent_exit"
    }

    private func disconnectLifecycleCategory(finalCause: String, externalKillTier: String) -> String {
        guard finalCause == "status_drop_without_stop_callback" else { return "none" }
        return externalKillTier == ExternalKillSignatureTier.none.rawValue ? "none" : externalKillTier
    }

    private func providerHeartbeatSnapshotFields(_ raw: String) -> [String: String] {
        let snapshot = decodeJSONObject(raw)
        let pathState = snapshot["path_state"] as? [String: Any] ?? [:]
        return [
            "provider_phase": stringValue(from: snapshot["provider_phase"], fallback: "unknown"),
            "startup_stability_phase": stringValue(from: snapshot["startup_stability_phase"], fallback: "unknown"),
            "startup_probe_completed": stringValue(from: snapshot["startup_probe_completed"], fallback: "false"),
            "proxy_ready": stringValue(from: snapshot["proxy_ready"], fallback: "false"),
            "memory_mb": stringValue(from: snapshot["memory_mb"], fallback: "unknown"),
            "tun2socks_up_packets": stringValue(from: snapshot["tun2socks_up_packets"], fallback: "unknown"),
            "tun2socks_down_packets": stringValue(from: snapshot["tun2socks_down_packets"], fallback: "unknown"),
            "active_udp": stringValue(from: snapshot["active_udp"], fallback: "unknown"),
            "queued_udp": stringValue(from: snapshot["queued_udp"], fallback: "unknown"),
            "last_udp_close_phase": stringValue(from: snapshot["last_udp_close_phase"], fallback: "unknown"),
            "dns_startup_drain_active": stringValue(from: snapshot["dns_startup_drain_active"], fallback: "false"),
            "dns_startup_drain_closes": stringValue(from: snapshot["dns_startup_drain_closes"], fallback: "0"),
            "dns_startup_drain_frames_processed": stringValue(from: snapshot["dns_startup_drain_frames_processed"], fallback: "0"),
            "dns_fast_lane_requests": stringValue(from: snapshot["dns_fast_lane_requests"], fallback: "0"),
            "dns_fast_lane_responses": stringValue(from: snapshot["dns_fast_lane_responses"], fallback: "0"),
            "dns_fast_lane_failures": stringValue(from: snapshot["dns_fast_lane_failures"], fallback: "0"),
            "dns_fast_lane_parse_failed": stringValue(from: snapshot["dns_fast_lane_parse_failed"], fallback: "0"),
            "dns_fast_lane_close": stringValue(from: snapshot["dns_fast_lane_close"], fallback: "0"),
            "dns_fast_lane_disabled": stringValue(from: snapshot["dns_fast_lane_disabled"], fallback: "false"),
            "dns_fast_lane_disabled_reason": stringValue(from: snapshot["dns_fast_lane_disabled_reason"], fallback: ""),
            "udp_non_dns_rejects": stringValue(from: snapshot["udp_non_dns_rejects"], fallback: "0"),
            "udp_quic_rejects": stringValue(from: snapshot["udp_quic_rejects"], fallback: "0"),
            "early_reconnect_suppressed": stringValue(from: snapshot["early_reconnect_suppressed"], fallback: "false"),
            "ios_safe_mode_reason": stringValue(from: snapshot["ios_safe_mode_reason"], fallback: ""),
            "last_decoder_event": jsonString(from: snapshot["last_decoder_event"], fallback: "{}"),
            "last_dns_close": jsonString(from: snapshot["last_dns_close"], fallback: "{}"),
            "app_lifecycle": stringValue(from: snapshot["app_lifecycle"], fallback: "unknown"),
            "path_status": stringValue(from: pathState["status"], fallback: "unknown"),
            "path_unsatisfied_reason": stringValue(from: pathState["unsatisfied_reason"], fallback: "unknown"),
        ]
    }

    private func decodeJSONObject(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return parsed
    }

    private func stringValue(from value: Any?, fallback: String) -> String {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(Int(double))
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return fallback
    }

    private func jsonString(from value: Any?, fallback: String) -> String {
        guard let value else { return fallback }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return json
    }

    private func remediationPath(for finalCause: String) -> String {
        if finalCause.hasPrefix("os_stop_reason_") {
            return "ne_session_or_profile_fix"
        }
        if finalCause == "tun2socks_exit" {
            return "tun2socks_transport_fix"
        }
        if finalCause == "provider_deinit_without_stop" {
            return "provider_lifecycle_fix"
        }
        if finalCause == "status_drop_without_stop_callback" {
            return "ne_external_lifecycle_investigation"
        }
        return "ne_external_lifecycle_investigation"
    }

    private func renderRunbookSummary() -> String {
        let lastCompletedStopEventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopEventIDKey) ?? ""
        let lastCompletedStopCauseFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ?? ""
        let lastCompletedStopSignalOrder = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSignalOrderKey) ?? ""
        let remediationPath = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleRemediationPathKey) ?? remediationPath(for: lastCompletedStopCauseFinal)
        let nextAction = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleNextActionKey) ?? nextActionForRemediationPath(remediationPath)
        let externalKillSignature = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureKey) ?? false
        let externalKillTier = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleExternalKillSignatureTierKey) ?? ExternalKillSignatureTier.none.rawValue
        let iosSafeModeReason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey) ?? ""
        let earlyReconnectSuppressed = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey) ?? false
        return [
            "latest_last_completed_stop_event_id=\(lastCompletedStopEventID)",
            "latest_last_completed_stop_cause_final=\(lastCompletedStopCauseFinal)",
            "latest_last_completed_stop_signal_order=\(lastCompletedStopSignalOrder)",
            "external_kill_signature=\(externalKillSignature)",
            "external_kill_signature_tier=\(externalKillTier)",
            "ios_safe_mode_reason=\(iosSafeModeReason.isEmpty ? "none" : iosSafeModeReason)",
            "early_reconnect_suppressed=\(earlyReconnectSuppressed)",
            "resolved_remediation_path=\(remediationPath)",
            "next_action=\(nextAction)"
        ].joined(separator: "\n")
    }

    private func nextActionForRemediationPath(_ path: String) -> String {
        switch path {
        case "ne_session_or_profile_fix":
            return "apply_profile_churn_reduction_and_reconnect_debounce"
        case "tun2socks_transport_fix":
            return "apply_transport_restart_once_then_backoff_with_exit_code_routing"
        case "provider_lifecycle_fix":
            return "reduce_provider_pressure_and_check_watchdog_markers"
        case "ne_external_lifecycle_investigation":
            return "capture_path_and_app_state_at_drop_then_enable_resilience_mode"
        default:
            return "capture_path_and_app_state_at_drop_then_enable_resilience_mode"
        }
    }

    private func isDiagnosticComplete() -> Bool {
        let eventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopEventIDKey) ?? ""
        let final = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ?? ""
        let order = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSignalOrderKey) ?? ""
        let seq = sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleLastCompletedStopSeqKey) ?? 0
        return !eventID.isEmpty && !final.isEmpty && !order.isEmpty && seq > 0
    }

    private func captureDropBoundaryContext(now: Date) {
        let state = currentApplicationStateString()
        let lockSleepHint = state == "background" ? "possible_lock_or_sleep" : "foreground"
        let memoryWarningTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleAppMemoryWarningTSKey) ?? 0
        let memoryWarningAge = memoryWarningTS > 0 ? now.timeIntervalSince1970 - memoryWarningTS : -1
        let lastHeartbeat = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        let heartbeatStale = lastHeartbeat > 0 ? max(0, now.timeIntervalSince1970 - lastHeartbeat) : -1
        let eventStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey) ?? now.timeIntervalSince1970
        let profileDelta = nearestProfileOpDeltaMS(nowTS: now.timeIntervalSince1970, eventStartTS: eventStart)
        sharedDefaults?.set(state, forKey: BubbleConstants.vpnLifecycleDropBoundaryAppStateKey)
        sharedDefaults?.set(lockSleepHint, forKey: BubbleConstants.vpnLifecycleDropBoundaryLockSleepHintKey)
        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleDropBoundaryTSKey)
        sharedDefaults?.set(sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventKey) ?? "unknown", forKey: BubbleConstants.vpnLifecycleDropBoundaryLifecycleEventKey)
        sharedDefaults?.set(UIApplication.shared.isProtectedDataAvailable, forKey: BubbleConstants.vpnLifecycleDropBoundaryProtectedDataAvailableKey)
        sharedDefaults?.set(currentThermalStateString(), forKey: BubbleConstants.vpnLifecycleDropBoundaryThermalStateKey)
        sharedDefaults?.set(memoryWarningAge, forKey: BubbleConstants.vpnLifecycleDropBoundaryMemoryWarningAgeSecondsKey)
        if heartbeatStale >= 0 {
            sharedDefaults?.set(heartbeatStale, forKey: BubbleConstants.vpnLifecycleExternalKillHeartbeatStaleSecondsAtDropKey)
        }
        if let profileDelta {
            sharedDefaults?.set(profileDelta, forKey: BubbleConstants.vpnLifecycleDropBoundaryProfileOpDeltaMSKey)
        }
    }

    private func renderPolicySummary() -> String {
        guard let data = sharedDefaults?.data(forKey: BubbleConstants.featurePolicyKey),
              var policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return "featurePolicyV1 missing"
        }
        policy.mergeDefaults()

        return [
            "revision=\(policy.revision)",
            "updated_by=\(policy.updatedBy)",
            "updated_at=\(formatUnixTS(policy.updatedAt))",
            "toggles=\(policy.appToggles)"
        ].joined(separator: "\n")
    }

    private func renderTrafficSummary(statsFileURL: URL) -> String {
        guard FileManager.default.fileExists(atPath: statsFileURL.path) else {
            return "traffic stats unavailable reason=file_missing path=\(statsFileURL.path)"
        }
        let data: Data
        do {
            data = try Data(contentsOf: statsFileURL)
        } catch {
            return "traffic stats unavailable reason=decode_failed path=\(statsFileURL.path) byte_count=0"
        }
        let byteCount = data.count
        let trafficData: TrafficData
        do {
            trafficData = try JSONDecoder().decode(TrafficData.self, from: data)
        } catch {
            return "traffic stats unavailable reason=decode_failed path=\(statsFileURL.path) byte_count=\(byteCount)"
        }
        guard let snapshot = trafficData.snapshots.last else {
            return "traffic stats unavailable reason=no_snapshots path=\(statsFileURL.path) byte_count=\(byteCount)"
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
            "udp_forwarding_mode=\(stats.udpForwardingMode)",
            "dns_fast_lane_requests=\(stats.dnsFastLaneRequests)",
            "dns_fast_lane_responses=\(stats.dnsFastLaneResponses)",
            "dns_fast_lane_failures=\(stats.dnsFastLaneFailures)",
            "dns_fast_lane_parse_failed=\(stats.dnsFastLaneParseFailed)",
            "dns_fast_lane_close=\(stats.dnsFastLaneClose)",
            "udp_non_dns_rejects=\(stats.udpNonDNSRejects)",
            "udp_quic_rejects=\(stats.udpQUICRejects)",
            "provider_last_phase=\(stats.providerLastPhase)",
            "startup_stability_phase=\(stats.startupStabilityPhase)",
            "startup_probe_completed=\(stats.startupProbeCompleted)",
            "dns_startup_drain_active=\(stats.dnsStartupDrainActive)",
            "dns_startup_drain_closes=\(stats.dnsStartupDrainCloses)",
            "dns_startup_drain_frames_processed=\(stats.dnsStartupDrainFramesProcessed)",
            "early_reconnect_suppressed=\(stats.earlyReconnectSuppressed)",
            "ios_safe_mode_reason=\(stats.iosSafeModeReason.isEmpty ? "none" : stats.iosSafeModeReason)",
            "udp_close_phase=\(stats.udpClosePhase)",
            "udp_deferred_cancels=\(stats.udpDeferredCancels)",
            "udp_graceful_dns_closes=\(stats.udpGracefulDNSCloses)",
            "udp_cancel_watchdog_fires=\(stats.udpCancelWatchdogFires)",
            "udp_startup_serial_mode_active=\(stats.udpStartupSerialModeActive)",
            "udp_crash_guard_active=\(stats.udpCrashGuardActive)",
            "udp_crash_guard_reason=\(stats.udpCrashGuardReason.isEmpty ? "none" : stats.udpCrashGuardReason)",
            "dns_one_shot_closes=\(stats.dnsOneShotCloses)",
            "dns_timeout_closes=\(stats.dnsTimeoutCloses)",
            "dns_malformed_closes=\(stats.dnsMalformedCloses)",
            "dns_trailing_frames_discarded=\(stats.dnsTrailingFramesDiscarded)",
            "dns_recovered_one_shot_closes=\(stats.dnsRecoveredOneShotCloses)",
            "dns_recovered_frames_discarded=\(stats.dnsRecoveredFramesDiscarded)",
            "udp_decode_resync_attempted=\(stats.udpDecodeResyncAttempted)",
            "udp_decode_resync_success=\(stats.udpDecodeResyncSuccess)",
            "udp_decode_recovered_continues=\(stats.udpDecodeRecoveredStreamContinues)",
            "reconnect_suppressed_by_breaker=\(stats.reconnectSuppressedByBreaker)",
            "reconnect_breaker_backoff_step=\(stats.reconnectBreakerBackoffStep)",
            "storm_mode_active_seconds=\(Int(stats.stormModeActiveSeconds))",
            "maintenance_reclaim_budget_exhausted=\(stats.maintenanceReclaimBudgetExhaustedCount)",
            "dns_reserved_slots_in_use=\(stats.dnsReservedSlotsInUse)",
            "decoder_soft_discards=\(stats.decoderSoftDiscards)",
            "decoder_error_density_closes=\(stats.decoderErrorDensityCloses)",
            "tiktok_hardening_actions=\(stats.tiktokHardeningActions)",
            "tcp_early_sni_blocks=\(stats.tcpEarlySNIBlocks)",
            "tcp_early_sni_allows=\(stats.tcpEarlySNIAllows)",
            "tcp_early_sni_fallbacks=\(stats.tcpEarlySNIFallbacks)",
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

    private static func isConnectedLike(_ status: NEVPNStatus) -> Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    private static func isDisconnectedLike(_ status: NEVPNStatus) -> Bool {
        status == .disconnected || status == .disconnecting || status == .invalid
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
