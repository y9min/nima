import Foundation
import Network
import os

// MARK: - Connection Filter Protocol

protocol ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision
    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision
    func evaluateEarlyTLS(host: String, sni: String, port: UInt16) -> PolicyDecision
    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision
    func healthMetrics() -> FilterHealthMetrics
    func runtimePolicy() -> RuntimePolicyTuning
}

enum UDPDecodeMode: String, Codable {
    case strict
    case adaptive
    case off
}

enum QUICHandlingMode: String, Codable {
    case classifyOnly = "classify_only"
    case blockMetaReelsOnly = "block_meta_reels_only"
}

enum MetaIPGuardMode: String, Codable {
    case fallbackOnly = "fallback_only"
}

struct RuntimePolicyTuning {
    let udpDecodeMode: UDPDecodeMode
    let udpCircuitBreakerThreshold: Int
    let udpCircuitBreakerWindowSec: Int
    let udpCircuitBreakerCooldownSec: Int
    let quicHandling: QUICHandlingMode
    let metaIPGuardMode: MetaIPGuardMode
    let thermalGuardEnabled: Bool
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
    private var attemptedByBucket: [String: Int] = [:]
    private var blockedByBucket: [String: Int] = [:]
    private var possibleFalsePositiveRetries = 0
    private var recentBlockedByHost: [String: Date] = [:]
    private var retryStormEvents = 0
    private var backoffActiveHosts = 0
    private var udpDecodeStrictDropCount = 0
    private var udpDecodeStrictDropDebouncedReopens = 0
    private var udpStreamReopenDebounceUntilByPeer: [String: Date] = [:]
    private var udpDecodeBypassedFrames = 0
    private var udpCircuitOpenPeers = 0
    private var decisionDedupHits = 0
    private var policyEvalMicrosSamples: [Double] = []
    private var policyEvalMicrosP95: Double = 0
    private var blockedReelsAttempts = 0
    private var totalReelsAttempts = 0
    private var playbackBlockRateEstimate = 0.0
    private var udpDecodeErrHighIntervals = 0
    private var udpDecodeErrLowIntervals = 0
    private var thermalForcedAdaptive = false
    private var effectiveUDPDecodeMode: UDPDecodeMode = .adaptive
    private var udpPeerStateByPeer: [String: UDPPeerState] = [:]
    private var decisionDedupUntilByPeer: [String: Date] = [:]
    private var udpDecoderLogLastByReason: [String: Date] = [:]
    private var udpDecoderLogSuppressedByReason: [String: Int] = [:]
    private let udpDecoderLogInterval: TimeInterval = 2.0
    private var statsTimer: DispatchSourceTimer?
    private var lastStatsSampleDate: Date?
    private var lastStatsTotalConnections = 0
    private var lastStatsBlocked = 0
    private var lastStatsUDPDecodeErrors = 0
    private var lastStatsHotPathLoggedAt: Date = .distantPast
    private var latestConnRatePerSec: Double = 0
    private var latestBlockRatePerSec: Double = 0
    private var latestUDPDecodeErrorRatePerSec: Double = 0
    private var latestMemMB: Double = 0

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

    init(filter: ConnectionFilter) {
        self.filter = filter
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
    }

    func stop() {
        queue.sync {
            statsTimer?.cancel()
            statsTimer = nil
            snapshotTimer?.cancel()
            snapshotTimer = nil
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
            let now = Date()
            let interval = max(now.timeIntervalSince(self.lastStatsSampleDate ?? now), 1.0)
            let currentUDPDecodeErrors = self.udpDecodeBadPrefix + self.udpDecodeBadLength + self.udpDecodeBadPayload
            let connDelta = max(0, total - self.lastStatsTotalConnections)
            let blockedDelta = max(0, self.statsBlocked - self.lastStatsBlocked)
            let udpDecodeDelta = max(0, currentUDPDecodeErrors - self.lastStatsUDPDecodeErrors)

            self.latestConnRatePerSec = Double(connDelta) / interval
            self.latestBlockRatePerSec = Double(blockedDelta) / interval
            self.latestUDPDecodeErrorRatePerSec = Double(udpDecodeDelta) / interval
            self.latestMemMB = Self.memoryUsageMBValue()
            let memMB = String(format: "%.1f", self.latestMemMB)
            let filterHealth = self.filter.healthMetrics()
            let runtime = self.filter.runtimePolicy()
            self.retryStormEvents = filterHealth.retryStormEvents
            self.backoffActiveHosts = filterHealth.backoffActiveHosts
            self.effectiveUDPDecodeMode = runtime.udpDecodeMode

            if runtime.thermalGuardEnabled {
                if self.latestUDPDecodeErrorRatePerSec > 1.0 {
                    self.udpDecodeErrHighIntervals += 1
                    self.udpDecodeErrLowIntervals = 0
                } else if self.latestUDPDecodeErrorRatePerSec < 0.2 {
                    self.udpDecodeErrLowIntervals += 1
                    self.udpDecodeErrHighIntervals = 0
                } else {
                    self.udpDecodeErrHighIntervals = 0
                    self.udpDecodeErrLowIntervals = 0
                }

                if self.udpDecodeErrHighIntervals >= 3, runtime.udpDecodeMode == .strict {
                    self.thermalForcedAdaptive = true
                    self.effectiveUDPDecodeMode = .adaptive
                } else if self.thermalForcedAdaptive, self.udpDecodeErrLowIntervals >= 5 {
                    self.thermalForcedAdaptive = false
                    self.effectiveUDPDecodeMode = runtime.udpDecodeMode
                } else if self.thermalForcedAdaptive {
                    self.effectiveUDPDecodeMode = .adaptive
                }
            } else {
                self.thermalForcedAdaptive = false
                self.udpDecodeErrHighIntervals = 0
                self.udpDecodeErrLowIntervals = 0
            }

            self.cleanupUDPPeerCircuitState(now: now)
            self.udpCircuitOpenPeers = self.udpPeerStateByPeer.values.filter { state in
                guard let until = state.opaqueUntil else { return false }
                return until > now
            }.count

            self.log.log(
                "SOCKS5 STATS: \(total) total, \(self.activeConnectionCount) active, \(self.activeRelays.count) relays, " +
                "\(self.statsAllowed) allowed, \(self.statsBlocked) blocked, \(self.statsUDP) UDP, \(self.statsErrors) errors, " +
                "udpActive=\(self.activeUDPStreams), udpOpened=\(self.totalUDPStreamsOpened), udpClosed=\(self.totalUDPStreamsClosed), " +
                "snapshots=\(self.snapshotHistory.count), mem=\(memMB)MB, connRate=\(String(format: "%.2f", self.latestConnRatePerSec))/s, " +
                "blockRate=\(String(format: "%.2f", self.latestBlockRatePerSec))/s, udpDecodeErrRate=\(String(format: "%.2f", self.latestUDPDecodeErrorRatePerSec))/s"
            )
            self.log.log(
                "SOCKS5 MITIGATION: backoffHosts=\(self.backoffActiveHosts), retryStormEvents=\(self.retryStormEvents), " +
                "udpStrictDrops=\(self.udpDecodeStrictDropCount), udpStrictDropDebouncedReopens=\(self.udpDecodeStrictDropDebouncedReopens), " +
                "udpMode=\(self.effectiveUDPDecodeMode.rawValue), circuitPeers=\(self.udpCircuitOpenPeers), bypassed=\(self.udpDecodeBypassedFrames)"
            )

            self.logHotPathIfNeeded(now: now)
            self.lastStatsSampleDate = now
            self.lastStatsTotalConnections = total
            self.lastStatsBlocked = self.statsBlocked
            self.lastStatsUDPDecodeErrors = currentUDPDecodeErrors
        }
        timer.resume()
        statsTimer = timer
    }

    private func logHotPathIfNeeded(now: Date) {
        let highConnRate = latestConnRatePerSec >= 15
        let highBlockRate = latestBlockRatePerSec >= 10
        let highUDPDecodeRate = latestUDPDecodeErrorRatePerSec >= 3

        guard highConnRate || highBlockRate || highUDPDecodeRate else { return }
        guard now.timeIntervalSince(lastStatsHotPathLoggedAt) >= 10 else { return }

        let connLabel = highConnRate ? "high_conn_churn" : "normal_conn_churn"
        let blockLabel = highBlockRate ? "high_block_churn" : "normal_block_churn"
        let udpLabel = highUDPDecodeRate ? "high_udp_decode" : "normal_udp_decode"

        log.log(
            "SOCKS5 HOT PATH: \(connLabel), \(blockLabel), \(udpLabel), " +
            "connRate=\(String(format: "%.2f", latestConnRatePerSec))/s, " +
            "blockRate=\(String(format: "%.2f", latestBlockRatePerSec))/s, " +
            "udpDecodeErrRate=\(String(format: "%.2f", latestUDPDecodeErrorRatePerSec))/s, " +
            "active=\(activeConnectionCount), relays=\(activeRelays.count), mem=\(String(format: "%.1f", latestMemMB))MB"
        )
        lastStatsHotPathLoggedAt = now
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
            attemptedByBucket: attemptedByBucket,
            blockedByBucket: blockedByBucket,
            possibleFalsePositiveRetries: possibleFalsePositiveRetries,
            healthState: currentHealthState(),
            retryStormEvents: retryStormEvents,
            backoffActiveHosts: backoffActiveHosts,
            udpDecodeStrictDropCount: udpDecodeStrictDropCount,
            udpDecodeStrictDropDebouncedReopens: udpDecodeStrictDropDebouncedReopens,
            udpCircuitOpenPeers: udpCircuitOpenPeers,
            udpDecodeBypassedFrames: udpDecodeBypassedFrames,
            decisionDedupHits: decisionDedupHits,
            policyEvalMicrosP95: policyEvalMicrosP95,
            playbackBlockRateEstimate: playbackBlockRateEstimate,
            connRatePerSec: latestConnRatePerSec,
            blockRatePerSec: latestBlockRatePerSec,
            udpDecodeErrorRatePerSec: latestUDPDecodeErrorRatePerSec,
            memoryMB: latestMemMB
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
        let decision = self.evaluatePolicy(kind: "tcp_connect") {
            self.filter.evaluateConnection(host: host, port: port)
        }

        switch decision.action {
        case .blockNow:
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
        log.log("UDP #\(id): FWD_UDP accepted, starting frame relay")
        let peerKey = peerKey(for: client)
        if let blockedUntil = udpStreamReopenDebounceUntilByPeer[peerKey], blockedUntil > Date() {
            udpDecodeStrictDropDebouncedReopens += 1
            log.log("UDP #\(id): FWD_UDP debounced for peer=\(peerKey)")
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }

        let state = UDPStreamState(id: id, peerKey: peerKey, decoder: UDPControlStreamDecoder(maxFrameSize: BubbleConstants.maxUDPFrameSize))
        let now = Date()
        if effectiveUDPDecodeMode == .off || isUDPCircuitOpen(peerKey: peerKey, now: now) {
            state.opaqueMode = true
            if isUDPCircuitOpen(peerKey: peerKey, now: now) {
                maybeLogDecisionDedup(peerKey: peerKey, action: "opaque_mode_reuse")
            }
        }
        activeUDPStreams += 1
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
                if state.opaqueMode {
                    self.handleOpaqueUDPChunk(client: client, state: state, data: data)
                    return
                }
                switch state.decoder.append(data) {
                case .success(let frames):
                    if let mode = state.decoder.currentMode, state.mode == nil {
                        state.mode = mode
                        self.markValidatedMode(peerKey: state.peerKey, mode: mode)
                        if mode == .plain {
                            self.udpModePlain += 1
                        } else {
                            self.udpModeControlPrefixed += 1
                        }
                        self.log.log("UDP_DECODER stream=\(state.id) event=mode_locked mode=\(mode.rawValue)")
                    }

                    state.pendingFrames.append(contentsOf: frames)
                    self.processNextUDPFrame(client: client, state: state)

                case .failure(let decodeError):
                    self.recordDecoderError(decodeError)
                    self.udpDecodeStrictDropCount += 1
                    self.logUDPDecoderError(streamID: state.id, reason: self.decoderReasonCode(decodeError))
                    let decodeReason = "decode_\(self.decoderReasonCode(decodeError))"
                    if self.effectiveUDPDecodeMode == .strict {
                        let openedCircuit = self.shouldOpenUDPCircuit(peerKey: state.peerKey, now: Date())
                        if openedCircuit {
                            state.opaqueMode = true
                            self.udpDecodeBypassedFrames += 1
                            self.log.log("UDP_DECODER stream=\(state.id) event=strict_degrade_bypass reason=\(decodeReason)")
                            self.readUDPControlStream(client: client, state: state)
                        } else {
                            self.log.log("UDP_DECODER stream=\(state.id) event=strict_drop reason=\(decodeReason)")
                            self.closeUDPControlStream(client: client, state: state, reason: decodeReason)
                        }
                    } else {
                        let openedCircuit = self.shouldOpenUDPCircuit(peerKey: state.peerKey, now: Date())
                        if openedCircuit || self.effectiveUDPDecodeMode == .off {
                            state.opaqueMode = true
                            self.log.log("UDP_DECODER stream=\(state.id) event=udp_decode_bypass reason=\(decodeReason)")
                            self.readUDPControlStream(client: client, state: state)
                        } else {
                            self.log.log("UDP_DECODER stream=\(state.id) event=strict_drop reason=\(decodeReason)")
                            self.closeUDPControlStream(client: client, state: state, reason: decodeReason)
                        }
                    }
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

        guard let parsed = parseUDPPayload(decodedFrame.payload, streamID: state.id) else {
            udpDecodeBadPayload += 1
            udpDecodeStrictDropCount += 1
            logUDPDecoderError(streamID: state.id, reason: "bad_payload")
            log.log("UDP_DECODER stream=\(state.id) event=strict_drop reason=decode_bad_payload")
            state.processingFrame = false
            closeUDPControlStream(client: client, state: state, reason: "decode_bad_payload")
            return
        }

        statsUDP += 1
        log.log("UDP #\(state.id): dest=\(parsed.addr.host):\(parsed.addr.port), payload=\(parsed.payload.count)B")

        let decision = evaluatePolicy(kind: "udp") {
            filter.evaluateUDP(host: parsed.addr.host, port: parsed.addr.port, payloadBytes: parsed.payload.count)
        }
        if decision.action == .blockNow {
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
                client.send(content: responseFrame, completion: .contentProcessed { [weak self] _ in
                    self?.processNextUDPFrame(client: client, state: state)
                })
            } else {
                self.processNextUDPFrame(client: client, state: state)
            }
        }
    }

    private func handleOpaqueUDPChunk(client: NWConnection, state: UDPStreamState, data: Data) {
        guard !state.closed else { return }
        guard !state.processingFrame else { return }
        state.processingFrame = true
        defer { state.processingFrame = false }

        let bytes = [UInt8](data)
        guard let parsed = parseUDPPayload(bytes, streamID: state.id) else {
            udpDecodeBypassedFrames += 1
            maybeLogDecisionDedup(peerKey: state.peerKey, action: "drop_unparseable_opaque")
            readUDPControlStream(client: client, state: state)
            return
        }

        udpDecodeBypassedFrames += 1
        log.log("udp_decode_bypass stream=\(state.id) dest=\(parsed.addr.host):\(parsed.addr.port) payload=\(parsed.payload.count)B")
        let decision = evaluatePolicy(kind: "udp_opaque") {
            filter.evaluateUDP(host: parsed.addr.host, port: parsed.addr.port, payloadBytes: parsed.payload.count)
        }
        if decision.action == .blockNow {
            statsBlocked += 1
            recordEvent(type: .blocked, connId: state.id, host: parsed.addr.host, port: parsed.addr.port, detail: "UDP opaque blocked by policy", decision: decision)
            maybeLogDecisionDedup(peerKey: state.peerKey, action: "opaque_blocked")
            readUDPControlStream(client: client, state: state)
            return
        }

        relayUDPDatagram(
            streamID: state.id,
            host: parsed.addr.host,
            port: parsed.addr.port,
            payload: parsed.payload,
            headerBytes: parsed.headerBytes,
            responseMode: .plain
        ) { [weak self] responseFrame in
            guard let self = self, !state.closed else { return }
            if let responseFrame {
                client.send(content: responseFrame, completion: .contentProcessed { _ in
                    self.readUDPControlStream(client: client, state: state)
                })
            } else {
                self.readUDPControlStream(client: client, state: state)
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
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log.log("UDP #\(streamID): invalid port \(port)")
            statsErrors += 1
            completion(nil)
            return
        }

        let udp = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)

        var completed = false
        let complete: (Data?) -> Void = { [weak self] responseFrame in
            self?.queue.async {
                guard !completed else { return }
                completed = true
                udp.cancel()
                completion(responseFrame)
            }
        }

        queue.asyncAfter(deadline: .now() + BubbleConstants.udpRelayTimeout) { [weak self] in
            self?.log.log("UDP #\(streamID): TIMEOUT for \(host):\(port)")
            complete(nil)
        }

        udp.stateUpdateHandler = { [weak self] connState in
            switch connState {
            case .ready:
                self?.log.log("UDP #\(streamID): NWConnection ready to \(host):\(port), sending \(payload.count)B")
                udp.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        self?.log.log("UDP #\(streamID): send FAILED to \(host):\(port): \(error)")
                        complete(nil)
                        return
                    }

                    udp.receiveMessage { respData, _, _, recvError in
                        if let respData, !respData.isEmpty {
                            self?.log.log("UDP #\(streamID): got \(respData.count)B response from \(host):\(port)")
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
                            self?.log.log("UDP #\(streamID): empty/nil response from \(host):\(port), error=\(String(describing: recvError))")
                            complete(nil)
                        }
                    }
                })

            case .failed(let error):
                self?.log.log("UDP #\(streamID): NWConnection FAILED to \(host):\(port): \(error)")
                complete(nil)

            case .waiting(let error):
                self?.log.log("UDP #\(streamID): NWConnection WAITING to \(host):\(port): \(error)")

            default:
                break
            }
        }

        udp.start(queue: queue)
    }

    private func closeUDPControlStream(client: NWConnection, state: UDPStreamState, reason: String) {
        guard !state.closed else { return }
        state.closed = true
        if effectiveUDPDecodeMode == .strict,
           (reason.contains("decode_bad_len") || reason.contains("decode_bad_payload")) {
            let now = Date()
            if !isUDPCircuitOpen(peerKey: state.peerKey, now: now) {
                udpStreamReopenDebounceUntilByPeer[state.peerKey] = now.addingTimeInterval(2.0)
            }
        }
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        activeUDPStreams = max(activeUDPStreams - 1, 0)
        totalUDPStreamsClosed += 1
        log.log("UDP_DECODER stream=\(state.id) event=close reason=\(reason) queued=\(state.pendingFrames.count)")
        client.cancel()
    }

    private func decoderReasonCode(_ error: UDPControlDecoderError) -> String {
        switch error {
        case .badPrefix:
            return "bad_prefix"
        case .badLength:
            return "bad_len"
        }
    }

    private func recordDecoderError(_ error: UDPControlDecoderError) {
        switch error {
        case .badPrefix:
            udpDecodeBadPrefix += 1
        case .badLength:
            udpDecodeBadLength += 1
        }
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
        var sniProbeBuffer = Data()
        var loggedUntracked = false

        init(id: Int, host: String, port: UInt16) {
            self.id = id
            self.host = host
            self.port = port
        }
    }

    private final class UDPStreamState {
        let id: Int
        let peerKey: String
        let decoder: UDPControlStreamDecoder
        var opaqueMode: Bool = false
        var mode: UDPControlFramingMode?
        var pendingFrames: [UDPControlFrame] = []
        var processingFrame = false
        var closed = false

        init(id: Int, peerKey: String, decoder: UDPControlStreamDecoder) {
            self.id = id
            self.peerKey = peerKey
            self.decoder = decoder
        }
    }

    private enum UDPPeerStreamMode: String {
        case unknown
        case validatedPlain
        case validatedControlPrefixed
        case opaqueQuicOrUnparseable
    }

    private struct UDPPeerState {
        var mode: UDPPeerStreamMode = .unknown
        var decodeErrors: [Date] = []
        var opaqueUntil: Date?
    }

    private func peerKey(for client: NWConnection) -> String {
        String(describing: client.endpoint)
    }

    private func cleanupUDPPeerCircuitState(now: Date) {
        let tuning = filter.runtimePolicy()
        let window = TimeInterval(max(tuning.udpCircuitBreakerWindowSec, 1))
        var updated: [String: UDPPeerState] = [:]
        for (key, state) in udpPeerStateByPeer {
            var next = state
            next.decodeErrors = next.decodeErrors.filter { now.timeIntervalSince($0) <= window }
            if let until = next.opaqueUntil, until <= now {
                next.opaqueUntil = nil
                if next.mode == .opaqueQuicOrUnparseable {
                    next.mode = .unknown
                    log.log("udp_circuit_close peer=\(key)")
                }
            }
            let hasOpaque = next.opaqueUntil != nil
            let hasRecentErrors = !next.decodeErrors.isEmpty
            if hasOpaque || hasRecentErrors || next.mode != .unknown {
                updated[key] = next
            }
        }
        udpPeerStateByPeer = updated
        decisionDedupUntilByPeer = decisionDedupUntilByPeer.filter { _, until in until > now }
    }

    private func markValidatedMode(peerKey: String, mode: UDPControlFramingMode) {
        var state = udpPeerStateByPeer[peerKey] ?? UDPPeerState()
        switch mode {
        case .plain:
            state.mode = .validatedPlain
        case .controlPrefixed:
            state.mode = .validatedControlPrefixed
        }
        state.opaqueUntil = nil
        udpPeerStateByPeer[peerKey] = state
    }

    private func shouldOpenUDPCircuit(peerKey: String, now: Date) -> Bool {
        let tuning = filter.runtimePolicy()
        var state = udpPeerStateByPeer[peerKey] ?? UDPPeerState()
        let window = TimeInterval(max(tuning.udpCircuitBreakerWindowSec, 1))
        state.decodeErrors = state.decodeErrors.filter { now.timeIntervalSince($0) <= window }
        state.decodeErrors.append(now)
        let threshold = max(tuning.udpCircuitBreakerThreshold, 1)
        guard state.decodeErrors.count >= threshold else {
            udpPeerStateByPeer[peerKey] = state
            return false
        }
        let cooldown = TimeInterval(max(tuning.udpCircuitBreakerCooldownSec, 1))
        state.mode = .opaqueQuicOrUnparseable
        state.opaqueUntil = now.addingTimeInterval(cooldown)
        state.decodeErrors.removeAll()
        udpPeerStateByPeer[peerKey] = state
        log.log("udp_circuit_open peer=\(peerKey) cooldown=\(Int(cooldown))s")
        return true
    }

    private func isUDPCircuitOpen(peerKey: String, now: Date) -> Bool {
        guard let state = udpPeerStateByPeer[peerKey], let until = state.opaqueUntil else { return false }
        return state.mode == .opaqueQuicOrUnparseable && until > now
    }

    private func maybeLogDecisionDedup(peerKey: String, action: String) {
        let now = Date()
        if let until = decisionDedupUntilByPeer[peerKey], until > now {
            decisionDedupHits += 1
            return
        }
        decisionDedupUntilByPeer[peerKey] = now.addingTimeInterval(1.0)
        log.log("decision_dedup peer=\(peerKey) action=\(action)")
    }

    private func logUDPDecoderError(streamID: Int, reason: String) {
        let now = Date()
        let lastLog = udpDecoderLogLastByReason[reason] ?? .distantPast
        let intervalElapsed = now.timeIntervalSince(lastLog) >= udpDecoderLogInterval

        if !intervalElapsed {
            udpDecoderLogSuppressedByReason[reason, default: 0] += 1
            return
        }

        let suppressed = udpDecoderLogSuppressedByReason[reason] ?? 0
        udpDecoderLogSuppressedByReason[reason] = 0
        udpDecoderLogLastByReason[reason] = now

        if suppressed > 0 {
            log.log("UDP_DECODER stream=\(streamID) event=decode_error reason=\(reason) suppressed=\(suppressed)")
        } else {
            log.log("UDP_DECODER stream=\(streamID) event=decode_error reason=\(reason)")
        }
    }

    private func currentHealthState() -> String {
        if thermalForcedAdaptive {
            return "thermal_guard_adaptive"
        }
        if backoffActiveHosts > 0 {
            return "mitigating_retries"
        }
        if latestUDPDecodeErrorRatePerSec >= 1.0 || udpDecodeStrictDropCount > 0 {
            return "strict_udp_drop_mode"
        }
        return "healthy"
    }

    private func evaluatePolicy(kind: String, evaluator: () -> PolicyDecision) -> PolicyDecision {
        let start = DispatchTime.now().uptimeNanoseconds
        let decision = evaluator()
        let elapsedMicros = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000.0
        policyEvalMicrosSamples.append(elapsedMicros)
        if policyEvalMicrosSamples.count > 500 {
            policyEvalMicrosSamples.removeFirst(policyEvalMicrosSamples.count - 500)
        }
        if !policyEvalMicrosSamples.isEmpty {
            let sorted = policyEvalMicrosSamples.sorted()
            let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95)))
            policyEvalMicrosP95 = sorted[idx]
        }
        if decision.classification.bucket == .reels {
            totalReelsAttempts += 1
            if decision.action == .blockNow {
                blockedReelsAttempts += 1
            }
            if totalReelsAttempts > 0 {
                playbackBlockRateEstimate = Double(blockedReelsAttempts) / Double(totalReelsAttempts)
            }
        }
        if kind == "opaque_dedup" {
            decisionDedupHits += 1
        }
        return decision
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
                        if tracker.sniProbeBuffer.count < 16 * 1024 {
                            tracker.sniProbeBuffer.append(data)
                        }
                        if let sni = self.extractSNI(from: tracker.sniProbeBuffer) {
                            tracker.sni = sni
                            self.log.logConnection("TCP #\(tracker.id): SNI=\(sni) IP=\(tracker.host):\(tracker.port)")
                            TunnelLogger.connectionLog.log("[SNI] \(sni, privacy: .public)")
                            let earlyDecision = self.evaluatePolicy(kind: "early_tls") {
                                self.filter.evaluateEarlyTLS(host: tracker.host, sni: sni, port: tracker.port)
                            }
                            if earlyDecision.action == .blockNow {
                                self.statsBlocked += 1
                                self.log.log("EARLY TLS BLOCK #\(tracker.id): killed \(sni)")
                                self.recordEvent(
                                    type: .streamBlocked,
                                    connId: tracker.id,
                                    host: tracker.host,
                                    port: tracker.port,
                                    sni: tracker.sni,
                                    detail: "Blocked during ClientHello",
                                    bytesDown: tracker.bytesDown,
                                    decision: earlyDecision
                                )
                                self.logRelayEnd(tracker: tracker, reason: "stream-blocked")
                                source.cancel()
                                destination.cancel()
                                return
                            }
                        }
                    }
                case .download:
                    let projectedBytesDown = tracker.bytesDown + data.count

                    let streamDecision = self.evaluatePolicy(kind: "stream") {
                        self.filter.evaluateStream(
                            host: tracker.host,
                            sni: tracker.sni,
                            port: tracker.port,
                            bytesDown: projectedBytesDown,
                            connectionAge: Date().timeIntervalSince(tracker.startTime),
                            parallelConnections: self.activeRelays.count
                        )
                    }

                    let threshold = streamDecision.blockAfterBytes
                    let shouldBlockNow = streamDecision.action == .blockNow
                    let shouldBlockAfter = streamDecision.action == .blockAfterBytes && threshold != nil && projectedBytesDown > threshold!
                    if shouldBlockNow || shouldBlockAfter {
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
        String(format: "%.1f", memoryUsageMBValue())
    }

    private static func memoryUsageMBValue() -> Double {
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
        return 0
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
