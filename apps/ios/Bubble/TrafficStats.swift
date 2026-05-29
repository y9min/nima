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
    let tiktokHardeningActions: [String: Int]
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
    let udpDisabledFastRejects: Int
    let udpDisabledFastRejectsSuppressed: Int
    let safeModeDNSOverTCP: Int
    let safeModeDNSFailures: Int
    let safeModeTargetedUDPBlocks: Int
    let safeModeUnknownUDPAllowed: Int
    let safeModeUDPRejectedByPressure: Int
    let safeModeKnownBadUDPCacheHits: Int
    let dnsFastLaneRequests: Int
    let dnsFastLaneResponses: Int
    let dnsFastLaneFailures: Int
    let dnsFastLaneParseFailed: Int
    let dnsFastLaneClose: Int
    let udpNonDNSRejects: Int
    let udpQUICRejects: Int
    let dnsOneShotCloses: Int
    let dnsTimeoutCloses: Int
    let dnsMalformedCloses: Int
    let dnsTrailingFramesDiscarded: Int
    let startupGraceUDPAccepted: Int
    let startupGraceUDPQueued: Int
    let startupGraceUDPRejected: Int
    let hardPressureUDPReclaims: Int
    let tiktokDNSHintsAdded: Int
    let tiktokDNSHintsExpired: Int
    let tiktokDNSHintsActive: Int
    let tiktokUDPBlocksFromDNSHints: Int
    let tcpSNIBlockSuppressed: Int
    let tcpSNIBlockTokenDrops: Int
    let protectedBlockSuppressionKeys: Int
    let udpForwardingMode: String
    let providerLastPhase: String
    let udpClosePhase: String
    let udpDeferredCancels: Int
    let udpGracefulDNSCloses: Int
    let udpCancelWatchdogFires: Int
    let udpStartupSerialModeActive: Bool
    let udpCrashGuardActive: Bool
    let udpCrashGuardReason: String
    let dnsRecoveredOneShotCloses: Int
    let dnsRecoveredFramesDiscarded: Int
    let startupStabilityPhase: String
    let startupProbeCompleted: Bool
    let dnsStartupDrainActive: Bool
    let dnsStartupDrainCloses: Int
    let dnsStartupDrainFramesProcessed: Int
    let earlyReconnectSuppressed: Bool
    let iosSafeModeReason: String
    let tcpEarlySNIBlocks: Int
    let tcpEarlySNIAllows: Int
    let tcpEarlySNIFallbacks: Int

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
        tiktokHardeningActions: [String: Int] = [:],
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
        udpSocketReuseHitRate: Double = 0,
        udpDisabledFastRejects: Int = 0,
        udpDisabledFastRejectsSuppressed: Int = 0,
        safeModeDNSOverTCP: Int = 0,
        safeModeDNSFailures: Int = 0,
        safeModeTargetedUDPBlocks: Int = 0,
        safeModeUnknownUDPAllowed: Int = 0,
        safeModeUDPRejectedByPressure: Int = 0,
        safeModeKnownBadUDPCacheHits: Int = 0,
        dnsFastLaneRequests: Int = 0,
        dnsFastLaneResponses: Int = 0,
        dnsFastLaneFailures: Int = 0,
        dnsFastLaneParseFailed: Int = 0,
        dnsFastLaneClose: Int = 0,
        udpNonDNSRejects: Int = 0,
        udpQUICRejects: Int = 0,
        dnsOneShotCloses: Int = 0,
        dnsTimeoutCloses: Int = 0,
        dnsMalformedCloses: Int = 0,
        dnsTrailingFramesDiscarded: Int = 0,
        startupGraceUDPAccepted: Int = 0,
        startupGraceUDPQueued: Int = 0,
        startupGraceUDPRejected: Int = 0,
        hardPressureUDPReclaims: Int = 0,
        tiktokDNSHintsAdded: Int = 0,
        tiktokDNSHintsExpired: Int = 0,
        tiktokDNSHintsActive: Int = 0,
        tiktokUDPBlocksFromDNSHints: Int = 0,
        tcpSNIBlockSuppressed: Int = 0,
        tcpSNIBlockTokenDrops: Int = 0,
        protectedBlockSuppressionKeys: Int = 0,
        udpForwardingMode: String = "unknown",
        providerLastPhase: String = "unknown",
        udpClosePhase: String = "none",
        udpDeferredCancels: Int = 0,
        udpGracefulDNSCloses: Int = 0,
        udpCancelWatchdogFires: Int = 0,
        udpStartupSerialModeActive: Bool = false,
        udpCrashGuardActive: Bool = false,
        udpCrashGuardReason: String = "",
        dnsRecoveredOneShotCloses: Int = 0,
        dnsRecoveredFramesDiscarded: Int = 0,
        startupStabilityPhase: String = "unknown",
        startupProbeCompleted: Bool = false,
        dnsStartupDrainActive: Bool = false,
        dnsStartupDrainCloses: Int = 0,
        dnsStartupDrainFramesProcessed: Int = 0,
        earlyReconnectSuppressed: Bool = false,
        iosSafeModeReason: String = "",
        tcpEarlySNIBlocks: Int = 0,
        tcpEarlySNIAllows: Int = 0,
        tcpEarlySNIFallbacks: Int = 0
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
        self.tiktokHardeningActions = tiktokHardeningActions
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
        self.udpDisabledFastRejects = udpDisabledFastRejects
        self.udpDisabledFastRejectsSuppressed = udpDisabledFastRejectsSuppressed
        self.safeModeDNSOverTCP = safeModeDNSOverTCP
        self.safeModeDNSFailures = safeModeDNSFailures
        self.safeModeTargetedUDPBlocks = safeModeTargetedUDPBlocks
        self.safeModeUnknownUDPAllowed = safeModeUnknownUDPAllowed
        self.safeModeUDPRejectedByPressure = safeModeUDPRejectedByPressure
        self.safeModeKnownBadUDPCacheHits = safeModeKnownBadUDPCacheHits
        self.dnsFastLaneRequests = dnsFastLaneRequests
        self.dnsFastLaneResponses = dnsFastLaneResponses
        self.dnsFastLaneFailures = dnsFastLaneFailures
        self.dnsFastLaneParseFailed = dnsFastLaneParseFailed
        self.dnsFastLaneClose = dnsFastLaneClose
        self.udpNonDNSRejects = udpNonDNSRejects
        self.udpQUICRejects = udpQUICRejects
        self.dnsOneShotCloses = dnsOneShotCloses
        self.dnsTimeoutCloses = dnsTimeoutCloses
        self.dnsMalformedCloses = dnsMalformedCloses
        self.dnsTrailingFramesDiscarded = dnsTrailingFramesDiscarded
        self.startupGraceUDPAccepted = startupGraceUDPAccepted
        self.startupGraceUDPQueued = startupGraceUDPQueued
        self.startupGraceUDPRejected = startupGraceUDPRejected
        self.hardPressureUDPReclaims = hardPressureUDPReclaims
        self.tiktokDNSHintsAdded = tiktokDNSHintsAdded
        self.tiktokDNSHintsExpired = tiktokDNSHintsExpired
        self.tiktokDNSHintsActive = tiktokDNSHintsActive
        self.tiktokUDPBlocksFromDNSHints = tiktokUDPBlocksFromDNSHints
        self.tcpSNIBlockSuppressed = tcpSNIBlockSuppressed
        self.tcpSNIBlockTokenDrops = tcpSNIBlockTokenDrops
        self.protectedBlockSuppressionKeys = protectedBlockSuppressionKeys
        self.udpForwardingMode = udpForwardingMode
        self.providerLastPhase = providerLastPhase
        self.udpClosePhase = udpClosePhase
        self.udpDeferredCancels = udpDeferredCancels
        self.udpGracefulDNSCloses = udpGracefulDNSCloses
        self.udpCancelWatchdogFires = udpCancelWatchdogFires
        self.udpStartupSerialModeActive = udpStartupSerialModeActive
        self.udpCrashGuardActive = udpCrashGuardActive
        self.udpCrashGuardReason = udpCrashGuardReason
        self.dnsRecoveredOneShotCloses = dnsRecoveredOneShotCloses
        self.dnsRecoveredFramesDiscarded = dnsRecoveredFramesDiscarded
        self.startupStabilityPhase = startupStabilityPhase
        self.startupProbeCompleted = startupProbeCompleted
        self.dnsStartupDrainActive = dnsStartupDrainActive
        self.dnsStartupDrainCloses = dnsStartupDrainCloses
        self.dnsStartupDrainFramesProcessed = dnsStartupDrainFramesProcessed
        self.earlyReconnectSuppressed = earlyReconnectSuppressed
        self.iosSafeModeReason = iosSafeModeReason
        self.tcpEarlySNIBlocks = tcpEarlySNIBlocks
        self.tcpEarlySNIAllows = tcpEarlySNIAllows
        self.tcpEarlySNIFallbacks = tcpEarlySNIFallbacks
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
        case tiktokHardeningActions
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
        case udpDisabledFastRejects
        case udpDisabledFastRejectsSuppressed
        case safeModeDNSOverTCP
        case safeModeDNSFailures
        case safeModeTargetedUDPBlocks
        case safeModeUnknownUDPAllowed
        case safeModeUDPRejectedByPressure
        case safeModeKnownBadUDPCacheHits
        case dnsFastLaneRequests
        case dnsFastLaneResponses
        case dnsFastLaneFailures
        case dnsFastLaneParseFailed
        case dnsFastLaneClose
        case udpNonDNSRejects
        case udpQUICRejects
        case dnsOneShotCloses
        case dnsTimeoutCloses
        case dnsMalformedCloses
        case dnsTrailingFramesDiscarded
        case startupGraceUDPAccepted
        case startupGraceUDPQueued
        case startupGraceUDPRejected
        case hardPressureUDPReclaims
        case tiktokDNSHintsAdded
        case tiktokDNSHintsExpired
        case tiktokDNSHintsActive
        case tiktokUDPBlocksFromDNSHints
        case tcpSNIBlockSuppressed
        case tcpSNIBlockTokenDrops
        case protectedBlockSuppressionKeys
        case udpForwardingMode
        case providerLastPhase
        case udpClosePhase
        case udpDeferredCancels
        case udpGracefulDNSCloses
        case udpCancelWatchdogFires
        case udpStartupSerialModeActive
        case udpCrashGuardActive
        case udpCrashGuardReason
        case dnsRecoveredOneShotCloses
        case dnsRecoveredFramesDiscarded
        case startupStabilityPhase
        case startupProbeCompleted
        case dnsStartupDrainActive
        case dnsStartupDrainCloses
        case dnsStartupDrainFramesProcessed
        case earlyReconnectSuppressed
        case iosSafeModeReason
        case tcpEarlySNIBlocks
        case tcpEarlySNIAllows
        case tcpEarlySNIFallbacks
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
        tiktokHardeningActions = try c.decodeIfPresent([String: Int].self, forKey: .tiktokHardeningActions) ?? [:]
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
        udpDisabledFastRejects = try c.decodeIfPresent(Int.self, forKey: .udpDisabledFastRejects) ?? 0
        udpDisabledFastRejectsSuppressed = try c.decodeIfPresent(Int.self, forKey: .udpDisabledFastRejectsSuppressed) ?? 0
        safeModeDNSOverTCP = try c.decodeIfPresent(Int.self, forKey: .safeModeDNSOverTCP) ?? 0
        safeModeDNSFailures = try c.decodeIfPresent(Int.self, forKey: .safeModeDNSFailures) ?? 0
        safeModeTargetedUDPBlocks = try c.decodeIfPresent(Int.self, forKey: .safeModeTargetedUDPBlocks) ?? 0
        safeModeUnknownUDPAllowed = try c.decodeIfPresent(Int.self, forKey: .safeModeUnknownUDPAllowed) ?? 0
        safeModeUDPRejectedByPressure = try c.decodeIfPresent(Int.self, forKey: .safeModeUDPRejectedByPressure) ?? 0
        safeModeKnownBadUDPCacheHits = try c.decodeIfPresent(Int.self, forKey: .safeModeKnownBadUDPCacheHits) ?? 0
        dnsFastLaneRequests = try c.decodeIfPresent(Int.self, forKey: .dnsFastLaneRequests) ?? 0
        dnsFastLaneResponses = try c.decodeIfPresent(Int.self, forKey: .dnsFastLaneResponses) ?? 0
        dnsFastLaneFailures = try c.decodeIfPresent(Int.self, forKey: .dnsFastLaneFailures) ?? 0
        dnsFastLaneParseFailed = try c.decodeIfPresent(Int.self, forKey: .dnsFastLaneParseFailed) ?? 0
        dnsFastLaneClose = try c.decodeIfPresent(Int.self, forKey: .dnsFastLaneClose) ?? 0
        udpNonDNSRejects = try c.decodeIfPresent(Int.self, forKey: .udpNonDNSRejects) ?? 0
        udpQUICRejects = try c.decodeIfPresent(Int.self, forKey: .udpQUICRejects) ?? 0
        dnsOneShotCloses = try c.decodeIfPresent(Int.self, forKey: .dnsOneShotCloses) ?? 0
        dnsTimeoutCloses = try c.decodeIfPresent(Int.self, forKey: .dnsTimeoutCloses) ?? 0
        dnsMalformedCloses = try c.decodeIfPresent(Int.self, forKey: .dnsMalformedCloses) ?? 0
        dnsTrailingFramesDiscarded = try c.decodeIfPresent(Int.self, forKey: .dnsTrailingFramesDiscarded) ?? 0
        startupGraceUDPAccepted = try c.decodeIfPresent(Int.self, forKey: .startupGraceUDPAccepted) ?? 0
        startupGraceUDPQueued = try c.decodeIfPresent(Int.self, forKey: .startupGraceUDPQueued) ?? 0
        startupGraceUDPRejected = try c.decodeIfPresent(Int.self, forKey: .startupGraceUDPRejected) ?? 0
        hardPressureUDPReclaims = try c.decodeIfPresent(Int.self, forKey: .hardPressureUDPReclaims) ?? 0
        tiktokDNSHintsAdded = try c.decodeIfPresent(Int.self, forKey: .tiktokDNSHintsAdded) ?? 0
        tiktokDNSHintsExpired = try c.decodeIfPresent(Int.self, forKey: .tiktokDNSHintsExpired) ?? 0
        tiktokDNSHintsActive = try c.decodeIfPresent(Int.self, forKey: .tiktokDNSHintsActive) ?? 0
        tiktokUDPBlocksFromDNSHints = try c.decodeIfPresent(Int.self, forKey: .tiktokUDPBlocksFromDNSHints) ?? 0
        tcpSNIBlockSuppressed = try c.decodeIfPresent(Int.self, forKey: .tcpSNIBlockSuppressed) ?? 0
        tcpSNIBlockTokenDrops = try c.decodeIfPresent(Int.self, forKey: .tcpSNIBlockTokenDrops) ?? 0
        protectedBlockSuppressionKeys = try c.decodeIfPresent(Int.self, forKey: .protectedBlockSuppressionKeys) ?? suppressionKeysActive
        udpForwardingMode = try c.decodeIfPresent(String.self, forKey: .udpForwardingMode) ?? "unknown"
        providerLastPhase = try c.decodeIfPresent(String.self, forKey: .providerLastPhase) ?? "unknown"
        udpClosePhase = try c.decodeIfPresent(String.self, forKey: .udpClosePhase) ?? "none"
        udpDeferredCancels = try c.decodeIfPresent(Int.self, forKey: .udpDeferredCancels) ?? 0
        udpGracefulDNSCloses = try c.decodeIfPresent(Int.self, forKey: .udpGracefulDNSCloses) ?? 0
        udpCancelWatchdogFires = try c.decodeIfPresent(Int.self, forKey: .udpCancelWatchdogFires) ?? 0
        udpStartupSerialModeActive = try c.decodeIfPresent(Bool.self, forKey: .udpStartupSerialModeActive) ?? false
        udpCrashGuardActive = try c.decodeIfPresent(Bool.self, forKey: .udpCrashGuardActive) ?? false
        udpCrashGuardReason = try c.decodeIfPresent(String.self, forKey: .udpCrashGuardReason) ?? ""
        dnsRecoveredOneShotCloses = try c.decodeIfPresent(Int.self, forKey: .dnsRecoveredOneShotCloses) ?? 0
        dnsRecoveredFramesDiscarded = try c.decodeIfPresent(Int.self, forKey: .dnsRecoveredFramesDiscarded) ?? 0
        startupStabilityPhase = try c.decodeIfPresent(String.self, forKey: .startupStabilityPhase) ?? "unknown"
        startupProbeCompleted = try c.decodeIfPresent(Bool.self, forKey: .startupProbeCompleted) ?? false
        dnsStartupDrainActive = try c.decodeIfPresent(Bool.self, forKey: .dnsStartupDrainActive) ?? false
        dnsStartupDrainCloses = try c.decodeIfPresent(Int.self, forKey: .dnsStartupDrainCloses) ?? 0
        dnsStartupDrainFramesProcessed = try c.decodeIfPresent(Int.self, forKey: .dnsStartupDrainFramesProcessed) ?? 0
        earlyReconnectSuppressed = try c.decodeIfPresent(Bool.self, forKey: .earlyReconnectSuppressed) ?? false
        iosSafeModeReason = try c.decodeIfPresent(String.self, forKey: .iosSafeModeReason) ?? ""
        tcpEarlySNIBlocks = try c.decodeIfPresent(Int.self, forKey: .tcpEarlySNIBlocks) ?? 0
        tcpEarlySNIAllows = try c.decodeIfPresent(Int.self, forKey: .tcpEarlySNIAllows) ?? 0
        tcpEarlySNIFallbacks = try c.decodeIfPresent(Int.self, forKey: .tcpEarlySNIFallbacks) ?? 0
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
