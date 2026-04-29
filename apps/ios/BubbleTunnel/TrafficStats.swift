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
    let healthState: String
    let retryStormEvents: Int
    let backoffActiveHosts: Int
    let udpDecodeStrictDropCount: Int
    let udpDecodeStrictDropDebouncedReopens: Int
    let udpCircuitOpenPeers: Int
    let udpDecodeBypassedFrames: Int
    let decisionDedupHits: Int
    let policyEvalMicrosP95: Double
    let playbackBlockRateEstimate: Double
    let connRatePerSec: Double
    let blockRatePerSec: Double
    let udpDecodeErrorRatePerSec: Double
    let memoryMB: Double

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
        healthState: String = "healthy",
        retryStormEvents: Int = 0,
        backoffActiveHosts: Int = 0,
        udpDecodeStrictDropCount: Int = 0,
        udpDecodeStrictDropDebouncedReopens: Int = 0,
        udpCircuitOpenPeers: Int = 0,
        udpDecodeBypassedFrames: Int = 0,
        decisionDedupHits: Int = 0,
        policyEvalMicrosP95: Double = 0,
        playbackBlockRateEstimate: Double = 0,
        connRatePerSec: Double = 0,
        blockRatePerSec: Double = 0,
        udpDecodeErrorRatePerSec: Double = 0,
        memoryMB: Double = 0
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
        self.healthState = healthState
        self.retryStormEvents = retryStormEvents
        self.backoffActiveHosts = backoffActiveHosts
        self.udpDecodeStrictDropCount = udpDecodeStrictDropCount
        self.udpDecodeStrictDropDebouncedReopens = udpDecodeStrictDropDebouncedReopens
        self.udpCircuitOpenPeers = udpCircuitOpenPeers
        self.udpDecodeBypassedFrames = udpDecodeBypassedFrames
        self.decisionDedupHits = decisionDedupHits
        self.policyEvalMicrosP95 = policyEvalMicrosP95
        self.playbackBlockRateEstimate = playbackBlockRateEstimate
        self.connRatePerSec = connRatePerSec
        self.blockRatePerSec = blockRatePerSec
        self.udpDecodeErrorRatePerSec = udpDecodeErrorRatePerSec
        self.memoryMB = memoryMB
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
        case healthState
        case retryStormEvents
        case backoffActiveHosts
        case udpDecodeStrictDropCount
        case udpDecodeStrictDropDebouncedReopens
        case udpCircuitOpenPeers
        case udpDecodeBypassedFrames
        case decisionDedupHits
        case policyEvalMicrosP95
        case playbackBlockRateEstimate
        case connRatePerSec
        case blockRatePerSec
        case udpDecodeErrorRatePerSec
        case memoryMB
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case udpDecodeFailOpenCount
        case udpDecodeDebouncedReopens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
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
        healthState = try c.decodeIfPresent(String.self, forKey: .healthState) ?? "healthy"
        retryStormEvents = try c.decodeIfPresent(Int.self, forKey: .retryStormEvents) ?? 0
        backoffActiveHosts = try c.decodeIfPresent(Int.self, forKey: .backoffActiveHosts) ?? 0
        udpDecodeStrictDropCount = try c.decodeIfPresent(Int.self, forKey: .udpDecodeStrictDropCount)
            ?? legacy.decodeIfPresent(Int.self, forKey: .udpDecodeFailOpenCount)
            ?? 0
        udpDecodeStrictDropDebouncedReopens = try c.decodeIfPresent(Int.self, forKey: .udpDecodeStrictDropDebouncedReopens)
            ?? legacy.decodeIfPresent(Int.self, forKey: .udpDecodeDebouncedReopens)
            ?? 0
        udpCircuitOpenPeers = try c.decodeIfPresent(Int.self, forKey: .udpCircuitOpenPeers) ?? 0
        udpDecodeBypassedFrames = try c.decodeIfPresent(Int.self, forKey: .udpDecodeBypassedFrames) ?? 0
        decisionDedupHits = try c.decodeIfPresent(Int.self, forKey: .decisionDedupHits) ?? 0
        policyEvalMicrosP95 = try c.decodeIfPresent(Double.self, forKey: .policyEvalMicrosP95) ?? 0
        playbackBlockRateEstimate = try c.decodeIfPresent(Double.self, forKey: .playbackBlockRateEstimate) ?? 0
        connRatePerSec = try c.decodeIfPresent(Double.self, forKey: .connRatePerSec) ?? 0
        blockRatePerSec = try c.decodeIfPresent(Double.self, forKey: .blockRatePerSec) ?? 0
        udpDecodeErrorRatePerSec = try c.decodeIfPresent(Double.self, forKey: .udpDecodeErrorRatePerSec) ?? 0
        memoryMB = try c.decodeIfPresent(Double.self, forKey: .memoryMB) ?? 0
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
