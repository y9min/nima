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
    let attemptedByBucket: [String: Int]
    let blockedByBucket: [String: Int]
    let possibleFalsePositiveRetries: Int
    let blockedSuppressedTCP: Int
    let blockedSuppressedUDP: Int
    let suppressionKeysActive: Int

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
        udpModeControlPrefixed: Int,
        attemptedByBucket: [String: Int] = [:],
        blockedByBucket: [String: Int] = [:],
        possibleFalsePositiveRetries: Int = 0,
        blockedSuppressedTCP: Int = 0,
        blockedSuppressedUDP: Int = 0,
        suppressionKeysActive: Int = 0
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
        self.attemptedByBucket = attemptedByBucket
        self.blockedByBucket = blockedByBucket
        self.possibleFalsePositiveRetries = possibleFalsePositiveRetries
        self.blockedSuppressedTCP = blockedSuppressedTCP
        self.blockedSuppressedUDP = blockedSuppressedUDP
        self.suppressionKeysActive = suppressionKeysActive
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
        case attemptedByBucket
        case blockedByBucket
        case possibleFalsePositiveRetries
        case blockedSuppressedTCP
        case blockedSuppressedUDP
        case suppressionKeysActive
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
        attemptedByBucket = try c.decodeIfPresent([String: Int].self, forKey: .attemptedByBucket) ?? [:]
        blockedByBucket = try c.decodeIfPresent([String: Int].self, forKey: .blockedByBucket) ?? [:]
        possibleFalsePositiveRetries = try c.decodeIfPresent(Int.self, forKey: .possibleFalsePositiveRetries) ?? 0
        blockedSuppressedTCP = try c.decodeIfPresent(Int.self, forKey: .blockedSuppressedTCP) ?? 0
        blockedSuppressedUDP = try c.decodeIfPresent(Int.self, forKey: .blockedSuppressedUDP) ?? 0
        suppressionKeysActive = try c.decodeIfPresent(Int.self, forKey: .suppressionKeysActive) ?? 0
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
    let bucket: String?
    let confidence: Double?
    let policyAction: String?
    let reasons: [String]?
    let toggleSnapshot: [String: Bool]?
    let policyVersion: Int?
    let decisionReason: String?
}
