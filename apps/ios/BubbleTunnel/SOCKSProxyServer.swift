import Foundation
import Network
import os

// MARK: - Connection Filter Protocol

protocol ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision
    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision
    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision
}

enum PolicyAction: String, Codable {
    case allow
    case blockNow = "block_now"
    case blockAfterBytes = "block_after_bytes"
    case shadowAllow = "shadow_allow"
}

struct FlowClassification {
    let bucket: ContentBucket
    let confidence: Double
    let reasons: [String]
}

struct PolicyDecision {
    let action: PolicyAction
    let blockAfterBytes: Int?
    let classification: FlowClassification
    let reason: String
    let toggleSnapshot: [String: Bool]
    let policyVersion: Int
    let intendedAction: PolicyAction?

    static func allow(reason: String, classification: FlowClassification, toggles: [String: Bool], policyVersion: Int) -> PolicyDecision {
        PolicyDecision(
            action: .allow,
            blockAfterBytes: nil,
            classification: classification,
            reason: reason,
            toggleSnapshot: toggles,
            policyVersion: policyVersion,
            intendedAction: nil
        )
    }
}

// MARK: - SOCKS5 Errors

enum SOCKSError: Error, LocalizedError {
    case invalidPort(UInt16)
    case listenerFailed(Error)
    case connectionLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidPort(let p): return "Invalid SOCKS port: \(p)"
        case .listenerFailed(let e): return "Listener failed: \(e.localizedDescription)"
        case .connectionLimitReached: return "Maximum connection limit reached"
        }
    }
}

// MARK: - Parsed Address

private struct ParsedAddress {
    let host: String
    let port: UInt16
    let headerEndOffset: Int
}

// MARK: - SOCKS5 Proxy Server

final class SOCKSProxyServer {
    enum UDPAdmissionDecision {
        case accept
        case queue
        case reject(reason: String)
    }

    private var listener: NWListener?
    private let filter: ConnectionFilter
    private let queue = DispatchQueue(label: "com.yamin.nimademo.socks5", qos: .userInitiated)
    private let log = TunnelLogger.shared
    private var connectionCount = 0      // total connections ever (used as ID)
    private var activeConnectionCount = 0 // currently open connections

    // Thread-safe actual port (written on queue, read from outside)
    private let _actualPort = OSAllocatedUnfairLock(initialState: UInt16(0))
    var actualPort: UInt16 {
        _actualPort.withLock { $0 }
    }
    var currentActiveUDPStreams: Int { queue.sync { activeUDPStreams } }
    var currentQueuedUDPStreams: Int { queue.sync { pendingUDPControlQueue.count } }

    // Connection stats (queue-confined)
    private var statsAllowed = 0
    private var statsBlocked = 0
    private var statsUDP = 0
    private var statsErrors = 0
    private var activeUDPStreams = 0
    private var totalUDPStreamsOpened = 0
    private var totalUDPStreamsClosed = 0
    private var udpDecodeBadPrefix = 0
    private var udpDecodeBadLength = 0
    private var udpDecodeBadPayload = 0
    private var udpModePlain = 0
    private var udpModeControlPrefixed = 0
    private var udpDecodeModeDetected = 0
    private var udpDecodeResyncAttempted = 0
    private var udpDecodeResyncSuccess = 0
    private var udpDecodeBadLengthHardFail = 0
    private var udpDecodeRecoveredStreamContinues = 0
    private var udpDecodeCloseAfterFailureThreshold = 0
    private var udpActivePeak = 0
    private var udpTimeoutCount = 0
    private var dnsInflight = 0
    private var dnsDedupHits = 0
    private var resolverSwitchCount = 0
    private var lastResolverSwitchAt = Date.distantPast
    private var currentPreferredResolver = "8.8.8.8"
    private var decoderErrorCount = 0
    private var streamCloseReasonCounts: [String: Int] = [:]
    private var tiktokHardeningActions: [String: Int] = [:]
    private var pendingUDPControlQueue: [PendingUDPControl] = []
    private var udpStreamsByID: [Int: UDPStreamState] = [:]
    private var inflightDNSRequests: [String: InflightDNSRequest] = [:]
    private var resolverHealth: [String: ResolverHealth] = [
        "8.8.8.8": ResolverHealth(),
        "1.1.1.1": ResolverHealth(),
    ]
    private var attemptedByBucket: [String: Int] = [:]
    private var blockedByBucket: [String: Int] = [:]
    private var possibleFalsePositiveRetries = 0
    private var recentBlockedByHost: [String: Date] = [:]
    private var blockedSuppressedTCP = 0
    private var blockedSuppressedUDP = 0
    private var blockedSuppression: [String: BlockSuppressionState] = [:]
    private let blockSuppressionCooldown: TimeInterval = BubbleConstants.blockSuppressionCooldown
    private let aggressiveBlockSuppressionCooldown: TimeInterval = BubbleConstants.aggressiveBlockSuppressionCooldown
    private let blockSuppressionLogCap = 3
    private let blockSuppressionSummaryEvery = 10
    private var statsTimer: DispatchSourceTimer?
    private var udpSweepTimer: DispatchSourceTimer?
    private var degradedState: TransportDegradedState = .healthy
    private var degradedTransitions = 0
    private var udpForcedRejects = 0
    private var udpReclaimsByReason: [String: Int] = [:]
    private var degradedEnteredAt = Date.distantPast
    private var trippedEnteredAt = Date.distantPast
    private var trippedTransitions = 0
    private var trippedSecondsTotal: TimeInterval = 0
    private var tokenBucketDrops = 0
    private var streamBlockSuppressed = 0
    private var streamBlockTokenDrops = 0
    private var tokenBucketsByHost: [String: TokenBucketState] = [:]
    private var emergencyReclaimTimestamps: [Date] = []
    private var lastEmergencyReclaimAt = Date.distantPast
    private var recentTikTokBlockEvents: [Date] = []
    private var recentBadLenHardFailTimestamps: [Date] = []
    private var admissionRejectsByReason: [String: Int] = [:]
    private var stateSecondsByMode: [String: TimeInterval] = [:]
    private var lastStateSampleAt = Date()
    private var degradedStableSince: Date?
    private var recoveringEnteredAt = Date.distantPast
    private var severeSignalSince: Date?
    private var lastStuckProcessingReclaimAt = Date.distantPast
    private var maintenanceReclaimTimestamps: [Date] = []
    private var maintenanceReclaimCooldownUntil = Date.distantPast
    private var maintenanceReclaimBudgetExhaustedCount = 0
    private var reclaimCooldownUntilByReason: [String: Date] = [:]
    private var stormModeActiveSince: Date?
    private var stormModeActiveSecondsTotal: TimeInterval = 0
    private var decoderSoftDiscards = 0
    private var decoderErrorDensityCloses = 0
    private let stabilityFirstModeEnabled: Bool
    private var protectionStartupGraceUntil = Date.distantPast
    private var recoveryGraceUntil = Date.distantPast
    private var lastPressureDiagnosticsAt = Date.distantPast
    private var hostCooldownUntilByKey: [String: Date] = [:]
    private let minimumUDPControlStreamsDuringGrace = 6

    // Active relay tracking for JSON stats
    private var activeRelays: [Int: RelayTracker] = [:]
    private var domainStats: [String: (count: Int, bytes: Int)] = [:]
    private var snapshotTimer: DispatchSourceTimer?
    private var snapshotHistory: [TrafficSnapshot] = []
    private var eventLog: [TrafficEvent] = []
    private var eventCounter = 0
    private let maxSnapshotHistory = 300 // 5 minutes at 1/sec
    private let maxEvents = 500
    private let statsFileURL: URL?
    private var udpSocketPool: [String: NWConnection] = [:]
    private var udpSocketPoolOrder: [String] = []
    private var startedUDPSocketKeys: Set<String> = []
    private var udpSocketReuseHits = 0
    private var udpSocketReuseMisses = 0
    private let udpSocketPoolMaxEntries = 16
    private let admissionController = UDPAdmissionController()

    init(filter: ConnectionFilter) {
        self.filter = filter
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        if let stored = defaults?.object(forKey: BubbleConstants.transportProtectionV2StabilityFirstKey) as? Bool {
            self.stabilityFirstModeEnabled = stored
        } else {
#if DEBUG
            self.stabilityFirstModeEnabled = true
#else
            self.stabilityFirstModeEnabled = false
#endif
        }
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BubbleConstants.appGroupID
        ) {
            self.statsFileURL = container.appendingPathComponent(BubbleConstants.statsFileName)
        } else {
            self.statsFileURL = nil
        }
    }

    // MARK: - Lifecycle

    func start(ready: @escaping (Error?) -> Void) {
        var didCallReady = false
        let callReady = { (error: Error?) in
            guard !didCallReady else { return }
            didCallReady = true
            ready(error)
        }

        let params = NWParameters.tcp
        guard let anyPort = NWEndpoint.Port(rawValue: 0) else {
            log.log("SOCKS5: Failed to create port 0 endpoint")
            callReady(SOCKSError.invalidPort(0))
            return
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(BubbleConstants.socksBindAddress),
            port: anyPort
        )

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            log.log("SOCKS5: Failed to create listener: \(error)")
            callReady(error)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let port = listener.port?.rawValue ?? 0
                self._actualPort.withLock { $0 = port }
                self.log.log("SOCKS5: Listening on port \(port)")
                callReady(nil)
            case .waiting(let error):
                let port = listener.port?.rawValue ?? 0
                self._actualPort.withLock { $0 = port }
                self.log.log("SOCKS5: Listener waiting (\(error)), port=\(port)")
                callReady(nil)
            case .failed(let error):
                self.log.log("SOCKS5: Listener failed: \(error)")
                callReady(error)
            case .cancelled:
                self.log.log("SOCKS5: Listener cancelled")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
        startStatsTimer()
        startSnapshotTimer()
        startUDPSweepTimer()
        if stabilityFirstModeEnabled {
            protectionStartupGraceUntil = Date().addingTimeInterval(BubbleConstants.stabilityFirstStartupGraceSeconds)
        } else {
            protectionStartupGraceUntil = .distantPast
        }
        log.log("TRANSPORT_PROTECTION flag_mode=\(stabilityFirstModeEnabled ? "stability_first_v2" : "legacy") grace_active=\(isStartupGraceActive())")
    }

    func stop() {
        queue.sync {
            statsTimer?.cancel()
            statsTimer = nil
            snapshotTimer?.cancel()
            snapshotTimer = nil
            udpSweepTimer?.cancel()
            udpSweepTimer = nil
            for conn in udpSocketPool.values {
                conn.cancel()
            }
            udpSocketPool.removeAll()
            udpSocketPoolOrder.removeAll()
            startedUDPSocketKeys.removeAll()
        }
        listener?.cancel()
        listener = nil
    }

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + BubbleConstants.statsInterval, repeating: BubbleConstants.statsInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let total = self.connectionCount
            guard total > 0 else { return }
            let memMB = Self.memoryUsageMB()
            let udpTimeoutRate = self.statsUDP > 0 ? Double(self.udpTimeoutCount) / Double(self.statsUDP) : 0
            self.updateTransportDegradedState()
            let queueOldestAgeMs: Int = {
                guard let oldest = self.pendingUDPControlQueue.first else { return 0 }
                return Int(Date().timeIntervalSince(oldest.enqueuedAt) * 1000.0)
            }()
            let queueP95AgeMs = self.queuedUDPControlP95AgeMs()
            let resolver88Streak = self.resolverHealth["8.8.8.8"]?.timeoutStreak ?? 0
            let resolver11Streak = self.resolverHealth["1.1.1.1"]?.timeoutStreak ?? 0
            let timeoutRateText = String(format: "%.2f", udpTimeoutRate)
            let badLenRate = self.badLenHardFailRate()
            let badLenRateText = String(format: "%.2f", badLenRate)
            self.log.log("SOCKS5 STATS: \(total) total, \(self.activeConnectionCount) active, \(self.activeRelays.count) relays, \(self.statsAllowed) allowed, \(self.statsBlocked) blocked, \(self.statsUDP) UDP, \(self.statsErrors) errors, udpActive=\(self.activeUDPStreams), udpPeak=\(self.udpActivePeak), udpOpened=\(self.totalUDPStreamsOpened), udpClosed=\(self.totalUDPStreamsClosed), queueDepth=\(self.pendingUDPControlQueue.count), queueOldestMs=\(queueOldestAgeMs), queueP95Ms=\(queueP95AgeMs), modeDetected=\(self.udpDecodeModeDetected), resyncAttempts=\(self.udpDecodeResyncAttempted), resyncSuccess=\(self.udpDecodeResyncSuccess), badLenHardFail=\(self.udpDecodeBadLengthHardFail), badLenRate=\(badLenRateText), recoveredContinues=\(self.udpDecodeRecoveredStreamContinues), closeAfterThreshold=\(self.udpDecodeCloseAfterFailureThreshold), decoderSoftDiscards=\(self.decoderSoftDiscards), decoderDensityCloses=\(self.decoderErrorDensityCloses), dnsInflight=\(self.dnsInflight), dnsReservedSlots=\(self.dnsReservedSlotsInUse()), dnsDedupHits=\(self.dnsDedupHits), resolverSwitches=\(self.resolverSwitchCount), udpTimeoutRate=\(timeoutRateText), ttHardening=\(self.tiktokHardeningActions), udpReclaims=\(self.udpReclaimsByReason), reclaimBudgetExhausted=\(self.maintenanceReclaimBudgetExhaustedCount), stormModeSeconds=\(Int(self.stormModeActiveSeconds())), degradedState=\(self.degradedState.rawValue), degradedTransitions=\(self.degradedTransitions), trippedTransitions=\(self.trippedTransitions), tokenBucketDrops=\(self.tokenBucketDrops), streamBlockSuppressed=\(self.streamBlockSuppressed), streamBlockTokenDrops=\(self.streamBlockTokenDrops), udpForcedRejects=\(self.udpForcedRejects), admissionRejects=\(self.admissionRejectsByReason), graceActive=\(self.hasAnyProtectionGrace()), flagMode=\(self.stabilityFirstModeEnabled ? "stability_first_v2" : "legacy"), udpSocketReuseHitRate=\(String(format: "%.2f", self.udpSocketReuseHitRate())), resolverTimeoutStreaks=[8.8.8.8:\(resolver88Streak),1.1.1.1:\(resolver11Streak)], snapshots=\(self.snapshotHistory.count), mem=\(memMB)MB")
            self.log.log("PROTECTION STATE: state=\(self.degradedState.rawValue) queue=\(self.pendingUDPControlQueue.count) timeout_rate=\(timeoutRateText) forced_rejects=\(self.udpForcedRejects) token_drops=\(self.tokenBucketDrops) stream_token_drops=\(self.streamBlockTokenDrops)")
            self.log.log("SUPPRESSION STATS: tcp=\(self.blockedSuppressedTCP) udp=\(self.blockedSuppressedUDP) keys=\(self.blockedSuppression.count)")
            self.pruneSuppressionState(now: Date())
        }
        timer.resume()
        statsTimer = timer
    }

    private func startUDPSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + BubbleConstants.tiktokHardeningSweepInterval,
            repeating: BubbleConstants.tiktokHardeningSweepInterval
        )
        timer.setEventHandler { [weak self] in
            self?.runUDPMaintenanceSweep()
        }
        timer.resume()
        udpSweepTimer = timer
    }

    // MARK: - Event Recording

    private func recordEvent(
        type: EventType,
        connId: Int,
        host: String,
        port: UInt16,
        sni: String? = nil,
        detail: String,
        bytesDown: Int? = nil,
        decision: PolicyDecision? = nil
    ) {
        eventCounter += 1
        if let decision {
            attemptedByBucket[decision.classification.bucket.rawValue, default: 0] += 1
            if type == .blocked || type == .streamBlocked {
                blockedByBucket[decision.classification.bucket.rawValue, default: 0] += 1
                recentBlockedByHost[(sni ?? host).lowercased()] = Date()
            } else if type == .allowed || type == .completed {
                let key = (sni ?? host).lowercased()
                if let blockedAt = recentBlockedByHost[key],
                   Date().timeIntervalSince(blockedAt) <= 5.0 {
                    possibleFalsePositiveRetries += 1
                }
            }
        }
        let event = TrafficEvent(
            id: eventCounter,
            timestamp: Date(),
            type: type,
            host: host,
            port: port,
            sni: sni,
            detail: detail,
            bytesDown: bytesDown,
            bucket: decision?.classification.bucket.rawValue,
            confidence: decision?.classification.confidence,
            policyAction: decision?.action.rawValue,
            reasons: decision?.classification.reasons,
            toggleSnapshot: decision?.toggleSnapshot,
            policyVersion: decision?.policyVersion,
            decisionReason: decision?.reason
        )
        eventLog.append(event)
        if eventLog.count > maxEvents {
            eventLog.removeFirst(eventLog.count - maxEvents)
        }
    }

    // MARK: - JSON Snapshot Writer

    private func startSnapshotTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.writeSnapshot()
        }
        timer.resume()
        snapshotTimer = timer
    }

    private func writeSnapshot() {
        guard let fileURL = statsFileURL else { return }

        let connections = activeRelays.values.map { tracker in
            ConnectionSnapshot(
                id: tracker.id,
                host: tracker.host,
                port: tracker.port,
                sni: tracker.sni,
                startTime: tracker.startTime,
                bytesUp: tracker.bytesUp,
                bytesDown: tracker.bytesDown,
                isActive: !tracker.logged
            )
        }.sorted { $0.id > $1.id }

        let stats = StatsSnapshot(
            totalConns: connectionCount,
            tcpAllowed: statsAllowed,
            tcpBlocked: statsBlocked,
            udpRelayed: statsUDP,
            errors: statsErrors,
            udpActiveStreams: activeUDPStreams,
            udpStreamsOpened: totalUDPStreamsOpened,
            udpStreamsClosed: totalUDPStreamsClosed,
            udpDecodeBadPrefix: udpDecodeBadPrefix,
            udpDecodeBadLength: udpDecodeBadLength,
            udpDecodeBadPayload: udpDecodeBadPayload,
            udpModePlain: udpModePlain,
            udpModeControlPrefixed: udpModeControlPrefixed,
            udpDecodeModeDetected: udpDecodeModeDetected,
            udpDecodeResyncAttempted: udpDecodeResyncAttempted,
            udpDecodeResyncSuccess: udpDecodeResyncSuccess,
            udpDecodeBadLengthHardFail: udpDecodeBadLengthHardFail,
            udpDecodeRecoveredStreamContinues: udpDecodeRecoveredStreamContinues,
            udpDecodeCloseAfterFailureThreshold: udpDecodeCloseAfterFailureThreshold,
            udpActivePeak: udpActivePeak,
            udpTimeoutRate: statsUDP > 0 ? Double(udpTimeoutCount) / Double(statsUDP) : 0,
            dnsInflight: dnsInflight,
            resolverTimeoutStreakByHost: [
                "8.8.8.8": resolverHealth["8.8.8.8"]?.timeoutStreak ?? 0,
                "1.1.1.1": resolverHealth["1.1.1.1"]?.timeoutStreak ?? 0,
            ],
            resolverSwitchCount: resolverSwitchCount,
            decoderErrorRate: statsUDP > 0 ? Double(decoderErrorCount) / Double(statsUDP) : 0,
            streamCloseReasonCounts: streamCloseReasonCounts,
            tiktokHardeningActions: tiktokHardeningActions,
            udpQueueDepth: pendingUDPControlQueue.count,
            udpQueueOldestAgeMs: {
                guard let oldest = pendingUDPControlQueue.first else { return 0 }
                return Int(Date().timeIntervalSince(oldest.enqueuedAt) * 1000.0)
            }(),
            udpQueueP95AgeMs: queuedUDPControlP95AgeMs(),
            udpReclaimsByReason: udpReclaimsByReason,
            udpForcedRejects: udpForcedRejects,
            udpForcedRejectsByReason: udpReclaimsByReason.filter { $0.key.contains("tiktok_udp_reject") },
            degradedState: degradedState.rawValue,
            degradedTransitions: degradedTransitions,
            trippedTransitions: trippedTransitions,
            trippedSecondsTotal: trippedSecondsTotal + (degradedState == .tripped ? Date().timeIntervalSince(trippedEnteredAt) : 0),
            badLenRate: badLenHardFailRate(),
            recentBadLenHardFails: recentBadLenHardFailCount(),
            tokenBucketDrops: tokenBucketDrops,
            streamBlockSuppressed: streamBlockSuppressed,
            streamBlockTokenDrops: streamBlockTokenDrops,
            admissionRejectsByReason: admissionRejectsByReason,
            stateSecondsByMode: stateSecondsByMode,
            reconnectBreakerCooldownRemainingSec: reconnectBreakerCooldownRemainingSec(),
            reconnectBreakerTrips: reconnectBreakerTrips(),
            reconnectSuppressedByBreaker: reconnectSuppressedByBreakerCount(),
            reconnectBreakerBackoffStep: reconnectBreakerBackoffStep(),
            maintenanceReclaimBudgetExhaustedCount: maintenanceReclaimBudgetExhaustedCount,
            stormModeActiveSeconds: stormModeActiveSeconds(),
            dnsReservedSlotsInUse: dnsReservedSlotsInUse(),
            decoderSoftDiscards: decoderSoftDiscards,
            decoderErrorDensityCloses: decoderErrorDensityCloses,
            attemptedByBucket: attemptedByBucket,
            blockedByBucket: blockedByBucket,
            possibleFalsePositiveRetries: possibleFalsePositiveRetries,
            blockedSuppressedTCP: blockedSuppressedTCP,
            blockedSuppressedUDP: blockedSuppressedUDP,
            suppressionKeysActive: blockedSuppression.count,
            udpSocketReuseHitRate: udpSocketReuseHitRate()
        )

        let topDomains = domainStats
            .map { DomainSnapshot(domain: $0.key, count: $0.value.count, totalBytes: $0.value.bytes) }
            .sorted { $0.totalBytes > $1.totalBytes }
            .prefix(10)

        let snapshot = TrafficSnapshot(
            timestamp: Date(),
            connections: connections,
            stats: stats,
            topDomains: Array(topDomains)
        )

        // Append to ring buffer
        snapshotHistory.append(snapshot)
        if snapshotHistory.count > maxSnapshotHistory {
            snapshotHistory.removeFirst(snapshotHistory.count - maxSnapshotHistory)
        }

        // Write full history + events so the app gets everything even when backgrounded
        let trafficData = TrafficData(snapshots: snapshotHistory, events: eventLog)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(trafficData) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ client: NWConnection) {
        connectionCount += 1
        activeConnectionCount += 1

        if activeConnectionCount > BubbleConstants.maxConnections {
            log.log("SOCKS5: Active connection limit reached (\(activeConnectionCount)/\(BubbleConstants.maxConnections)), rejecting #\(connectionCount)")
            statsErrors += 1
            recordEvent(type: .error, connId: connectionCount, host: "?", port: 0, detail: "Connection limit reached (\(activeConnectionCount)/\(BubbleConstants.maxConnections))")
            activeConnectionCount -= 1
            client.cancel()
            return
        }

        let id = connectionCount
        if id % 50 == 0 {
            log.log("SOCKS5 DIAG: conn #\(id), active=\(activeConnectionCount), relays=\(activeRelays.count), totalAllowed=\(statsAllowed), totalBlocked=\(statsBlocked), errors=\(statsErrors)")
        }
        client.start(queue: queue)
        readMethodNegotiation(client: client, id: id)
    }

    // MARK: - SOCKS5 Method Negotiation

    private func readMethodNegotiation(client: NWConnection, id: Int) {
        client.receive(minimumIncompleteLength: 3, maximumLength: 512) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.log.log("SOCKS5 #\(id): Method negotiation failed: \(String(describing: error))")
                self?.statsErrors += 1
                self?.recordEvent(type: .error, connId: id, host: "?", port: 0, detail: "Method negotiation failed: \(String(describing: error))")
                self?.activeConnectionCount -= 1
                client.cancel()
                return
            }

            let bytes = [UInt8](data)
            guard bytes.count >= 3, bytes[0] == 0x05 else {
                self.log.log("SOCKS5 #\(id): Invalid SOCKS version or short handshake (\(bytes.count) bytes)")
                self.statsErrors += 1
                self.activeConnectionCount -= 1
                client.cancel()
                return
            }

            let nmethods = Int(bytes[1])
            let handshakeLen = 2 + nmethods
            let excess: Data? = bytes.count > handshakeLen ? Data(bytes[handshakeLen...]) : nil

            let reply = Data([0x05, 0x00])
            client.send(content: reply, completion: .contentProcessed { error in
                if error != nil {
                    self.log.log("SOCKS5 #\(id): Failed to send method reply: \(String(describing: error))")
                    self.statsErrors += 1
                    self.activeConnectionCount -= 1
                    client.cancel()
                    return
                }
                self.readRequest(client: client, id: id, buffered: excess)
            })
        }
    }

    // MARK: - SOCKS5 Request (CONNECT / FWD_UDP)

    private func readRequest(client: NWConnection, id: Int, buffered: Data?) {
        if let buffered = buffered, buffered.count >= 4 {
            self.parseRequest(client: client, id: id, data: buffered)
            return
        }

        let existingBytes = buffered ?? Data()

        client.receive(minimumIncompleteLength: 4 - existingBytes.count, maximumLength: 512) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                self?.log.log("SOCKS5 #\(id): Request read failed: \(String(describing: error))")
                self?.statsErrors += 1
                self?.recordEvent(type: .error, connId: id, host: "?", port: 0, detail: "Request read failed: \(String(describing: error))")
                self?.activeConnectionCount -= 1
                client.cancel()
                return
            }
            self.parseRequest(client: client, id: id, data: existingBytes + data)
        }
    }

    private func parseRequest(client: NWConnection, id: Int, data: Data) {
        let bytes = [UInt8](data)

        guard bytes.count >= 4, bytes[0] == 0x05 else {
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            log.log("SOCKS5 #\(id): Invalid request (ver=\(bytes.first.map(String.init) ?? "nil"), len=\(bytes.count))")
            client.cancel()
            return
        }

        let cmd = bytes[1]
        let atyp = bytes[3]

        // Parse address using shared helper (ATYP is at byte index 3)
        guard let addr = parseSOCKSAddress(from: bytes, atypOffset: 3) else {
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            log.log("SOCKS5 #\(id): Failed to parse destination address")
            self.sendSocksError(client: client, reply: 0x08)
            return
        }

        // Diagnostic: log ATYP so we know if tun2socks sends domains or IPs
        let atypName: String
        switch atyp {
        case 0x01: atypName = "IPv4"
        case 0x03: atypName = "DOMAIN"
        case 0x04: atypName = "IPv6"
        default: atypName = "UNKNOWN(\(atyp))"
        }

        switch cmd {
        case 0x01: // CONNECT (TCP)
            log.log("TCP #\(id): CONNECT atyp=\(atypName) host=\(addr.host) port=\(addr.port)")
            handleConnect(client: client, id: id, host: addr.host, port: addr.port)

        case 0x05: // FWD_UDP (hev-socks5-tunnel custom extension)
            handleFwdUDP(client: client, id: id)

        default:
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            log.log("SOCKS5 #\(id): unsupported cmd=\(cmd)")
            self.sendSocksError(client: client, reply: 0x07)
        }
    }

    // MARK: - Shared Address Parser

    /// Parses ATYP + address + port from a byte buffer.
    /// `atypOffset` is the index of the ATYP byte in the buffer.
    /// Returns nil if the buffer is too short or address type is unknown.
    private func parseSOCKSAddress(from bytes: [UInt8], atypOffset: Int) -> ParsedAddress? {
        guard bytes.count > atypOffset else { return nil }
        let atyp = bytes[atypOffset]
        let addrStart = atypOffset + 1

        switch atyp {
        case 0x01: // IPv4
            guard bytes.count >= addrStart + 4 + 2 else { return nil }
            let host = "\(bytes[addrStart]).\(bytes[addrStart + 1]).\(bytes[addrStart + 2]).\(bytes[addrStart + 3])"
            let portOffset = addrStart + 4
            let port = (UInt16(bytes[portOffset]) << 8) | UInt16(bytes[portOffset + 1])
            return ParsedAddress(host: host, port: port, headerEndOffset: portOffset + 2)

        case 0x03: // Domain name
            guard bytes.count > addrStart else { return nil }
            let domainLen = Int(bytes[addrStart])
            let domainStart = addrStart + 1
            guard bytes.count >= domainStart + domainLen + 2 else { return nil }
            guard let domain = String(bytes: Array(bytes[domainStart..<(domainStart + domainLen)]), encoding: .utf8) else {
                return nil
            }
            let portOffset = domainStart + domainLen
            let port = (UInt16(bytes[portOffset]) << 8) | UInt16(bytes[portOffset + 1])
            return ParsedAddress(host: domain, port: port, headerEndOffset: portOffset + 2)

        case 0x04: // IPv6
            guard bytes.count >= addrStart + 16 + 2 else { return nil }
            let parts = (0..<8).map { i in
                String(format: "%02x%02x", bytes[addrStart + i * 2], bytes[addrStart + i * 2 + 1])
            }
            let host = parts.joined(separator: ":")
            let portOffset = addrStart + 16
            let port = (UInt16(bytes[portOffset]) << 8) | UInt16(bytes[portOffset + 1])
            return ParsedAddress(host: host, port: port, headerEndOffset: portOffset + 2)

        default:
            return nil
        }
    }

    // MARK: - CONNECT (TCP)

    private func handleConnect(client: NWConnection, id: Int, host: String, port: UInt16) {
        let decision = self.filter.evaluateConnection(host: host, port: port)

        switch decision.action {
        case .blockNow:
            let gate = evaluateProtectionGate(
                host: host,
                port: port,
                decision: decision,
                transport: "tcp",
                stage: .admission
            )
            if gate == .rejectNewStream || gate == .dropFast {
                blockedSuppressedTCP += 1
                admissionRejectsByReason["tcp_drop_fast", default: 0] += 1
                activeConnectionCount -= 1
                sendSocksError(client: client, reply: 0x05)
                return
            }
            if gate == .suppress {
                blockedSuppressedTCP += 1
                admissionRejectsByReason["tcp_suppressed", default: 0] += 1
                activeConnectionCount -= 1
                sendSocksError(client: client, reply: 0x05)
                return
            }
            self.statsBlocked += 1
            self.activeConnectionCount -= 1
            self.log.log("SOCKS5 #\(id): BLOCKED \(host):\(port)")
            self.recordEvent(type: .blocked, connId: id, host: host, port: port, detail: "Connection blocked by policy", decision: decision)
            self.sendSocksError(client: client, reply: 0x05)

        case .allow, .blockAfterBytes, .shadowAllow:
            self.statsAllowed += 1
            self.recordEvent(type: .allowed, connId: id, host: host, port: port, detail: "TCP CONNECT", decision: decision)
            self.connectToTarget(client: client, host: host, port: port, id: id)
        }
    }

    // MARK: - FWD_UDP (hev-socks5-tunnel custom command 0x05)
    //
    // Framing modes accepted by the decoder:
    //  - [len16][payload]
    //  - [0x0001][len16][payload]
    //
    // Mode is locked per stream after first valid frame and mirrored on responses.
    // Parse errors are stream-local and never escalate to tunnel shutdown.

    private func handleFwdUDP(client: NWConnection, id: Int) {
        if isDNSResolverStormActive(), activeUDPStreams >= 2 {
            log.log("UDP #\(id): FWD_UDP rejected by admission controller reason=dns_timeout_storm active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count)")
            admissionRejectsByReason["udp_admission_dns_timeout_storm", default: 0] += 1
            udpForcedRejects += 1
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }
        let stormMode = isStormMode()
        let now = Date()
        let pressurePhase = currentTransportPressurePhase(now: now)
        let admission = admissionController.decide(
            active: activeUDPStreams,
            queued: pendingUDPControlQueue.count,
            stormMode: stormMode,
            maxActive: effectiveMaxActiveUDPStreams(stormMode: stormMode),
            pressurePhase: pressurePhase,
            preferQueueing: stabilityFirstModeEnabled,
            graceActive: hasAnyProtectionGrace(now: now),
            now: now
        )
        switch admission {
        case .accept:
            break
        case .queue:
            log.log("UDP #\(id): FWD_UDP queued by admission controller active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count + 1)")
            pendingUDPControlQueue.append(PendingUDPControl(client: client, id: id, enqueuedAt: Date()))
            return
        case .reject(let reason):
            log.log("UDP #\(id): FWD_UDP rejected by admission controller reason=\(reason) active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count)")
            admissionRejectsByReason["udp_admission_\(reason)", default: 0] += 1
            udpForcedRejects += 1
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }
        if shouldRejectNewTikTokUDPControlStream() {
            let reason = degradedState == .tripped ? "tripped_tiktok_udp_reject" : "degraded_tiktok_udp_reject"
            log.log("UDP #\(id): FWD_UDP rejected reason=\(reason) state=\(degradedState.rawValue) queue=\(pendingUDPControlQueue.count)")
            udpForcedRejects += 1
            udpReclaimsByReason[reason, default: 0] += 1
            admissionRejectsByReason[reason, default: 0] += 1
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }
        log.log("UDP #\(id): FWD_UDP accepted, starting frame relay")
        let state = UDPStreamState(id: id, client: client, decoder: UDPControlStreamDecoder(maxFrameSize: BubbleConstants.maxUDPFrameSize))
        udpStreamsByID[id] = state
        activeUDPStreams += 1
        udpActivePeak = max(udpActivePeak, activeUDPStreams)
        totalUDPStreamsOpened += 1

        let reply = buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
        client.send(content: reply, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                self.closeUDPControlStream(client: client, state: state, reason: "send_reply_failed")
                return
            }
            self.readUDPControlStream(client: client, state: state)
        })
    }

    private func readUDPControlStream(client: NWConnection, state: UDPStreamState) {
        guard !state.closed, !state.processingFrame else { return }
        if !state.pendingFrames.isEmpty {
            processNextUDPFrame(client: client, state: state)
            return
        }

        client.receive(minimumIncompleteLength: 1, maximumLength: BubbleConstants.maxUDPFrameSize + 8) { [weak self] data, _, isComplete, error in
            guard let self = self, !state.closed else { return }

            if let error = error {
                self.closeUDPControlStream(client: client, state: state, reason: "read_error=\(error)")
                return
            }

            if let data, !data.isEmpty {
                state.lastActivityAt = Date()
                let appendResult = state.decoder.append(data)
                if let mode = state.decoder.currentMode, state.mode == nil {
                    state.mode = mode
                    self.udpDecodeModeDetected += 1
                    if mode == .plain {
                        self.udpModePlain += 1
                    } else {
                        self.udpModeControlPrefixed += 1
                    }
                    self.log.log("UDP_DECODER stream=\(state.id) event=mode_locked mode=\(mode.rawValue)")
                }
                let diagnostics = state.decoder.drainDiagnostics()
                self.udpDecodeResyncAttempted += diagnostics.resyncAttempts
                self.udpDecodeResyncSuccess += diagnostics.resyncSuccesses

                state.pendingFrames.append(contentsOf: appendResult.frames)
                if state.hardeningEnabled && state.pendingFrames.count > BubbleConstants.tiktokHardeningMaxPendingFramesPerStream {
                    self.tiktokHardeningActions["pending_frames_overflow_close", default: 0] += 1
                    self.closeUDPControlStream(client: client, state: state, reason: "tiktok_pending_frames_overflow")
                    return
                }

                switch appendResult.status {
                case .ok:
                    if !appendResult.frames.isEmpty {
                        state.decoderFailureCount = 0
                        state.firstDecoderFailureAt = nil
                    }
                    self.processNextUDPFrame(client: client, state: state)
                case .needMoreBytes:
                    self.readUDPControlStream(client: client, state: state)
                case .recovered(let decodeError):
                    self.recordDecoderError(decodeError, hardFailure: false)
                    state.decoderRecoveryCount += 1
                    self.decoderSoftDiscards += 1
                    let failuresInWindow = state.decoderFailuresInWindow(now: Date(), window: BubbleConstants.udpDecodeFailureWindowSeconds)
                    let density = state.bumpDecoderErrorDensity(now: Date())
                    self.udpDecodeRecoveredStreamContinues += 1
                    self.log.log("UDP_DECODER stream=\(state.id) event=decode_recovered reason=\(self.decoderReasonCode(decodeError)) failures_in_window=\(failuresInWindow) density=\(String(format: "%.2f", density))")
                    if (failuresInWindow > effectiveDecodeFailureCloseThreshold() || density >= effectiveRecoveredDecoderCloseDensity()) && !hasAnyProtectionGrace() {
                        self.recordDecoderError(decodeError, hardFailure: true)
                        self.udpDecodeCloseAfterFailureThreshold += 1
                        self.decoderErrorDensityCloses += 1
                        self.closeUDPControlStream(client: client, state: state, reason: "decode_recovered_threshold_exceeded")
                        return
                    }
                    self.processNextUDPFrame(client: client, state: state)
                case .failed(let decodeError):
                    self.recordDecoderError(decodeError, hardFailure: false)
                    self.decoderErrorCount += 1
                    state.decoderFailureCount += 1
                    self.decoderSoftDiscards += 1
                    let density = state.bumpDecoderErrorDensity(now: Date())
                    if state.firstDecoderFailureAt == nil {
                        state.firstDecoderFailureAt = Date()
                    }
                    self.log.log("UDP_DECODER stream=\(state.id) event=decode_error reason=\(self.decoderReasonCode(decodeError)) failures=\(state.decoderFailureCount) density=\(String(format: "%.2f", density))")
                    if case .badLength = decodeError {
                        let failuresInWindow = state.decoderFailuresInWindow(now: Date(), window: BubbleConstants.udpDecodeFailureWindowSeconds)
                        if failuresInWindow <= effectiveBadLenSoftFailureLimit() || self.isStormMode() || self.hasAnyProtectionGrace() {
                            self.log.log("UDP_DECODER stream=\(state.id) event=soft_fail_bad_len reason=bad_len failures_in_window=\(failuresInWindow)")
                            self.readUDPControlStream(client: client, state: state)
                            return
                        }
                        self.recordDecoderError(decodeError, hardFailure: true)
                        self.log.log("UDP_DECODER stream=\(state.id) event=close_after_bad_len_window reason=bad_len failures_in_window=\(failuresInWindow)")
                        self.closeUDPControlStream(client: client, state: state, reason: "decode_bad_len_window_fail_closed")
                        return
                    }
                    if (state.decoderFailureCount >= effectiveDecodeFailureCloseThreshold() || density >= effectiveDecoderCloseDensity()) && !hasAnyProtectionGrace() {
                        self.recordDecoderError(decodeError, hardFailure: true)
                        self.udpDecodeCloseAfterFailureThreshold += 1
                        self.decoderErrorDensityCloses += 1
                        self.log.log("UDP_DECODER stream=\(state.id) event=close_after_failures reason=\(self.decoderReasonCode(decodeError)) threshold=\(BubbleConstants.udpDecodeFailureCloseThreshold)")
                        self.closeUDPControlStream(client: client, state: state, reason: "decode_\(self.decoderReasonCode(decodeError))_threshold_exceeded")
                        return
                    }
                    self.readUDPControlStream(client: client, state: state)
                }
                return
            }

            if isComplete {
                self.closeUDPControlStream(client: client, state: state, reason: "control_stream_completed")
            } else {
                self.readUDPControlStream(client: client, state: state)
            }
        }
    }

    private func processNextUDPFrame(client: NWConnection, state: UDPStreamState) {
        guard !state.closed else { return }
        guard !state.processingFrame else { return }

        guard !state.pendingFrames.isEmpty else {
            readUDPControlStream(client: client, state: state)
            return
        }

        let decodedFrame = state.pendingFrames.removeFirst()
        state.processingFrame = true
        state.processingStartedAt = Date()
        state.lastActivityAt = Date()

        guard let parsed = parseUDPPayload(decodedFrame.payload, streamID: state.id) else {
            udpDecodeBadPayload += 1
            log.log("UDP_DECODER stream=\(state.id) event=decode_error reason=bad_payload_soft_drop")
            state.processingFrame = false
            state.processingStartedAt = nil
            readUDPControlStream(client: client, state: state)
            return
        }

        statsUDP += 1
        state.lastHost = parsed.addr.host
        state.lastPort = parsed.addr.port
        log.log("UDP #\(state.id): dest=\(parsed.addr.host):\(parsed.addr.port), payload=\(parsed.payload.count)B")

        let decision = filter.evaluateUDP(host: parsed.addr.host, port: parsed.addr.port, payloadBytes: parsed.payload.count)
        if !state.hardeningEnabled, isTikTokProtectedBucket(decision.classification.bucket) {
            state.hardeningEnabled = true
            state.hardeningBucket = decision.classification.bucket
            tiktokHardeningActions["stream_promoted_to_tiktok_hardening", default: 0] += 1
        }
        log.log("UDP_POLICY stream=\(state.id) host=\(parsed.addr.host) port=\(parsed.addr.port) action=\(decision.action.rawValue) reason=\(decision.reason) bucket=\(decision.classification.bucket.rawValue)")
        if decision.action == .blockNow {
            let gate = evaluateProtectionGate(
                host: parsed.addr.host,
                port: parsed.addr.port,
                decision: decision,
                transport: "udp",
                stage: .admission
            )
            if gate == .rejectNewStream || gate == .dropFast {
                blockedSuppressedUDP += 1
                admissionRejectsByReason["udp_drop_fast", default: 0] += 1
                state.processingFrame = false
                processNextUDPFrame(client: client, state: state)
                return
            }
            if gate == .suppress {
                blockedSuppressedUDP += 1
                admissionRejectsByReason["udp_suppressed", default: 0] += 1
                state.processingFrame = false
                processNextUDPFrame(client: client, state: state)
                return
            }
            statsBlocked += 1
            recordEvent(type: .blocked, connId: state.id, host: parsed.addr.host, port: parsed.addr.port, detail: "UDP blocked by policy", decision: decision)
            state.processingFrame = false
            processNextUDPFrame(client: client, state: state)
            return
        }

        relayUDPDatagram(
            streamID: state.id,
            host: parsed.addr.host,
            port: parsed.addr.port,
            payload: parsed.payload,
            headerBytes: parsed.headerBytes,
            responseMode: decodedFrame.mode
        ) { [weak self] responseFrame in
            guard let self = self, !state.closed else { return }
            state.processingFrame = false

            if let responseFrame {
                state.timeoutStreak = 0
                state.markProgress(now: Date())
                client.send(content: responseFrame, completion: .contentProcessed { [weak self] _ in
                    guard let self = self else { return }
                    state.processingStartedAt = nil
                    if self.isStormMode(),
                       state.lastPort == 53,
                       state.pendingFrames.isEmpty,
                       !state.processingFrame,
                       !self.hasAnyProtectionGrace() {
                        self.closeUDPControlStream(client: client, state: state, reason: "storm_dns_one_shot_retire")
                        return
                    }
                    self.processNextUDPFrame(client: client, state: state)
                })
            } else {
                state.timeoutStreak += 1
                let timeoutThreshold = state.hardeningEnabled
                    ? BubbleConstants.tiktokHardeningTimeoutStreakCloseThreshold
                    : BubbleConstants.udpGlobalTimeoutStreakCloseThreshold
                if state.timeoutStreak >= effectiveTimeoutStreakCloseThreshold(base: timeoutThreshold),
                   shouldCloseStreamForTimeout(state: state, now: Date()) {
                    let reason = state.hardeningEnabled ? "tiktok_timeout_streak_reclaim" : "global_timeout_streak_reclaim"
                    self.tiktokHardeningActions["timeout_streak_reclaim", default: 0] += 1
                    self.udpReclaimsByReason[reason, default: 0] += 1
                    self.closeUDPControlStream(client: client, state: state, reason: reason)
                    return
                }
                if self.isStormMode(), state.lastPort == 53, state.pendingFrames.isEmpty, !self.hasAnyProtectionGrace() {
                    self.closeUDPControlStream(client: client, state: state, reason: "storm_dns_timeout_retire")
                    return
                }
                state.processingStartedAt = nil
                self.processNextUDPFrame(client: client, state: state)
            }
        }
    }

    private func parseUDPPayload(_ bytes: [UInt8], streamID: Int) -> (addr: ParsedAddress, headerBytes: [UInt8], payload: Data)? {
        // hev-socks5-tunnel payload:
        // [0x0a][ATYP][DST.ADDR][DST.PORT][PAYLOAD]
        if bytes.count >= 8, bytes[0] == 0x0a,
           let addr = parseSOCKSAddress(from: bytes, atypOffset: 1), addr.headerEndOffset <= bytes.count {
            let headerBytes = Array(bytes[0..<addr.headerEndOffset])
            let payload = addr.headerEndOffset < bytes.count ? Data(bytes[addr.headerEndOffset...]) : Data()
            return (addr, headerBytes, payload)
        }

        // SOCKS5 UDP fallback payload:
        // [RSV 2][FRAG 1][ATYP][DST.ADDR][DST.PORT][PAYLOAD]
        if bytes.count >= 10, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x00,
           let addr = parseSOCKSAddress(from: bytes, atypOffset: 3), addr.headerEndOffset <= bytes.count {
            log.log("UDP #\(streamID): parser fallback succeeded using SOCKS UDP offset 3")
            let headerBytes = Array(bytes[0..<addr.headerEndOffset])
            let payload = addr.headerEndOffset < bytes.count ? Data(bytes[addr.headerEndOffset...]) : Data()
            return (addr, headerBytes, payload)
        }

        return nil
    }

    private func relayUDPDatagram(
        streamID: Int,
        host: String,
        port: UInt16,
        payload: Data,
        headerBytes: [UInt8],
        responseMode: UDPControlFramingMode,
        completion: @escaping (Data?) -> Void
    ) {
        let resolvedHost = effectiveResolverHost(originalHost: host, port: port)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log.log("UDP #\(streamID): invalid port \(port)")
            statsErrors += 1
            completion(nil)
            return
        }

        let dedupKey = dnsDedupKey(host: resolvedHost, port: port, payload: payload)
        let dnsDedupWindow = dnsDedupWindowForStream(streamID: streamID)
        if let dedupKey, var inflight = inflightDNSRequests[dedupKey], Date().timeIntervalSince(inflight.startedAt) <= dnsDedupWindow {
            dnsDedupHits += 1
            inflight.callbacks.append(completion)
            inflightDNSRequests[dedupKey] = inflight
            return
        }

        if let dedupKey {
            dnsInflight += 1
            inflightDNSRequests[dedupKey] = InflightDNSRequest(startedAt: Date(), callbacks: [completion])
        }

        let poolKey = "\(resolvedHost):\(port)"
        let allowReuse = port == 53
        let udp = pooledUDPConnection(host: resolvedHost, port: nwPort, poolKey: poolKey, allowReuse: allowReuse)

        var completed = false
        let complete: (Data?) -> Void = { [weak self] responseFrame in
            self?.queue.async {
                guard !completed else { return }
                completed = true
                if let dedupKey, var inflight = self?.inflightDNSRequests.removeValue(forKey: dedupKey) {
                    self?.dnsInflight = max((self?.dnsInflight ?? 1) - 1, 0)
                    let callbacks = inflight.callbacks
                    inflight.callbacks.removeAll()
                    for cb in callbacks {
                        cb(responseFrame)
                    }
                } else {
                    completion(responseFrame)
                }
            }
        }

        queue.asyncAfter(deadline: .now() + BubbleConstants.udpRelayTimeout) { [weak self] in
            if !(self?.hasAnyProtectionGrace() ?? false) || port != 53 {
                self?.udpTimeoutCount += 1
            }
            self?.markResolverTimeout(host: resolvedHost, port: port)
            if allowReuse {
                self?.evictUDPSocket(poolKey: poolKey)
            } else {
                udp.cancel()
            }
            self?.log.log("UDP #\(streamID): TIMEOUT for \(resolvedHost):\(port)")
            complete(nil)
        }

        udp.stateUpdateHandler = { [weak self] connState in
            switch connState {
            case .ready:
                self?.log.log("UDP #\(streamID): NWConnection ready to \(resolvedHost):\(port), sending \(payload.count)B")
                udp.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        self?.markResolverTimeout(host: resolvedHost, port: port)
                        if allowReuse {
                            self?.evictUDPSocket(poolKey: poolKey)
                        } else {
                            udp.cancel()
                        }
                        self?.log.log("UDP #\(streamID): send FAILED to \(resolvedHost):\(port): \(error)")
                        complete(nil)
                        return
                    }

                    udp.receiveMessage { respData, _, _, recvError in
                        if let respData, !respData.isEmpty {
                            self?.markResolverSuccess(host: resolvedHost, port: port)
                            self?.log.log("UDP #\(streamID): got \(respData.count)B response from \(resolvedHost):\(port)")
                            var frame = headerBytes
                            frame.append(contentsOf: [UInt8](respData))
                            let frameLen = frame.count
                            var framedData: [UInt8] = []
                            if responseMode == .controlPrefixed {
                                framedData.append(contentsOf: [0x00, 0x01])
                            }
                            framedData.append(contentsOf: [UInt8(frameLen >> 8), UInt8(frameLen & 0xFF)])
                            framedData.append(contentsOf: frame)
                            complete(Data(framedData))
                        } else {
                            self?.markResolverTimeout(host: resolvedHost, port: port)
                            if allowReuse {
                                self?.evictUDPSocket(poolKey: poolKey)
                            } else {
                                udp.cancel()
                            }
                            self?.log.log("UDP #\(streamID): empty/nil response from \(resolvedHost):\(port), error=\(String(describing: recvError))")
                            complete(nil)
                        }
                    }
                })

            case .failed(let error):
                self?.markResolverTimeout(host: resolvedHost, port: port)
                self?.log.log("UDP #\(streamID): NWConnection FAILED to \(resolvedHost):\(port): \(error)")
                if allowReuse {
                    self?.evictUDPSocket(poolKey: poolKey)
                } else {
                    udp.cancel()
                }
                complete(nil)

            case .waiting(let error):
                self?.log.log("UDP #\(streamID): NWConnection WAITING to \(resolvedHost):\(port): \(error)")

            default:
                break
            }
        }

        if allowReuse {
            startUDPConnectionIfNeeded(udp, for: poolKey)
        } else {
            udp.start(queue: queue)
        }
    }

    private func closeUDPControlStream(client: NWConnection, state: UDPStreamState, reason: String) {
        guard !state.closed else { return }
        if shouldBlockCloseDuringGrace(state: state, reason: reason) {
            log.log("TRANSPORT_PROTECTION grace_close_blocked stream=\(state.id) reason=\(reason)")
            state.processingFrame = false
            state.processingStartedAt = nil
            return
        }
        state.closed = true
        udpStreamsByID.removeValue(forKey: state.id)
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        activeUDPStreams = max(activeUDPStreams - 1, 0)
        totalUDPStreamsClosed += 1
        streamCloseReasonCounts[reason, default: 0] += 1
        log.log("UDP_DECODER stream=\(state.id) event=close reason=\(reason) queued=\(state.pendingFrames.count) decode_failures=\(state.decoderFailureCount) recoveries=\(state.decoderRecoveryCount)")
        client.cancel()
        drainQueuedUDPControlStreamsIfNeeded()
    }

    private func shouldBlockCloseDuringGrace(state: UDPStreamState, reason: String, now: Date = Date()) -> Bool {
        guard hasAnyProtectionGrace(now: now) else { return false }
        let guardedReasons: Set<String> = [
            "stuck_processing_reclaim",
            "global_idle_timeout_reclaim",
            "tiktok_idle_timeout_reclaim",
            "global_max_lifetime_reclaim",
            "tiktok_max_lifetime_reclaim",
            "global_timeout_streak_reclaim",
            "tiktok_timeout_streak_reclaim",
            "storm_dns_timeout_retire",
            "storm_dns_one_shot_retire",
        ]
        if guardedReasons.contains(reason) || reason.hasPrefix("emergency_reclaim_") {
            return true
        }
        if activeUDPStreams <= minimumUDPControlStreamsDuringGrace, state.lastPort == 53 {
            return true
        }
        return false
    }

    private func drainQueuedUDPControlStreamsIfNeeded() {
        let stormMode = isStormMode()
        let effectiveMax = effectiveMaxActiveUDPStreams(stormMode: stormMode)
        while activeUDPStreams < effectiveMax, !pendingUDPControlQueue.isEmpty {
            let next = pendingUDPControlQueue.removeFirst()
            handleFwdUDP(client: next.client, id: next.id)
        }
    }

    private func isTikTokProtectedBucket(_ bucket: ContentBucket) -> Bool {
        bucket == .tiktokControl || bucket == .tiktokVideo
    }

    private func dnsDedupWindowForStream(streamID: Int) -> TimeInterval {
        guard let state = udpStreamsByID[streamID], state.hardeningEnabled else {
            return BubbleConstants.dnsDedupWindow
        }
        return BubbleConstants.tiktokHardeningDNSDedupWindow
    }

    private func runUDPMaintenanceSweep() {
        closeStaleQueuedUDPControlStreams()
        sweepInflightDNSExpirations()
        sweepUDPControlStreams()
        reclaimUDPStreamsUnderPressure(reason: "maintenance")
        pruneHostCooldowns()
        drainQueuedUDPControlStreamsIfNeeded()
    }

    private func sweepUDPControlStreams() {
        let now = Date()
        for state in udpStreamsByID.values where !state.closed {
            if hasAnyProtectionGrace(now: now), state.lastPort == 53 {
                continue
            }
            if let started = state.processingStartedAt,
               now.timeIntervalSince(started) > watchdogTimeoutForState() {
                if now.timeIntervalSince(lastStuckProcessingReclaimAt) < BubbleConstants.udpEmergencyReclaimMinInterval {
                    continue
                }
                lastStuckProcessingReclaimAt = now
                udpReclaimsByReason["stuck_processing_reclaim", default: 0] += 1
                closeUDPControlStream(client: state.client, state: state, reason: "stuck_processing_reclaim")
                continue
            }

            let maxLifetime = state.hardeningEnabled ? BubbleConstants.tiktokHardeningMaxLifetime : BubbleConstants.udpGlobalMaxLifetime
            if now.timeIntervalSince(state.createdAt) > effectiveMaxLifetime(base: maxLifetime) {
                let reason = state.hardeningEnabled ? "tiktok_max_lifetime_reclaim" : "global_max_lifetime_reclaim"
                tiktokHardeningActions["max_lifetime_reclaim", default: 0] += 1
                udpReclaimsByReason[reason, default: 0] += 1
                if shouldAllowReclaim(reason: reason, now: now) {
                    closeUDPControlStream(client: state.client, state: state, reason: reason)
                } else {
                    log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reason)")
                }
                continue
            }

            let idleTimeout = state.hardeningEnabled ? BubbleConstants.tiktokHardeningIdleTimeout : BubbleConstants.udpGlobalIdleTimeout
            if now.timeIntervalSince(state.lastActivityAt) > effectiveIdleTimeout(base: idleTimeout) {
                let reason = state.hardeningEnabled ? "tiktok_idle_timeout_reclaim" : "global_idle_timeout_reclaim"
                tiktokHardeningActions["idle_timeout_reclaim", default: 0] += 1
                udpReclaimsByReason[reason, default: 0] += 1
                if shouldSkipIdleReclaimDueToRecentSuccess(state: state, now: now) {
                    log.log("TRANSPORT_PROTECTION reclaim_skipped_recent_success stream=\(state.id) reason=\(reason)")
                    continue
                }
                if shouldAllowReclaim(reason: reason, now: now) {
                    closeUDPControlStream(client: state.client, state: state, reason: reason)
                } else {
                    log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reason)")
                }
            }
        }
        updateTransportDegradedState()
    }

    private func closeStaleQueuedUDPControlStreams() {
        let now = Date()
        if hasAnyProtectionGrace(now: now) {
            return
        }
        let maxQueueAge = isStormMode() ? BubbleConstants.udpStormQueueMaxAge : BubbleConstants.udpQueuedStreamMaxAge
        var retained: [PendingUDPControl] = []
        retained.reserveCapacity(pendingUDPControlQueue.count)
        for item in pendingUDPControlQueue {
            if now.timeIntervalSince(item.enqueuedAt) > maxQueueAge {
                udpReclaimsByReason["queue_age_reclaim", default: 0] += 1
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                item.client.cancel()
            } else {
                retained.append(item)
            }
        }
        pendingUDPControlQueue = retained
    }

    private func sweepInflightDNSExpirations() {
        let now = Date()
        for (key, inflight) in inflightDNSRequests where now.timeIntervalSince(inflight.startedAt) > BubbleConstants.dnsInflightMaxAge {
            inflightDNSRequests.removeValue(forKey: key)
            dnsInflight = max(dnsInflight - 1, 0)
            for callback in inflight.callbacks {
                callback(nil)
            }
        }
    }

    private func updateTransportDegradedState() {
        let now = Date()
        sampleStateSeconds(now: now)
        sampleStormModeDuration(now: now)
        let timeoutRate = statsUDP > 0 ? Double(udpTimeoutCount) / Double(statsUDP) : 0
        let badLenRate = badLenHardFailRate(now: now)
        let isSaturated = pendingUDPControlQueue.count >= effectiveDegradedEnterQueueDepth()
        let isRecoveringDepth = pendingUDPControlQueue.count <= BubbleConstants.degradedRecoverQueueDepth
        let timeoutStorm = timeoutRate >= effectiveDegradedTimeoutRateEnter()
        let timeoutRecovered = timeoutRate <= BubbleConstants.degradedTimeoutRateRecover
        let badLenStorm = badLenRate >= BubbleConstants.degradedBadLenRateEnter
        let badLenRecovered = badLenRate <= BubbleConstants.degradedBadLenRateRecover
        let recentEmergencyReclaims = countRecentEmergencyReclaims(windowSeconds: BubbleConstants.trippedWindowSeconds)
        let severeSaturation = pendingUDPControlQueue.count >= effectiveTrippedEnterQueueDepth()
        let severeTimeoutStorm = timeoutRate >= effectiveTrippedEnterTimeoutRate()
        let severeBadLenStorm = badLenRate >= BubbleConstants.trippedBadLenRateEnter
        let severeReclaims = recentEmergencyReclaims >= BubbleConstants.trippedEnterEmergencyReclaims
        let severeCondition = Self.shouldTripFromSevereSignals(
            severeSaturation: severeSaturation,
            severeTimeoutStorm: severeTimeoutStorm,
            severeBadLenStorm: severeBadLenStorm,
            severeReclaims: severeReclaims
        )
        if severeCondition {
            if severeSignalSince == nil {
                severeSignalSince = now
            }
        } else {
            severeSignalSince = nil
        }
        let severeSustained = severeSignalSince.map {
            now.timeIntervalSince($0) >= effectiveTrippedEnterMinDegradedSeconds()
        } ?? false
        let trippedRecovered = timeoutRate <= BubbleConstants.trippedRecoverTimeoutRate &&
            pendingUDPControlQueue.count <= BubbleConstants.trippedRecoverQueueDepth &&
            badLenRate <= BubbleConstants.trippedBadLenRateRecover
        let previous = degradedState
        let degradedConditionActive = isSaturated || timeoutStorm || badLenStorm
        switch degradedState {
        case .healthy:
            if degradedConditionActive {
                degradedState = .degraded
                degradedEnteredAt = now
                degradedStableSince = nil
            }
        case .degraded:
            let degradedDwellMet = now.timeIntervalSince(degradedEnteredAt) >= effectiveTrippedEnterMinDegradedSeconds()
            if severeCondition && severeSustained && degradedDwellMet {
                if hasAnyProtectionGrace() {
                    log.log("TRANSPORT_PROTECTION state_transition_blocked_by_grace attempted=\(TransportDegradedState.tripped.rawValue)")
                } else {
                    degradedState = .tripped
                    trippedEnteredAt = now
                    degradedStableSince = nil
                    severeSignalSince = nil
                }
            } else if isRecoveringDepth && timeoutRecovered && badLenRecovered {
                if degradedStableSince == nil {
                    degradedStableSince = now
                }
                if let stableSince = degradedStableSince,
                   now.timeIntervalSince(stableSince) >= BubbleConstants.degradedRecoverStabilizationSeconds {
                    degradedState = .recovering
                    recoveringEnteredAt = now
                    degradedStableSince = nil
                }
            } else {
                degradedStableSince = nil
            }
        case .recovering:
            if isRecoveringDepth && timeoutRecovered && badLenRecovered &&
                now.timeIntervalSince(recoveringEnteredAt) >= BubbleConstants.degradedRecoverStabilizationSeconds {
                degradedState = .healthy
                severeSignalSince = nil
            } else if degradedConditionActive {
                degradedState = .degraded
                degradedEnteredAt = now
                degradedStableSince = nil
            }
        case .tripped:
            let stabilizedSeconds = now.timeIntervalSince(trippedEnteredAt)
            if trippedRecovered && stabilizedSeconds >= BubbleConstants.trippedRecoverStabilizationSeconds {
                degradedState = .recovering
                trippedSecondsTotal += stabilizedSeconds
                recoveringEnteredAt = now
                if stabilityFirstModeEnabled {
                    recoveryGraceUntil = now.addingTimeInterval(BubbleConstants.stabilityFirstRecoveryGraceSeconds)
                }
            }
        }
        if degradedState != previous {
            degradedTransitions += 1
            if degradedState == .tripped {
                trippedTransitions += 1
            }
            log.log("TRANSPORT_PROTECTION state_transition from=\(previous.rawValue) to=\(degradedState.rawValue) timeoutRate=\(String(format: "%.2f", timeoutRate)) badLenRate=\(String(format: "%.2f", badLenRate)) queueDepth=\(pendingUDPControlQueue.count) recentEmergencyReclaims=\(recentEmergencyReclaims)")
        }
        emitPressureDiagnosticsIfNeeded(now: now, timeoutRate: timeoutRate, badLenRate: badLenRate)
        updateTikTokTransportDegradedState()
    }

    private func emitPressureDiagnosticsIfNeeded(now: Date, timeoutRate: Double, badLenRate: Double) {
        let phase = currentTransportPressurePhase(now: now)
        guard phase != .normal else { return }
        guard now.timeIntervalSince(lastPressureDiagnosticsAt) >= BubbleConstants.transportPressureDiagnosticsInterval else { return }
        lastPressureDiagnosticsAt = now
        log.log(
            "TRANSPORT_PROTECTION pressure phase=\(phase.rawValue) state=\(degradedState.rawValue) queue=\(pendingUDPControlQueue.count) activeUDP=\(activeUDPStreams) timeoutRate=\(String(format: "%.2f", timeoutRate)) badLenRate=\(String(format: "%.2f", badLenRate)) grace=\(hasAnyProtectionGrace(now: now))"
        )
    }

    private func sampleStateSeconds(now: Date) {
        let delta = max(0, now.timeIntervalSince(lastStateSampleAt))
        guard delta > 0 else { return }
        stateSecondsByMode[degradedState.rawValue, default: 0] += delta
        lastStateSampleAt = now
    }

    private func updateTikTokTransportDegradedState() {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let degradedReason: String?
        switch degradedState {
        case .healthy:
            degradedReason = nil
        case .degraded:
            degradedReason = pendingUDPControlQueue.count >= effectiveDegradedEnterQueueDepth() ? "udp_queue_saturation" : "udp_timeout_storm"
        case .tripped:
            degradedReason = "tripped_overload_guard"
        case .recovering:
            degradedReason = "recovering"
        }
        defaults?.set(degradedReason != nil, forKey: BubbleConstants.vpnLifecycleTransportDegradedKey)
        defaults?.set(degradedReason ?? "", forKey: BubbleConstants.vpnLifecycleTransportDegradedReasonKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleTransportDegradedTSKey)
    }

    private func reclaimUDPStreamsUnderPressure(reason: String) {
        guard reason == "maintenance" else { return }
        if hasAnyProtectionGrace() {
            log.log("TRANSPORT_PROTECTION grace_active=true reclaim_blocked reason=\(reason)")
            return
        }
        guard isStormMode() else { return }
        guard activeUDPStreams >= BubbleConstants.maxActiveUDPControlStreams else { return }
        guard !pendingUDPControlQueue.isEmpty else { return }
        let now = Date()
        guard now >= maintenanceReclaimCooldownUntil else { return }
        if let oldest = pendingUDPControlQueue.first,
           now.timeIntervalSince(oldest.enqueuedAt) < 0.25 {
            return
        }
        maintenanceReclaimTimestamps = maintenanceReclaimTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.udpMaintenanceReclaimWindowSeconds
        }
        if maintenanceReclaimTimestamps.count >= BubbleConstants.udpMaintenanceReclaimBudgetPerWindow {
            maintenanceReclaimBudgetExhaustedCount += 1
            let extraCooldown = Double(maintenanceReclaimBudgetExhaustedCount) * BubbleConstants.udpEmergencyReclaimMinInterval
            maintenanceReclaimCooldownUntil = now.addingTimeInterval(BubbleConstants.udpEmergencyReclaimMinInterval + min(extraCooldown, 3.0))
            return
        }
        guard now.timeIntervalSince(lastEmergencyReclaimAt) >= BubbleConstants.udpEmergencyReclaimMinInterval else { return }
        lastEmergencyReclaimAt = now
        let hardQueuePressure = pendingUDPControlQueue.count >= BubbleConstants.maxQueuedUDPControlStreams
        var candidates = udpStreamsByID.values
            .filter {
                !$0.closed &&
                !$0.hardeningEnabled &&
                !$0.processingFrame &&
                $0.pendingFrames.isEmpty &&
                now.timeIntervalSince($0.lastProgressAt) > 1.0 &&
                $0.lastPort != 53
            }
            .sorted { $0.lastActivityAt < $1.lastActivityAt }
        if candidates.isEmpty && hardQueuePressure {
            candidates = udpStreamsByID.values
                .filter {
                    !$0.closed &&
                    !$0.processingFrame &&
                    $0.pendingFrames.isEmpty &&
                    now.timeIntervalSince($0.lastProgressAt) > 1.0
                }
                .sorted { $0.lastActivityAt < $1.lastActivityAt }
        }
        let batch = min(BubbleConstants.selectiveReclaimMaxPerSweep, min(BubbleConstants.udpEmergencyReclaimBatchSize, candidates.count))
        guard batch > 0 else { return }
        maintenanceReclaimTimestamps.append(now)
        for state in candidates.prefix(batch) {
            udpReclaimsByReason["emergency_reclaim", default: 0] += 1
            emergencyReclaimTimestamps.append(now)
            let reclaimReason = "emergency_reclaim_\(reason)"
            if shouldAllowReclaim(reason: reclaimReason, now: now) {
                closeUDPControlStream(client: state.client, state: state, reason: reclaimReason)
            } else {
                log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reclaimReason)")
            }
        }
    }

    private func pooledUDPConnection(host: String, port: NWEndpoint.Port, poolKey: String, allowReuse: Bool) -> NWConnection {
        if !allowReuse {
            udpSocketReuseMisses += 1
            return NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        }
        if let existing = udpSocketPool[poolKey] {
            udpSocketReuseHits += 1
            return existing
        }
        udpSocketReuseMisses += 1
        let created = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        udpSocketPool[poolKey] = created
        udpSocketPoolOrder.append(poolKey)
        if udpSocketPoolOrder.count > udpSocketPoolMaxEntries {
            let evicted = udpSocketPoolOrder.removeFirst()
            udpSocketPool.removeValue(forKey: evicted)?.cancel()
            startedUDPSocketKeys.remove(evicted)
        }
        return created
    }

    private func startUDPConnectionIfNeeded(_ connection: NWConnection, for poolKey: String) {
        if !startedUDPSocketKeys.contains(poolKey) {
            startedUDPSocketKeys.insert(poolKey)
            connection.start(queue: queue)
        }
    }

    private func evictUDPSocket(poolKey: String) {
        udpSocketPool.removeValue(forKey: poolKey)?.cancel()
        udpSocketPoolOrder.removeAll { $0 == poolKey }
        startedUDPSocketKeys.remove(poolKey)
    }

    private func watchdogTimeoutForState() -> TimeInterval {
        switch degradedState {
        case .degraded, .tripped:
            return BubbleConstants.udpProcessingWatchdogTimeoutDegraded
        case .healthy, .recovering:
            return BubbleConstants.udpProcessingWatchdogTimeout
        }
    }

    private func isStormMode() -> Bool {
        degradedState == .degraded || degradedState == .tripped || pendingUDPControlQueue.count >= (effectiveDegradedEnterQueueDepth() / 2)
    }

    private func effectiveMaxActiveUDPStreams(stormMode: Bool) -> Int {
        guard stormMode else { return BubbleConstants.maxActiveUDPControlStreams }
        return max(1, BubbleConstants.maxActiveUDPControlStreams - BubbleConstants.udpStormReservedSlots)
    }

    private func sampleStormModeDuration(now: Date) {
        if isStormMode() {
            if stormModeActiveSince == nil {
                stormModeActiveSince = now
            }
        } else if let since = stormModeActiveSince {
            stormModeActiveSecondsTotal += now.timeIntervalSince(since)
            stormModeActiveSince = nil
        }
    }

    private func stormModeActiveSeconds(now: Date = Date()) -> Double {
        if let since = stormModeActiveSince {
            return stormModeActiveSecondsTotal + now.timeIntervalSince(since)
        }
        return stormModeActiveSecondsTotal
    }

    private func dnsReservedSlotsInUse() -> Int {
        udpStreamsByID.values.filter { !$0.closed && $0.lastPort == 53 }.count
    }

    private func decoderReasonCode(_ error: UDPControlDecoderError) -> String {
        switch error {
        case .badPrefix:
            return "bad_prefix"
        case .badLength:
            return "bad_len"
        }
    }

    private struct BlockSuppressionState {
        var lastSeen: Date
        var suppressedHits: Int
    }

    private enum ProtectionGateStage {
        case admission
        case streamBlock
    }

    private enum ProtectionGateResult {
        case allow
        case suppress
        case dropFast
        case rejectNewStream
    }

    private func suppressionKey(host: String, port: UInt16, reason: String) -> String {
        "\(host.lowercased()):\(port):\(reason)"
    }

    private func hostCooldownKey(host: String, port: UInt16, bucket: ContentBucket) -> String {
        "\(host.lowercased()):\(port):\(bucket.rawValue)"
    }

    private func shouldDropFromHostCooldown(host: String, port: UInt16, bucket: ContentBucket, now: Date = Date()) -> Bool {
        let key = hostCooldownKey(host: host, port: port, bucket: bucket)
        guard let until = hostCooldownUntilByKey[key], now < until else { return false }
        return true
    }

    private func markHostCooldown(host: String, port: UInt16, bucket: ContentBucket, now: Date = Date()) {
        let key = hostCooldownKey(host: host, port: port, bucket: bucket)
        hostCooldownUntilByKey[key] = now.addingTimeInterval(BubbleConstants.hostCooldownDropSeconds)
    }

    private func shouldSuppressBlockedFlow(host: String, port: UInt16, reason: String, transport: String) -> Bool {
        let now = Date()
        let key = suppressionKey(host: host, port: port, reason: reason)
        let cooldown = suppressionCooldown(for: reason)
        if var state = blockedSuppression[key] {
            if now.timeIntervalSince(state.lastSeen) <= cooldown {
                state.lastSeen = now
                state.suppressedHits += 1
                blockedSuppression[key] = state
                if state.suppressedHits >= blockSuppressionLogCap && state.suppressedHits % blockSuppressionSummaryEvery == 0 {
                    log.log("POLICY_SUPPRESSION transport=\(transport) host=\(host.lowercased()) port=\(port) reason=\(reason) suppressed=\(state.suppressedHits)")
                }
                return true
            }
            blockedSuppression[key] = BlockSuppressionState(lastSeen: now, suppressedHits: 0)
            return false
        }
        blockedSuppression[key] = BlockSuppressionState(lastSeen: now, suppressedHits: 0)
        return false
    }

    private func evaluateProtectionGate(
        host: String,
        port: UInt16,
        decision: PolicyDecision,
        transport: String,
        stage: ProtectionGateStage
    ) -> ProtectionGateResult {
        guard decision.action == .blockNow, isTikTokProtectedBucket(decision.classification.bucket) else {
            return .allow
        }

        recentTikTokBlockEvents.append(Date())

        if stage == .admission && shouldRejectNewTikTokUDPControlStream() {
            return .rejectNewStream
        }
        if shouldDropFromHostCooldown(host: host, port: port, bucket: decision.classification.bucket) {
            return .dropFast
        }
        if shouldDropTikTokRetryByTokenBucket(host: host, port: port, decision: decision, transport: transport) {
            tokenBucketDrops += 1
            markHostCooldown(host: host, port: port, bucket: decision.classification.bucket)
            return .dropFast
        }
        if shouldSuppressBlockedFlow(host: host, port: port, reason: decision.reason, transport: transport) {
            return .suppress
        }
        return .allow
    }

    private func suppressionCooldown(for reason: String) -> TimeInterval {
        if reason == "tiktok_video_block_now" {
            switch degradedState {
            case .healthy:
                return aggressiveBlockSuppressionCooldown
            case .degraded, .tripped:
                return BubbleConstants.aggressiveBlockSuppressionStormCooldown
            case .recovering:
                return aggressiveBlockSuppressionCooldown * 1.5
            }
        }
        return blockSuppressionCooldown
    }

    private func countRecentEmergencyReclaims(windowSeconds: TimeInterval) -> Int {
        let now = Date()
        emergencyReclaimTimestamps = emergencyReclaimTimestamps.filter { now.timeIntervalSince($0) <= windowSeconds }
        return emergencyReclaimTimestamps.count
    }

    private func shouldRejectNewTikTokUDPControlStream() -> Bool {
        let now = Date()
        if hasAnyProtectionGrace(now: now) {
            return false
        }
        guard isTikTokRetryStormActive() else { return false }
        let phase = currentTransportPressurePhase(now: now)
        if phase == .critical {
            // Invariant: avoid full rejection unless we're truly at hard cap.
            return Self.shouldForceGlobalUDPReject(
                active: activeUDPStreams,
                queued: pendingUDPControlQueue.count,
                maxActive: BubbleConstants.maxActiveUDPControlStreams,
                maxQueued: BubbleConstants.maxQueuedUDPControlStreams
            )
        }
        if phase == .degraded {
            return pendingUDPControlQueue.count >= BubbleConstants.degradedTikTokUDPRejectQueueDepth
        }
        return false
    }

    private func shouldDropTikTokRetryByTokenBucket(host: String, port: UInt16, decision: PolicyDecision, transport: String) -> Bool {
        guard decision.action == .blockNow, isTikTokProtectedBucket(decision.classification.bucket) else {
            return false
        }
        let key = "\(host.lowercased()):\(port):\(decision.classification.bucket.rawValue)"
        let now = Date()
        var bucket = tokenBucketsByHost[key] ?? TokenBucketState(
            tokens: BubbleConstants.tiktokRetryTokenBucketCapacity,
            lastRefillAt: now
        )
        let elapsed = max(0, now.timeIntervalSince(bucket.lastRefillAt))
        let refill = elapsed * BubbleConstants.tiktokRetryTokenBucketRefillPerSecond
        bucket.tokens = min(BubbleConstants.tiktokRetryTokenBucketCapacity, bucket.tokens + refill)
        bucket.lastRefillAt = now

        if bucket.tokens < 1.0 {
            tokenBucketsByHost[key] = bucket
            log.log("POLICY_TOKEN_BUCKET_DROP transport=\(transport) host=\(host.lowercased()) port=\(port) bucket=\(decision.classification.bucket.rawValue) reason=\(decision.reason)")
            return true
        }

        bucket.tokens -= 1.0
        tokenBucketsByHost[key] = bucket
        return false
    }

    private func isTikTokRetryStormActive(now: Date = Date()) -> Bool {
        recentTikTokBlockEvents = recentTikTokBlockEvents.filter { now.timeIntervalSince($0) <= 15 }
        return recentTikTokBlockEvents.count >= 8
    }

    private func recentBadLenHardFailCount(now: Date = Date()) -> Int {
        recentBadLenHardFailTimestamps = recentBadLenHardFailTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.badLenRateWindowSeconds
        }
        return recentBadLenHardFailTimestamps.count
    }

    private func badLenHardFailRate(now: Date = Date()) -> Double {
        let count = recentBadLenHardFailCount(now: now)
        let denom = max(1.0, BubbleConstants.badLenRateWindowSeconds)
        return Double(count) / denom
    }

    private func isStartupGraceActive(now: Date = Date()) -> Bool {
        stabilityFirstModeEnabled && now < protectionStartupGraceUntil
    }

    private func isRecoveryGraceActive(now: Date = Date()) -> Bool {
        stabilityFirstModeEnabled && now < recoveryGraceUntil
    }

    private func hasAnyProtectionGrace(now: Date = Date()) -> Bool {
        isStartupGraceActive(now: now) || isRecoveryGraceActive(now: now)
    }

    private func currentTransportPressurePhase(now: Date = Date()) -> TransportPressurePhase {
        if degradedState == .tripped {
            return .critical
        }
        if degradedState == .degraded || degradedState == .recovering {
            return .degraded
        }
        return .normal
    }

    private func effectiveDegradedEnterQueueDepth() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.degradedEnterQueueDepth + 8 : BubbleConstants.degradedEnterQueueDepth
    }

    private func effectiveTrippedEnterQueueDepth() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.trippedEnterQueueDepth + 8 : BubbleConstants.trippedEnterQueueDepth
    }

    private func effectiveDegradedTimeoutRateEnter() -> Double {
        stabilityFirstModeEnabled ? 0.65 : BubbleConstants.degradedTimeoutRateEnter
    }

    private func effectiveTrippedEnterTimeoutRate() -> Double {
        stabilityFirstModeEnabled ? 0.80 : BubbleConstants.trippedEnterTimeoutRate
    }

    private func effectiveTrippedEnterMinDegradedSeconds() -> TimeInterval {
        stabilityFirstModeEnabled ? max(BubbleConstants.trippedCriticalDwellSeconds, BubbleConstants.trippedEnterMinDegradedSeconds * 2.0) : BubbleConstants.trippedEnterMinDegradedSeconds
    }

    private func effectiveDecodeFailureCloseThreshold() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.udpDecodeFailureCloseThreshold + 2 : BubbleConstants.udpDecodeFailureCloseThreshold
    }

    private func effectiveBadLenSoftFailureLimit() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.udpDecodeBadLenSoftFailureLimit + 4 : BubbleConstants.udpDecodeBadLenSoftFailureLimit
    }

    private func effectiveRecoveredDecoderCloseDensity() -> Double {
        stabilityFirstModeEnabled ? 7.0 : 4.0
    }

    private func effectiveDecoderCloseDensity() -> Double {
        stabilityFirstModeEnabled ? 8.0 : 5.0
    }

    private func effectiveTimeoutStreakCloseThreshold(base: Int) -> Int {
        stabilityFirstModeEnabled ? base + 2 : base
    }

    private func effectiveMaxLifetime(base: TimeInterval) -> TimeInterval {
        stabilityFirstModeEnabled ? base * 1.5 : base
    }

    private func effectiveIdleTimeout(base: TimeInterval) -> TimeInterval {
        stabilityFirstModeEnabled ? base * 2.0 : base
    }

    private func shouldCloseStreamForTimeout(state: UDPStreamState, now: Date) -> Bool {
        if hasAnyProtectionGrace(now: now) {
            return false
        }
        guard stabilityFirstModeEnabled else { return true }
        let lifetimeOK = now.timeIntervalSince(state.createdAt) >= BubbleConstants.selectiveReclaimMinLifetimeSeconds
        let idleOK = now.timeIntervalSince(state.lastActivityAt) >= BubbleConstants.selectiveReclaimMinIdleSeconds
        let noRecentSuccess = state.lastSuccessfulResponseAt.map { now.timeIntervalSince($0) > 2.0 } ?? true
        return lifetimeOK && idleOK && noRecentSuccess
    }

    private func shouldSkipIdleReclaimDueToRecentSuccess(state: UDPStreamState, now: Date) -> Bool {
        guard stabilityFirstModeEnabled else { return false }
        if let recent = state.lastSuccessfulResponseAt, now.timeIntervalSince(recent) <= 3.0 {
            return true
        }
        return false
    }

    private func shouldAllowReclaim(reason: String, now: Date) -> Bool {
        if let until = reclaimCooldownUntilByReason[reason], now < until {
            return false
        }
        reclaimCooldownUntilByReason[reason] = now.addingTimeInterval(BubbleConstants.reclaimReasonCooldownSeconds)
        return true
    }

    private func pruneSuppressionState(now: Date) {
        let maxWindow = max(blockSuppressionCooldown, BubbleConstants.aggressiveBlockSuppressionStormCooldown)
        blockedSuppression = blockedSuppression.filter { now.timeIntervalSince($0.value.lastSeen) <= (maxWindow * 4.0) }
    }

    private func pruneHostCooldowns(now: Date = Date()) {
        hostCooldownUntilByKey = hostCooldownUntilByKey.filter { now < $0.value }
    }

    private func reconnectBreakerCooldownRemainingSec(now: Date = Date()) -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let until = defaults?.double(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey) ?? 0
        guard until > now.timeIntervalSince1970 else { return 0 }
        return Int(ceil(until - now.timeIntervalSince1970))
    }

    private func reconnectBreakerTrips() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey) ?? 0
    }

    private func reconnectSuppressedByBreakerCount() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectSuppressedByBreakerKey) ?? 0
    }

    private func reconnectBreakerBackoffStep() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey) ?? 0
    }

    private func recordDecoderError(_ error: UDPControlDecoderError, hardFailure: Bool) {
        switch error {
        case .badPrefix:
            udpDecodeBadPrefix += 1
        case .badLength:
            udpDecodeBadLength += 1
            if hardFailure {
                udpDecodeBadLengthHardFail += 1
                recentBadLenHardFailTimestamps.append(Date())
            }
        }
    }

    private struct ResolverHealth {
        var timeoutStreak = 0
        var failoverScore = 0
        var lastSuccessfulResponseAt: Date?
        var lastSuccessAt = Date.distantPast
    }

    private struct TokenBucketState {
        var tokens: Double
        var lastRefillAt: Date
    }

    private enum TransportDegradedState: String {
        case healthy
        case degraded
        case tripped
        case recovering
    }

    private enum TransportPressurePhase: String {
        case normal
        case degraded
        case critical
    }

    static func shouldTripFromSevereSignals(
        severeSaturation: Bool,
        severeTimeoutStorm: Bool,
        severeBadLenStorm: Bool,
        severeReclaims: Bool
    ) -> Bool {
        let severeDecodeAndNetwork = severeBadLenStorm && (severeTimeoutStorm || severeSaturation)
        let severeReclaimAndStress = severeReclaims && (severeTimeoutStorm || severeSaturation || severeBadLenStorm)
        return severeDecodeAndNetwork || severeReclaimAndStress
    }

    static func shouldInferCrashFromLifecycle(stopSource: String, runningMarker: Bool, heartbeatAgeSeconds: TimeInterval, staleThresholdSeconds: TimeInterval) -> Bool {
        if stopSource == "stopTunnel" || stopSource == "tun2socks_exit" || stopSource == "cancelTunnelWithError" || stopSource == "inferred_crash" {
            return false
        }
        return runningMarker && heartbeatAgeSeconds >= staleThresholdSeconds
    }

    static func effectiveActiveLimit(baseLimit: Int, reservedSlots: Int, stormMode: Bool) -> Int {
        guard stormMode else { return baseLimit }
        return max(1, baseLimit - reservedSlots)
    }

    static func shouldForceGlobalUDPReject(active: Int, queued: Int, maxActive: Int, maxQueued: Int) -> Bool {
        active >= maxActive && queued >= maxQueued
    }

    private func queuedUDPControlP95AgeMs(now: Date = Date()) -> Int {
        guard !pendingUDPControlQueue.isEmpty else { return 0 }
        let ages = pendingUDPControlQueue
            .map { max(0, now.timeIntervalSince($0.enqueuedAt) * 1000.0) }
            .sorted()
        let idx = min(ages.count - 1, Int(Double(ages.count - 1) * 0.95))
        return Int(ages[idx])
    }

    private func udpSocketReuseHitRate() -> Double {
        let total = udpSocketReuseHits + udpSocketReuseMisses
        guard total > 0 else { return 0 }
        return Double(udpSocketReuseHits) / Double(total)
    }

    private struct PendingUDPControl {
        let client: NWConnection
        let id: Int
        let enqueuedAt: Date
    }

    private final class UDPAdmissionController {
        private var rejectUntil = Date.distantPast
        private var createTokens = Double(BubbleConstants.udpAdmissionCreateRateCapacity)
        private var lastRefillAt = Date.distantPast

        func decide(
            active: Int,
            queued: Int,
            stormMode: Bool,
            maxActive: Int,
            pressurePhase: TransportPressurePhase,
            preferQueueing: Bool,
            graceActive: Bool,
            now: Date
        ) -> UDPAdmissionDecision {
            refillTokens(now: now, stormMode: stormMode)
            if now < rejectUntil {
                return .reject(reason: "cooldown")
            }
            if createTokens < 1 {
                if preferQueueing && queued < BubbleConstants.maxQueuedUDPControlStreams {
                    return .queue
                }
                return .reject(reason: "rate_limited")
            }
            if active >= maxActive && queued >= BubbleConstants.maxQueuedUDPControlStreams {
                if graceActive || preferQueueing {
                    return .queue
                }
                rejectUntil = now.addingTimeInterval(1.5)
                return .reject(reason: "hard_saturation")
            }
            if active >= maxActive {
                return .queue
            }
            if pressurePhase == .critical && queued >= BubbleConstants.maxQueuedUDPControlStreams {
                return .reject(reason: "critical_backpressure")
            }
            if pressurePhase == .degraded && queued >= (BubbleConstants.maxQueuedUDPControlStreams - 1) {
                return .queue
            }
            if queued > (BubbleConstants.maxQueuedUDPControlStreams / 2) && active >= (maxActive - 1) {
                if preferQueueing {
                    return .queue
                }
                return .reject(reason: "preemptive_backpressure")
            }
            createTokens -= 1
            return .accept
        }

        private func refillTokens(now: Date, stormMode: Bool) {
            if lastRefillAt == .distantPast {
                lastRefillAt = now
                return
            }
            let elapsed = max(0, now.timeIntervalSince(lastRefillAt))
            let refillRate = stormMode ? (BubbleConstants.udpAdmissionCreateRatePerSecond * 0.4) : BubbleConstants.udpAdmissionCreateRatePerSecond
            let refill = elapsed * refillRate
            createTokens = min(Double(BubbleConstants.udpAdmissionCreateRateCapacity), createTokens + refill)
            lastRefillAt = now
        }
    }

    private struct InflightDNSRequest {
        let startedAt: Date
        var callbacks: [(Data?) -> Void]
    }

    private func dnsDedupKey(host: String, port: UInt16, payload: Data) -> String? {
        guard port == 53 else { return nil }
        return "\(host):\(port):\(payload.hashValue)"
    }

    private func effectiveResolverHost(originalHost: String, port: UInt16) -> String {
        guard port == 53, originalHost == "8.8.8.8" || originalHost == "1.1.1.1" else {
            return originalHost
        }
        let googleScore = resolverHealth["8.8.8.8"]?.failoverScore ?? 0
        let cloudflareScore = resolverHealth["1.1.1.1"]?.failoverScore ?? 0
        if googleScore >= BubbleConstants.dnsFailoverScoreThreshold, cloudflareScore < googleScore {
            return "1.1.1.1"
        }
        if cloudflareScore >= BubbleConstants.dnsFailoverScoreThreshold, googleScore < cloudflareScore {
            return "8.8.8.8"
        }
        let preferred = preferredResolverHost()
        return preferred ?? originalHost
    }

    private func preferredResolverHost() -> String? {
        let google = resolverHealth["8.8.8.8"] ?? ResolverHealth()
        let cloudflare = resolverHealth["1.1.1.1"] ?? ResolverHealth()
        let now = Date()
        let selected: String
        if google.failoverScore >= BubbleConstants.dnsFailoverScoreThreshold, cloudflare.failoverScore < google.failoverScore {
            selected = "1.1.1.1"
        } else if cloudflare.failoverScore >= BubbleConstants.dnsFailoverScoreThreshold, google.failoverScore < cloudflare.failoverScore {
            selected = "8.8.8.8"
        } else {
            selected = google.lastSuccessAt >= cloudflare.lastSuccessAt ? "8.8.8.8" : "1.1.1.1"
        }
        let isReturnToPreviousHealthy = selected != currentPreferredResolver &&
            (resolverHealth[selected]?.failoverScore ?? 0) == 0
        let minSwitchDelay = isReturnToPreviousHealthy
            ? max(BubbleConstants.resolverSwitchCooldown, BubbleConstants.dnsFailoverReturnDelaySeconds)
            : BubbleConstants.resolverSwitchCooldown
        if selected != currentPreferredResolver, now.timeIntervalSince(lastResolverSwitchAt) >= minSwitchDelay {
            currentPreferredResolver = selected
            lastResolverSwitchAt = now
            resolverSwitchCount += 1
        }
        return currentPreferredResolver
    }

    private func markResolverSuccess(host: String, port: UInt16) {
        guard port == 53 else { return }
        var health = resolverHealth[host] ?? ResolverHealth()
        health.timeoutStreak = 0
        health.failoverScore = max(0, health.failoverScore - BubbleConstants.dnsFailoverScoreDecayPerSuccess)
        health.lastSuccessAt = Date()
        resolverHealth[host] = health
    }

    private func markResolverTimeout(host: String, port: UInt16) {
        guard port == 53 else { return }
        var health = resolverHealth[host] ?? ResolverHealth()
        health.timeoutStreak += 1
        health.failoverScore += 1
        resolverHealth[host] = health
        if host == currentPreferredResolver {
            let fallback = host == "8.8.8.8" ? "1.1.1.1" : "8.8.8.8"
            currentPreferredResolver = fallback
            lastResolverSwitchAt = Date()
            resolverSwitchCount += 1
        }
    }

    private func isDNSResolverStormActive() -> Bool {
        let googleScore = resolverHealth["8.8.8.8"]?.failoverScore ?? 0
        let cloudflareScore = resolverHealth["1.1.1.1"]?.failoverScore ?? 0
        return googleScore >= BubbleConstants.dnsFailoverScoreThreshold &&
            cloudflareScore >= BubbleConstants.dnsFailoverScoreThreshold
    }

    // MARK: - Target Connection (TCP)

    private func connectToTarget(client: NWConnection, host: String, port: UInt16, id: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            self.log.log("SOCKS5 #\(id): invalid port \(port)")
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            self.sendSocksError(client: client, reply: 0x05)
            return
        }

        let target = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        // Track bytes for diagnostic logging
        let tracker = RelayTracker(id: id, host: host, port: port)
        activeRelays[id] = tracker

        // TCP relay timeout — cancel both sides if idle too long
        let timeout = DispatchWorkItem { [weak self] in
            self?.log.log("SOCKS5 #\(id): relay timeout to \(host):\(port)")
            self?.logRelayEnd(tracker: tracker, reason: "timeout")
            client.cancel()
            target.cancel()
        }
        queue.asyncAfter(deadline: .now() + BubbleConstants.tcpRelayTimeout, execute: timeout)

        target.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let reply = self.buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
                client.send(content: reply, completion: .contentProcessed { error in
                    if error != nil {
                        timeout.cancel()
                        self.logRelayEnd(tracker: tracker, reason: "send-error")
                        client.cancel()
                        target.cancel()
                        return
                    }
                    self.relay(from: client, to: target, tracker: tracker, direction: .upload)
                    self.relay(from: target, to: client, tracker: tracker, direction: .download)
                })

            case .failed(let error):
                timeout.cancel()
                self.log.log("SOCKS5 #\(id): target failed \(host):\(port) — \(error)")
                self.statsErrors += 1
                self.recordEvent(type: .error, connId: id, host: host, port: port, detail: "Target connection failed: \(error.localizedDescription)")
                self.logRelayEnd(tracker: tracker, reason: "target-failed")
                self.sendSocksError(client: client, reply: 0x05)
                target.cancel()

            case .cancelled:
                timeout.cancel()
                self.logRelayEnd(tracker: tracker, reason: "cancelled")
                client.cancel()

            default:
                break
            }
        }

        target.start(queue: queue)
    }

    // MARK: - Relay Byte Tracking

    private enum RelayDirection {
        case upload
        case download
    }

    private class RelayTracker {
        let id: Int
        let host: String
        let port: UInt16
        let startTime = Date()
        var bytesUp: Int = 0
        var bytesDown: Int = 0
        var logged = false
        var sni: String?
        var sniProbeAttempts = 0
        var loggedUntracked = false

        init(id: Int, host: String, port: UInt16) {
            self.id = id
            self.host = host
            self.port = port
        }
    }

    private final class UDPStreamState {
        let id: Int
        let decoder: UDPControlStreamDecoder
        let client: NWConnection
        let createdAt = Date()
        var lastActivityAt = Date()
        var timeoutStreak = 0
        var hardeningEnabled = false
        var hardeningBucket: ContentBucket?
        var lastHost: String?
        var lastPort: UInt16?
        var mode: UDPControlFramingMode?
        var pendingFrames: [UDPControlFrame] = []
        var processingFrame = false
        var processingStartedAt: Date?
        var closed = false
        var lastProgressAt = Date()
        var lastSuccessfulResponseAt: Date?
        var decoderFailureCount = 0
        var decoderRecoveryCount = 0
        var firstDecoderFailureAt: Date?
        private var decoderFailureTimestamps: [Date] = []
        private var decoderErrorDensity = 0.0
        private var lastDecoderDensityAt = Date()

        init(id: Int, client: NWConnection, decoder: UDPControlStreamDecoder) {
            self.id = id
            self.client = client
            self.decoder = decoder
        }

        func decoderFailuresInWindow(now: Date, window: TimeInterval) -> Int {
            decoderFailureTimestamps = decoderFailureTimestamps.filter { now.timeIntervalSince($0) <= window }
            decoderFailureTimestamps.append(now)
            return decoderFailureTimestamps.count
        }

        func markProgress(now: Date) {
            let elapsed = max(0, now.timeIntervalSince(lastDecoderDensityAt))
            decoderErrorDensity = max(0, decoderErrorDensity - (elapsed * 0.7))
            lastDecoderDensityAt = now
            lastProgressAt = now
            lastSuccessfulResponseAt = now
        }

        func bumpDecoderErrorDensity(now: Date) -> Double {
            let elapsed = max(0, now.timeIntervalSince(lastDecoderDensityAt))
            decoderErrorDensity = max(0, decoderErrorDensity - (elapsed * 0.5))
            decoderErrorDensity += 1.0
            lastDecoderDensityAt = now
            return decoderErrorDensity
        }
    }

    private func logRelayEnd(tracker: RelayTracker, reason: String) {
        guard !tracker.logged else { return }
        tracker.logged = true
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        let duration = String(format: "%.1f", Date().timeIntervalSince(tracker.startTime))
        let totalBytes = tracker.bytesUp + tracker.bytesDown
        let sniStr = tracker.sni ?? "n/a"
        log.logConnection("RELAY #\(tracker.id): \(tracker.host):\(tracker.port) SNI=\(sniStr) — \(reason) — \(duration)s — up:\(tracker.bytesUp)B down:\(tracker.bytesDown)B total:\(totalBytes)B (active:\(activeConnectionCount))")

        // Record completed event (unless already recorded as stream-blocked or error)
        if reason != "stream-blocked" && reason != "target-failed" {
            recordEvent(type: .completed, connId: tracker.id, host: tracker.host, port: tracker.port, sni: tracker.sni, detail: "\(reason) — \(duration)s — \(totalBytes)B", bytesDown: tracker.bytesDown)
        }

        // Update domain stats
        let domain = tracker.sni ?? tracker.host
        let current = domainStats[domain] ?? (count: 0, bytes: 0)
        domainStats[domain] = (count: current.count + 1, bytes: current.bytes + totalBytes)

        // Remove from active relays after 5s (so dashboard sees the final state briefly)
        let relayId = tracker.id
        queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.activeRelays.removeValue(forKey: relayId)
        }
    }

    // MARK: - TLS SNI Parser

    /// Extracts the SNI (Server Name Indication) from a TLS ClientHello message.
    /// The ClientHello is the first thing the client sends on a TLS connection,
    /// and the SNI extension contains the plaintext domain name.
    private func extractSNI(from data: Data) -> String? {
        let bytes = [UInt8](data)
        // TLS record: [ContentType(1)][Version(2)][Length(2)][Handshake...]
        guard bytes.count >= 5,
              bytes[0] == 0x16,         // ContentType: Handshake
              bytes[1] == 0x03          // TLS major version 3.x
        else { return nil }

        let recordLen = (Int(bytes[3]) << 8) | Int(bytes[4])
        guard bytes.count >= 5 + recordLen else { return nil }

        // Handshake: [Type(1)][Length(3)][ClientHello...]
        let hsStart = 5
        guard bytes.count > hsStart,
              bytes[hsStart] == 0x01    // HandshakeType: ClientHello
        else { return nil }

        // ClientHello body starts at hsStart + 4
        let chStart = hsStart + 4
        // ClientHello: [Version(2)][Random(32)][SessionIDLen(1)][SessionID...]
        guard bytes.count >= chStart + 2 + 32 + 1 else { return nil }

        var offset = chStart + 2 + 32 // skip version + random

        // Session ID
        let sessionIDLen = Int(bytes[offset])
        offset += 1 + sessionIDLen

        // Cipher suites: [Length(2)][...]
        guard bytes.count >= offset + 2 else { return nil }
        let cipherLen = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2 + cipherLen

        // Compression methods: [Length(1)][...]
        guard bytes.count >= offset + 1 else { return nil }
        let compLen = Int(bytes[offset])
        offset += 1 + compLen

        // Extensions: [TotalLength(2)][Extension...]
        guard bytes.count >= offset + 2 else { return nil }
        let extTotalLen = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
        offset += 2

        let extEnd = min(offset + extTotalLen, bytes.count)

        // Walk extensions looking for SNI (type 0x0000)
        while offset + 4 <= extEnd {
            let extType = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            let extLen = (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
            offset += 4

            if extType == 0x0000 { // SNI extension
                // SNI extension data: [ListLength(2)][Type(1)][NameLength(2)][Name...]
                guard offset + 5 <= extEnd else { return nil }
                // skip list length (2 bytes)
                let nameType = bytes[offset + 2]
                guard nameType == 0x00 else { return nil } // host_name type
                let nameLen = (Int(bytes[offset + 3]) << 8) | Int(bytes[offset + 4])
                let nameStart = offset + 5
                guard nameStart + nameLen <= bytes.count else { return nil }
                return String(bytes: Array(bytes[nameStart..<(nameStart + nameLen)]), encoding: .utf8)
            }

            offset += extLen
        }

        return nil
    }

    // MARK: - Bidirectional Relay

    private func relay(from source: NWConnection, to destination: NWConnection, tracker: RelayTracker, direction: RelayDirection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: BubbleConstants.relayBufferSize) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                switch direction {
                case .upload:
                    tracker.bytesUp += data.count
                    // Extract SNI from early upload packets (ClientHello can be fragmented).
                    if tracker.sni == nil && tracker.sniProbeAttempts < BubbleConstants.maxSNIProbePackets {
                        tracker.sniProbeAttempts += 1
                        if let sni = self.extractSNI(from: data) {
                            tracker.sni = sni
                            self.log.logConnection("TCP #\(tracker.id): SNI=\(sni) IP=\(tracker.host):\(tracker.port)")
                            TunnelLogger.connectionLog.log("[SNI] \(sni, privacy: .public)")
                        }
                    }
                case .download:
                    let projectedBytesDown = tracker.bytesDown + data.count

                    let streamDecision = self.filter.evaluateStream(
                        host: tracker.host,
                        sni: tracker.sni,
                        port: tracker.port,
                        bytesDown: projectedBytesDown,
                        connectionAge: Date().timeIntervalSince(tracker.startTime),
                        parallelConnections: self.activeRelays.count
                    )

                    let threshold = streamDecision.blockAfterBytes
                    let shouldBlockNow = streamDecision.action == .blockNow
                    let shouldBlockAfter = streamDecision.action == .blockAfterBytes && threshold != nil && projectedBytesDown > threshold!
                    if shouldBlockNow || shouldBlockAfter {
                        let gate = self.evaluateProtectionGate(
                            host: tracker.sni ?? tracker.host,
                            port: tracker.port,
                            decision: streamDecision,
                            transport: "tcp_stream",
                            stage: .streamBlock
                        )
                        if gate == .dropFast || gate == .suppress {
                            if gate == .dropFast {
                                self.streamBlockTokenDrops += 1
                            } else {
                                self.streamBlockSuppressed += 1
                            }
                            self.blockedSuppressedTCP += 1
                            self.logRelayEnd(tracker: tracker, reason: "stream-blocked-suppressed")
                            source.cancel()
                            destination.cancel()
                            return
                        }
                        tracker.bytesDown = projectedBytesDown
                        self.statsBlocked += 1
                        let thresholdLabel = threshold.map { "\($0)B" } ?? "n/a"
                        self.log.log("STREAM BLOCK #\(tracker.id): killed \((tracker.sni ?? tracker.host)) at \(tracker.bytesDown)B (threshold: \(thresholdLabel))")
                        self.recordEvent(
                            type: .streamBlocked,
                            connId: tracker.id,
                            host: tracker.host,
                            port: tracker.port,
                            sni: tracker.sni,
                            detail: "Killed at \(tracker.bytesDown)B",
                            bytesDown: tracker.bytesDown,
                            decision: streamDecision
                        )
                        self.logRelayEnd(tracker: tracker, reason: "stream-blocked")
                        source.cancel()
                        destination.cancel()
                        return
                    }

                    tracker.bytesDown = projectedBytesDown
                    if streamDecision.action == .allow && tracker.bytesDown > 100_000 && !tracker.loggedUntracked {
                        tracker.loggedUntracked = true
                        TunnelLogger.connectionLog.log("[UNTRACKED-LARGE] \((tracker.sni ?? tracker.host), privacy: .public) \(tracker.bytesDown, privacy: .public)B+ (no blocking rule)")
                    }
                }
                destination.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        self.logRelayEnd(tracker: tracker, reason: "relay-error")
                        source.cancel()
                        destination.cancel()
                        return
                    }
                    if isComplete {
                        self.logRelayEnd(tracker: tracker, reason: "complete")
                        source.cancel()
                        destination.cancel()
                    } else {
                        self.relay(from: source, to: destination, tracker: tracker, direction: direction)
                    }
                })
            } else if isComplete || error != nil {
                self.logRelayEnd(tracker: tracker, reason: isComplete ? "complete" : "error")
                source.cancel()
                destination.cancel()
            }
        }
    }

    // MARK: - SOCKS5 Reply Helpers

    private func sendSocksError(client: NWConnection, reply: UInt8) {
        let data = buildSocksReply(reply: reply, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
        client.send(content: data, completion: .contentProcessed { _ in
            client.cancel()
        })
    }

    private static func memoryUsageMB() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return String(format: "%.1f", Double(info.resident_size) / 1_048_576)
        }
        return "?"
    }

    private func buildSocksReply(reply: UInt8, atyp: UInt8, addr: [UInt8], port: UInt16) -> Data {
        var response: [UInt8] = [
            0x05,   // VER
            reply,  // REP
            0x00,   // RSV
            atyp    // ATYP
        ]
        response.append(contentsOf: addr)
        response.append(UInt8(port >> 8))
        response.append(UInt8(port & 0xFF))
        return Data(response)
    }

}
