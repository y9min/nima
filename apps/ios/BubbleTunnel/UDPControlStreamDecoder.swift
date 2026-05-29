import Foundation

// Decoder assumptions are pinned to Tun2SocksKit 5.14.4 behavior:
// FWD_UDP control streams use either len16, 0x0001+len16, or raw UDP payload framing.
// For framed UDP payloads, len16 is the datagram payload length after the
// HEV/SOCKS destination header, not the full header+payload byte count.

enum UDPControlFramingMode: String {
    case plain
    case controlPrefixed
    case rawPayload
}

enum UDPControlDecoderError: Error, Equatable {
    case badPrefix
    case badLength
}

enum UDPControlAppendStatus: Equatable {
    case ok
    case needMoreBytes
    case recovered(error: UDPControlDecoderError)
    case failed(error: UDPControlDecoderError)
}

struct UDPControlFrame: Equatable {
    let mode: UDPControlFramingMode
    let payload: [UInt8]
}

struct UDPControlDecoderDiagnosticSnapshot: Equatable {
    let state: String
    let mode: String
    let bufferedBytes: Int
    let pendingResyncAttempts: Int
    let resyncAttempts: Int
    let resyncSuccesses: Int
    let maxFrameSize: Int
}

enum UDPControlFrameCodec {
    static func buildResponseFrame(
        mode: UDPControlFramingMode,
        headerBytes: [UInt8],
        responsePayload: Data,
        maxFrameSize: Int
    ) -> Data? {
        var frame = headerBytes
        frame.append(contentsOf: [UInt8](responsePayload))
        guard !responsePayload.isEmpty,
              responsePayload.count <= maxFrameSize,
              responsePayload.count <= UInt16.max,
              frame.count <= UInt16.max else {
            return nil
        }

        if mode == .rawPayload {
            return Data(frame)
        }

        var framedData: [UInt8] = []
        if mode == .controlPrefixed {
            framedData.append(contentsOf: [0x00, 0x01])
        }
        framedData.append(contentsOf: [UInt8(responsePayload.count >> 8), UInt8(responsePayload.count & 0xFF)])
        framedData.append(contentsOf: frame)
        return Data(framedData)
    }
}

struct UDPControlAppendResult {
    let frames: [UDPControlFrame]
    let status: UDPControlAppendStatus
}

final class UDPControlStreamDecoder {
    private enum DestinationHeaderStatus {
        case complete(length: Int)
        case needMoreBytes
        case invalid
    }

    enum State: Equatable {
        case awaitPrefix2
        case awaitLength2(controlPrefixed: Bool)
        case awaitPayload(length: Int, controlPrefixed: Bool)

        var diagnosticDescription: String {
            switch self {
            case .awaitPrefix2:
                return "await_prefix2"
            case .awaitLength2(let controlPrefixed):
                return controlPrefixed ? "await_length2_control_prefixed" : "await_length2_plain"
            case .awaitPayload(let length, let controlPrefixed):
                return "await_payload_len_\(length)_\(controlPrefixed ? "control_prefixed" : "plain")"
            }
        }
    }

    private enum LockedMode {
        case unknown
        case plain
        case controlPrefixed

        var diagnosticDescription: String {
            switch self {
            case .unknown:
                return "unknown"
            case .plain:
                return "plain"
            case .controlPrefixed:
                return "control_prefixed"
            }
        }
    }

    private(set) var state: State = .awaitPrefix2
    private var lockedMode: LockedMode = .unknown
    private var buffer: [UInt8] = []
    private let maxFrameSize: Int
    private let maxResyncAttempts: Int
    private var pendingResyncAttempts = 0
    private(set) var resyncAttempts = 0
    private(set) var resyncSuccesses = 0

    init(maxFrameSize: Int, maxResyncAttempts: Int = 2) {
        self.maxFrameSize = maxFrameSize
        self.maxResyncAttempts = maxResyncAttempts
    }

    func append(_ data: Data) -> UDPControlAppendResult {
        if !data.isEmpty {
            buffer.append(contentsOf: data)
        }

        var emitted: [UDPControlFrame] = []
        var hadRecovery = false

        while true {
            switch state {
            case .awaitPrefix2:
                guard buffer.count >= 2 else {
                    if !emitted.isEmpty {
                        return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                    }
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .needMoreBytes)
                }

                let prefix = Self.readBE16(buffer[0], buffer[1])
                buffer.removeFirst(2)

                switch lockedMode {
                case .controlPrefixed:
                    guard prefix == 0x0001 else {
                        return UDPControlAppendResult(frames: emitted, status: .failed(error: .badPrefix))
                    }
                    state = .awaitLength2(controlPrefixed: true)

                case .plain:
                    guard prefix > 0, prefix <= maxFrameSize else {
                        if recoverFromInvalidPrefix(prefix) {
                            hadRecovery = true
                            continue
                        }
                        if hadRecovery {
                            return UDPControlAppendResult(frames: emitted, status: .recovered(error: .badLength))
                        }
                        return UDPControlAppendResult(frames: emitted, status: .failed(error: .badLength))
                    }
                    state = .awaitPayload(length: prefix, controlPrefixed: false)

                case .unknown:
                    if prefix == 0x0001 {
                        state = .awaitLength2(controlPrefixed: true)
                    } else {
                        guard prefix > 0, prefix <= maxFrameSize else {
                            if recoverFromInvalidPrefix(prefix) {
                                hadRecovery = true
                                continue
                            }
                            return UDPControlAppendResult(frames: emitted, status: .failed(error: .badLength))
                        }
                        state = .awaitPayload(length: prefix, controlPrefixed: false)
                    }
                }

            case .awaitLength2(let controlPrefixed):
                guard buffer.count >= 2 else {
                    if !emitted.isEmpty {
                        return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                    }
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .needMoreBytes)
                }

                let length = Self.readBE16(buffer[0], buffer[1])
                buffer.removeFirst(2)

                guard length > 0, length <= maxFrameSize else {
                    if lockedMode == .unknown, recoverFromInvalidPrefix(length) {
                        hadRecovery = true
                        continue
                    }
                    return UDPControlAppendResult(frames: emitted, status: .failed(error: .badLength))
                }

                state = .awaitPayload(length: length, controlPrefixed: controlPrefixed)

            case .awaitPayload(let length, let controlPrefixed):
                guard let frameLength = frameLengthForCurrentBuffer(prefixLength: length) else {
                    if !emitted.isEmpty {
                        return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                    }
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .needMoreBytes)
                }

                guard buffer.count >= frameLength else {
                    if !emitted.isEmpty {
                        return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                    }
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .needMoreBytes)
                }

                let payload = Array(buffer.prefix(frameLength))
                buffer.removeFirst(frameLength)

                let mode: UDPControlFramingMode = controlPrefixed ? .controlPrefixed : .plain
                switch lockedMode {
                case .unknown:
                    lockedMode = controlPrefixed ? .controlPrefixed : .plain
                case .plain where controlPrefixed:
                    return UDPControlAppendResult(frames: emitted, status: .failed(error: .badPrefix))
                case .controlPrefixed where !controlPrefixed:
                    return UDPControlAppendResult(frames: emitted, status: .failed(error: .badPrefix))
                default:
                    break
                }

                if pendingResyncAttempts > 0 {
                    resyncSuccesses += 1
                    pendingResyncAttempts = 0
                }

                emitted.append(UDPControlFrame(mode: mode, payload: payload))
                state = .awaitPrefix2
            }
        }
    }

    var currentMode: UDPControlFramingMode? {
        switch lockedMode {
        case .unknown:
            return nil
        case .plain:
            return .plain
        case .controlPrefixed:
            return .controlPrefixed
        }
    }

    func diagnosticSnapshot() -> UDPControlDecoderDiagnosticSnapshot {
        UDPControlDecoderDiagnosticSnapshot(
            state: state.diagnosticDescription,
            mode: lockedMode.diagnosticDescription,
            bufferedBytes: buffer.count,
            pendingResyncAttempts: pendingResyncAttempts,
            resyncAttempts: resyncAttempts,
            resyncSuccesses: resyncSuccesses,
            maxFrameSize: maxFrameSize
        )
    }

    private static func readBE16(_ b0: UInt8, _ b1: UInt8) -> Int {
        (Int(b0) << 8) | Int(b1)
    }

    private func frameLengthForCurrentBuffer(prefixLength: Int) -> Int? {
        switch Self.destinationHeaderStatus(in: buffer) {
        case .complete(let headerLength):
            return headerLength + prefixLength
        case .needMoreBytes:
            return nil
        case .invalid:
            return prefixLength
        }
    }

    private static func destinationHeaderStatus(in bytes: [UInt8]) -> DestinationHeaderStatus {
        guard !bytes.isEmpty else { return .needMoreBytes }

        if bytes[0] == 0x0a {
            return addressHeaderStatus(in: bytes, atypOffset: 1)
        }

        guard bytes[0] == 0x00 else { return .invalid }
        guard bytes.count >= 3 else {
            return bytes.allSatisfy { $0 == 0x00 } ? .needMoreBytes : .invalid
        }
        guard bytes[1] == 0x00, bytes[2] == 0x00 else { return .invalid }
        return addressHeaderStatus(in: bytes, atypOffset: 3)
    }

    private static func addressHeaderStatus(in bytes: [UInt8], atypOffset: Int) -> DestinationHeaderStatus {
        guard bytes.count > atypOffset else { return .needMoreBytes }

        let requiredHeaderBytes: Int
        switch bytes[atypOffset] {
        case 0x01:
            requiredHeaderBytes = atypOffset + 1 + 4 + 2
        case 0x04:
            requiredHeaderBytes = atypOffset + 1 + 16 + 2
        case 0x03:
            guard bytes.count > atypOffset + 1 else { return .needMoreBytes }
            let domainLength = Int(bytes[atypOffset + 1])
            guard domainLength > 0 else { return .invalid }
            requiredHeaderBytes = atypOffset + 2 + domainLength + 2
        default:
            return .invalid
        }

        guard bytes.count >= requiredHeaderBytes else { return .needMoreBytes }
        return .complete(length: requiredHeaderBytes)
    }

    func drainDiagnostics() -> (resyncAttempts: Int, resyncSuccesses: Int) {
        let out = (resyncAttempts, resyncSuccesses)
        resyncAttempts = 0
        resyncSuccesses = 0
        return out
    }

    private func recoverFromInvalidPrefix(_ prefix: Int) -> Bool {
        guard prefix != 0x0001 else { return false }
        guard pendingResyncAttempts < maxResyncAttempts else { return false }
        let lowByteLength = prefix & 0xFF
        pendingResyncAttempts += 1
        resyncAttempts += 1
        if lockedMode == .unknown, lowByteLength > 0, lowByteLength <= maxFrameSize, buffer.count >= lowByteLength {
            state = .awaitPayload(length: lowByteLength, controlPrefixed: false)
            return true
        }
        guard !buffer.isEmpty else { return false }
        state = .awaitPrefix2
        return true
    }
}
