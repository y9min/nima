import Foundation
import Network
import os

// MARK: - Connection Filter Protocol

protocol ConnectionFilter {
    func shouldAllow(host: String, port: UInt16) -> FilterDecision
    func shouldBlockUDP(host: String, port: UInt16) -> Bool
    func isStreamBlockTarget(_ domain: String) -> Bool
    func streamBlockThreshold(for sni: String) -> Int?
}

enum FilterDecision {
    case allow
    case block
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
    private var statsTimer: DispatchSourceTimer?

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
            let memMB = Self.memoryUsageMB()
            self.log.log("SOCKS5 STATS: \(total) total, \(self.activeConnectionCount) active, \(self.activeRelays.count) relays, \(self.statsAllowed) allowed, \(self.statsBlocked) blocked, \(self.statsUDP) UDP, \(self.statsErrors) errors, udpActive=\(self.activeUDPStreams), udpOpened=\(self.totalUDPStreamsOpened), udpClosed=\(self.totalUDPStreamsClosed), snapshots=\(self.snapshotHistory.count), mem=\(memMB)MB")
        }
        timer.resume()
        statsTimer = timer
    }

    // MARK: - Event Recording

    private func recordEvent(type: EventType, connId: Int, host: String, port: UInt16, sni: String? = nil, detail: String, bytesDown: Int? = nil) {
        eventCounter += 1
        let event = TrafficEvent(
            id: eventCounter,
            timestamp: Date(),
            type: type,
            host: host,
            port: port,
            sni: sni,
            detail: detail,
            bytesDown: bytesDown
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
            udpModeControlPrefixed: udpModeControlPrefixed
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
        let decision = self.filter.shouldAllow(host: host, port: port)

        switch decision {
        case .block:
            self.statsBlocked += 1
            self.activeConnectionCount -= 1
            self.log.log("SOCKS5 #\(id): BLOCKED \(host):\(port)")
            self.recordEvent(type: .blocked, connId: id, host: host, port: port, detail: "Connection blocked by filter")
            self.sendSocksError(client: client, reply: 0x05)

        case .allow:
            self.statsAllowed += 1
            self.recordEvent(type: .allowed, connId: id, host: host, port: port, detail: "TCP CONNECT")
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
        let state = UDPStreamState(id: id, decoder: UDPControlStreamDecoder(maxFrameSize: BubbleConstants.maxUDPFrameSize))
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
                switch state.decoder.append(data) {
                case .success(let frames):
                    if let mode = state.decoder.currentMode, state.mode == nil {
                        state.mode = mode
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
                    self.log.log("UDP_DECODER stream=\(state.id) event=decode_error reason=\(self.decoderReasonCode(decodeError))")
                    self.closeUDPControlStream(client: client, state: state, reason: "decode_\(self.decoderReasonCode(decodeError))")
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
            log.log("UDP_DECODER stream=\(state.id) event=decode_error reason=bad_payload")
            closeUDPControlStream(client: client, state: state, reason: "decode_bad_payload")
            return
        }

        statsUDP += 1
        log.log("UDP #\(state.id): dest=\(parsed.addr.host):\(parsed.addr.port), payload=\(parsed.payload.count)B")

        let decision = filter.shouldAllow(host: parsed.addr.host, port: parsed.addr.port)
        if decision == .block {
            statsBlocked += 1
            state.processingFrame = false
            processNextUDPFrame(client: client, state: state)
            return
        }

        if filter.shouldBlockUDP(host: parsed.addr.host, port: parsed.addr.port) {
            statsBlocked += 1
            log.log("UDP #\(state.id): BLOCKED strict UDP policy for \(parsed.addr.host):\(parsed.addr.port)")
            recordEvent(type: .blocked, connId: state.id, host: parsed.addr.host, port: parsed.addr.port, detail: "UDP blocked by strict policy")
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
        var mode: UDPControlFramingMode?
        var pendingFrames: [UDPControlFrame] = []
        var processingFrame = false
        var closed = false

        init(id: Int, decoder: UDPControlStreamDecoder) {
            self.id = id
            self.decoder = decoder
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
                    tracker.bytesDown += data.count

                    let domainForRules = tracker.sni ?? (Self.looksLikeDomainName(tracker.host) ? tracker.host : nil)

                    // Stream blocking: per-domain byte thresholds (SNI first, then SOCKS host fallback).
                    if let domainForRules = domainForRules {
                        let threshold = self.filter.streamBlockThreshold(for: domainForRules)
                        if let threshold, tracker.bytesDown > threshold {
                            self.statsBlocked += 1
                            self.log.log("STREAM BLOCK #\(tracker.id): killed \(domainForRules) at \(tracker.bytesDown)B (threshold: \(threshold)B)")
                            self.recordEvent(type: .streamBlocked, connId: tracker.id, host: tracker.host, port: tracker.port, sni: tracker.sni ?? domainForRules, detail: "Killed at \(tracker.bytesDown)B (threshold: \(threshold)B)", bytesDown: tracker.bytesDown)
                            self.logRelayEnd(tracker: tracker, reason: "stream-blocked")
                            source.cancel()
                            destination.cancel()
                            return
                        }
                        // Log untracked domains receiving large downloads (potential failover)
                        if threshold == nil && tracker.bytesDown > 100_000 && !tracker.loggedUntracked {
                            tracker.loggedUntracked = true
                            TunnelLogger.connectionLog.log("[UNTRACKED-LARGE] \(domainForRules, privacy: .public) \(tracker.bytesDown, privacy: .public)B+ (no blocking rule)")
                        }
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

    private static func looksLikeDomainName(_ host: String) -> Bool {
        guard host.contains(".") else { return false }
        guard !host.contains(":") else { return false } // likely IPv6
        return host.rangeOfCharacter(from: .letters) != nil
    }
}
