import Foundation

// MARK: - Top-level wrapper

struct TrafficData: Codable {
    let snapshots: [TrafficSnapshot]
    let events: [TrafficEvent]
}

// MARK: - Snapshots

struct TrafficSnapshot: Codable {
    let timestamp: Date
    let connections: [ConnectionSnapshot]
    let stats: StatsSnapshot
    let topDomains: [DomainSnapshot]
}

struct ConnectionSnapshot: Codable, Identifiable {
    let id: Int
    let host: String
    let port: UInt16
    let sni: String?
    let startTime: Date
    let bytesUp: Int
    let bytesDown: Int
    let isActive: Bool

    var totalBytes: Int { bytesUp + bytesDown }
}

struct StatsSnapshot: Codable {
    let totalConns: Int
    let tcpAllowed: Int
    let tcpBlocked: Int
    let udpRelayed: Int
    let errors: Int
    let udpActiveStreams: Int
    let udpStreamsOpened: Int
    let udpStreamsClosed: Int
    let udpDecodeBadPrefix: Int
    let udpDecodeBadLength: Int
    let udpDecodeBadPayload: Int
    let udpModePlain: Int
    let udpModeControlPrefixed: Int

    init(
        totalConns: Int,
        tcpAllowed: Int,
        tcpBlocked: Int,
        udpRelayed: Int,
        errors: Int,
        udpActiveStreams: Int,
        udpStreamsOpened: Int,
        udpStreamsClosed: Int,
        udpDecodeBadPrefix: Int,
        udpDecodeBadLength: Int,
        udpDecodeBadPayload: Int,
        udpModePlain: Int,
        udpModeControlPrefixed: Int
    ) {
        self.totalConns = totalConns
        self.tcpAllowed = tcpAllowed
        self.tcpBlocked = tcpBlocked
        self.udpRelayed = udpRelayed
        self.errors = errors
        self.udpActiveStreams = udpActiveStreams
        self.udpStreamsOpened = udpStreamsOpened
        self.udpStreamsClosed = udpStreamsClosed
        self.udpDecodeBadPrefix = udpDecodeBadPrefix
        self.udpDecodeBadLength = udpDecodeBadLength
        self.udpDecodeBadPayload = udpDecodeBadPayload
        self.udpModePlain = udpModePlain
        self.udpModeControlPrefixed = udpModeControlPrefixed
    }

    private enum CodingKeys: String, CodingKey {
        case totalConns
        case tcpAllowed
        case tcpBlocked
        case udpRelayed
        case errors
        case udpActiveStreams
        case udpStreamsOpened
        case udpStreamsClosed
        case udpDecodeBadPrefix
        case udpDecodeBadLength
        case udpDecodeBadPayload
        case udpModePlain
        case udpModeControlPrefixed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalConns = try c.decode(Int.self, forKey: .totalConns)
        tcpAllowed = try c.decode(Int.self, forKey: .tcpAllowed)
        tcpBlocked = try c.decode(Int.self, forKey: .tcpBlocked)
        udpRelayed = try c.decode(Int.self, forKey: .udpRelayed)
        errors = try c.decode(Int.self, forKey: .errors)
        udpActiveStreams = try c.decodeIfPresent(Int.self, forKey: .udpActiveStreams) ?? 0
        udpStreamsOpened = try c.decodeIfPresent(Int.self, forKey: .udpStreamsOpened) ?? 0
        udpStreamsClosed = try c.decodeIfPresent(Int.self, forKey: .udpStreamsClosed) ?? 0
        udpDecodeBadPrefix = try c.decodeIfPresent(Int.self, forKey: .udpDecodeBadPrefix) ?? 0
        udpDecodeBadLength = try c.decodeIfPresent(Int.self, forKey: .udpDecodeBadLength) ?? 0
        udpDecodeBadPayload = try c.decodeIfPresent(Int.self, forKey: .udpDecodeBadPayload) ?? 0
        udpModePlain = try c.decodeIfPresent(Int.self, forKey: .udpModePlain) ?? 0
        udpModeControlPrefixed = try c.decodeIfPresent(Int.self, forKey: .udpModeControlPrefixed) ?? 0
    }
}

struct DomainSnapshot: Codable, Identifiable {
    var id: String { domain }
    let domain: String
    let count: Int
    let totalBytes: Int
}

// MARK: - Events

enum EventType: String, Codable {
    case allowed
    case blocked
    case streamBlocked
    case error
    case completed
}

struct TrafficEvent: Codable, Identifiable {
    let id: Int
    let timestamp: Date
    let type: EventType
    let host: String
    let port: UInt16
    let sni: String?
    let detail: String
    let bytesDown: Int?
}
