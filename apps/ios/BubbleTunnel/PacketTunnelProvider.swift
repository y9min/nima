import Foundation
import Network
import NetworkExtension
import Tun2SocksKit

class PacketTunnelProvider: NEPacketTunnelProvider {
    typealias StopAttributionSnapshot = TunnelLifecycleDiagnostics.StopAttributionSnapshot
    typealias StopAttributionDecision = TunnelLifecycleDiagnostics.StopAttributionDecision

    static func resolveStopAttribution(snapshot: StopAttributionSnapshot, nowTS: TimeInterval, windowSeconds: TimeInterval) -> StopAttributionDecision? {
        TunnelLifecycleDiagnostics.resolveStopAttribution(
            snapshot: snapshot,
            nowTS: nowTS,
            windowSeconds: windowSeconds
        )
    }

    private let log = TunnelLogger.shared
    private var proxyServer: SOCKSProxyServer?
    private let filter = ReelsBlockFilter()
    private let tunnelStateLock = NSLock()
    private var tunnelStopping = false
    private var didRequestCancel = false
    private let sharedDefaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
    private var heartbeatTimer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "BubbleTunnel.PathMonitor")
    private var lastRecordedStop = false
    private var tun2SocksRestartAttemptedForSession = false
    private var tun2SocksConsecutiveUnexpectedExits = 0
    private var tun2SocksRestartCount = 0
    private var pressureSamplerTimer: DispatchSourceTimer?

    deinit {
        stopPressureSampler()
        let now = Date().timeIntervalSince1970
        ensureStopEventExists(nowTS: now)
        upsertStopSignal(candidate: "provider_deinit_without_stop", ts: now, osRaw: nil, osName: nil, tun2socksExitCode: nil)
        finalizeStopAttributionIfNeeded(nowTS: now)
        if sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleRunningMarkerKey) == true {
            sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleInferredCrashKey)
        }
        if !lastRecordedStop {
            recordLifecycleStop(
                source: "inferred_crash",
                reason: "provider_deinit_without_stop",
                reasonRaw: "deinit",
                exitCode: nil,
                unexpectedExit: true
            )
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        tunnelStateLock.lock()
        tunnelStopping = false
        didRequestCancel = false
        lastRecordedStop = false
        tun2SocksRestartAttemptedForSession = false
        tun2SocksConsecutiveUnexpectedExits = 0
        tun2SocksRestartCount = 0
        tunnelStateLock.unlock()

        log.clear()
        recordLifecycleStart()
        recordProviderPhase("tunnel_start")
        let sessionID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleSessionIDKey) ?? "unknown"
        let udpMode = SOCKSProxyServer.currentUDPForwardingMode(defaults: sharedDefaults).rawValue
        log.breadcrumb(
            "tunnel_start",
            details: "provider_pid=\(ProcessInfo.processInfo.processIdentifier) session_id=\(sessionID) udp_forwarding_mode=\(udpMode)",
            minInterval: 0
        )
        log.log("========== TUNNEL STARTING ==========")
        log.log("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        log.log("Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
        log.log("UDP_DECODER selfcheck modes=len16,control-prefixed,raw-payload udp_control_length_semantics=payload_length build=\(build)")

        // Step 1: Network settings
        log.log("STEP 1: Setting tunnel network settings...")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: BubbleConstants.tunnelRemoteAddress)
        let ipv4 = NEIPv4Settings(
            addresses: [BubbleConstants.tunnelLocalAddress],
            subnetMasks: [BubbleConstants.tunnelSubnetMask]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let dns = NEDNSSettings(servers: BubbleConstants.dnsServers)
        settings.dnsSettings = dns
        settings.mtu = BubbleConstants.mtu

        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                self.log.log("STEP 1 FAILED: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self.recordProviderPhase("network_settings_ready")
            self.log.logAndFlush("STEP 1 SUCCESS: Network settings applied, utun created")

            // Step 2: Start SOCKS5 proxy
            self.log.log("STEP 2: Starting SOCKS5 proxy...")
            let proxy = SOCKSProxyServer(filter: self.filter)
            self.proxyServer = proxy

            proxy.start { startError in
                if let startError = startError {
                    self.log.log("STEP 2 FAILED: Proxy error: \(startError.localizedDescription)")
                    completionHandler(startError)
                    return
                }

                let proxyPort = proxy.actualPort
                let startupMode = self.currentTun2SocksStartupMode()
                self.recordProviderPhase("proxy_ready")
                self.log.logAndFlush("STEP 2 SUCCESS: SOCKS5 proxy is ready on port \(proxyPort)")

                self.recordProviderPhase("vpn_completion_called")
                self.markTransportReady()
                self.log.logAndFlush("STEP 4: Calling completionHandler(nil) immediately after proxy readiness mode=\(startupMode.rawValue)")
                completionHandler(nil)
                self.log.logAndFlush("========== TUNNEL CONNECTED ==========")

                self.startPostCompletionDiagnostics(proxyPort: proxyPort)
                self.scheduleTun2SocksLaunchIfNeeded(proxyPort: proxyPort, startupMode: startupMode)
            }
        }
    }

    private func currentTun2SocksStartupMode() -> Tun2SocksStartupMode {
        let mode = Tun2SocksStartupMode.resolve(
            rawValue: sharedDefaults?.string(forKey: BubbleConstants.tun2socksStartupModeKey)
        )
        sharedDefaults?.set(mode.rawValue, forKey: BubbleConstants.tun2socksStartupModeKey)
        return mode
    }

    private func markTransportReady() {
        let now = Date().timeIntervalSince1970
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleTransportReadyKey)
        sharedDefaults?.set(now, forKey: BubbleConstants.vpnLifecycleTransportReadyTSKey)
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedKey)
        sharedDefaults?.set(now, forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedTSKey)
    }

    private func startPostCompletionDiagnostics(proxyPort: UInt16) {
        recordProviderPhase("post_completion_diagnostics_start")
        log.logAndFlush("STEP 4: post_completion_diagnostics_start")
        startPathMonitor()
        startPressureSampler()
        recordStartupProbe(proxyPort: proxyPort, phase: "startup_probe_completed")
        recordStartupStabilityPhase("operational")
        startHeartbeat()
    }

    private func scheduleTun2SocksLaunchIfNeeded(proxyPort: UInt16, startupMode: Tun2SocksStartupMode) {
        guard TunnelStartupPlanner.shouldLaunchTun2Socks(mode: startupMode) else {
            recordProviderPhase("tun2socks_bypass")
            log.logAndFlush("STEP 3: tun2socks bypassed by diagnostic startup mode")
            return
        }

        let delay = BubbleConstants.tun2socksPostConnectLaunchDelaySeconds
        recordProviderPhase("tun2socks_launch_scheduled")
        log.logAndFlush("STEP 3: tun2socks launch scheduled delay=\(String(format: "%.2f", delay))s mode=\(startupMode.rawValue)")

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.tunnelStateLock.lock()
            let shouldSkip = self.tunnelStopping || self.didRequestCancel
            self.tunnelStateLock.unlock()
            guard !shouldSkip else {
                self.log.logAndFlush("STEP 3: tun2socks launch skipped because tunnel is stopping")
                return
            }

            let config = self.tun2SocksConfig(proxyPort: proxyPort)
            self.recordProviderPhase("tun2socks_start")
            self.log.logAndFlush("STEP 3: Starting tun2socks after VPN completion")
            self.log.logAndFlush("STEP 3: tun2socks config:\n\(config)")
            self.launchTun2Socks(config: config)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                let stats = Socks5Tunnel.stats
                self.recordTun2SocksStats(lastExitCode: nil)
                self.log.log("STEP 3 CHECK: tun2socks stats after 1s — up: \(stats.up.packets) pkts, down: \(stats.down.packets) pkts")
            }
        }
    }

    private func tun2SocksConfig(proxyPort: UInt16) -> String {
        """
        tunnel:
          mtu: \(BubbleConstants.mtu)
        socks5:
          port: \(proxyPort)
          address: \(BubbleConstants.socksBindAddress)
        misc:
          task-stack-size: \(BubbleConstants.tun2socksTaskStackSize)
          tcp-buffer-size: \(BubbleConstants.tun2socksTCPBufferSize)
          connect-timeout: \(BubbleConstants.tun2socksConnectTimeout)
          read-write-timeout: \(BubbleConstants.tun2socksReadWriteTimeout)
          log-level: info
        """
    }

    private func launchTun2Socks(config: String) {
        recordProviderPhase("tun2socks_run_dispatching")
        log.logAndFlush("STEP 3: tun2socks_run_dispatching")
        Socks5Tunnel.run(withConfig: .string(content: config)) { [weak self] exitCode in
            guard let self else { return }
            self.recordProviderPhase("tun2socks_exit")
            self.recordTun2SocksStats(lastExitCode: Int(exitCode))
            self.log.logAndFlush("STEP 3: tun2socks EXITED with code \(exitCode)")
            self.log.breadcrumb("tun2socks_exit", details: "exit_code=\(exitCode)", minInterval: 0)
            if exitCode == -1 {
                self.log.log("STEP 3: exit code -1 means utun fd was NOT found!")
            }
            self.handleTun2SocksExit(exitCode: exitCode, config: config)
        }
        recordProviderPhase("tun2socks_run_dispatched")
        log.logAndFlush("STEP 3: tun2socks_run_dispatched")
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        tunnelStateLock.lock()
        tunnelStopping = true
        tunnelStateLock.unlock()

        let reasonName: String
        switch reason {
        case .none: reasonName = "none"
        case .userInitiated: reasonName = "userInitiated"
        case .providerFailed: reasonName = "providerFailed"
        case .noNetworkAvailable: reasonName = "noNetworkAvailable"
        case .unrecoverableNetworkChange: reasonName = "unrecoverableNetworkChange"
        case .providerDisabled: reasonName = "providerDisabled"
        case .authenticationCanceled: reasonName = "authenticationCanceled"
        case .configurationFailed: reasonName = "configurationFailed"
        case .idleTimeout: reasonName = "idleTimeout"
        case .configurationDisabled: reasonName = "configurationDisabled"
        case .configurationRemoved: reasonName = "configurationRemoved"
        case .superceded: reasonName = "superceded"
        case .userLogout: reasonName = "userLogout"
        case .userSwitch: reasonName = "userSwitch"
        case .connectionFailed: reasonName = "connectionFailed"
        case .sleep: reasonName = "sleep"
        case .appUpdate: reasonName = "appUpdate"
        default: reasonName = "unknown(\(reason.rawValue))"
        }
        log.log("========== TUNNEL STOPPING (reason: \(reasonName) / \(reason.rawValue)) ==========")
        log.breadcrumb("stop_callback", details: "reason=\(reasonName) raw=\(reason.rawValue)", minInterval: 0)
        logPathSnapshot(prefix: "STOP PATH SNAPSHOT")
        let now = Date().timeIntervalSince1970
        ensureStopEventExists(nowTS: now)
        let reasonRaw = "provider_reason_\(reason.rawValue)"
        upsertStopSignal(candidate: "os_stop_reason", ts: now, osRaw: reasonRaw, osName: reasonName, tun2socksExitCode: nil)
        finalizeStopAttributionIfNeeded(nowTS: now)
        let stopOrigin = classifyStopOrigin(now: Date())
        sharedDefaults?.set(stopOrigin, forKey: BubbleConstants.vpnLifecycleLastStopOriginKey)
        log.log("STOP_ORIGIN classification=\(stopOrigin)")
        recordLifecycleStop(
            source: "stopTunnel",
            reason: reasonName,
            reasonRaw: reasonRaw,
            exitCode: nil,
            unexpectedExit: false
        )
        stopPathMonitor()
        stopHeartbeat()
        stopPressureSampler()
        let stats = Socks5Tunnel.stats
        recordTun2SocksStats(lastExitCode: nil)
        log.log("Final stats — Up: \(stats.up.packets) pkts / \(stats.up.bytes) bytes, Down: \(stats.down.packets) pkts / \(stats.down.bytes) bytes")
        log.log("Memory: \(Self.memoryUsageMB()) MB")
        Socks5Tunnel.quit()
        proxyServer?.stop()
        proxyServer = nil
        completionHandler()
    }

    private func classifyStopOrigin(now: Date) -> String {
        let pendingID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecyclePendingStopIDKey) ?? ""
        let pendingSource = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecyclePendingStopSourceKey) ?? ""
        let pendingTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecyclePendingStopTSKey) ?? 0
        defer {
            sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecyclePendingStopIDKey)
            sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecyclePendingStopSourceKey)
            sharedDefaults?.removeObject(forKey: BubbleConstants.vpnLifecyclePendingStopTSKey)
        }

        guard !pendingID.isEmpty, pendingTS > 0 else {
            sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleLastStopObservedPendingIDKey)
            log.log("STOP_ORIGIN pending_stop=missing")
            return "external_or_system"
        }

        let age = now.timeIntervalSince1970 - pendingTS
        sharedDefaults?.set(pendingID, forKey: BubbleConstants.vpnLifecycleLastStopObservedPendingIDKey)
        log.log("STOP_ORIGIN pending_stop_id=\(pendingID) pending_source=\(pendingSource) pending_age_s=\(Int(age))")
        return age >= 0 && age <= 20 ? "app_intent" : "external_or_system"
    }

    private func handleTun2SocksExit(exitCode: Int32, config: String) {
        tunnelStateLock.lock()
        let isStopping = tunnelStopping
        if !isStopping && didRequestCancel {
            tunnelStateLock.unlock()
            return
        }
        if !isStopping {
            didRequestCancel = true
        }
        tunnelStateLock.unlock()

        if isStopping {
            log.log("STEP 3: tun2socks exit observed during tunnel stop sequence")
            return
        }
        tun2SocksConsecutiveUnexpectedExits += 1
        if shouldAttemptTun2SocksRestart(exitCode: exitCode) {
            tun2SocksRestartAttemptedForSession = true
            tun2SocksRestartCount += 1
            let backoff = min(4.0, pow(2.0, Double(max(0, tun2SocksConsecutiveUnexpectedExits - 1))))
            log.log("STEP 3 RECOVERY: restarting tun2socks once after exit code \(exitCode), delay=\(String(format: "%.2f", backoff))s")
            DispatchQueue.global().asyncAfter(deadline: .now() + backoff) { [weak self] in
                self?.launchTun2Socks(config: config)
            }
            return
        }

        let reason = "tun2socks exited unexpectedly with code \(exitCode)"
        log.log("STEP 3 FAILED: \(reason)")
        logPathSnapshot(prefix: "UNEXPECTED EXIT PATH SNAPSHOT")
        let now = Date().timeIntervalSince1970
        ensureStopEventExists(nowTS: now)
        upsertStopSignal(candidate: "tun2socks_exit", ts: now, osRaw: nil, osName: nil, tun2socksExitCode: Int(exitCode))
        finalizeStopAttributionIfNeeded(nowTS: now)
        recordLifecycleStop(
            source: "tun2socks_exit",
            reason: "tun2socks_crash",
            reasonRaw: "exit_\(exitCode)",
            exitCode: Int(exitCode),
            unexpectedExit: true
        )
        stopPathMonitor()
        stopHeartbeat()
        stopPressureSampler()
        let error = NSError(
            domain: "BubbleTunnel.PacketTunnel",
            code: Int(exitCode),
            userInfo: [NSLocalizedDescriptionKey: reason]
        )
        recordLifecycleStop(
            source: "cancelTunnelWithError",
            reason: "provider_cancelled_with_error",
            reasonRaw: error.localizedDescription,
            exitCode: Int(exitCode),
            unexpectedExit: true
        )
        cancelTunnelWithError(error)
    }

    private func shouldAttemptTun2SocksRestart(exitCode: Int32) -> Bool {
        if tun2SocksRestartAttemptedForSession { return false }
        // Known fatal local configuration exits should fail fast.
        if exitCode == -1 || exitCode == 64 || exitCode == 78 { return false }
        return true
    }

    private static func memoryUsageMB() -> String {
        guard let memoryMB = memoryUsageMBDouble() else { return "?" }
        return String(format: "%.1f", memoryMB)
    }

    private static func memoryUsageMBDouble() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1_048_576
        }
        return nil
    }

    private static func cpuUsagePercent() -> String {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else {
            return "unavailable"
        }
        defer {
            let bytes = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), bytes)
        }

        var totalCPU = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard infoResult == KERN_SUCCESS else { continue }
            if info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        return String(format: "%.1f", totalCPU)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let message = String(data: messageData, encoding: .utf8) ?? "unknown"
        log.log("App message: \(message)")
        if message == "ping" {
            let stats = Socks5Tunnel.stats
            let reply = "pong — up: \(stats.up.packets) pkts, down: \(stats.down.packets) pkts"
            completionHandler?(reply.data(using: .utf8))
        } else {
            completionHandler?(nil)
        }
    }

    private func recordLifecycleStart() {
        let ts = Date().timeIntervalSince1970
        sharedDefaults?.set(UUID().uuidString, forKey: BubbleConstants.vpnLifecycleSessionIDKey)
        finalizeStopAttributionIfNeeded(nowTS: ts)
        persistLastCompletedStopSnapshot(nowTS: ts)
        clearStopAttributionState()
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleLastStartTSKey)
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey)
        sharedDefaults?.set(true, forKey: BubbleConstants.vpnLifecycleRunningMarkerKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleInferredCrashKey)
        sharedDefaults?.set("unknown", forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey)
        sharedDefaults?.set("{}", forKey: BubbleConstants.vpnLifecycleProviderHeartbeatSnapshotJSONKey)
        sharedDefaults?.set("starting", forKey: BubbleConstants.vpnLifecycleStartupStabilityPhaseKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedTSKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleTransportReadyKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleTransportReadyTSKey)
        let startupMode = Tun2SocksStartupMode.resolve(
            rawValue: sharedDefaults?.string(forKey: BubbleConstants.tun2socksStartupModeKey)
        )
        sharedDefaults?.set(startupMode.rawValue, forKey: BubbleConstants.tun2socksStartupModeKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleDNSStartupDrainActiveKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleDNSStartupDrainClosesKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleDNSStartupDrainFramesProcessedKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey)
        sharedDefaults?.set("stability_first_startup", forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey)
    }

    private func recordProviderPhase(_ phase: String) {
        let ts = Date().timeIntervalSince1970
        sharedDefaults?.set(phase, forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey)
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleProviderLastPhaseTSKey)
        appendProviderPhaseRing(phase: phase, ts: ts, source: "provider")
    }

    private func recordStartupStabilityPhase(_ phase: String) {
        sharedDefaults?.set(phase, forKey: BubbleConstants.vpnLifecycleStartupStabilityPhaseKey)
    }

    private func recordStartupProbe(proxyPort: UInt16, phase: String) {
        recordProviderPhase(phase)
        recordStartupStabilityPhase(phase)
        ensurePathProbeSnapshotExists()
        recordTun2SocksStats(lastExitCode: nil)
        recordProviderHeartbeatSnapshot(nowTS: Date().timeIntervalSince1970, proxyPort: proxyPort)
        log.logAndFlush("STEP 4: \(phase) proxy_port=\(proxyPort)")
        log.breadcrumb(
            "startup_probe",
            details: "phase=\(phase) proxy_port=\(proxyPort) completed=\(sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedKey) ?? false)",
            minInterval: 0
        )
    }

    private func ensurePathProbeSnapshotExists() {
        let existingTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey) ?? 0
        guard existingTS <= 0 else { return }
        let now = Date().timeIntervalSince1970
        sharedDefaults?.set("probe_pending", forKey: BubbleConstants.vpnLifecycleLastPathStatusKey)
        sharedDefaults?.set("none", forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey)
        sharedDefaults?.set("none", forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey)
        sharedDefaults?.set(now, forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey)
    }

    private func appendProviderPhaseRing(phase: String, ts: TimeInterval, source: String) {
        var ring = decodeJSONArray(sharedDefaults?.string(forKey: BubbleConstants.providerPhaseRingJSONKey))
        let lastSeq = ring.compactMap { $0["seq"] as? Int }.max() ?? 0
        ring.append([
            "seq": lastSeq + 1,
            "ts": ts,
            "phase": phase,
            "source": source,
        ])
        if ring.count > 32 {
            ring.removeFirst(ring.count - 32)
        }
        writeJSONObject(ring, key: BubbleConstants.providerPhaseRingJSONKey)
    }

    private func recordTun2SocksStats(lastExitCode: Int?) {
        let stats = Socks5Tunnel.stats
        var payload: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "up_packets": "\(stats.up.packets)",
            "up_bytes": "\(stats.up.bytes)",
            "down_packets": "\(stats.down.packets)",
            "down_bytes": "\(stats.down.bytes)",
            "memory_mb": Self.memoryUsageMB(),
            "restart_count": tun2SocksRestartCount,
        ]
        if let lastExitCode {
            payload["last_exit_code"] = lastExitCode
        }
        writeJSONObject(payload, key: BubbleConstants.tun2socksLastStatsJSONKey)
    }

    private func recordProviderHeartbeatSnapshot(nowTS: TimeInterval, proxyPort: UInt16? = nil) {
        let stats = Socks5Tunnel.stats
        let proxySnapshot = proxyServer?.currentPressureSnapshot
        let resolvedProxyPort = proxyPort ?? proxyServer?.actualPort ?? 0
        let payload: [String: Any] = [
            "ts": nowTS,
            "provider_phase": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey) ?? "unknown",
            "startup_stability_phase": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStartupStabilityPhaseKey) ?? "unknown",
            "startup_probe_completed": sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleStartupProbeCompletedKey) ?? false,
            "proxy_ready": resolvedProxyPort > 0,
            "proxy_port": Int(resolvedProxyPort),
            "memory_mb": Self.memoryUsageMB(),
            "tun2socks_up_packets": "\(stats.up.packets)",
            "tun2socks_down_packets": "\(stats.down.packets)",
            "active_udp": proxySnapshot?.activeUDP ?? -1,
            "queued_udp": proxySnapshot?.queuedUDP ?? -1,
            "last_udp_close_phase": proxySnapshot?.lastUDPClosePhase ?? "unknown",
            "dns_startup_drain_active": proxySnapshot?.dnsStartupDrainActive ?? false,
            "dns_startup_drain_closes": proxySnapshot?.dnsStartupDrainCloses ?? (sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDNSStartupDrainClosesKey) ?? 0),
            "dns_startup_drain_frames_processed": proxySnapshot?.dnsStartupDrainFramesProcessed ?? (sharedDefaults?.integer(forKey: BubbleConstants.vpnLifecycleDNSStartupDrainFramesProcessedKey) ?? 0),
            "dns_fast_lane_requests": proxySnapshot?.dnsFastLaneRequests ?? -1,
            "dns_fast_lane_responses": proxySnapshot?.dnsFastLaneResponses ?? -1,
            "dns_fast_lane_failures": proxySnapshot?.dnsFastLaneFailures ?? -1,
            "dns_fast_lane_parse_failed": proxySnapshot?.dnsFastLaneParseFailed ?? -1,
            "dns_fast_lane_close": proxySnapshot?.dnsFastLaneClose ?? -1,
            "dns_fast_lane_disabled": proxySnapshot?.dnsFastLaneDisabled ?? false,
            "dns_fast_lane_disabled_reason": proxySnapshot?.dnsFastLaneDisabledReason ?? "",
            "udp_non_dns_rejects": proxySnapshot?.udpNonDNSRejects ?? -1,
            "udp_quic_rejects": proxySnapshot?.udpQUICRejects ?? -1,
            "early_reconnect_suppressed": sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey) ?? false,
            "ios_safe_mode_reason": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleIOSSafeModeReasonKey) ?? "",
            "last_decoder_event": decodeJSONObject(sharedDefaults?.string(forKey: BubbleConstants.udpLastDecoderEventJSONKey)),
            "last_dns_close": decodeJSONObject(sharedDefaults?.string(forKey: BubbleConstants.udpLastDNSCloseJSONKey)),
            "app_lifecycle": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventKey) ?? "unknown",
            "path_state": [
                "status": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathStatusKey) ?? "unknown",
                "unsatisfied_reason": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey) ?? "none",
                "interfaces": sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey) ?? "none",
                "is_expensive": sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey) ?? false,
                "is_constrained": sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey) ?? false,
                "updated_at": sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey) ?? 0,
            ],
        ]
        writeJSONObject(payload, key: BubbleConstants.vpnLifecycleProviderHeartbeatSnapshotJSONKey)
    }

    private func decodeJSONArray(_ raw: String?) -> [[String: Any]] {
        guard let raw, let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return parsed
    }

    private func decodeJSONObject(_ raw: String?) -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return parsed
    }

    private func writeJSONObject(_ object: Any, key: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        sharedDefaults?.set(json, forKey: key)
    }

    private func recordLifecycleStop(source: String, reason: String, reasonRaw: String, exitCode: Int?, unexpectedExit: Bool) {
        guard !lastRecordedStop else { return }
        lastRecordedStop = true
        let ts = Date().timeIntervalSince1970
        sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleLastStopTSKey)
        sharedDefaults?.set(reason, forKey: BubbleConstants.vpnLifecycleStopReasonKey)
        sharedDefaults?.set(source, forKey: BubbleConstants.vpnLifecycleStopSourceKey)
        sharedDefaults?.set(reasonRaw, forKey: BubbleConstants.vpnLifecycleStopReasonRawKey)
        sharedDefaults?.set(unexpectedExit, forKey: BubbleConstants.vpnLifecycleUnexpectedExitKey)
        sharedDefaults?.set(false, forKey: BubbleConstants.vpnLifecycleRunningMarkerKey)
        let resolvedClass = (source == "stopTunnel") ? "clean_stop" : "inferred_crash"
        sharedDefaults?.set(resolvedClass, forKey: BubbleConstants.vpnLifecycleResolvedStopClassKey)
        if source == "inferred_crash" || source == "tun2socks_exit" || source == "cancelTunnelWithError" {
            sharedDefaults?.set(reasonRaw, forKey: BubbleConstants.vpnLifecycleInferredCrashReasonKey)
        }
        if let exitCode {
            sharedDefaults?.set(exitCode, forKey: BubbleConstants.vpnLifecycleLastExitCodeKey)
        }
        let udpActive = proxyServer?.currentActiveUDPStreams ?? -1
        let udpQueued = proxyServer?.currentQueuedUDPStreams ?? -1
        let memMB = Self.memoryUsageMB()
        log.log("TUNNEL_STOP_SOURCE=\(source) STOP_REASON=\(reason) STOP_REASON_RAW=\(reasonRaw) EXIT_CODE=\(exitCode.map(String.init) ?? "nil") ACTIVE_UDP=\(udpActive) QUEUED_UDP=\(udpQueued) MEM_MB=\(memMB)")
    }

    private func clearStopAttributionState() {
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
            BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey,
            BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey,
            BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey,
            BubbleConstants.vpnLifecyclePendingStopIDKey,
            BubbleConstants.vpnLifecyclePendingStopSourceKey,
            BubbleConstants.vpnLifecyclePendingStopTSKey
        ]
        keys.forEach { sharedDefaults?.removeObject(forKey: $0) }
    }

    private func ensureStopEventExists(nowTS: TimeInterval) {
        let eventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        if !eventID.isEmpty { return }
        sharedDefaults?.set(UUID().uuidString, forKey: BubbleConstants.vpnLifecycleStopEventIDKey)
        sharedDefaults?.set(nowTS, forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey)
        sharedDefaults?.set("", forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey)
    }

    private func upsertStopSignal(candidate: String, ts: TimeInterval, osRaw: String?, osName: String?, tun2socksExitCode: Int?) {
        switch candidate {
        case "os_stop_reason":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopSignalOSStopTSKey)
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopTerminalSeenStopTunnelTSKey)
            if let osRaw { sharedDefaults?.set(osRaw, forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonRawKey) }
            if let osName { sharedDefaults?.set(osName, forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonNameKey) }
        case "tun2socks_exit":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey)
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopTerminalSeenTun2SocksExitTSKey)
            if let tun2socksExitCode { sharedDefaults?.set(tun2socksExitCode, forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitCodeKey) }
        case "provider_deinit_without_stop":
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopSignalProviderDeinitTSKey)
            sharedDefaults?.set(ts, forKey: BubbleConstants.vpnLifecycleStopTerminalSeenProviderDeinitTSKey)
        default:
            break
        }
    }

    private func finalizeStopAttributionIfNeeded(nowTS: TimeInterval) {
        let existingFinal = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        if !existingFinal.isEmpty { return }
        let eventStart = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopEventStartTSKey) ?? 0
        let appTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalAppRequestedTSKey) ?? 0
        let osTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopTSKey) ?? 0
        let tunTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitTSKey) ?? 0
        let deinitTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalProviderDeinitTSKey) ?? 0
        let dropTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopSignalStatusDropTSKey) ?? 0
        let osRaw = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonRawKey) ?? ""
        let osName = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopSignalOSStopReasonNameKey) ?? ""
        let tunExit = sharedDefaults?.object(forKey: BubbleConstants.vpnLifecycleStopSignalTun2SocksExitCodeKey) as? Int
        let snapshot = StopAttributionSnapshot(
            eventStart: eventStart,
            appRequestedTS: appTS,
            osStopTS: osTS,
            osStopRaw: osRaw,
            osStopName: osName,
            tun2socksExitTS: tunTS,
            tun2socksExitCode: tunExit,
            providerDeinitTS: deinitTS,
            statusDropTS: dropTS
        )
        guard let decision = Self.resolveStopAttribution(
            snapshot: snapshot,
            nowTS: nowTS,
            windowSeconds: attributionWindowSeconds()
        ) else {
            return
        }

        sharedDefaults?.set(decision.final, forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey)
        sharedDefaults?.set(decision.confidence, forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey)
        sharedDefaults?.set(decision.evidence, forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey)
        sharedDefaults?.set(decision.signalOrder, forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey)
        sharedDefaults?.set(nowTS, forKey: BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey)
        persistLastCompletedStopSnapshot(nowTS: nowTS)
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

    private func persistLastCompletedStopSnapshot(nowTS: TimeInterval) {
        let eventID = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopEventIDKey) ?? ""
        let final = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let signalOrder = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseSignalOrderKey) ?? ""
        guard !eventID.isEmpty, !final.isEmpty, !signalOrder.isEmpty else { return }
        let confidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseConfidenceKey) ?? ""
        let evidence = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseEvidenceKey) ?? ""
        let finalizedTS = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleStopCauseFinalizedTSKey) ?? nowTS
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
    }

    private func remediationPath(for finalCause: String) -> String {
        if finalCause.hasPrefix("os_stop_reason_") { return "ne_session_or_profile_fix" }
        if finalCause == "tun2socks_exit" { return "tun2socks_transport_fix" }
        if finalCause == "provider_deinit_without_stop" { return "provider_lifecycle_fix" }
        return "ne_external_lifecycle_investigation"
    }

    private func nextActionForRemediationPath(_ path: String) -> String {
        switch path {
        case "ne_session_or_profile_fix":
            return "apply_profile_churn_reduction_and_reconnect_debounce"
        case "tun2socks_transport_fix":
            return "apply_transport_restart_once_then_backoff_with_exit_code_routing"
        case "provider_lifecycle_fix":
            return "reduce_provider_pressure_and_check_watchdog_markers"
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

    static func dropCadenceSeconds(from timestamps: [TimeInterval], nowTS: TimeInterval, windowSeconds: TimeInterval) -> TimeInterval? {
        TunnelLifecycleDiagnostics.dropCadenceSeconds(
            from: timestamps,
            nowTS: nowTS,
            windowSeconds: windowSeconds
        )
    }

    static func isExternalKillSignature(
        finalCause: String,
        evidence: String,
        diagnosticHoldSeconds: TimeInterval,
        dropCadenceSeconds: TimeInterval?
    ) -> Bool {
        TunnelLifecycleDiagnostics.isExternalKillSignature(
            finalCause: finalCause,
            evidence: evidence,
            diagnosticHoldSeconds: diagnosticHoldSeconds,
            dropCadenceSeconds: dropCadenceSeconds
        )
    }

    static func externalKillReconnectGate(
        attemptTimestamps: [TimeInterval],
        nowTS: TimeInterval,
        windowSeconds: TimeInterval = BubbleConstants.vpnLifecycleExternalKillReconnectWindowSeconds,
        maxAttempts: Int = BubbleConstants.vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow
    ) -> (allowed: Bool, attemptsInWindow: Int, nextAllowedTS: TimeInterval?) {
        TunnelLifecycleDiagnostics.externalKillReconnectGate(
            attemptTimestamps: attemptTimestamps,
            nowTS: nowTS,
            windowSeconds: windowSeconds,
            maxAttempts: maxAttempts
        )
    }

    private func startPressureSampler() {
        stopPressureSampler()
        let now = Date().timeIntervalSince1970
        sharedDefaults?.set(now, forKey: BubbleConstants.vpnLifecycleExtensionPressureLastSampleTSKey)
        sharedDefaults?.set(0, forKey: BubbleConstants.vpnLifecycleExtensionPressureRuntimeSecondsKey)
        sharedDefaults?.set(SOCKSProxyServer.ExtensionPressureLevel.normal.rawValue, forKey: BubbleConstants.vpnLifecycleExtensionPressureLevelKey)
        sharedDefaults?.set("passive_sampler_disabled", forKey: BubbleConstants.vpnLifecycleExtensionPressureActionKey)
        log.log("EXTENSION_PRESSURE sampler disabled active=false mach_cpu_sampling=false queue_shedding=false")
    }

    private func stopPressureSampler() {
        pressureSamplerTimer?.cancel()
        pressureSamplerTimer = nil
    }

    private func sampleExtensionPressure(sessionStartTS: TimeInterval) {
        let now = Date()
        let runtimeSeconds = max(0, now.timeIntervalSince1970 - sessionStartTS)
        guard runtimeSeconds >= BubbleConstants.extensionPressureSamplerStartSeconds else { return }

        let memoryMB = Self.memoryUsageMBDouble()
        let proxySnapshot = proxyServer?.currentPressureSnapshot
        let activeUDP = proxySnapshot?.activeUDP ?? -1
        let queuedUDP = proxySnapshot?.queuedUDP ?? -1
        let degradedState = proxySnapshot?.degradedState ?? "unknown"
        let level = SOCKSProxyServer.extensionPressureLevel(
            memoryMB: memoryMB,
            activeUDP: max(0, activeUDP),
            queuedUDP: max(0, queuedUDP),
            degradedState: degradedState
        )
        proxyServer?.applyExtensionPressureLevel(level)

        let stats = Socks5Tunnel.stats
        let appLifecycle = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleAppLifecycleLastEventKey) ?? "unknown"
        let action: String
        switch level {
        case .normal: action = "observe"
        case .soft: action = "trim_idle_and_diagnostics"
        case .hard: action = "trim_queues_and_reject_low_confidence"
        case .critical: action = "critical_shed_and_mute_expensive_diagnostics"
        }

        sharedDefaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleExtensionPressureLastSampleTSKey)
        sharedDefaults?.set(runtimeSeconds, forKey: BubbleConstants.vpnLifecycleExtensionPressureRuntimeSecondsKey)
        sharedDefaults?.set(level.rawValue, forKey: BubbleConstants.vpnLifecycleExtensionPressureLevelKey)
        sharedDefaults?.set(memoryMB ?? -1, forKey: BubbleConstants.vpnLifecycleExtensionPressureMemoryMBKey)
        let cpuPercent = Self.cpuUsagePercent()
        sharedDefaults?.set(cpuPercent, forKey: BubbleConstants.vpnLifecycleExtensionPressureCPUPercentKey)
        sharedDefaults?.set(activeUDP, forKey: BubbleConstants.vpnLifecycleExtensionPressureUDPActiveKey)
        sharedDefaults?.set(queuedUDP, forKey: BubbleConstants.vpnLifecycleExtensionPressureUDPQueuedKey)
        sharedDefaults?.set(degradedState, forKey: BubbleConstants.vpnLifecycleExtensionPressureDegradedStateKey)
        sharedDefaults?.set(action, forKey: BubbleConstants.vpnLifecycleExtensionPressureActionKey)
        sharedDefaults?.set("\(stats.up.packets)", forKey: BubbleConstants.vpnLifecycleExtensionPressureTun2SocksUpPacketsKey)
        sharedDefaults?.set("\(stats.down.packets)", forKey: BubbleConstants.vpnLifecycleExtensionPressureTun2SocksDownPacketsKey)
        sharedDefaults?.set(appLifecycle, forKey: BubbleConstants.vpnLifecycleExtensionPressureAppLifecycleKey)

        log.log(
            "EXTENSION_PRESSURE sample runtime_s=\(Int(runtimeSeconds)) level=\(level.rawValue) action=\(action) memory_mb=\(memoryMB.map { String(format: "%.1f", $0) } ?? "unavailable") cpu_percent=\(cpuPercent) active_udp=\(activeUDP) queued_udp=\(queuedUDP) degraded_state=\(degradedState) app_lifecycle=\(appLifecycle) tun_up=\(stats.up.packets) tun_down=\(stats.down.packets)"
        )
    }

    private func startHeartbeat() {
        stopHeartbeat()
        recordHeartbeatTick(source: "immediate")
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.recordHeartbeatTick(source: "timer")
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func recordHeartbeatTick(source: String) {
        let now = Date().timeIntervalSince1970
        let previous = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey) ?? 0
        sharedDefaults?.set(now, forKey: BubbleConstants.vpnLifecycleLastHeartbeatTSKey)
        recordTun2SocksStats(lastExitCode: nil)
        recordProviderHeartbeatSnapshot(nowTS: now)
        let age = previous > 0 ? max(0, now - previous) : 0
        log.breadcrumb(
            "heartbeat",
            details: "source=\(source) heartbeat_age_s=\(String(format: "%.1f", age))",
            minInterval: source == "immediate" ? 0 : 30.0
        )
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func startPathMonitor() {
        stopPathMonitor()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        monitor.start(queue: pathMonitorQueue)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathUpdate(_ path: Network.NWPath) {
        let status = pathStatusString(path.status)
        let reason = unsatisfiedReasonString(path.unsatisfiedReason)
        let interfaces = path.availableInterfaces.map { "\($0.type)" }.joined(separator: ",")
        sharedDefaults?.set(status, forKey: BubbleConstants.vpnLifecycleLastPathStatusKey)
        sharedDefaults?.set(reason, forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey)
        sharedDefaults?.set(interfaces.isEmpty ? "none" : interfaces, forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey)
        sharedDefaults?.set(path.isExpensive, forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey)
        sharedDefaults?.set(path.isConstrained, forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey)
        log.breadcrumb(
            "path_state",
            details: "status=\(status) unsatisfied_reason=\(reason) expensive=\(path.isExpensive) constrained=\(path.isConstrained)",
            minInterval: 10.0
        )
        log.log(
            "NETWORK PATH status=\(status) unsatisfied_reason=\(reason) expensive=\(path.isExpensive) constrained=\(path.isConstrained) interfaces=\(interfaces.isEmpty ? "none" : interfaces)"
        )
    }

    private func logPathSnapshot(prefix: String) {
        let status = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathStatusKey) ?? "unknown"
        let reason = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathUnsatisfiedReasonKey) ?? "none"
        let interfaces = sharedDefaults?.string(forKey: BubbleConstants.vpnLifecycleLastPathInterfacesKey) ?? "unknown"
        let expensive = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsExpensiveKey) ?? false
        let constrained = sharedDefaults?.bool(forKey: BubbleConstants.vpnLifecycleLastPathIsConstrainedKey) ?? false
        let ts = sharedDefaults?.double(forKey: BubbleConstants.vpnLifecycleLastPathUpdateTSKey) ?? 0
        let tsText = ts > 0 ? Date(timeIntervalSince1970: ts).ISO8601Format() : "unknown"
        log.log(
            "\(prefix): status=\(status) unsatisfied_reason=\(reason) expensive=\(expensive) constrained=\(constrained) interfaces=\(interfaces) observed_at=\(tsText)"
        )
    }

    private func pathStatusString(_ status: Network.NWPath.Status) -> String {
        switch status {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requires_connection"
        @unknown default: return "unknown"
        }
    }

    private func unsatisfiedReasonString(_ reason: Network.NWPath.UnsatisfiedReason) -> String {
        String(describing: reason)
    }
}
