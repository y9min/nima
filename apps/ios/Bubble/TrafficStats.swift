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
    let udpDecodeModeDetected: Int
    let udpDecodeResyncAttempted: Int
    let udpDecodeResyncSuccess: Int
    let udpDecodeBadLengthHardFail: Int
    let udpDecodeRecoveredStreamContinues: Int
    let udpDecodeCloseAfterFailureThreshold: Int
    let udpActivePeak: Int
    let udpTimeoutRate: Double
    let dnsInflight: Int
    let resolverTimeoutStreakByHost: [String: Int]
    let resolverSwitchCount: Int
    let decoderErrorRate: Double
    let streamCloseReasonCounts: [String: Int]
    let udpQueueDepth: Int
    let udpQueueOldestAgeMs: Int
    let udpQueueP95AgeMs: Int
    let udpReclaimsByReason: [String: Int]
    let udpForcedRejects: Int
    let udpForcedRejectsByReason: [String: Int]
    let degradedState: String
    let degradedTransitions: Int
    let trippedTransitions: Int
    let trippedSecondsTotal: Double
    let badLenRate: Double
    let recentBadLenHardFails: Int
    let tokenBucketDrops: Int
    let streamBlockSuppressed: Int
    let streamBlockTokenDrops: Int
    let admissionRejectsByReason: [String: Int]
    let stateSecondsByMode: [String: Double]
    let reconnectBreakerCooldownRemainingSec: Int
    let reconnectBreakerTrips: Int
    let reconnectSuppressedByBreaker: Int
    let reconnectBreakerBackoffStep: Int
    let maintenanceReclaimBudgetExhaustedCount: Int
    let stormModeActiveSeconds: Double
    let dnsReservedSlotsInUse: Int
    let decoderSoftDiscards: Int
    let decoderErrorDensityCloses: Int
    let attemptedByBucket: [String: Int]
    let blockedByBucket: [String: Int]
    let possibleFalsePositiveRetries: Int
    let blockedSuppressedTCP: Int
    let blockedSuppressedUDP: Int
    let suppressionKeysActive: Int
    let udpSocketReuseHitRate: Double

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
        udpDecodeModeDetected: Int = 0,
        udpDecodeResyncAttempted: Int = 0,
        udpDecodeResyncSuccess: Int = 0,
        udpDecodeBadLengthHardFail: Int = 0,
        udpDecodeRecoveredStreamContinues: Int = 0,
        udpDecodeCloseAfterFailureThreshold: Int = 0,
        udpActivePeak: Int = 0,
        udpTimeoutRate: Double = 0,
        dnsInflight: Int = 0,
        resolverTimeoutStreakByHost: [String: Int] = [:],
        resolverSwitchCount: Int = 0,
        decoderErrorRate: Double = 0,
        streamCloseReasonCounts: [String: Int] = [:],
        udpQueueDepth: Int = 0,
        udpQueueOldestAgeMs: Int = 0,
        udpQueueP95AgeMs: Int = 0,
        udpReclaimsByReason: [String: Int] = [:],
        udpForcedRejects: Int = 0,
        udpForcedRejectsByReason: [String: Int] = [:],
        degradedState: String = "healthy",
        degradedTransitions: Int = 0,
        trippedTransitions: Int = 0,
        trippedSecondsTotal: Double = 0,
        badLenRate: Double = 0,
        recentBadLenHardFails: Int = 0,
        tokenBucketDrops: Int = 0,
        streamBlockSuppressed: Int = 0,
        streamBlockTokenDrops: Int = 0,
        admissionRejectsByReason: [String: Int] = [:],
        stateSecondsByMode: [String: Double] = [:],
        reconnectBreakerCooldownRemainingSec: Int = 0,
        reconnectBreakerTrips: Int = 0,
        reconnectSuppressedByBreaker: Int = 0,
        reconnectBreakerBackoffStep: Int = 0,
        maintenanceReclaimBudgetExhaustedCount: Int = 0,
        stormModeActiveSeconds: Double = 0,
        dnsReservedSlotsInUse: Int = 0,
        decoderSoftDiscards: Int = 0,
        decoderErrorDensityCloses: Int = 0,
        attemptedByBucket: [String: Int] = [:],
        blockedByBucket: [String: Int] = [:],
        possibleFalsePositiveRetries: Int = 0,
        blockedSuppressedTCP: Int = 0,
        blockedSuppressedUDP: Int = 0,
        suppressionKeysActive: Int = 0,
        udpSocketReuseHitRate: Double = 0
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
        self.udpDecodeModeDetected = udpDecodeModeDetected
        self.udpDecodeResyncAttempted = udpDecodeResyncAttempted
        self.udpDecodeResyncSuccess = udpDecodeResyncSuccess
        self.udpDecodeBadLengthHardFail = udpDecodeBadLengthHardFail
        self.udpDecodeRecoveredStreamContinues = udpDecodeRecoveredStreamContinues
        self.udpDecodeCloseAfterFailureThreshold = udpDecodeCloseAfterFailureThreshold
        self.udpActivePeak = udpActivePeak
        self.udpTimeoutRate = udpTimeoutRate
        self.dnsInflight = dnsInflight
        self.resolverTimeoutStreakByHost = resolverTimeoutStreakByHost
        self.resolverSwitchCount = resolverSwitchCount
        self.decoderErrorRate = decoderErrorRate
        self.streamCloseReasonCounts = streamCloseReasonCounts
        self.udpQueueDepth = udpQueueDepth
        self.udpQueueOldestAgeMs = udpQueueOldestAgeMs
        self.udpQueueP95AgeMs = udpQueueP95AgeMs
        self.udpReclaimsByReason = udpReclaimsByReason
        self.udpForcedRejects = udpForcedRejects
        self.udpForcedRejectsByReason = udpForcedRejectsByReason
        self.degradedState = degradedState
        self.degradedTransitions = degradedTransitions
        self.trippedTransitions = trippedTransitions
        self.trippedSecondsTotal = trippedSecondsTotal
        self.badLenRate = badLenRate
        self.recentBadLenHardFails = recentBadLenHardFails
        self.tokenBucketDrops = tokenBucketDrops
        self.streamBlockSuppressed = streamBlockSuppressed
        self.streamBlockTokenDrops = streamBlockTokenDrops
        self.admissionRejectsByReason = admissionRejectsByReason
        self.stateSecondsByMode = stateSecondsByMode
        self.reconnectBreakerCooldownRemainingSec = reconnectBreakerCooldownRemainingSec
        self.reconnectBreakerTrips = reconnectBreakerTrips
        self.reconnectSuppressedByBreaker = reconnectSuppressedByBreaker
        self.reconnectBreakerBackoffStep = reconnectBreakerBackoffStep
        self.maintenanceReclaimBudgetExhaustedCount = maintenanceReclaimBudgetExhaustedCount
        self.stormModeActiveSeconds = stormModeActiveSeconds
        self.dnsReservedSlotsInUse = dnsReservedSlotsInUse
        self.decoderSoftDiscards = decoderSoftDiscards
        self.decoderErrorDensityCloses = decoderErrorDensityCloses
        self.attemptedByBucket = attemptedByBucket
        self.blockedByBucket = blockedByBucket
        self.possibleFalsePositiveRetries = possibleFalsePositiveRetries
        self.blockedSuppressedTCP = blockedSuppressedTCP
        self.blockedSuppressedUDP = blockedSuppressedUDP
        self.suppressionKeysActive = suppressionKeysActive
        self.udpSocketReuseHitRate = udpSocketReuseHitRate
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
        case udpDecodeModeDetected
        case udpDecodeResyncAttempted
        case udpDecodeResyncSuccess
        case udpDecodeBadLengthHardFail
        case udpDecodeRecoveredStreamContinues
        case udpDecodeCloseAfterFailureThreshold
        case udpActivePeak
        case udpTimeoutRate
        case dnsInflight
        case resolverTimeoutStreakByHost
        case resolverSwitchCount
        case decoderErrorRate
        case streamCloseReasonCounts
        case udpQueueDepth
        case udpQueueOldestAgeMs
        case udpQueueP95AgeMs
        case udpReclaimsByReason
        case udpForcedRejects
        case udpForcedRejectsByReason
        case degradedState
        case degradedTransitions
        case trippedTransitions
        case trippedSecondsTotal
        case badLenRate
        case recentBadLenHardFails
        case tokenBucketDrops
        case streamBlockSuppressed
        case streamBlockTokenDrops
        case admissionRejectsByReason
        case stateSecondsByMode
        case reconnectBreakerCooldownRemainingSec
        case reconnectBreakerTrips
        case reconnectSuppressedByBreaker
        case reconnectBreakerBackoffStep
        case maintenanceReclaimBudgetExhaustedCount
        case stormModeActiveSeconds
        case dnsReservedSlotsInUse
        case decoderSoftDiscards
        case decoderErrorDensityCloses
        case attemptedByBucket
        case blockedByBucket
        case possibleFalsePositiveRetries
        case blockedSuppressedTCP
        case blockedSuppressedUDP
        case suppressionKeysActive
        case udpSocketReuseHitRate
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
        udpDecodeModeDetected = try c.decodeIfPresent(Int.self, forKey: .udpDecodeModeDetected) ?? 0
        udpDecodeResyncAttempted = try c.decodeIfPresent(Int.self, forKey: .udpDecodeResyncAttempted) ?? 0
        udpDecodeResyncSuccess = try c.decodeIfPresent(Int.self, forKey: .udpDecodeResyncSuccess) ?? 0
        udpDecodeBadLengthHardFail = try c.decodeIfPresent(Int.self, forKey: .udpDecodeBadLengthHardFail) ?? 0
        udpDecodeRecoveredStreamContinues = try c.decodeIfPresent(Int.self, forKey: .udpDecodeRecoveredStreamContinues) ?? 0
        udpDecodeCloseAfterFailureThreshold = try c.decodeIfPresent(Int.self, forKey: .udpDecodeCloseAfterFailureThreshold) ?? 0
        udpActivePeak = try c.decodeIfPresent(Int.self, forKey: .udpActivePeak) ?? 0
        udpTimeoutRate = try c.decodeIfPresent(Double.self, forKey: .udpTimeoutRate) ?? 0
        dnsInflight = try c.decodeIfPresent(Int.self, forKey: .dnsInflight) ?? 0
        resolverTimeoutStreakByHost = try c.decodeIfPresent([String: Int].self, forKey: .resolverTimeoutStreakByHost) ?? [:]
        resolverSwitchCount = try c.decodeIfPresent(Int.self, forKey: .resolverSwitchCount) ?? 0
        decoderErrorRate = try c.decodeIfPresent(Double.self, forKey: .decoderErrorRate) ?? 0
        streamCloseReasonCounts = try c.decodeIfPresent([String: Int].self, forKey: .streamCloseReasonCounts) ?? [:]
        udpQueueDepth = try c.decodeIfPresent(Int.self, forKey: .udpQueueDepth) ?? 0
        udpQueueOldestAgeMs = try c.decodeIfPresent(Int.self, forKey: .udpQueueOldestAgeMs) ?? 0
        udpQueueP95AgeMs = try c.decodeIfPresent(Int.self, forKey: .udpQueueP95AgeMs) ?? 0
        udpReclaimsByReason = try c.decodeIfPresent([String: Int].self, forKey: .udpReclaimsByReason) ?? [:]
        udpForcedRejects = try c.decodeIfPresent(Int.self, forKey: .udpForcedRejects) ?? 0
        udpForcedRejectsByReason = try c.decodeIfPresent([String: Int].self, forKey: .udpForcedRejectsByReason) ?? [:]
        degradedState = try c.decodeIfPresent(String.self, forKey: .degradedState) ?? "healthy"
        degradedTransitions = try c.decodeIfPresent(Int.self, forKey: .degradedTransitions) ?? 0
        trippedTransitions = try c.decodeIfPresent(Int.self, forKey: .trippedTransitions) ?? 0
        trippedSecondsTotal = try c.decodeIfPresent(Double.self, forKey: .trippedSecondsTotal) ?? 0
        badLenRate = try c.decodeIfPresent(Double.self, forKey: .badLenRate) ?? 0
        recentBadLenHardFails = try c.decodeIfPresent(Int.self, forKey: .recentBadLenHardFails) ?? 0
        tokenBucketDrops = try c.decodeIfPresent(Int.self, forKey: .tokenBucketDrops) ?? 0
        streamBlockSuppressed = try c.decodeIfPresent(Int.self, forKey: .streamBlockSuppressed) ?? 0
        streamBlockTokenDrops = try c.decodeIfPresent(Int.self, forKey: .streamBlockTokenDrops) ?? 0
        admissionRejectsByReason = try c.decodeIfPresent([String: Int].self, forKey: .admissionRejectsByReason) ?? [:]
        stateSecondsByMode = try c.decodeIfPresent([String: Double].self, forKey: .stateSecondsByMode) ?? [:]
        reconnectBreakerCooldownRemainingSec = try c.decodeIfPresent(Int.self, forKey: .reconnectBreakerCooldownRemainingSec) ?? 0
        reconnectBreakerTrips = try c.decodeIfPresent(Int.self, forKey: .reconnectBreakerTrips) ?? 0
        reconnectSuppressedByBreaker = try c.decodeIfPresent(Int.self, forKey: .reconnectSuppressedByBreaker) ?? 0
        reconnectBreakerBackoffStep = try c.decodeIfPresent(Int.self, forKey: .reconnectBreakerBackoffStep) ?? 0
        maintenanceReclaimBudgetExhaustedCount = try c.decodeIfPresent(Int.self, forKey: .maintenanceReclaimBudgetExhaustedCount) ?? 0
        stormModeActiveSeconds = try c.decodeIfPresent(Double.self, forKey: .stormModeActiveSeconds) ?? 0
        dnsReservedSlotsInUse = try c.decodeIfPresent(Int.self, forKey: .dnsReservedSlotsInUse) ?? 0
        decoderSoftDiscards = try c.decodeIfPresent(Int.self, forKey: .decoderSoftDiscards) ?? 0
        decoderErrorDensityCloses = try c.decodeIfPresent(Int.self, forKey: .decoderErrorDensityCloses) ?? 0
        attemptedByBucket = try c.decodeIfPresent([String: Int].self, forKey: .attemptedByBucket) ?? [:]
        blockedByBucket = try c.decodeIfPresent([String: Int].self, forKey: .blockedByBucket) ?? [:]
        possibleFalsePositiveRetries = try c.decodeIfPresent(Int.self, forKey: .possibleFalsePositiveRetries) ?? 0
        blockedSuppressedTCP = try c.decodeIfPresent(Int.self, forKey: .blockedSuppressedTCP) ?? 0
        blockedSuppressedUDP = try c.decodeIfPresent(Int.self, forKey: .blockedSuppressedUDP) ?? 0
        suppressionKeysActive = try c.decodeIfPresent(Int.self, forKey: .suppressionKeysActive) ?? 0
        udpSocketReuseHitRate = try c.decodeIfPresent(Double.self, forKey: .udpSocketReuseHitRate) ?? 0
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
