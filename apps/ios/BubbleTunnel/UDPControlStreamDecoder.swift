import Foundation

// Decoder assumptions are pinned to Tun2SocksKit 5.14.4 behavior:
// FWD_UDP control streams use either len16 or 0x0001+len16 framing.

enum UDPControlFramingMode: String {
    case plain
    case controlPrefixed
}

enum UDPControlDecoderError: Error, Equatable {
    case badPrefix
    case badLength
}

enum UDPControlAppendStatus: Equatable {
    case ok
    case recovered(error: UDPControlDecoderError)
    case failed(error: UDPControlDecoderError)
}

struct UDPControlFrame {
    let mode: UDPControlFramingMode
    let payload: [UInt8]
}

struct UDPControlAppendResult {
    let frames: [UDPControlFrame]
    let status: UDPControlAppendStatus
}

final class UDPControlStreamDecoder {
    enum State: Equatable {
        case awaitPrefix2
        case awaitLength2(controlPrefixed: Bool)
        case awaitPayload(length: Int, controlPrefixed: Bool)
    }

    private enum LockedMode {
        case unknown
        case plain
        case controlPrefixed
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
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
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
                        if attemptResync(fromInvalidPrefix: prefix) {
                            hadRecovery = true
                            continue
                        }
                        return UDPControlAppendResult(frames: emitted, status: .failed(error: .badLength))
                    }
                    state = .awaitPayload(length: prefix, controlPrefixed: false)

                case .unknown:
                    if prefix == 0x0001 {
                        state = .awaitLength2(controlPrefixed: true)
                    } else {
                        guard prefix > 0, prefix <= maxFrameSize else {
                            if attemptResync(fromInvalidPrefix: prefix) {
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
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                }

                let length = Self.readBE16(buffer[0], buffer[1])
                buffer.removeFirst(2)

                guard length > 0, length <= maxFrameSize else {
                    if lockedMode == .unknown, attemptResync(fromInvalidPrefix: length) {
                        hadRecovery = true
                        continue
                    }
                    return UDPControlAppendResult(frames: emitted, status: .failed(error: .badLength))
                }

                state = .awaitPayload(length: length, controlPrefixed: controlPrefixed)

            case .awaitPayload(let length, let controlPrefixed):
                guard buffer.count >= length else {
                    return UDPControlAppendResult(frames: emitted, status: hadRecovery ? .recovered(error: .badLength) : .ok)
                }

                let payload = Array(buffer.prefix(length))
                buffer.removeFirst(length)

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

    private static func readBE16(_ b0: UInt8, _ b1: UInt8) -> Int {
        (Int(b0) << 8) | Int(b1)
    }

    func drainDiagnostics() -> (resyncAttempts: Int, resyncSuccesses: Int) {
        let out = (resyncAttempts, resyncSuccesses)
        resyncAttempts = 0
        resyncSuccesses = 0
        return out
    }

    private func attemptResync(fromInvalidPrefix prefix: Int) -> Bool {
        guard lockedMode == .unknown, prefix != 0x0001 else { return false }
        guard pendingResyncAttempts < maxResyncAttempts else { return false }
        pendingResyncAttempts += 1
        resyncAttempts += 1
        state = .awaitPrefix2
        buffer.insert(UInt8(prefix & 0xFF), at: 0)
        return true
    }
}
