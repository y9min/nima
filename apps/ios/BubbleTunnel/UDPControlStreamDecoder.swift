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

struct UDPControlFrame {
    let mode: UDPControlFramingMode
    let payload: [UInt8]
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

    init(maxFrameSize: Int) {
        self.maxFrameSize = maxFrameSize
    }

    func append(_ data: Data) -> Result<[UDPControlFrame], UDPControlDecoderError> {
        if !data.isEmpty {
            buffer.append(contentsOf: data)
        }

        var emitted: [UDPControlFrame] = []

        while true {
            switch state {
            case .awaitPrefix2:
                guard buffer.count >= 2 else {
                    return .success(emitted)
                }

                let prefix = Self.readBE16(buffer[0], buffer[1])
                buffer.removeFirst(2)

                switch lockedMode {
                case .controlPrefixed:
                    guard prefix == 0x0001 else {
                        return .failure(.badPrefix)
                    }
                    state = .awaitLength2(controlPrefixed: true)

                case .plain:
                    guard prefix > 0, prefix <= maxFrameSize else {
                        return .failure(.badLength)
                    }
                    state = .awaitPayload(length: prefix, controlPrefixed: false)

                case .unknown:
                    if prefix == 0x0001 {
                        state = .awaitLength2(controlPrefixed: true)
                    } else {
                        guard prefix > 0, prefix <= maxFrameSize else {
                            return .failure(.badLength)
                        }
                        state = .awaitPayload(length: prefix, controlPrefixed: false)
                    }
                }

            case .awaitLength2(let controlPrefixed):
                guard buffer.count >= 2 else {
                    return .success(emitted)
                }

                let length = Self.readBE16(buffer[0], buffer[1])
                buffer.removeFirst(2)

                guard length > 0, length <= maxFrameSize else {
                    return .failure(.badLength)
                }

                state = .awaitPayload(length: length, controlPrefixed: controlPrefixed)

            case .awaitPayload(let length, let controlPrefixed):
                guard buffer.count >= length else {
                    return .success(emitted)
                }

                let payload = Array(buffer.prefix(length))
                buffer.removeFirst(length)

                let mode: UDPControlFramingMode = controlPrefixed ? .controlPrefixed : .plain
                switch lockedMode {
                case .unknown:
                    lockedMode = controlPrefixed ? .controlPrefixed : .plain
                case .plain where controlPrefixed:
                    return .failure(.badPrefix)
                case .controlPrefixed where !controlPrefixed:
                    return .failure(.badPrefix)
                default:
                    break
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
}
