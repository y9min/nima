import Foundation
import Network
import os

enum TunnelLifecycleDiagnostics {
    struct StopAttributionSnapshot {
        let eventStart: TimeInterval
        let appRequestedTS: TimeInterval
        let osStopTS: TimeInterval
        let osStopRaw: String
        let osStopName: String
        let tun2socksExitTS: TimeInterval
        let tun2socksExitCode: Int?
        let providerDeinitTS: TimeInterval
        let statusDropTS: TimeInterval
    }

    struct StopAttributionDecision {
        let final: String
        let confidence: String
        let evidence: String
        let signalOrder: String
    }

    static func resolveStopAttribution(snapshot: StopAttributionSnapshot, nowTS: TimeInterval, windowSeconds: TimeInterval) -> StopAttributionDecision? {
        if snapshot.eventStart > 0, nowTS - snapshot.eventStart < windowSeconds {
            return nil
        }

        let appIntentFresh: Bool
        if snapshot.appRequestedTS <= 0 {
            appIntentFresh = false
        } else if snapshot.eventStart > 0 {
            appIntentFresh = abs(snapshot.appRequestedTS - snapshot.eventStart) <= 20
        } else {
            appIntentFresh = true
        }

        let final: String
        let confidence: String
        if appIntentFresh {
            final = "app_requested_stop"
            confidence = "high"
        } else if snapshot.osStopTS > 0 {
            final = snapshot.osStopRaw.isEmpty ? "os_stop_reason_unknown" : "os_stop_reason_\(snapshot.osStopRaw)"
            confidence = "high"
        } else if snapshot.tun2socksExitTS > 0 {
            final = "tun2socks_exit"
            confidence = "high"
        } else if snapshot.providerDeinitTS > 0 {
            final = "provider_deinit_without_stop"
            confidence = "medium"
        } else if snapshot.statusDropTS > 0 {
            final = "status_drop_without_stop_callback"
            confidence = "low"
        } else {
            final = "unknown"
            confidence = "low"
        }

        var entries: [(String, TimeInterval)] = []
        if appIntentFresh { entries.append(("app_requested_stop", snapshot.appRequestedTS)) }
        if snapshot.osStopTS > 0 { entries.append(("os_stop_reason", snapshot.osStopTS)) }
        if snapshot.tun2socksExitTS > 0 { entries.append(("tun2socks_exit", snapshot.tun2socksExitTS)) }
        if snapshot.providerDeinitTS > 0 { entries.append(("provider_deinit_without_stop", snapshot.providerDeinitTS)) }
        if snapshot.statusDropTS > 0 { entries.append(("status_drop_without_stop_callback", snapshot.statusDropTS)) }
        entries.sort { $0.1 < $1.1 }
        let baseTS = snapshot.eventStart > 0 ? snapshot.eventStart : entries.first?.1 ?? nowTS
        let signalOrder = entries.map { name, ts in
            let deltaMS = Int(max(0, (ts - baseTS) * 1000))
            return "\(name)+\(deltaMS)ms"
        }.joined(separator: " -> ")

        var evidence: [String] = []
        if !snapshot.osStopRaw.isEmpty || !snapshot.osStopName.isEmpty {
            evidence.append("ne_stop_reason_raw=\(snapshot.osStopRaw.isEmpty ? "unknown" : snapshot.osStopRaw)")
            evidence.append("ne_stop_reason_name=\(snapshot.osStopName.isEmpty ? "unknown" : snapshot.osStopName)")
        }
        if let code = snapshot.tun2socksExitCode {
            evidence.append("tun2socks_exit_code=\(code)")
        }
        if !signalOrder.isEmpty {
            evidence.append("signal_order=\(signalOrder)")
        }
        let terminalObserved = snapshot.osStopTS > 0 || snapshot.tun2socksExitTS > 0 || snapshot.providerDeinitTS > 0
        evidence.append("terminal_callback_observed=\(terminalObserved)")
        if !terminalObserved, snapshot.eventStart > 0 {
            let holdElapsedMS = Int(max(0, (nowTS - snapshot.eventStart) * 1000))
            evidence.append("hold_window_elapsed_ms=\(holdElapsedMS)")
        }

        return StopAttributionDecision(
            final: final,
            confidence: confidence,
            evidence: evidence.joined(separator: ";"),
            signalOrder: signalOrder
        )
    }

    static func dropCadenceSeconds(from timestamps: [TimeInterval], nowTS: TimeInterval, windowSeconds: TimeInterval) -> TimeInterval? {
        let recent = timestamps
            .filter { $0 > 0 && nowTS - $0 <= windowSeconds }
            .sorted()
        guard recent.count >= 2 else { return nil }
        let intervals = zip(recent.dropFirst(), recent).map { max(0, $0 - $1) }
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        return sorted[sorted.count / 2]
    }

    static func isExternalKillSignature(
        finalCause: String,
        evidence: String,
        diagnosticHoldSeconds: TimeInterval,
        dropCadenceSeconds: TimeInterval?
    ) -> Bool {
        guard finalCause == "status_drop_without_stop_callback" else { return false }
        guard diagnosticHoldSeconds >= BubbleConstants.vpnLifecycleDiagnosticHoldDefaultSeconds else { return false }
        guard evidence.contains("terminal_callback_observed=false") else { return false }
        guard let cadence = dropCadenceSeconds else { return false }
        return cadence >= BubbleConstants.vpnLifecycleExternalKillCadenceMinSeconds &&
            cadence <= BubbleConstants.vpnLifecycleExternalKillCadenceMaxSeconds
    }

    static func externalKillReconnectGate(
        attemptTimestamps: [TimeInterval],
        nowTS: TimeInterval,
        windowSeconds: TimeInterval = BubbleConstants.vpnLifecycleExternalKillReconnectWindowSeconds,
        maxAttempts: Int = BubbleConstants.vpnLifecycleExternalKillReconnectMaxAttemptsPerWindow
    ) -> (allowed: Bool, attemptsInWindow: Int, nextAllowedTS: TimeInterval?) {
        let attempts = attemptTimestamps
            .filter { $0 > 0 && nowTS - $0 <= windowSeconds }
            .sorted()
        guard attempts.count < maxAttempts else {
            return (false, attempts.count, (attempts.first ?? nowTS) + windowSeconds)
        }
        return (true, attempts.count, nil)
    }

    static func reconnectBreakerShortUnknownDropDecision(
        recentDropTimestamps: [TimeInterval],
        nowTS: TimeInterval,
        shortLivedSession: Bool,
        finalCause: String,
        windowSeconds: TimeInterval = BubbleConstants.reconnectBreakerShortUnknownDropWindowSeconds,
        threshold: Int = BubbleConstants.reconnectBreakerShortUnknownDropThreshold
    ) -> (shouldSuppress: Bool, retainedTimestamps: [TimeInterval]) {
        var retained = recentDropTimestamps
            .filter { $0 > 0 && nowTS - $0 <= windowSeconds }
            .sorted()
        guard shortLivedSession, finalCause == "status_drop_without_stop_callback" else {
            return (false, retained)
        }
        retained.append(nowTS)
        retained.sort()
        return (retained.count >= threshold, retained)
    }
}

// MARK: - Connection Filter Protocol

protocol ConnectionFilter {
    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision
    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision
    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision
}

struct InstagramMediaHintCounterSnapshot {
    let added: Int
    let expired: Int
    let active: Int
    let blocks: Int

    static let zero = InstagramMediaHintCounterSnapshot(added: 0, expired: 0, active: 0, blocks: 0)
}

struct TikTokIPHintCounterSnapshot {
    let added: Int
    let expired: Int
    let active: Int
    let blocks: Int

    static let zero = TikTokIPHintCounterSnapshot(added: 0, expired: 0, active: 0, blocks: 0)
}

protocol StreamObservationRecorder {
    func recordBlockedStream(host: String, sni: String?, port: UInt16, decision: PolicyDecision, bytesDown: Int, now: Date)
}

protocol InstagramMediaHintReporting {
    func instagramMediaHintCounterSnapshot(now: Date) -> InstagramMediaHintCounterSnapshot
}

protocol TikTokIPHintReporting {
    func tiktokIPHintCounterSnapshot(now: Date) -> TikTokIPHintCounterSnapshot
}

enum PolicyAction: String, Codable {
    case allow
    case blockNow = "block_now"
    case blockAfterBytes = "block_after_bytes"
    case shadowAllow = "shadow_allow"
}

enum TrafficClass: String, Codable, CaseIterable {
    case generic
    case tiktok
    case instagram
    case x
    case unknown
}

struct ClassifiedFlow {
    let trafficClass: TrafficClass
    let confidence: Double
    let reason: String
}

struct AppClassManifest {
    let appId: TrafficClass
    let hostTokens: [String]
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
    let appStrategy: String
    let trafficClass: TrafficClass

    static func allow(
        reason: String,
        classification: FlowClassification,
        toggles: [String: Bool],
        policyVersion: Int,
        appStrategy: String,
        trafficClass: TrafficClass
    ) -> PolicyDecision {
        PolicyDecision(
            action: .allow,
            blockAfterBytes: nil,
            classification: classification,
            reason: reason,
            toggleSnapshot: toggles,
            policyVersion: policyVersion,
            intendedAction: nil,
            appStrategy: appStrategy,
            trafficClass: trafficClass
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

final class SOCKSProxyServer: TikTokIPHintReporting {
    enum UDPForwardingMode: String {
        case selectiveSafeMode = "selective_safe_mode"
        case nativeForwarding = "native_forwarding"
        case disabledFastReject = "disabled_fast_reject"
    }

    struct SOCKSRequestMetadata: Equatable {
        let command: UInt8
        let atyp: UInt8
        let host: String
        let port: UInt16
        let headerEndOffset: Int
        let requestTail: Data
    }

    enum UDPAdmissionDecision {
        case accept
        case queue
        case reject(reason: String)
    }

    enum SelectiveSafeModeUDPDecision: Equatable {
        case dnsFastLane
        case reject(reason: String)
    }

    enum UDPControlClosePhase: String {
        case open
        case graceBlocked = "grace_close_blocked"
        case retiring
        case cancelScheduled = "cancel_scheduled"
        case cancelled
        case drainScheduled = "drain_scheduled"
    }

    struct UDPControlClosePlan: Equatable {
        let phase: UDPControlClosePhase
        let sendWithConnectionCompletion: Bool
        let discardTrailingFrames: Bool
        let cancelDelaySeconds: TimeInterval
        let deferDrainUntilCancel: Bool
        let cancelAsWatchdog: Bool
    }

    struct DNSFrameDiscardPlan: Equatable {
        let trailingDiscarded: Int
        let recoveredDiscarded: Int
        let recoveredOneShotClose: Bool
    }

    enum ExtensionPressureLevel: String {
        case normal
        case soft
        case hard
        case critical

        var rank: Int {
            switch self {
            case .normal: return 0
            case .soft: return 1
            case .hard: return 2
            case .critical: return 3
            }
        }
    }

    private enum StartupGraceUDPAdmissionOutcome {
        case accepted
        case queued
        case rejected
    }

    private enum DNSFastLaneConsumeOutcome {
        case waitingForMore
        case consumed
    }

    enum DNSFastLaneDecodeResult {
        case frame(UDPControlFrame, trailingFrameCount: Int)
        case needMoreBytes
        case failed(UDPControlDecoderError)
    }

    private enum RawUDPControlPayloadStatus {
        case parseable(kind: String)
        case needMoreBytes(kind: String)
        case notRaw
    }

    struct ExtensionPressureSnapshot {
        let activeUDP: Int
        let queuedUDP: Int
        let degradedState: String
        let pressureLevel: ExtensionPressureLevel
        let lastUDPClosePhase: String
        let dnsStartupDrainActive: Bool
        let dnsStartupDrainCloses: Int
        let dnsStartupDrainFramesProcessed: Int
        let dnsFastLaneRequests: Int
        let dnsFastLaneResponses: Int
        let dnsFastLaneFailures: Int
        let dnsFastLaneParseFailed: Int
        let dnsFastLaneClose: Int
        let dnsFastLaneDisabled: Bool
        let dnsFastLaneDisabledReason: String
        let udpNonDNSRejects: Int
        let udpQUICRejects: Int
    }

    private var listener: NWListener?
    private let filter: ConnectionFilter
    private let queue = DispatchQueue(label: "com.yamin.nimademo.socks5", qos: .userInitiated)
    private let queueSpecificKey = DispatchSpecificKey<Bool>()
    private let log = TunnelLogger.shared
    private var connectionCount = 0      // total connections ever (used as ID)
    private var activeConnectionCount = 0 // currently open connections

    // Thread-safe actual port (written on queue, read from outside)
    private let _actualPort = OSAllocatedUnfairLock(initialState: UInt16(0))
    var actualPort: UInt16 {
        _actualPort.withLock { $0 }
    }
    var currentActiveUDPStreams: Int { syncOnQueue { activeUDPStreams } }
    var currentQueuedUDPStreams: Int { syncOnQueue { pendingUDPControlQueue.count } }
    var currentPressureSnapshot: ExtensionPressureSnapshot {
        syncOnQueue {
            ExtensionPressureSnapshot(
                activeUDP: activeUDPStreams,
                queuedUDP: pendingUDPControlQueue.count,
                degradedState: degradedState.rawValue,
                pressureLevel: extensionPressureLevel,
                lastUDPClosePhase: lastUDPClosePhase.rawValue,
                dnsStartupDrainActive: isDNSStartupDrainActive(),
                dnsStartupDrainCloses: dnsStartupDrainCloses,
                dnsStartupDrainFramesProcessed: dnsStartupDrainFramesProcessed,
                dnsFastLaneRequests: dnsFastLaneRequests,
                dnsFastLaneResponses: dnsFastLaneResponses,
                dnsFastLaneFailures: dnsFastLaneFailures,
                dnsFastLaneParseFailed: dnsFastLaneParseFailed,
                dnsFastLaneClose: dnsFastLaneClose,
                dnsFastLaneDisabled: dnsFastLaneDisabledForSession,
                dnsFastLaneDisabledReason: dnsFastLaneDisabledReason,
                udpNonDNSRejects: udpNonDNSRejects,
                udpQUICRejects: udpQUICRejects
            )
        }
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
    private var udpDecodeModeDetected = 0
    private var udpDecodeResyncAttempted = 0
    private var udpDecodeResyncSuccess = 0
    private var udpDecodeBadLengthHardFail = 0
    private var udpDecodeRecoveredStreamContinues = 0
    private var udpDecodeCloseAfterFailureThreshold = 0
    private var udpActivePeak = 0
    private var udpTimeoutCount = 0
    private var dnsInflight = 0
    private var dnsDedupHits = 0
    private var resolverSwitchCount = 0
    private var lastResolverSwitchAt = Date.distantPast
    private var currentPreferredResolver = "8.8.8.8"
    private var decoderErrorCount = 0
    private var streamCloseReasonCounts: [String: Int] = [:]
    private var tiktokHardeningActions: [String: Int] = [:]
    private var pendingUDPControlQueue: [PendingUDPControl] = []
    private var queuedUDPControlIDs: Set<Int> = []
    private var udpStreamsByID: [Int: UDPStreamState] = [:]
    private var inflightDNSRequests: [String: InflightDNSRequest] = [:]
    private var resolverHealth: [String: ResolverHealth] = [
        "8.8.8.8": ResolverHealth(),
        "1.1.1.1": ResolverHealth(),
    ]
    private var recentClassHintsByHost: [String: (trafficClass: TrafficClass, confidence: Double, ts: Date)] = [:]
    private var requeueChurnCount = 0
    private var queueInvariantViolationCount = 0
    private var attemptedByBucket: [String: Int] = [:]
    private var blockedByBucket: [String: Int] = [:]
    private var possibleFalsePositiveRetries = 0
    private var recentBlockedByHost: [String: Date] = [:]
    private var blockedSuppressedTCP = 0
    private var blockedSuppressedUDP = 0
    private var blockedSuppression: [String: BlockSuppressionState] = [:]
    private var udpDisabledRejectLogStateByDestination: [String: UDPDisabledRejectLogState] = [:]
    private var udpDisabledFastRejects = 0
    private var udpDisabledFastRejectsSuppressed = 0
    private var safeModeDNSOverTCP = 0
    private var safeModeDNSFailures = 0
    private var safeModeTargetedUDPBlocks = 0
    private var safeModeUnknownUDPAllowed = 0
    private var safeModeUDPRejectedByPressure = 0
    private var safeModeKnownBadUDPCacheHits = 0
    private var dnsFastLaneRequests = 0
    private var dnsFastLaneResponses = 0
    private var dnsFastLaneFailures = 0
    private var dnsFastLaneParseFailed = 0
    private var dnsFastLaneClose = 0
    private var dnsFastLaneParseFailureSummaryWindowStartedAt: Date?
    private var dnsFastLaneParseFailureSummaryCount = 0
    private var dnsFastLaneParseFailureSummaryByDetail: [String: Int] = [:]
    private var dnsFastLaneParseFailureSummaryWorkItem: DispatchWorkItem?
    private var dnsFastLaneParseFailureTimestamps: [Date] = []
    private var dnsFastLaneDisabledForSession = false
    private var dnsFastLaneDisabledReason = ""
    private var udpNonDNSRejects = 0
    private var udpQUICRejects = 0
    private var dnsOneShotCloses = 0
    private var dnsTimeoutCloses = 0
    private var dnsMalformedCloses = 0
    private var dnsTrailingFramesDiscarded = 0
    private var dnsRecoveredOneShotCloses = 0
    private var dnsRecoveredFramesDiscarded = 0
    private var dnsStartupDrainCloses = 0
    private var dnsStartupDrainFramesProcessed = 0
    private var udpDeferredCancels = 0
    private var udpGracefulDNSCloses = 0
    private var udpCancelWatchdogFires = 0
    private var udpCloseFinalizationsInFlight = 0
    private var lastUDPClosePhase = UDPControlClosePhase.open
    private var startupGraceUDPAccepted = 0
    private var startupGraceUDPQueued = 0
    private var startupGraceUDPRejected = 0
    private var hardPressureUDPReclaims = 0
    private var tiktokDNSHintsAdded = 0
    private var tiktokDNSHintsExpired = 0
    private var tiktokUDPBlocksFromDNSHints = 0
    private var tiktokIPHintsAdded = 0
    private var tiktokIPHintsExpired = 0
    private var tiktokIPHintBlocks = 0
    private var instagramDNSHintsAdded = 0
    private var instagramDNSHintsExpired = 0
    private var instagramUDPBlocksFromDNSHints = 0
    private var dnsHintsByIP: [String: DNSIPHint] = [:]
    private var tiktokIPHintsByKey: [String: TikTokIPHint] = [:]
    private var recentTikTokVideoBlockEvents: [Date] = []
    private var recentUnknownTikTokDirectIPAttemptsByKey: [String: [Date]] = [:]
    private var knownBadUDPCache: [String: KnownBadUDPCacheEntry] = [:]
    private var tcpSNIBlockSuppressed = 0
    private var tcpSNIBlockTokenDrops = 0
    private var tcpEarlySNIBlocks = 0
    private var tcpEarlySNIAllows = 0
    private var tcpEarlySNIFallbacks = 0
    private var protectedBlockFailOpenUntil = Date.distantPast
    private var protectedBlockFailOpenActivations = 0
    private var protectedBlockFailOpenAllows = 0
    private var recentFailOpenCandidateBlockEvents: [Date] = []
    private let blockSuppressionCooldown: TimeInterval = BubbleConstants.blockSuppressionCooldown
    private let aggressiveBlockSuppressionCooldown: TimeInterval = BubbleConstants.aggressiveBlockSuppressionCooldown
    private let blockSuppressionLogCap = 3
    private let blockSuppressionSummaryEvery = 250
    private var statsTimer: DispatchSourceTimer?
    private var udpSweepTimer: DispatchSourceTimer?
    private var degradedState: TransportDegradedState = .healthy
    private var degradedTransitions = 0
    private var udpForcedRejects = 0
    private var udpReclaimsByReason: [String: Int] = [:]
    private var degradedEnteredAt = Date.distantPast
    private var trippedEnteredAt = Date.distantPast
    private var trippedTransitions = 0
    private var trippedSecondsTotal: TimeInterval = 0
    private var tokenBucketDrops = 0
    private var streamBlockSuppressed = 0
    private var streamBlockTokenDrops = 0
    private var tokenBucketsByHost: [String: TokenBucketState] = [:]
    private var emergencyReclaimTimestamps: [Date] = []
    private var lastEmergencyReclaimAt = Date.distantPast
    private var recentProtectedBlockEvents: [Date] = []
    private var recentBadLenHardFailTimestamps: [Date] = []
    private var admissionRejectsByReason: [String: Int] = [:]
    private var perClassAdmissionControllers: [TrafficClass: UDPAdmissionController] = [:]
    private var classTransportStateByClass: [TrafficClass: ClassTransportState] = [:]
    private let classManifests: [AppClassManifest] = [
        AppClassManifest(appId: .tiktok, hostTokens: ["tiktok", "musical.ly", "byte", "ibytedtos", "tiktokcdn"]),
        AppClassManifest(appId: .instagram, hostTokens: ["instagram", "fbcdn", "facebook", "fbvideo", "cdninstagram"]),
        AppClassManifest(appId: .x, hostTokens: ["x.com", "twitter", "twimg", "t.co"]),
    ]
    private var stateSecondsByMode: [String: TimeInterval] = [:]
    private var lastStateSampleAt = Date()
    private var degradedStableSince: Date?
    private var recoveringEnteredAt = Date.distantPast
    private var severeSignalSince: Date?
    private var lastStuckProcessingReclaimAt = Date.distantPast
    private var maintenanceReclaimTimestamps: [Date] = []
    private var maintenanceReclaimCooldownUntil = Date.distantPast
    private var maintenanceReclaimBudgetExhaustedCount = 0
    private var reclaimCooldownUntilByReason: [String: Date] = [:]
    private var stormModeActiveSince: Date?
    private var stormModeActiveSecondsTotal: TimeInterval = 0
    private var decoderSoftDiscards = 0
    private var decoderErrorDensityCloses = 0
    private let stabilityFirstModeEnabled: Bool
    private var protectionStartupGraceUntil = Date.distantPast
    private var recoveryGraceUntil = Date.distantPast
    private var lastPressureDiagnosticsAt = Date.distantPast
    private var extensionPressureLevel: ExtensionPressureLevel = .normal
    private var extensionPressureDiagnosticsMutedUntil = Date.distantPast
    private var extensionPressureRecoveryNotBefore = Date.distantPast
    private var extensionPressureReclaimBlockedCount = 0
    private var lastObservedReclaimBlockedCount = 0
    private var recentUDPCreateTimestamps: [Date] = []
    private var highQueuedPressureConsecutiveSamples = 0
    private var stormModeEnabled = false
    private var stormModeStableSince: Date?
    private var hostCooldownUntilByKey: [String: Date] = [:]
    private let minimumUDPControlStreamsDuringGrace = 6
    private var udpSessionStartedAt = Date.distantPast
    private var udpStartupSerialUntil = Date.distantPast
    private var udpCrashGuardUntil = Date.distantPast
    private var udpCrashGuardReason = ""
    private var udpCrashGuardHits = 0

    // Active relay tracking for JSON stats
    private var activeRelays: [Int: RelayTracker] = [:]
    private var domainStats: [String: (count: Int, bytes: Int)] = [:]
    private var snapshotTimer: DispatchSourceTimer?
    private var snapshotHistory: [TrafficSnapshot] = []
    private var eventLog: [TrafficEvent] = []
    private var eventCounter = 0
    private let maxSnapshotHistory = BubbleConstants.extensionPressureMaxSnapshotHistory
    private let maxEvents = BubbleConstants.extensionPressureMaxEvents
    private let statsFileURL: URL?
    private var udpSocketPool: [String: NWConnection] = [:]
    private var udpSocketPoolOrder: [String] = []
    private var startedUDPSocketKeys: Set<String> = []
    private var udpSocketReuseHits = 0
    private var udpSocketReuseMisses = 0
    private let udpSocketPoolMaxEntries = 16
    private func admissionController(for trafficClass: TrafficClass) -> UDPAdmissionController {
        if let existing = perClassAdmissionControllers[trafficClass] {
            return existing
        }
        let created = UDPAdmissionController()
        perClassAdmissionControllers[trafficClass] = created
        return created
    }

    init(filter: ConnectionFilter) {
        self.filter = filter
        queue.setSpecific(key: queueSpecificKey, value: true)
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        if let stored = defaults?.object(forKey: BubbleConstants.transportProtectionV2StabilityFirstKey) as? Bool {
            self.stabilityFirstModeEnabled = Self.resolveStabilityFirstMode(storedValue: stored)
        } else {
            self.stabilityFirstModeEnabled = Self.resolveStabilityFirstMode(storedValue: nil)
        }
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BubbleConstants.appGroupID
        ) {
            self.statsFileURL = container.appendingPathComponent(BubbleConstants.statsFileName)
        } else {
            self.statsFileURL = nil
        }
    }

    // MARK: - Lifecycle

    private func syncOnQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == true {
            return work()
        }
        return queue.sync(execute: work)
    }

    func start(callbackQueue: DispatchQueue = .global(qos: .userInitiated), ready: @escaping (Error?) -> Void) {
        let readyLock = NSLock()
        var didCallReady = false
        let callReady = { (error: Error?) in
            readyLock.lock()
            let shouldCall = !didCallReady
            if shouldCall {
                didCallReady = true
            }
            readyLock.unlock()
            guard shouldCall else { return }
            callbackQueue.async {
                ready(error)
            }
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
        startUDPSweepTimer()
        configureUDPStartupCrashGuard()
        if stabilityFirstModeEnabled {
            protectionStartupGraceUntil = Date().addingTimeInterval(BubbleConstants.stabilityFirstStartupGraceSeconds)
        } else {
            protectionStartupGraceUntil = .distantPast
        }
        persistDNSStartupDrainState()
        log.logAndFlush("TRANSPORT_PROTECTION flag_mode=\(stabilityFirstModeEnabled ? "stability_first_v2" : "legacy") grace_active=\(isStartupGraceActive()) udp_forwarding_mode=\(udpForwardingMode())")
    }

    func stop() {
        syncOnQueue {
            statsTimer?.cancel()
            statsTimer = nil
            snapshotTimer?.cancel()
            snapshotTimer = nil
            udpSweepTimer?.cancel()
            udpSweepTimer = nil
            for conn in udpSocketPool.values {
                conn.cancel()
            }
            udpSocketPool.removeAll()
            udpSocketPoolOrder.removeAll()
            startedUDPSocketKeys.removeAll()
        }
        listener?.cancel()
        listener = nil
    }

    private func configureUDPStartupCrashGuard(now: Date = Date()) {
        udpSessionStartedAt = now
        udpStartupSerialUntil = now.addingTimeInterval(BubbleConstants.udpStartupSerialModeSeconds)

        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        udpCrashGuardHits = defaults?.integer(forKey: BubbleConstants.udpCrashGuardHitsKey) ?? 0
        udpCrashGuardReason = defaults?.string(forKey: BubbleConstants.udpCrashGuardReasonKey) ?? ""
        udpCrashGuardUntil = Date(timeIntervalSince1970: defaults?.double(forKey: BubbleConstants.udpCrashGuardUntilKey) ?? 0)

        let finalCause = defaults?.string(forKey: BubbleConstants.vpnLifecycleLastCompletedStopCauseFinalKey) ??
            defaults?.string(forKey: BubbleConstants.vpnLifecycleStopCauseFinalKey) ?? ""
        let lastPhase = defaults?.string(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey) ?? ""
        let lastDecoderEvent = defaults?.string(forKey: BubbleConstants.udpLastDecoderEventJSONKey) ?? ""
        if Self.shouldActivateUDPStartupCrashGuard(
            previousStopCause: finalCause,
            lastProviderPhase: lastPhase,
            lastDecoderEventJSON: lastDecoderEvent
        ) {
            udpCrashGuardReason = Self.udpStartupCrashGuardReason(
                previousStopCause: finalCause,
                lastProviderPhase: lastPhase,
                lastDecoderEventJSON: lastDecoderEvent
            )
            udpCrashGuardUntil = now.addingTimeInterval(BubbleConstants.udpCrashGuardSerialModeSeconds)
            udpCrashGuardHits += 1
            defaults?.set(udpCrashGuardUntil.timeIntervalSince1970, forKey: BubbleConstants.udpCrashGuardUntilKey)
            defaults?.set(udpCrashGuardReason, forKey: BubbleConstants.udpCrashGuardReasonKey)
            defaults?.set(udpCrashGuardHits, forKey: BubbleConstants.udpCrashGuardHitsKey)
        } else if udpCrashGuardUntil <= now {
            udpCrashGuardReason = ""
            defaults?.set("", forKey: BubbleConstants.udpCrashGuardReasonKey)
        }

        log.logAndFlush(
            "UDP_STARTUP_GUARD serial_until=\(Int(udpStartupSerialUntil.timeIntervalSince1970)) crash_guard_active=\(isUDPCrashGuardActive(now: now)) reason=\(udpCrashGuardReason.isEmpty ? "none" : udpCrashGuardReason) hits=\(udpCrashGuardHits)"
        )
    }

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + BubbleConstants.statsInterval, repeating: BubbleConstants.statsInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let total = self.connectionCount
            guard total > 0 else { return }
            let memMB = Self.memoryUsageMB()
            let udpTimeoutRate = self.statsUDP > 0 ? Double(self.udpTimeoutCount) / Double(self.statsUDP) : 0
            self.updateTransportDegradedState()
            self.trimRetainedDiagnostics(now: Date())
            guard !self.areExpensiveDiagnosticsMuted() else { return }
            let queueOldestAgeMs: Int = {
                guard let oldest = self.pendingUDPControlQueue.first else { return 0 }
                return Int(Date().timeIntervalSince(oldest.enqueuedAt) * 1000.0)
            }()
            let queueP95AgeMs = self.queuedUDPControlP95AgeMs()
            let resolver88Streak = self.resolverHealth["8.8.8.8"]?.timeoutStreak ?? 0
            let resolver11Streak = self.resolverHealth["1.1.1.1"]?.timeoutStreak ?? 0
            let timeoutRateText = String(format: "%.2f", udpTimeoutRate)
            let badLenRate = self.badLenHardFailRate()
            let badLenRateText = String(format: "%.2f", badLenRate)
            let classStats = TrafficClass.allCases.map { trafficClass -> String in
                let s = self.classState(for: trafficClass)
                return "\(trafficClass.rawValue)[active=\(s.activeUDP),queued=\(s.queuedUDP),rejects=\(s.forcedRejects),tokenDrops=\(s.tokenDrops)]"
            }.joined(separator: ",")
            let statsNow = Date()
            let tiktokIPHintCounters = self.tiktokIPHintCounterSnapshot(now: statsNow)
            let instagramMediaHintCounters = self.instagramMediaHintCounters(now: statsNow)
            self.assertQueueInvariants()
            let healthVerdict = self.healthVerdict()
            self.log.log("SOCKS5 STATS: \(total) total, \(self.activeConnectionCount) active, \(self.activeRelays.count) relays, \(self.statsAllowed) allowed, \(self.statsBlocked) blocked, \(self.statsUDP) UDP, \(self.statsErrors) errors, udpActive=\(self.activeUDPStreams), active_udp_high_water_mark=\(self.udpActivePeak), udpOpened=\(self.totalUDPStreamsOpened), udpClosed=\(self.totalUDPStreamsClosed), queueDepth=\(self.pendingUDPControlQueue.count), queueOldestMs=\(queueOldestAgeMs), queueP95Ms=\(queueP95AgeMs), modeDetected=\(self.udpDecodeModeDetected), resyncAttempts=\(self.udpDecodeResyncAttempted), resyncSuccess=\(self.udpDecodeResyncSuccess), badLenHardFail=\(self.udpDecodeBadLengthHardFail), badLenRate=\(badLenRateText), recoveredContinues=\(self.udpDecodeRecoveredStreamContinues), closeAfterThreshold=\(self.udpDecodeCloseAfterFailureThreshold), decoderSoftDiscards=\(self.decoderSoftDiscards), decoderDensityCloses=\(self.decoderErrorDensityCloses), dnsInflight=\(self.dnsInflight), dnsReservedSlots=\(self.dnsReservedSlotsInUse()), dnsDedupHits=\(self.dnsDedupHits), dnsOneShotCloses=\(self.dnsOneShotCloses), dnsTimeoutCloses=\(self.dnsTimeoutCloses), dnsMalformedCloses=\(self.dnsMalformedCloses), dnsTrailingFramesDiscarded=\(self.dnsTrailingFramesDiscarded), dnsRecoveredOneShotCloses=\(self.dnsRecoveredOneShotCloses), dnsRecoveredFramesDiscarded=\(self.dnsRecoveredFramesDiscarded), dnsFastLane=[requests:\(self.dnsFastLaneRequests),responses:\(self.dnsFastLaneResponses),failures:\(self.dnsFastLaneFailures),parseFailed:\(self.dnsFastLaneParseFailed),close:\(self.dnsFastLaneClose)], dnsStartupDrain=[active:\(self.isDNSStartupDrainActive()),closes:\(self.dnsStartupDrainCloses),frames:\(self.dnsStartupDrainFramesProcessed)], udpClosePhase=\(self.lastUDPClosePhase.rawValue), udpDeferredCancels=\(self.udpDeferredCancels), udpGracefulDNSCloses=\(self.udpGracefulDNSCloses), udpCancelWatchdogFires=\(self.udpCancelWatchdogFires), udpStartupSerialModeActive=\(self.isUDPStartupSerialModeActive()), udpCrashGuardActive=\(self.isUDPCrashGuardActive()), udpCrashGuardReason=\(self.udpCrashGuardReason.isEmpty ? "none" : self.udpCrashGuardReason), startupGraceUDP=[accepted:\(self.startupGraceUDPAccepted),queued:\(self.startupGraceUDPQueued),rejected:\(self.startupGraceUDPRejected)], resolverSwitches=\(self.resolverSwitchCount), udpTimeoutRate=\(timeoutRateText), ttHardening=\(self.tiktokHardeningActions), udpReclaims=\(self.udpReclaimsByReason), hardPressureUDPReclaims=\(self.hardPressureUDPReclaims), tiktokDNSHints=[added:\(self.tiktokDNSHintsAdded),expired:\(self.tiktokDNSHintsExpired),active:\(self.activeDNSHintCount(bucket: .tiktokVideo)),udpBlocks:\(self.tiktokUDPBlocksFromDNSHints)], tiktokIPHints=[added:\(tiktokIPHintCounters.added),expired:\(tiktokIPHintCounters.expired),active:\(tiktokIPHintCounters.active),blocks:\(tiktokIPHintCounters.blocks)], instagramDNSHints=[added:\(self.instagramDNSHintsAdded),expired:\(self.instagramDNSHintsExpired),active:\(self.activeDNSHintCount(bucket: .reels)),udpBlocks:\(self.instagramUDPBlocksFromDNSHints)], instagramMediaHints=[added:\(instagramMediaHintCounters.added),expired:\(instagramMediaHintCounters.expired),active:\(instagramMediaHintCounters.active),blocks:\(instagramMediaHintCounters.blocks)], reclaimBudgetExhausted=\(self.maintenanceReclaimBudgetExhaustedCount), stormModeSeconds=\(Int(self.stormModeActiveSeconds())), degradedState=\(self.degradedState.rawValue), degradedTransitions=\(self.degradedTransitions), trippedTransitions=\(self.trippedTransitions), tokenBucketDrops=\(self.tokenBucketDrops), streamBlockSuppressed=\(self.streamBlockSuppressed), streamBlockTokenDrops=\(self.streamBlockTokenDrops), protectedFailOpen=[active:\(Date() < self.protectedBlockFailOpenUntil),activations:\(self.protectedBlockFailOpenActivations),allows:\(self.protectedBlockFailOpenAllows)], udpForcedRejects=\(self.udpForcedRejects), udp_disabled_fast_rejects=\(self.udpDisabledFastRejects), udp_disabled_fast_rejects_suppressed=\(self.udpDisabledFastRejectsSuppressed), udp_non_dns_rejects=\(self.udpNonDNSRejects), udp_quic_rejects=\(self.udpQUICRejects), safeMode=[dnsTCP:\(self.safeModeDNSOverTCP),dnsFail:\(self.safeModeDNSFailures),targetBlocks:\(self.safeModeTargetedUDPBlocks),unknownAllows:\(self.safeModeUnknownUDPAllowed),pressureRejects:\(self.safeModeUDPRejectedByPressure),knownBadCacheHits:\(self.safeModeKnownBadUDPCacheHits)], udp_forwarding_mode=\(self.udpForwardingMode()), provider_last_phase=\(self.providerLastPhase()), admissionRejects=\(self.admissionRejectsByReason), graceActive=\(self.hasAnyProtectionGrace()), flagMode=\(self.stabilityFirstModeEnabled ? "stability_first_v2" : "legacy"), udpSocketReuseHitRate=\(String(format: "%.2f", self.udpSocketReuseHitRate())), tcpEarlySNI=[block:\(self.tcpEarlySNIBlocks),allow:\(self.tcpEarlySNIAllows),fallback:\(self.tcpEarlySNIFallbacks),suppressed:\(self.tcpSNIBlockSuppressed),tokenDrops:\(self.tcpSNIBlockTokenDrops)], resolverTimeoutStreaks=[8.8.8.8:\(resolver88Streak),1.1.1.1:\(resolver11Streak)], snapshots=\(self.snapshotHistory.count), mem=\(memMB)MB")
            self.log.log("PROTECTION STATE: state=\(self.degradedState.rawValue) queue=\(self.pendingUDPControlQueue.count) timeout_rate=\(timeoutRateText) forced_rejects=\(self.udpForcedRejects) token_drops=\(self.tokenBucketDrops) stream_token_drops=\(self.streamBlockTokenDrops) class_stats=[\(classStats)] churn=\(self.requeueChurnCount) invariant_violations=\(self.queueInvariantViolationCount) health_verdict=\(healthVerdict)")
            self.log.log("SUPPRESSION STATS: tcp=\(self.blockedSuppressedTCP) udp=\(self.blockedSuppressedUDP) keys=\(self.blockedSuppression.count) protected_block_suppression_keys=\(self.blockedSuppression.count) tcp_early_sni_block=\(self.tcpEarlySNIBlocks) tcp_early_sni_allow=\(self.tcpEarlySNIAllows) tcp_early_sni_fallback=\(self.tcpEarlySNIFallbacks) tcp_sni_block_suppressed=\(self.tcpSNIBlockSuppressed) tcp_sni_block_token_drops=\(self.tcpSNIBlockTokenDrops)")
            self.pruneSuppressionState(now: Date())
        }
        timer.resume()
        statsTimer = timer
    }

    private func startUDPSweepTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + BubbleConstants.tiktokHardeningSweepInterval,
            repeating: BubbleConstants.tiktokHardeningSweepInterval
        )
        timer.setEventHandler { [weak self] in
            self?.runUDPMaintenanceSweep()
        }
        timer.resume()
        udpSweepTimer = timer
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

    private func recordProviderPhase(_ phase: String) {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let ts = Date().timeIntervalSince1970
        defaults?.set(phase, forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey)
        defaults?.set(ts, forKey: BubbleConstants.vpnLifecycleProviderLastPhaseTSKey)
        appendProviderPhaseRing(defaults: defaults, phase: phase, ts: ts, source: "socks_proxy")
    }

    private func providerLastPhase() -> String {
        UserDefaults(suiteName: BubbleConstants.appGroupID)?
            .string(forKey: BubbleConstants.vpnLifecycleProviderLastPhaseKey) ?? "unknown"
    }

    private func defaultsString(_ key: String, fallback: String) -> String {
        UserDefaults(suiteName: BubbleConstants.appGroupID)?.string(forKey: key) ?? fallback
    }

    private func defaultsBool(_ key: String) -> Bool {
        UserDefaults(suiteName: BubbleConstants.appGroupID)?.bool(forKey: key) ?? false
    }

    private func appendProviderPhaseRing(defaults: UserDefaults?, phase: String, ts: TimeInterval, source: String) {
        guard let defaults else { return }
        var ring = decodeJSONArray(defaults.string(forKey: BubbleConstants.providerPhaseRingJSONKey))
        let lastSeq = ring.compactMap { $0["seq"] as? Int }.max() ?? 0
        ring.append([
            "seq": lastSeq + 1,
            "ts": ts,
            "phase": phase,
            "source": source,
        ])
        if ring.count > 32 {
            ring.removeFirst(ring.count - 32)
        }
        writeJSONObject(ring, key: BubbleConstants.providerPhaseRingJSONKey, defaults: defaults)
    }

    private func decodeJSONArray(_ raw: String?) -> [[String: Any]] {
        guard let raw, let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return parsed
    }

    private func writeJSONObject(_ object: Any, key: String, defaults: UserDefaults?) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        defaults?.set(json, forKey: key)
    }

    private func recordLastControlStream(state: UDPStreamState, reason: String? = nil) {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let payload: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "stream_id": state.id,
            "class": state.trafficClass.rawValue,
            "host": state.lastHost ?? "",
            "port": state.lastPort.map { Int($0) } ?? 0,
            "mode": state.mode?.rawValue ?? "",
            "close_reason": reason ?? state.closeReason ?? "",
            "close_phase": state.closePhase.rawValue,
        ]
        writeJSONObject(payload, key: BubbleConstants.udpLastControlStreamJSONKey, defaults: defaults)
    }

    private func recordLastDNSClose(
        state: UDPStreamState,
        reason: String,
        trailingDiscarded: Int,
        recoveredDiscarded: Int
    ) {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let payload: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "stream_id": state.id,
            "reason": reason,
            "response_sent": reason == "dns_response_one_shot_retire" || reason == "dns_fast_lane_close",
            "timeout": reason == "dns_timeout_one_shot_retire",
            "malformed": reason == "dns_malformed_one_shot_retire" || reason == "dns_fast_lane_parse_failed",
            "trailing_discarded": trailingDiscarded,
            "recovered_count": state.decoderRecoveryCount,
            "recovered_discarded": recoveredDiscarded,
            "close_phase": state.closePhase.rawValue,
        ]
        writeJSONObject(payload, key: BubbleConstants.udpLastDNSCloseJSONKey, defaults: defaults)
    }

    private func recordLastDecoderEvent(
        reason: String,
        hexPrefix: String,
        recoveredFrames: Int,
        discardedFrames: Int,
        streamID: Int? = nil,
        source: String? = nil,
        byteCount: Int? = nil,
        decoderMode: String? = nil,
        decoderState: String? = nil,
        socksRequestHadTail: Bool? = nil
    ) {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        var payload: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "reason": reason,
            "hex_prefix": hexPrefix,
            "recovered_frames": recoveredFrames,
            "discarded_frames": discardedFrames,
        ]
        if let streamID { payload["stream_id"] = streamID }
        if let source { payload["source"] = source }
        if let byteCount { payload["byte_count"] = byteCount }
        if let decoderMode { payload["decoder_mode"] = decoderMode }
        if let decoderState { payload["decoder_state"] = decoderState }
        if let socksRequestHadTail { payload["socks_request_had_tail"] = socksRequestHadTail }
        writeJSONObject(payload, key: BubbleConstants.udpLastDecoderEventJSONKey, defaults: defaults)
    }

    private func startSnapshotTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + 1.0,
            repeating: BubbleConstants.extensionPressureSnapshotIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.writeSnapshot()
        }
        timer.resume()
        snapshotTimer = timer
    }

    private func writeSnapshot() {
        guard let fileURL = statsFileURL else { return }
        guard !areExpensiveDiagnosticsMuted() else { return }

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

        let tiktokIPHintCounters = tiktokIPHintCounterSnapshot()
        let instagramMediaHintCounters = instagramMediaHintCounters()
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
            udpDecodeModeDetected: udpDecodeModeDetected,
            udpDecodeResyncAttempted: udpDecodeResyncAttempted,
            udpDecodeResyncSuccess: udpDecodeResyncSuccess,
            udpDecodeBadLengthHardFail: udpDecodeBadLengthHardFail,
            udpDecodeRecoveredStreamContinues: udpDecodeRecoveredStreamContinues,
            udpDecodeCloseAfterFailureThreshold: udpDecodeCloseAfterFailureThreshold,
            udpActivePeak: udpActivePeak,
            udpTimeoutRate: statsUDP > 0 ? Double(udpTimeoutCount) / Double(statsUDP) : 0,
            dnsInflight: dnsInflight,
            resolverTimeoutStreakByHost: [
                "8.8.8.8": resolverHealth["8.8.8.8"]?.timeoutStreak ?? 0,
                "1.1.1.1": resolverHealth["1.1.1.1"]?.timeoutStreak ?? 0,
            ],
            resolverSwitchCount: resolverSwitchCount,
            decoderErrorRate: statsUDP > 0 ? Double(decoderErrorCount) / Double(statsUDP) : 0,
            streamCloseReasonCounts: streamCloseReasonCounts,
            tiktokHardeningActions: tiktokHardeningActions,
            udpQueueDepth: pendingUDPControlQueue.count,
            udpQueueOldestAgeMs: {
                guard let oldest = pendingUDPControlQueue.first else { return 0 }
                return Int(Date().timeIntervalSince(oldest.enqueuedAt) * 1000.0)
            }(),
            udpQueueP95AgeMs: queuedUDPControlP95AgeMs(),
            udpReclaimsByReason: udpReclaimsByReason,
            udpForcedRejects: udpForcedRejects,
            udpForcedRejectsByReason: udpReclaimsByReason.filter { $0.key.contains("tiktok_udp_reject") },
            degradedState: degradedState.rawValue,
            degradedTransitions: degradedTransitions,
            trippedTransitions: trippedTransitions,
            trippedSecondsTotal: trippedSecondsTotal + (degradedState == .tripped ? Date().timeIntervalSince(trippedEnteredAt) : 0),
            badLenRate: badLenHardFailRate(),
            recentBadLenHardFails: recentBadLenHardFailCount(),
            tokenBucketDrops: tokenBucketDrops,
            streamBlockSuppressed: streamBlockSuppressed,
            streamBlockTokenDrops: streamBlockTokenDrops,
            admissionRejectsByReason: admissionRejectsByReason,
            stateSecondsByMode: stateSecondsByMode,
            reconnectBreakerCooldownRemainingSec: reconnectBreakerCooldownRemainingSec(),
            reconnectBreakerTrips: reconnectBreakerTrips(),
            reconnectSuppressedByBreaker: reconnectSuppressedByBreakerCount(),
            reconnectBreakerBackoffStep: reconnectBreakerBackoffStep(),
            maintenanceReclaimBudgetExhaustedCount: maintenanceReclaimBudgetExhaustedCount,
            stormModeActiveSeconds: stormModeActiveSeconds(),
            dnsReservedSlotsInUse: dnsReservedSlotsInUse(),
            decoderSoftDiscards: decoderSoftDiscards,
            decoderErrorDensityCloses: decoderErrorDensityCloses,
            attemptedByBucket: attemptedByBucket,
            blockedByBucket: blockedByBucket,
            possibleFalsePositiveRetries: possibleFalsePositiveRetries,
            blockedSuppressedTCP: blockedSuppressedTCP,
            blockedSuppressedUDP: blockedSuppressedUDP,
            suppressionKeysActive: blockedSuppression.count,
            udpSocketReuseHitRate: udpSocketReuseHitRate(),
            udpDisabledFastRejects: udpDisabledFastRejects,
            udpDisabledFastRejectsSuppressed: udpDisabledFastRejectsSuppressed,
            safeModeDNSOverTCP: safeModeDNSOverTCP,
            safeModeDNSFailures: safeModeDNSFailures,
            safeModeTargetedUDPBlocks: safeModeTargetedUDPBlocks,
            safeModeUnknownUDPAllowed: safeModeUnknownUDPAllowed,
            safeModeUDPRejectedByPressure: safeModeUDPRejectedByPressure,
            safeModeKnownBadUDPCacheHits: safeModeKnownBadUDPCacheHits,
            dnsFastLaneRequests: dnsFastLaneRequests,
            dnsFastLaneResponses: dnsFastLaneResponses,
            dnsFastLaneFailures: dnsFastLaneFailures,
            dnsFastLaneParseFailed: dnsFastLaneParseFailed,
            dnsFastLaneClose: dnsFastLaneClose,
            udpNonDNSRejects: udpNonDNSRejects,
            udpQUICRejects: udpQUICRejects,
            dnsOneShotCloses: dnsOneShotCloses,
            dnsTimeoutCloses: dnsTimeoutCloses,
            dnsMalformedCloses: dnsMalformedCloses,
            dnsTrailingFramesDiscarded: dnsTrailingFramesDiscarded,
            startupGraceUDPAccepted: startupGraceUDPAccepted,
            startupGraceUDPQueued: startupGraceUDPQueued,
            startupGraceUDPRejected: startupGraceUDPRejected,
            hardPressureUDPReclaims: hardPressureUDPReclaims,
            tiktokDNSHintsAdded: tiktokDNSHintsAdded,
            tiktokDNSHintsExpired: tiktokDNSHintsExpired,
            tiktokDNSHintsActive: activeDNSHintCount(bucket: .tiktokVideo),
            tiktokUDPBlocksFromDNSHints: tiktokUDPBlocksFromDNSHints,
            tiktokIPHintsAdded: tiktokIPHintCounters.added,
            tiktokIPHintsExpired: tiktokIPHintCounters.expired,
            tiktokIPHintsActive: tiktokIPHintCounters.active,
            tiktokIPHintBlocks: tiktokIPHintCounters.blocks,
            instagramMediaHintsAdded: instagramMediaHintCounters.added,
            instagramMediaHintsExpired: instagramMediaHintCounters.expired,
            instagramMediaHintBlocks: instagramMediaHintCounters.blocks,
            tcpSNIBlockSuppressed: tcpSNIBlockSuppressed,
            tcpSNIBlockTokenDrops: tcpSNIBlockTokenDrops,
            protectedBlockSuppressionKeys: blockedSuppression.count,
            udpForwardingMode: udpForwardingMode(),
            providerLastPhase: providerLastPhase(),
            udpClosePhase: lastUDPClosePhase.rawValue,
            udpDeferredCancels: udpDeferredCancels,
            udpGracefulDNSCloses: udpGracefulDNSCloses,
            udpCancelWatchdogFires: udpCancelWatchdogFires,
            udpStartupSerialModeActive: isUDPStartupSerialModeActive(),
            udpCrashGuardActive: isUDPCrashGuardActive(),
            udpCrashGuardReason: udpCrashGuardReason,
            dnsRecoveredOneShotCloses: dnsRecoveredOneShotCloses,
            dnsRecoveredFramesDiscarded: dnsRecoveredFramesDiscarded,
            startupStabilityPhase: defaultsString(BubbleConstants.vpnLifecycleStartupStabilityPhaseKey, fallback: "unknown"),
            startupProbeCompleted: defaultsBool(BubbleConstants.vpnLifecycleStartupProbeCompletedKey),
            dnsStartupDrainActive: isDNSStartupDrainActive(),
            dnsStartupDrainCloses: dnsStartupDrainCloses,
            dnsStartupDrainFramesProcessed: dnsStartupDrainFramesProcessed,
            earlyReconnectSuppressed: defaultsBool(BubbleConstants.vpnLifecycleEarlyReconnectSuppressedKey),
            iosSafeModeReason: defaultsString(BubbleConstants.vpnLifecycleIOSSafeModeReasonKey, fallback: ""),
            tcpEarlySNIBlocks: tcpEarlySNIBlocks,
            tcpEarlySNIAllows: tcpEarlySNIAllows,
            tcpEarlySNIFallbacks: tcpEarlySNIFallbacks
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
        applyLockSafeProtection(to: fileURL)
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

        guard let request = Self.parseSOCKSRequestMetadata(from: data) else {
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            log.log("SOCKS5 #\(id): Failed to parse destination address")
            self.sendSocksError(client: client, reply: 0x08)
            return
        }

        let cmd = request.command

        // Diagnostic: log ATYP so we know if tun2socks sends domains or IPs
        let atypName: String
        switch request.atyp {
        case 0x01: atypName = "IPv4"
        case 0x03: atypName = "DOMAIN"
        case 0x04: atypName = "IPv6"
        default: atypName = "UNKNOWN(\(request.atyp))"
        }

        switch cmd {
        case 0x01: // CONNECT (TCP)
            log.log("TCP #\(id): CONNECT atyp=\(atypName) host=\(request.host) port=\(request.port)")
            handleConnect(client: client, id: id, host: request.host, port: request.port)

        case 0x05: // FWD_UDP (hev-socks5-tunnel custom extension)
            let udpMode = currentUDPForwardingMode()
            if udpMode == .disabledFastReject {
                rejectFwdUDPDisabled(client: client, id: id, host: request.host, port: request.port)
                return
            }
            if udpMode == .selectiveSafeMode {
                if dnsFastLaneDisabledForSession {
                    log.log(
                        "UDP #\(id): FWD_UDP dns_fast_lane_bypassed reason=\(dnsFastLaneDisabledReason.isEmpty ? "session_disabled" : dnsFastLaneDisabledReason) request_host=\(request.host) request_port=\(request.port) request_tail_bytes=\(request.requestTail.count) request_tail_hex=\(hexPrefix(request.requestTail)) udp_forwarding_mode=\(udpMode.rawValue)"
                    )
                    handleFwdUDP(
                        client: client,
                        id: id,
                        trafficClassHint: .generic,
                        initialBytes: request.requestTail,
                        requestHadTail: !request.requestTail.isEmpty
                    )
                    return
                }
                log.log(
                    "UDP #\(id): FWD_UDP routed_to_dns_fast_lane request_host=\(request.host) request_port=\(request.port) request_tail_bytes=\(request.requestTail.count) request_tail_hex=\(hexPrefix(request.requestTail)) udp_forwarding_mode=\(udpMode.rawValue)"
                )
                startDNSFastLaneControlStream(client: client, id: id, initialBytes: request.requestTail)
                return
            }
            let classified = classifyEarly(host: request.host, port: request.port)
            let admissionClass = Self.admissionTrafficClass(for: classified)
            log.log(
                "UDP #\(id): classify_early class=\(classified.trafficClass.rawValue) confidence=\(String(format: "%.2f", classified.confidence)) " +
                "reason=\(classified.reason) admission_class=\(admissionClass.rawValue) udp_forwarding_mode=\(udpForwardingMode())"
            )
            handleFwdUDP(
                client: client,
                id: id,
                trafficClassHint: admissionClass,
                initialBytes: request.requestTail,
                requestHadTail: !request.requestTail.isEmpty
            )

        default:
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            log.log("SOCKS5 #\(id): unsupported cmd=\(cmd)")
            self.sendSocksError(client: client, reply: 0x07)
        }
    }

    // MARK: - Shared Address Parser

    static func parseSOCKSRequestMetadata(from data: Data) -> SOCKSRequestMetadata? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0x05 else { return nil }
        guard let addr = parseSOCKSAddressBytes(from: bytes, atypOffset: 3) else { return nil }
        let tail = addr.headerEndOffset < data.count ? Data(data.dropFirst(addr.headerEndOffset)) : Data()
        return SOCKSRequestMetadata(
            command: bytes[1],
            atyp: bytes[3],
            host: addr.host,
            port: addr.port,
            headerEndOffset: addr.headerEndOffset,
            requestTail: tail
        )
    }

    static func isParseableRawUDPControlPayload(_ data: Data) -> Bool {
        if case .parseable = rawUDPControlPayloadStatus(data) {
            return true
        }
        return false
    }

    static func decodeDNSFastLaneInput(data: Data, decoder: UDPControlStreamDecoder) -> DNSFastLaneDecodeResult {
        if decoder.currentMode == nil, case .parseable = rawUDPControlPayloadStatus(data) {
            return .frame(UDPControlFrame(mode: .rawPayload, payload: [UInt8](data)), trailingFrameCount: 0)
        }

        let appendResult = decoder.append(data)
        switch appendResult.status {
        case .ok:
            guard let frame = appendResult.frames.first else {
                return .needMoreBytes
            }
            return .frame(frame, trailingFrameCount: max(0, appendResult.frames.count - 1))
        case .needMoreBytes:
            return .needMoreBytes
        case .recovered(let decodeError), .failed(let decodeError):
            return .failed(decodeError)
        }
    }

    private static func dnsFastLaneInputFormat(data: Data, decoder: UDPControlStreamDecoder) -> String {
        switch rawUDPControlPayloadStatus(data) {
        case .parseable(let kind):
            return kind
        case .needMoreBytes:
            return "partial_chunked_frame"
        case .notRaw:
            break
        }

        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return "partial_chunked_frame" }
        let prefix = (Int(bytes[0]) << 8) | Int(bytes[1])
        if prefix == 0x0001 {
            return bytes.count >= 4 ? "framed_udp_payload" : "partial_chunked_frame"
        }
        if prefix > 0, prefix <= BubbleConstants.maxUDPFrameSize {
            return "framed_udp_payload"
        }
        if decoder.currentMode != nil {
            return "framed_udp_payload"
        }
        return "invalid_non_dns_payload"
    }

    private static func rawUDPControlPayloadStatus(_ data: Data) -> RawUDPControlPayloadStatus {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return .needMoreBytes(kind: "raw_udp_payload") }

        if bytes[0] == 0x0a {
            return rawAddressPayloadStatus(bytes: bytes, atypOffset: 1, kind: "raw_udp_payload")
        }

        guard bytes[0] == 0x00 else { return .notRaw }
        if bytes.count < 3 {
            return bytes.allSatisfy { $0 == 0x00 } ? .needMoreBytes(kind: "socks5_udp_fallback_payload") : .notRaw
        }
        guard bytes[1] == 0x00, bytes[2] == 0x00 else { return .notRaw }
        return rawAddressPayloadStatus(bytes: bytes, atypOffset: 3, kind: "socks5_udp_fallback_payload")
    }

    private static func rawAddressPayloadStatus(bytes: [UInt8], atypOffset: Int, kind: String) -> RawUDPControlPayloadStatus {
        guard bytes.count > atypOffset else { return .needMoreBytes(kind: kind) }

        let requiredHeaderBytes: Int
        switch bytes[atypOffset] {
        case 0x01:
            requiredHeaderBytes = atypOffset + 1 + 4 + 2
        case 0x04:
            requiredHeaderBytes = atypOffset + 1 + 16 + 2
        case 0x03:
            guard bytes.count > atypOffset + 1 else { return .needMoreBytes(kind: kind) }
            let domainLength = Int(bytes[atypOffset + 1])
            guard domainLength > 0 else { return .notRaw }
            requiredHeaderBytes = atypOffset + 2 + domainLength + 2
        default:
            return .notRaw
        }

        guard bytes.count >= requiredHeaderBytes else {
            return .needMoreBytes(kind: kind)
        }
        guard let addr = parseSOCKSAddressBytes(from: bytes, atypOffset: atypOffset),
              addr.headerEndOffset <= bytes.count else {
            return .notRaw
        }
        return .parseable(kind: kind)
    }

    /// Parses ATYP + address + port from a byte buffer.
    /// `atypOffset` is the index of the ATYP byte in the buffer.
    /// Returns nil if the buffer is too short or address type is unknown.
    private func parseSOCKSAddress(from bytes: [UInt8], atypOffset: Int) -> ParsedAddress? {
        Self.parseSOCKSAddressBytes(from: bytes, atypOffset: atypOffset)
    }

    private static func parseSOCKSAddressBytes(from bytes: [UInt8], atypOffset: Int) -> ParsedAddress? {
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
        let initialDecision = self.filter.evaluateConnection(host: host, port: port)
        let decision = self.evaluateTikTokDirectIPDecision(
            host: host,
            port: port,
            initialDecision: initialDecision,
            now: Date()
        ) ?? initialDecision

        switch decision.action {
        case .blockNow:
            let gate = evaluateProtectionGate(
                host: host,
                port: port,
                decision: decision,
                transport: "tcp",
                stage: .admission
            )
            if gate == .failOpen {
                statsAllowed += 1
                recordEvent(type: .allowed, connId: id, host: host, port: port, detail: "TCP protected block fail-open", decision: decision)
                connectToTarget(client: client, host: host, port: port, id: id)
                return
            }
            if gate == .rejectNewStream || gate == .dropFast {
                blockedSuppressedTCP += 1
                admissionRejectsByReason["tcp_drop_fast", default: 0] += 1
                activeConnectionCount -= 1
                sendSocksError(client: client, reply: 0x05)
                return
            }
            if gate == .suppress {
                blockedSuppressedTCP += 1
                admissionRejectsByReason["tcp_suppressed", default: 0] += 1
                activeConnectionCount -= 1
                sendSocksError(client: client, reply: 0x05)
                return
            }
            self.statsBlocked += 1
            self.activeConnectionCount -= 1
            self.log.log("SOCKS5 #\(id): BLOCKED \(host):\(port)")
            self.recordEvent(type: .blocked, connId: id, host: host, port: port, detail: "Connection blocked by policy", decision: decision)
            self.sendSocksError(client: client, reply: 0x05)

        case .allow, .blockAfterBytes, .shadowAllow:
            if shouldUseTCPSNIGate(host: host, port: port, decision: decision) {
                startTCPSNIGatedConnect(client: client, id: id, host: host, port: port, initialDecision: decision)
                return
            }
            self.statsAllowed += 1
            self.recordEvent(type: .allowed, connId: id, host: host, port: port, detail: "TCP CONNECT", decision: decision)
            self.connectToTarget(client: client, host: host, port: port, id: id)
        }
    }

    private func shouldUseTCPSNIGate(host: String, port: UInt16, decision: PolicyDecision) -> Bool {
        guard port == 443 else { return false }
        guard decision.action != .blockNow else { return false }
        return true
    }

    private func startTCPSNIGatedConnect(
        client: NWConnection,
        id: Int,
        host: String,
        port: UInt16,
        initialDecision: PolicyDecision
    ) {
        let reply = buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
        client.send(content: reply, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.statsErrors += 1
                self.activeConnectionCount = max(self.activeConnectionCount - 1, 0)
                self.log.log("TCP #\(id): tcp_early_sni_fallback send_reply_failed error=\(error)")
                client.cancel()
                return
            }

            let state = TCPSNIGateState()
            let timeout = DispatchWorkItem { [weak self, weak state] in
                guard let self, let state, !state.completed else { return }
                state.probeTimedOut = true
                self.log.log("TCP #\(id): tcp_early_sni_fallback probe_timeout_armed buffered=\(state.buffer.count)B")
            }
            state.timeoutWorkItem = timeout
            self.queue.asyncAfter(deadline: .now() + BubbleConstants.tcpSNIGateTimeout, execute: timeout)
            self.readTCPSNIGateBytes(client: client, id: id, host: host, port: port, state: state, initialDecision: initialDecision)
        })
    }

    private func readTCPSNIGateBytes(
        client: NWConnection,
        id: Int,
        host: String,
        port: UInt16,
        state: TCPSNIGateState,
        initialDecision: PolicyDecision
    ) {
        guard !state.completed else { return }
        let remaining = BubbleConstants.tcpSNIGateMaxBufferedBytes - state.buffer.count
        guard remaining > 0 else {
            finishTCPSNIGateAllow(
                client: client,
                id: id,
                host: host,
                port: port,
                state: state,
                decision: initialDecision,
                sni: nil,
                reason: "max_buffer_reached"
            )
            return
        }

        client.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
            guard let self, !state.completed else { return }

            if let error {
                state.completed = true
                state.timeoutWorkItem?.cancel()
                self.statsErrors += 1
                self.activeConnectionCount = max(self.activeConnectionCount - 1, 0)
                self.log.log("TCP #\(id): tcp_early_sni_fallback read_failed error=\(error)")
                client.cancel()
                return
            }

            if let data, !data.isEmpty {
                state.buffer.append(data)
                switch self.probeTLSClientHelloSNI(state.buffer) {
                case .sni(let sni):
                    let sniDecision = self.filter.evaluateStream(
                        host: host,
                        sni: sni,
                        port: port,
                        bytesDown: 0,
                        connectionAge: 0,
                        parallelConnections: self.activeRelays.count
                    )
                    self.recordTikTokIPHintFromSNI(ip: host, port: port, sni: sni, decision: sniDecision, now: Date())
                    if Self.shouldEarlyBlockFromSNIDecision(sniDecision) {
                        self.finishTCPSNIGateBlock(
                            client: client,
                            id: id,
                            host: host,
                            port: port,
                            sni: sni,
                            state: state,
                            decision: sniDecision
                        )
                    } else {
                        self.finishTCPSNIGateAllow(
                            client: client,
                            id: id,
                            host: host,
                            port: port,
                            state: state,
                            decision: sniDecision,
                            sni: sni,
                            reason: "sni_allow"
                        )
                    }
                case .nonTLS:
                    self.finishTCPSNIGateAllow(
                        client: client,
                        id: id,
                        host: host,
                        port: port,
                        state: state,
                        decision: initialDecision,
                        sni: nil,
                        reason: "non_tls"
                    )
                case .noSNI:
                    self.finishTCPSNIGateAllow(
                        client: client,
                        id: id,
                        host: host,
                        port: port,
                        state: state,
                        decision: initialDecision,
                        sni: nil,
                        reason: "no_sni"
                    )
                case .needsMore:
                    if state.buffer.count >= BubbleConstants.tcpSNIGateMaxBufferedBytes || state.probeTimedOut {
                        self.finishTCPSNIGateAllow(
                            client: client,
                            id: id,
                            host: host,
                            port: port,
                            state: state,
                            decision: initialDecision,
                            sni: nil,
                            reason: state.probeTimedOut ? "timeout_incomplete_tls" : "max_buffer_incomplete_tls"
                        )
                    } else {
                        self.readTCPSNIGateBytes(
                            client: client,
                            id: id,
                            host: host,
                            port: port,
                            state: state,
                            initialDecision: initialDecision
                        )
                    }
                }
                return
            }

            if isComplete {
                state.completed = true
                state.timeoutWorkItem?.cancel()
                self.activeConnectionCount = max(self.activeConnectionCount - 1, 0)
                client.cancel()
            } else {
                self.readTCPSNIGateBytes(client: client, id: id, host: host, port: port, state: state, initialDecision: initialDecision)
            }
        }
    }

    private func finishTCPSNIGateBlock(
        client: NWConnection,
        id: Int,
        host: String,
        port: UInt16,
        sni: String,
        state: TCPSNIGateState,
        decision: PolicyDecision
    ) {
        guard !state.completed else { return }
        let gate = applyTCPSNIBlockProtection(sni: sni, port: port, decision: decision)
        if gate == .failOpen {
            finishTCPSNIGateAllow(
                client: client,
                id: id,
                host: host,
                port: port,
                state: state,
                decision: decision,
                sni: sni,
                reason: "protected_storm_fail_open"
            )
            return
        }
        state.completed = true
        state.timeoutWorkItem?.cancel()
        if gate != .allow {
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }
        tcpEarlySNIBlocks += 1
        statsBlocked += 1
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        log.log("TCP #\(id): tcp_early_sni_block sni=\(sni) host=\(host):\(port) reason=\(decision.reason)")
        recordEvent(
            type: .blocked,
            connId: id,
            host: host,
            port: port,
            sni: sni,
            detail: "TCP early SNI blocked before target connect",
            decision: decision
        )
        client.cancel()
    }

    @discardableResult
    private func applyTCPSNIBlockProtection(sni: String, port: UInt16, decision: PolicyDecision) -> ProtectionGateResult {
        let gate = evaluateProtectionGate(
            host: sni,
            port: port,
            decision: decision,
            transport: "tcp_sni",
            stage: .streamBlock
        )
        switch gate {
        case .allow:
            return .allow
        case .failOpen:
            admissionRejectsByReason["tcp_sni_block_fail_open", default: 0] += 1
            return gate
        case .suppress:
            tcpSNIBlockSuppressed += 1
            streamBlockSuppressed += 1
            blockedSuppressedTCP += 1
            admissionRejectsByReason["tcp_sni_block_suppressed", default: 0] += 1
            return gate
        case .dropFast, .rejectNewStream:
            tcpSNIBlockSuppressed += 1
            tcpSNIBlockTokenDrops += 1
            streamBlockTokenDrops += 1
            blockedSuppressedTCP += 1
            admissionRejectsByReason["tcp_sni_block_drop_fast", default: 0] += 1
            return gate
        }
    }

    private func finishTCPSNIGateAllow(
        client: NWConnection,
        id: Int,
        host: String,
        port: UInt16,
        state: TCPSNIGateState,
        decision: PolicyDecision,
        sni: String?,
        reason: String
    ) {
        guard !state.completed else { return }
        state.completed = true
        state.timeoutWorkItem?.cancel()
        if sni == nil || reason.contains("timeout") || reason.contains("buffer") || reason == "non_tls" || reason == "no_sni" {
            tcpEarlySNIFallbacks += 1
            log.log("TCP #\(id): tcp_early_sni_fallback reason=\(reason) buffered=\(state.buffer.count)B host=\(host):\(port)")
        } else {
            tcpEarlySNIAllows += 1
            log.log("TCP #\(id): tcp_early_sni_allow sni=\(sni ?? "n/a") host=\(host):\(port) reason=\(decision.reason)")
        }
        statsAllowed += 1
        recordEvent(
            type: .allowed,
            connId: id,
            host: host,
            port: port,
            sni: sni,
            detail: "TCP CONNECT after early SNI \(reason)",
            decision: decision
        )
        connectToTarget(
            client: client,
            host: host,
            port: port,
            id: id,
            initialClientData: state.buffer.isEmpty ? nil : state.buffer,
            socksReplyAlreadySent: true,
            initialSNI: sni
        )
    }

    private func probeTLSClientHelloSNI(_ data: Data) -> TLSClientHelloProbe {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { return .needsMore }
        guard bytes[0] == 0x16, bytes[1] == 0x03 else { return .nonTLS }
        let recordLength = (Int(bytes[3]) << 8) | Int(bytes[4])
        guard recordLength > 0 else { return .noSNI }
        let recordEnd = 5 + recordLength
        guard recordEnd <= BubbleConstants.tcpSNIGateMaxBufferedBytes else { return .noSNI }
        guard bytes.count >= recordEnd else { return .needsMore }
        if let sni = extractSNI(from: Data(data.prefix(recordEnd))) {
            return .sni(sni)
        }
        return .noSNI
    }

    // MARK: - FWD_UDP (hev-socks5-tunnel custom command 0x05)
    //
    // Framing modes accepted by the decoder:
    //  - [len16][payload]
    //  - [0x0001][len16][payload]
    //
    // Mode is locked per stream after first valid frame and mirrored on responses.
    // Parse errors are stream-local and never escalate to tunnel shutdown.

    private func handleFwdUDP(
        client: NWConnection,
        id: Int,
        bypassAdmission: Bool = false,
        trafficClassHint: TrafficClass = .unknown,
        initialBytes: Data = Data(),
        requestHadTail: Bool = false
    ) {
        if udpStreamsByID[id] != nil {
            log.log("UDP #\(id): duplicate_fwd_udp_ignored class=\(trafficClassHint.rawValue)")
            return
        }
        let udpMode = currentUDPForwardingMode()
        if udpMode == .disabledFastReject {
            rejectFwdUDPDisabled(client: client, id: id, host: "unknown", port: 0)
            return
        }
        let now = Date()
        let initialClass = trafficClassHint
        let queuedForClass = countQueuedUDPStreams(for: initialClass)
        let activeForClass = countActiveUDPStreams(for: initialClass)
        let classConfig = classConfig(for: initialClass)
        let safeMode = udpMode == .selectiveSafeMode
        let graceAdjustedLimits = Self.startupGraceAdjustedUDPLimits(
            trafficClass: initialClass,
            maxActive: classConfig.maxActive,
            maxQueued: classConfig.maxQueued,
            globalMaxActive: BubbleConstants.maxActiveUDPControlStreams,
            globalMaxQueued: BubbleConstants.maxQueuedUDPControlStreams,
            graceActive: isStartupGraceActive(now: now),
            safeMode: safeMode
        )
        let graceAdjustedCreateRateCapacity = Self.startupGraceAdjustedUDPCreateRateCapacity(
            trafficClass: initialClass,
            createRateCapacity: classConfig.createRateCapacity,
            globalCreateRateCapacity: BubbleConstants.udpAdmissionCreateRateCapacity,
            graceActive: isStartupGraceActive(now: now),
            safeMode: safeMode
        )
        let effectiveGlobalMaxActive = safeMode
            ? BubbleConstants.safeModeMaxActiveUDPControlStreams
            : BubbleConstants.maxActiveUDPControlStreams
        let effectiveGlobalMaxQueued = safeMode
            ? BubbleConstants.safeModeMaxQueuedUDPControlStreams
            : BubbleConstants.maxQueuedUDPControlStreams
        let effectiveCreateRatePerSecond = safeMode
            ? BubbleConstants.safeModeUDPAdmissionCreateRatePerSecond
            : classConfig.createRatePerSecond

        if !bypassAdmission {
            if queueUDPControlForStartupSerialMode(
                client: client,
                id: id,
                trafficClass: initialClass,
                now: now,
                maxQueued: effectiveGlobalMaxQueued,
                initialBytes: initialBytes,
                requestHadTail: requestHadTail
            ) {
                return
            }
            if let pressureReason = extensionPressureRejectReason(for: initialClass) {
                log.log("UDP #\(id): FWD_UDP rejected reason=\(pressureReason) reject_scope=extension_pressure class=\(initialClass.rawValue) pressure=\(extensionPressureLevel.rawValue) active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count)")
                admissionRejectsByReason["udp_admission_\(initialClass.rawValue)_\(pressureReason)", default: 0] += 1
                udpForcedRejects += 1
                if safeMode { safeModeUDPRejectedByPressure += 1 }
                recordStartupGraceUDPAdmission(.rejected, now: now)
                var classState = classState(for: initialClass)
                classState.forcedRejects += 1
                setClassState(classState, for: initialClass)
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                client.cancel()
                return
            }
            if Self.shouldForceGlobalUDPReject(
                active: activeUDPStreams,
                queued: pendingUDPControlQueue.count,
                maxActive: effectiveGlobalMaxActive,
                maxQueued: effectiveGlobalMaxQueued
            ) {
                log.log("UDP #\(id): FWD_UDP rejected reason=global_hard_saturation reject_scope=global class=\(initialClass.rawValue) active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count)")
                admissionRejectsByReason["udp_admission_global_hard_saturation", default: 0] += 1
                udpForcedRejects += 1
                if safeMode { safeModeUDPRejectedByPressure += 1 }
                recordStartupGraceUDPAdmission(.rejected, now: now)
                var classState = classState(for: initialClass)
                classState.forcedRejects += 1
                setClassState(classState, for: initialClass)
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                client.cancel()
                return
            }
            let stormMode = isStormMode()
            let pressurePhase = currentTransportPressurePhase(now: now)
            let lowConfidenceFlow = initialClass == .unknown || initialClass == .generic
            let admission = admissionController(for: initialClass).decide(
                active: activeForClass,
                queued: queuedForClass,
                stormMode: stormMode,
                maxActive: min(
                    graceAdjustedLimits.maxActive,
                    effectiveMaxActiveUDPStreams(stormMode: stormMode, safeMode: safeMode)
                ),
                maxQueued: graceAdjustedLimits.maxQueued,
                createRatePerSecond: effectiveCreateRatePerSecond,
                createRateCapacity: graceAdjustedCreateRateCapacity,
                pressurePhase: pressurePhase,
                preferQueueing: stabilityFirstModeEnabled && !(lowConfidenceFlow && (stormMode || extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank)),
                graceActive: hasAnyProtectionGrace(now: now),
                now: now
            )
            switch admission {
            case .accept:
                recordStartupGraceUDPAdmission(.accepted, now: now)
                break
            case .queue:
                if queuedUDPControlIDs.contains(id) {
                    requeueChurnCount += 1
                    log.log("UDP #\(id): FWD_UDP queue_dedup_skip class=\(initialClass.rawValue)")
                    return
                }
                log.log("UDP #\(id): FWD_UDP queued by admission controller class=\(initialClass.rawValue) active=\(activeForClass) queued=\(queuedForClass + 1)")
                recordStartupGraceUDPAdmission(.queued, now: now)
                pendingUDPControlQueue.append(
                    PendingUDPControl(
                        client: client,
                        id: id,
                        enqueuedAt: Date(),
                        trafficClass: initialClass,
                        preserveDuringPressure: Self.isPreservedQueuedTrafficClass(initialClass),
                        lowConfidence: initialClass == .unknown || initialClass == .generic,
                        initialBytes: initialBytes,
                        requestHadTail: requestHadTail
                    )
                )
                queuedUDPControlIDs.insert(id)
                var classState = classState(for: initialClass)
                classState.queuedUDP = queuedForClass + 1
                setClassState(classState, for: initialClass)
                return
            case .reject(let reason):
                log.log("UDP #\(id): FWD_UDP rejected by admission controller reason=\(reason) reject_scope=class class=\(initialClass.rawValue) active=\(activeForClass) queued=\(queuedForClass)")
                admissionRejectsByReason["udp_admission_\(initialClass.rawValue)_\(reason)", default: 0] += 1
                udpForcedRejects += 1
                if safeMode { safeModeUDPRejectedByPressure += 1 }
                recordStartupGraceUDPAdmission(.rejected, now: now)
                var classState = classState(for: initialClass)
                classState.forcedRejects += 1
                setClassState(classState, for: initialClass)
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                client.cancel()
                return
            }
        }
        if Self.isTargetTrafficClass(initialClass) && shouldRejectNewProtectedUDPControlStream() {
            let reason = degradedState == .tripped ? "tripped_\(initialClass.rawValue)_udp_reject" : "degraded_\(initialClass.rawValue)_udp_reject"
            log.log("UDP #\(id): FWD_UDP rejected reason=\(reason) reject_scope=class class=\(initialClass.rawValue) state=\(degradedState.rawValue) queue=\(pendingUDPControlQueue.count)")
            udpForcedRejects += 1
            if safeMode { safeModeUDPRejectedByPressure += 1 }
            udpReclaimsByReason[reason, default: 0] += 1
            admissionRejectsByReason[reason, default: 0] += 1
            recordStartupGraceUDPAdmission(.rejected, now: now)
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return
        }
        startAcceptedUDPControlStream(
            client: client,
            id: id,
            trafficClass: initialClass,
            initialBytes: initialBytes,
            requestHadTail: requestHadTail
        )
    }

    private func currentUDPForwardingMode() -> UDPForwardingMode {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return Self.currentUDPForwardingMode(defaults: defaults)
    }

    static func currentUDPForwardingMode(defaults: UserDefaults?) -> UDPForwardingMode {
        let selective = defaults?.object(forKey: BubbleConstants.udpSelectiveSafeModeEnabledKey) as? Bool
        let legacyDisabled = defaults?.object(forKey: BubbleConstants.udpForwardingDisabledKey) as? Bool
        let diagnosticFastReject = defaults?.object(forKey: BubbleConstants.udpDisabledFastRejectEnabledKey) as? Bool
        return resolveUDPForwardingMode(
            selectiveSafeModeValue: selective,
            legacyDisabledValue: legacyDisabled,
            diagnosticFastRejectValue: diagnosticFastReject
        )
    }

    static func resolveUDPForwardingMode(
        selectiveSafeModeValue: Bool?,
        legacyDisabledValue: Bool?,
        diagnosticFastRejectValue: Bool? = nil
    ) -> UDPForwardingMode {
        if diagnosticFastRejectValue == true {
            return .disabledFastReject
        }
        if let selectiveSafeModeValue {
            if selectiveSafeModeValue {
                return .selectiveSafeMode
            }
            return .nativeForwarding
        }
        if let legacyDisabledValue {
            return legacyDisabledValue ? .selectiveSafeMode : .nativeForwarding
        }
        return .selectiveSafeMode
    }

    static func migratedUDPSelectiveSafeModeValue(
        existingSelectiveValue: Bool?,
        legacyDisabledValue: Bool?
    ) -> Bool {
        existingSelectiveValue ?? legacyDisabledValue ?? true
    }

    private func recordStartupGraceUDPAdmission(_ outcome: StartupGraceUDPAdmissionOutcome, now: Date = Date()) {
        guard isStartupGraceActive(now: now) else { return }
        switch outcome {
        case .accepted:
            startupGraceUDPAccepted += 1
        case .queued:
            startupGraceUDPQueued += 1
        case .rejected:
            startupGraceUDPRejected += 1
        }
    }

    private func udpForwardingMode() -> String {
        currentUDPForwardingMode().rawValue
    }

    private func isUDPCrashGuardActive(now: Date = Date()) -> Bool {
        now < udpCrashGuardUntil
    }

    private func isUDPStartupSerialModeActive(now: Date = Date()) -> Bool {
        now < udpStartupSerialUntil || isUDPCrashGuardActive(now: now)
    }

    private func effectiveMaxActiveUDPStreamsForDrain(now: Date = Date(), stormMode: Bool, safeMode: Bool) -> Int {
        Self.drainActiveLimitDuringStartupGuard(
            startupGuardActive: isUDPStartupSerialModeActive(now: now),
            stormMode: stormMode,
            safeMode: safeMode
        )
    }

    private func queueUDPControlForStartupSerialMode(
        client: NWConnection,
        id: Int,
        trafficClass: TrafficClass,
        now: Date,
        maxQueued: Int,
        initialBytes: Data = Data(),
        requestHadTail: Bool = false
    ) -> Bool {
        guard isUDPStartupSerialModeActive(now: now) else { return false }
        let serialActiveLimit = Self.drainActiveLimitDuringStartupGuard(
            startupGuardActive: true,
            stormMode: isStormMode(),
            safeMode: currentUDPForwardingMode() == .selectiveSafeMode
        )
        guard activeUDPStreams >= serialActiveLimit || !pendingUDPControlQueue.isEmpty || udpCloseFinalizationsInFlight > 0 else {
            return false
        }
        if queuedUDPControlIDs.contains(id) {
            requeueChurnCount += 1
            log.log("UDP #\(id): FWD_UDP startup_serial_queue_dedup_skip class=\(trafficClass.rawValue)")
            return true
        }
        guard pendingUDPControlQueue.count < maxQueued else {
            drainQueuedUDPControlStreamsIfNeeded()
            if pendingUDPControlQueue.count < maxQueued {
                return queueUDPControlForStartupSerialMode(
                    client: client,
                    id: id,
                    trafficClass: trafficClass,
                    now: now,
                    maxQueued: maxQueued,
                    initialBytes: initialBytes,
                    requestHadTail: requestHadTail
                )
            }
            _ = maybeTriggerUDPStartupGuardEscapeHatch(reason: "queue_full_reject", now: now)
            log.log("UDP #\(id): FWD_UDP rejected reason=udp_startup_serial_queue_full class=\(trafficClass.rawValue) active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count)")
            admissionRejectsByReason["udp_startup_serial_queue_full", default: 0] += 1
            udpForcedRejects += 1
            recordStartupGraceUDPAdmission(.rejected, now: now)
            activeConnectionCount = max(activeConnectionCount - 1, 0)
            client.cancel()
            return true
        }
        log.log("UDP #\(id): FWD_UDP queued by startup serial mode class=\(trafficClass.rawValue) active=\(activeUDPStreams) queued=\(pendingUDPControlQueue.count + 1) crash_guard=\(isUDPCrashGuardActive(now: now))")
        pendingUDPControlQueue.append(
            PendingUDPControl(
                client: client,
                id: id,
                enqueuedAt: now,
                trafficClass: trafficClass,
                preserveDuringPressure: Self.isPreservedQueuedTrafficClass(trafficClass),
                lowConfidence: trafficClass == .unknown || trafficClass == .generic,
                initialBytes: initialBytes,
                requestHadTail: requestHadTail
            )
        )
        queuedUDPControlIDs.insert(id)
        recordStartupGraceUDPAdmission(.queued, now: now)
        var classState = classState(for: trafficClass)
        classState.queuedUDP = countQueuedUDPStreams(for: trafficClass)
        setClassState(classState, for: trafficClass)
        _ = maybeTriggerUDPStartupGuardEscapeHatch(reason: "queue_saturated", now: now)
        return true
    }

    private func rejectFwdUDPDisabled(client: NWConnection, id: Int, host: String, port: UInt16) {
        let trafficClass = TrafficClass.unknown
        recordUDPDisabledFastReject(id: id, host: host, port: port)
        admissionRejectsByReason["udp_forwarding_disabled", default: 0] += 1
        udpForcedRejects += 1
        var classState = classState(for: trafficClass)
        classState.forcedRejects += 1
        setClassState(classState, for: trafficClass)
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        client.cancel()
    }

    private func recordUDPDisabledFastReject(id: Int, host: String, port: UInt16, now: Date = Date()) {
        udpDisabledFastRejects += 1
        let destination = "\(host.lowercased()):\(port)"
        let logWindow = BubbleConstants.udpDisabledFastRejectLogWindowSeconds

        if var state = udpDisabledRejectLogStateByDestination[destination],
           now.timeIntervalSince(state.windowStartedAt) <= logWindow {
            state.lastSeen = now
            state.suppressedHits += 1
            udpDisabledRejectLogStateByDestination[destination] = state
            udpDisabledFastRejectsSuppressed += 1
            if state.suppressedHits % BubbleConstants.udpDisabledFastRejectSummaryEvery == 0 {
                log.log(
                    "UDP_DISABLED_FAST_REJECT_SUMMARY destination=\(destination) suppressed=\(state.suppressedHits) total=\(udpDisabledFastRejects) udp_forwarding_mode=disabled_fast_reject"
                )
            }
            return
        }

        udpDisabledRejectLogStateByDestination[destination] = UDPDisabledRejectLogState(
            windowStartedAt: now,
            lastSeen: now,
            suppressedHits: 0
        )
        log.breadcrumb(
            "udp_off_fast_reject",
            details: "destination=\(destination) udp_forwarding_mode=disabled_fast_reject",
            minInterval: 10.0
        )
        log.log(
            "UDP #\(id): FWD_UDP rejected reason=udp_forwarding_disabled reject_scope=user_setting destination=\(destination) udp_forwarding_mode=disabled_fast_reject"
        )
        if udpDisabledRejectLogStateByDestination.count > BubbleConstants.extensionPressureMaxSuppressionEntries {
            let overflow = udpDisabledRejectLogStateByDestination.count - BubbleConstants.extensionPressureMaxSuppressionEntries
            for oldKey in udpDisabledRejectLogStateByDestination.sorted(by: { $0.value.lastSeen < $1.value.lastSeen }).prefix(overflow).map(\.key) {
                udpDisabledRejectLogStateByDestination.removeValue(forKey: oldKey)
            }
        }
    }

    private func startDNSFastLaneControlStream(client: NWConnection, id: Int, initialBytes: Data) {
        if udpStreamsByID[id] != nil {
            log.log("DNS_FAST_LANE duplicate_fwd_udp_ignored stream=\(id)")
            return
        }

        recordProviderPhase("dns_fast_lane_accept")
        log.log("DNS_FAST_LANE accept stream=\(id) request_tail_bytes=\(initialBytes.count) request_tail_hex=\(hexPrefix(initialBytes)) udp_forwarding_mode=selective_safe_mode")
        let state = UDPStreamState(
            id: id,
            client: client,
            decoder: UDPControlStreamDecoder(maxFrameSize: BubbleConstants.maxUDPFrameSize, maxResyncAttempts: 0),
            trafficClass: .generic
        )
        state.socksRequestHadTail = !initialBytes.isEmpty
        udpStreamsByID[id] = state
        recordLastControlStream(state: state, reason: "dns_fast_lane_accept")
        activeUDPStreams += 1
        var classState = classState(for: state.trafficClass)
        classState.activeUDP = countActiveUDPStreams(for: state.trafficClass)
        setClassState(classState, for: state.trafficClass)
        udpActivePeak = max(udpActivePeak, activeUDPStreams)
        totalUDPStreamsOpened += 1
        recentUDPCreateTimestamps.append(Date())

        let reply = buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
        client.send(content: reply, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.dnsFastLaneFailures += 1
                self.log.logAndFlush("DNS_FAST_LANE reply_failed stream=\(id) error=\(error)")
                self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_reply_failed")
                return
            }
            if !initialBytes.isEmpty {
                let outcome = self.consumeDNSFastLaneBytes(
                    client: client,
                    state: state,
                    data: initialBytes,
                    isComplete: false,
                    source: "request_tail"
                )
                if outcome == .consumed {
                    return
                }
            }
            self.readDNSFastLaneFrame(client: client, state: state)
        })
    }

    private func readDNSFastLaneFrame(client: NWConnection, state: UDPStreamState) {
        guard !state.closed else { return }
        client.receive(minimumIncompleteLength: 1, maximumLength: BubbleConstants.maxUDPFrameSize + 8) { [weak self] data, _, isComplete, error in
            guard let self, !state.closed else { return }

            if let error {
                self.recordDNSFastLaneParseFailure(state: state, stage: "read_error", detail: "\(error)", source: "client_receive")
                self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
                return
            }

            guard let data, !data.isEmpty else {
                if isComplete {
                    self.recordDNSFastLaneParseFailure(state: state, stage: "empty_stream", detail: "complete_without_frame", source: "client_receive")
                    self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
                } else {
                    self.readDNSFastLaneFrame(client: client, state: state)
                }
                return
            }

            state.lastActivityAt = Date()
            let outcome = self.consumeDNSFastLaneBytes(
                client: client,
                state: state,
                data: data,
                isComplete: isComplete,
                source: "client_receive"
            )
            if outcome == .waitingForMore {
                self.readDNSFastLaneFrame(client: client, state: state)
            }
        }
    }

    @discardableResult
    private func consumeDNSFastLaneBytes(
        client: NWConnection,
        state: UDPStreamState,
        data: Data,
        isComplete: Bool,
        source: String
    ) -> DNSFastLaneConsumeOutcome {
        guard !state.closed else { return .consumed }
        let inputData: Data
        if state.dnsFastLanePendingRawBytes.isEmpty {
            inputData = data
        } else {
            var merged = state.dnsFastLanePendingRawBytes
            merged.append(data)
            inputData = merged
        }
        let inputFormat = Self.dnsFastLaneInputFormat(data: inputData, decoder: state.decoder)
        let decoderSnapshotBefore = state.decoder.diagnosticSnapshot()
        log.log(
            "DNS_FAST_LANE input stream=\(state.id) source=\(source) bytes=\(inputData.count) hex=\(hexPrefix(inputData)) decoder_mode=\(decoderSnapshotBefore.mode) decoder_state=\(decoderSnapshotBefore.state) input_format=\(inputFormat) socks_request_had_tail=\(state.socksRequestHadTail)"
        )

        if state.decoder.currentMode == nil {
            switch Self.rawUDPControlPayloadStatus(inputData) {
            case .parseable:
                state.dnsFastLanePendingRawBytes.removeAll()
            case .needMoreBytes(let kind):
                if !isComplete, inputData.count <= BubbleConstants.maxUDPFrameSize {
                    state.dnsFastLanePendingRawBytes = inputData
                    log.log(
                        "DNS_FAST_LANE raw_payload_wait stream=\(state.id) source=\(source) kind=\(kind) bytes=\(inputData.count) hex=\(hexPrefix(inputData)) socks_request_had_tail=\(state.socksRequestHadTail)"
                    )
                    return .waitingForMore
                }
                state.dnsFastLanePendingRawBytes.removeAll()
            case .notRaw:
                state.dnsFastLanePendingRawBytes.removeAll()
            }
        }

        let decodeResult = Self.decodeDNSFastLaneInput(data: inputData, decoder: state.decoder)
        if let mode = state.decoder.currentMode {
            state.mode = mode
        }

        switch decodeResult {
        case .frame(let frame, let trailing):
            if trailing > 0 {
                dnsTrailingFramesDiscarded += trailing
                log.log("DNS_FAST_LANE trailing_frames_ignored stream=\(state.id) count=\(trailing)")
            }
            processDNSFastLaneFrame(client: client, state: state, decodedFrame: frame)
            return .consumed

        case .needMoreBytes:
            if isComplete {
                recordDNSFastLaneParseFailure(
                    state: state,
                    stage: "frame_decode",
                    detail: "complete_without_decoded_frame",
                    source: source,
                    byteCount: inputData.count,
                    hexPrefix: hexPrefix(inputData),
                    decoderMode: decoderSnapshotBefore.mode,
                    decoderState: decoderSnapshotBefore.state,
                    inputFormat: inputFormat
                )
                closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
                return .consumed
            }
            return .waitingForMore

        case .failed(let decodeError):
            recordDNSFastLaneParseFailure(
                state: state,
                stage: "frame_decode",
                detail: decoderReasonCode(decodeError),
                source: source,
                byteCount: inputData.count,
                hexPrefix: hexPrefix(inputData),
                decoderMode: state.decoder.diagnosticSnapshot().mode,
                decoderState: state.decoder.diagnosticSnapshot().state,
                inputFormat: inputFormat
            )
            closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
            return .consumed
        }
    }

    private func processDNSFastLaneFrame(client: NWConnection, state: UDPStreamState, decodedFrame: UDPControlFrame) {
        guard !state.closed else { return }
        guard let parsed = parseUDPPayload(decodedFrame.payload, streamID: state.id) else {
            recordDNSFastLaneParseFailure(
                state: state,
                stage: "udp_payload",
                detail: "invalid_udp_payload",
                source: "decoded_frame",
                byteCount: decodedFrame.payload.count,
                hexPrefix: hexPrefix(Data(decodedFrame.payload)),
                decoderMode: decodedFrame.mode.rawValue,
                decoderState: state.decoder.diagnosticSnapshot().state,
                inputFormat: "invalid_non_dns_payload"
            )
            closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
            return
        }

        state.mode = decodedFrame.mode
        state.lastHost = parsed.addr.host
        state.lastPort = parsed.addr.port
        state.seenDNSPort = parsed.addr.port == 53
        recordLastControlStream(state: state, reason: "dns_fast_lane_frame")

        switch Self.selectiveSafeModeUDPDecision(destinationPort: parsed.addr.port) {
        case .reject(let reason):
            recordSelectiveSafeModeUDPReject(streamID: state.id, host: parsed.addr.host, port: parsed.addr.port, reason: reason)
            closeDNSFastLaneControlStream(client: client, state: state, reason: reason)
            return

        case .dnsFastLane:
            break
        }

        guard Self.isValidDNSFastLanePayload(parsed.payload) else {
            recordDNSFastLaneParseFailure(
                state: state,
                stage: "dns_payload",
                detail: "invalid_dns_datagram_length=\(parsed.payload.count)",
                source: "decoded_frame",
                byteCount: decodedFrame.payload.count,
                hexPrefix: hexPrefix(Data(decodedFrame.payload)),
                decoderMode: decodedFrame.mode.rawValue,
                decoderState: state.decoder.diagnosticSnapshot().state,
                inputFormat: "invalid_non_dns_payload"
            )
            closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_parse_failed")
            return
        }

        statsUDP += 1
        dnsFastLaneRequests += 1
        recordProviderPhase("dns_fast_lane_request")
        log.logAndFlush("DNS_FAST_LANE request stream=\(state.id) host=\(parsed.addr.host):\(parsed.addr.port) bytes=\(parsed.payload.count)")
        let resolvedHost = effectiveResolverHost(originalHost: parsed.addr.host, port: parsed.addr.port)
        relayDNSOverTCPDatagram(
            streamID: state.id,
            host: resolvedHost,
            port: parsed.addr.port,
            payload: parsed.payload,
            headerBytes: parsed.headerBytes,
            responseMode: decodedFrame.mode
        ) { [weak self] responseFrame in
            guard let self, !state.closed else { return }
            guard let responseFrame else {
                self.dnsFastLaneFailures += 1
                self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_failure_close")
                return
            }

            self.dnsFastLaneResponses += 1
            state.markProgress(now: Date())
            self.recordProviderPhase("dns_fast_lane_response_send_start")
            self.log.logAndFlush("DNS_FAST_LANE response_send_start stream=\(state.id) bytes=\(responseFrame.count)")
            client.send(
                content: responseFrame,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { [weak self] sendError in
                    guard let self, !state.closed else { return }
                    if let sendError {
                        self.dnsFastLaneFailures += 1
                        self.log.logAndFlush("DNS_FAST_LANE response_send_error stream=\(state.id) error=\(sendError)")
                        self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_failure_close")
                        return
                    }
                    self.recordProviderPhase("dns_fast_lane_response_sent")
                    self.log.logAndFlush("DNS_FAST_LANE response_sent stream=\(state.id) bytes=\(responseFrame.count)")
                    self.closeDNSFastLaneControlStream(client: client, state: state, reason: "dns_fast_lane_close")
                }
            )
        }
    }

    private func recordDNSFastLaneParseFailure(
        state: UDPStreamState,
        stage: String,
        detail: String,
        source: String,
        byteCount: Int? = nil,
        hexPrefix: String = "",
        decoderMode: String? = nil,
        decoderState: String? = nil,
        inputFormat: String? = nil
    ) {
        dnsFastLaneParseFailed += 1
        dnsFastLaneFailures += 1
        statsErrors += 1
        recordProviderPhase("dns_fast_lane_parse_failed")
        let snapshot = state.decoder.diagnosticSnapshot()
        log.log(
            "DNS_FAST_LANE dns_fast_lane_parse_failed stream=\(state.id) stage=\(stage) detail=\(detail) source=\(source) bytes=\(byteCount.map(String.init) ?? "unknown") hex=\(hexPrefix) decoder_mode=\(decoderMode ?? snapshot.mode) decoder_state=\(decoderState ?? snapshot.state) buffered=\(snapshot.bufferedBytes) input_format=\(inputFormat ?? "unknown") socks_request_had_tail=\(state.socksRequestHadTail)"
        )
        if !hexPrefix.isEmpty {
            recordLastDecoderEvent(
                reason: detail,
                hexPrefix: hexPrefix,
                recoveredFrames: 0,
                discardedFrames: 0,
                streamID: state.id,
                source: source,
                byteCount: byteCount,
                decoderMode: decoderMode ?? snapshot.mode,
                decoderState: decoderState ?? snapshot.state,
                socksRequestHadTail: state.socksRequestHadTail
            )
        }
        noteDNSFastLaneParseFailureForSummary(stage: stage, detail: detail)
        noteDNSFastLaneParseFailureForSafetyValve(stage: stage, detail: detail)
    }

    private func noteDNSFastLaneParseFailureForSummary(stage: String, detail: String) {
        let now = Date()
        if dnsFastLaneParseFailureSummaryWindowStartedAt == nil {
            dnsFastLaneParseFailureSummaryWindowStartedAt = now
            let work = DispatchWorkItem { [weak self] in
                self?.flushDNSFastLaneParseFailureSummary()
            }
            dnsFastLaneParseFailureSummaryWorkItem = work
            queue.asyncAfter(deadline: .now() + BubbleConstants.dnsFastLaneParseFailureSummaryWindowSeconds, execute: work)
        }
        dnsFastLaneParseFailureSummaryCount += 1
        let key = "\(stage):\(detail)"
        dnsFastLaneParseFailureSummaryByDetail[key, default: 0] += 1
    }

    private func noteDNSFastLaneParseFailureForSafetyValve(stage: String, detail: String, now: Date = Date()) {
        dnsFastLaneParseFailureTimestamps = dnsFastLaneParseFailureTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.dnsFastLaneDisableFailureWindowSeconds
        }
        dnsFastLaneParseFailureTimestamps.append(now)

        guard !dnsFastLaneDisabledForSession,
              dnsFastLaneParseFailureTimestamps.count >= BubbleConstants.dnsFastLaneDisableFailureThreshold else {
            return
        }

        dnsFastLaneDisabledForSession = true
        dnsFastLaneDisabledReason = "parse_failure_threshold_stage_\(stage)_detail_\(detail)"
        recordProviderPhase("dns_fast_lane_disabled")
        log.logAndFlush(
            "DNS_FAST_LANE disabled_for_session reason=\(dnsFastLaneDisabledReason) failures=\(dnsFastLaneParseFailureTimestamps.count) window_s=\(String(format: "%.2f", BubbleConstants.dnsFastLaneDisableFailureWindowSeconds)) fallback=generic_udp_relay"
        )
    }

    private func flushDNSFastLaneParseFailureSummary() {
        guard dnsFastLaneParseFailureSummaryCount > 0 else {
            dnsFastLaneParseFailureSummaryWindowStartedAt = nil
            dnsFastLaneParseFailureSummaryWorkItem = nil
            return
        }
        let startedAt = dnsFastLaneParseFailureSummaryWindowStartedAt ?? Date()
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        let details = dnsFastLaneParseFailureSummaryByDetail
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        log.log(
            "DNS_FAST_LANE_PARSE_FAILED_SUMMARY window_s=\(String(format: "%.2f", elapsed)) total=\(dnsFastLaneParseFailureSummaryCount) details=\(details)"
        )
        dnsFastLaneParseFailureSummaryWindowStartedAt = nil
        dnsFastLaneParseFailureSummaryCount = 0
        dnsFastLaneParseFailureSummaryByDetail.removeAll()
        dnsFastLaneParseFailureSummaryWorkItem = nil
    }

    private func recordSelectiveSafeModeUDPReject(streamID: Int, host: String, port: UInt16, reason: String) {
        udpNonDNSRejects += 1
        if port == 443 {
            udpQUICRejects += 1
        }
        udpForcedRejects += 1
        admissionRejectsByReason[reason, default: 0] += 1
        log.log(
            "UDP #\(streamID): FWD_UDP rejected reason=\(reason) reject_scope=selective_safe_mode destination=\(host.lowercased()):\(port) udp_forwarding_mode=selective_safe_mode"
        )
    }

    private func closeDNSFastLaneControlStream(client: NWConnection, state: UDPStreamState, reason: String) {
        guard !state.closed else { return }
        state.closed = true
        state.closeReason = reason
        state.closePhase = .cancelled
        lastUDPClosePhase = state.closePhase
        dnsFastLaneClose += 1
        recordProviderPhase("dns_fast_lane_close")
        udpStreamsByID.removeValue(forKey: state.id)
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        activeUDPStreams = max(activeUDPStreams - 1, 0)
        var classState = classState(for: state.trafficClass)
        classState.activeUDP = countActiveUDPStreams(for: state.trafficClass)
        setClassState(classState, for: state.trafficClass)
        totalUDPStreamsClosed += 1
        streamCloseReasonCounts[reason, default: 0] += 1
        recordLastControlStream(state: state, reason: reason)
        if state.lastPort == 53 {
            recordLastDNSClose(state: state, reason: reason, trailingDiscarded: 0, recoveredDiscarded: 0)
        }
        log.logAndFlush(
            "DNS_FAST_LANE close stream=\(state.id) reason=\(reason) host=\(state.lastHost ?? "") port=\(state.lastPort.map(String.init) ?? "unknown")"
        )
        client.cancel()
    }

    private func startAcceptedUDPControlStream(
        client: NWConnection,
        id: Int,
        trafficClass: TrafficClass,
        initialBytes: Data = Data(),
        requestHadTail: Bool = false
    ) {
        recordProviderPhase("udp_accept")
        log.log("UDP #\(id): FWD_UDP accepted, starting frame relay class=\(trafficClass.rawValue) request_tail_bytes=\(initialBytes.count) request_tail_hex=\(hexPrefix(initialBytes))")
        let state = UDPStreamState(
            id: id,
            client: client,
            decoder: UDPControlStreamDecoder(maxFrameSize: BubbleConstants.maxUDPFrameSize),
            trafficClass: trafficClass
        )
        state.socksRequestHadTail = requestHadTail || !initialBytes.isEmpty
        udpStreamsByID[id] = state
        recordLastControlStream(state: state, reason: "accepted")
        activeUDPStreams += 1
        var classState = classState(for: trafficClass)
        classState.activeUDP = countActiveUDPStreams(for: trafficClass)
        setClassState(classState, for: trafficClass)
        udpActivePeak = max(udpActivePeak, activeUDPStreams)
        totalUDPStreamsOpened += 1
        recentUDPCreateTimestamps.append(Date())

        let reply = buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
        client.send(content: reply, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                self.closeUDPControlStream(client: client, state: state, reason: "send_reply_failed")
                return
            }
            if !initialBytes.isEmpty {
                self.consumeUDPControlStreamBytes(
                    client: client,
                    state: state,
                    data: initialBytes,
                    source: "request_tail"
                )
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
                state.lastActivityAt = Date()
                self.consumeUDPControlStreamBytes(client: client, state: state, data: data, source: "client_receive")
                return
            }

            if isComplete {
                self.closeUDPControlStream(client: client, state: state, reason: "control_stream_completed")
            } else {
                self.readUDPControlStream(client: client, state: state)
            }
        }
    }

    private func consumeUDPControlStreamBytes(client: NWConnection, state: UDPStreamState, data: Data, source: String) {
        let appendResult = state.decoder.append(data)
        if let mode = state.decoder.currentMode, state.mode == nil {
            state.mode = mode
            udpDecodeModeDetected += 1
            if mode == .plain {
                udpModePlain += 1
            } else {
                udpModeControlPrefixed += 1
            }
            log.log("UDP_DECODER stream=\(state.id) event=mode_locked mode=\(mode.rawValue) source=\(source) socks_request_had_tail=\(state.socksRequestHadTail)")
        }
        let diagnostics = state.decoder.drainDiagnostics()
        udpDecodeResyncAttempted += diagnostics.resyncAttempts
        udpDecodeResyncSuccess += diagnostics.resyncSuccesses

        state.pendingFrames.append(contentsOf: appendResult.frames)
        if state.hardeningEnabled && state.pendingFrames.count > BubbleConstants.tiktokHardeningMaxPendingFramesPerStream {
            tiktokHardeningActions["pending_frames_overflow_close", default: 0] += 1
            closeUDPControlStream(client: client, state: state, reason: "tiktok_pending_frames_overflow")
            return
        }

        switch appendResult.status {
        case .ok:
            if !appendResult.frames.isEmpty {
                state.decoderFailureCount = 0
                state.firstDecoderFailureAt = nil
            }
            processNextUDPFrame(client: client, state: state)
        case .needMoreBytes:
            readUDPControlStream(client: client, state: state)
        case .recovered(let decodeError):
            recordProviderPhase("decoder_recovery")
            recordDecoderError(decodeError, hardFailure: false)
            state.decoderRecoveryCount += 1
            state.recoveredFramesPending += appendResult.frames.count
            decoderSoftDiscards += 1
            let now = Date()
            let failuresInWindow = state.decoderFailuresInWindow(now: now, window: BubbleConstants.udpDecodeFailureWindowSeconds)
            let density = state.bumpDecoderErrorDensity(now: now)
            udpDecodeRecoveredStreamContinues += 1
            let reasonCode = decoderReasonCode(decodeError)
            let prefix = hexPrefix(data)
            let snapshot = state.decoder.diagnosticSnapshot()
            recordLastDecoderEvent(
                reason: reasonCode,
                hexPrefix: prefix,
                recoveredFrames: appendResult.frames.count,
                discardedFrames: 0,
                streamID: state.id,
                source: source,
                byteCount: data.count,
                decoderMode: snapshot.mode,
                decoderState: snapshot.state,
                socksRequestHadTail: state.socksRequestHadTail
            )
            log.log(
                "UDP_DECODER stream=\(state.id) event=decode_recovered reason=\(reasonCode) source=\(source) bytes=\(data.count) bytes_hex=\(prefix) decoder_mode=\(snapshot.mode) decoder_state=\(snapshot.state) buffered=\(snapshot.bufferedBytes) socks_request_had_tail=\(state.socksRequestHadTail) failures_in_window=\(failuresInWindow) density=\(String(format: "%.2f", density))"
            )
            if (failuresInWindow > effectiveDecodeFailureCloseThreshold() || density >= effectiveRecoveredDecoderCloseDensity()) && !hasAnyProtectionGrace() {
                recordDecoderError(decodeError, hardFailure: true)
                udpDecodeCloseAfterFailureThreshold += 1
                decoderErrorDensityCloses += 1
                closeUDPControlStream(client: client, state: state, reason: "decode_recovered_threshold_exceeded")
                return
            }
            processNextUDPFrame(client: client, state: state)
        case .failed(let decodeError):
            recordDecoderError(decodeError, hardFailure: false)
            decoderErrorCount += 1
            state.decoderFailureCount += 1
            decoderSoftDiscards += 1
            let snapshot = state.decoder.diagnosticSnapshot()
            let reasonCode = decoderReasonCode(decodeError)
            recordLastDecoderEvent(
                reason: reasonCode,
                hexPrefix: hexPrefix(data),
                recoveredFrames: 0,
                discardedFrames: 0,
                streamID: state.id,
                source: source,
                byteCount: data.count,
                decoderMode: snapshot.mode,
                decoderState: snapshot.state,
                socksRequestHadTail: state.socksRequestHadTail
            )
            let density = state.bumpDecoderErrorDensity(now: Date())
            if state.firstDecoderFailureAt == nil {
                state.firstDecoderFailureAt = Date()
            }
            log.log(
                "UDP_DECODER stream=\(state.id) event=decode_error reason=\(reasonCode) source=\(source) bytes=\(data.count) bytes_hex=\(hexPrefix(data)) decoder_mode=\(snapshot.mode) decoder_state=\(snapshot.state) buffered=\(snapshot.bufferedBytes) socks_request_had_tail=\(state.socksRequestHadTail) failures=\(state.decoderFailureCount) density=\(String(format: "%.2f", density))"
            )
            if case .badLength = decodeError {
                let failuresInWindow = state.decoderFailuresInWindow(now: Date(), window: BubbleConstants.udpDecodeFailureWindowSeconds)
                if failuresInWindow <= effectiveBadLenSoftFailureLimit() || isStormMode() || hasAnyProtectionGrace() {
                    log.log("UDP_DECODER stream=\(state.id) event=soft_fail_bad_len reason=bad_len source=\(source) bytes=\(data.count) bytes_hex=\(hexPrefix(data)) decoder_mode=\(snapshot.mode) decoder_state=\(snapshot.state) buffered=\(snapshot.bufferedBytes) socks_request_had_tail=\(state.socksRequestHadTail) failures_in_window=\(failuresInWindow)")
                    readUDPControlStream(client: client, state: state)
                    return
                }
                recordDecoderError(decodeError, hardFailure: true)
                log.log("UDP_DECODER stream=\(state.id) event=close_after_bad_len_window reason=bad_len source=\(source) failures_in_window=\(failuresInWindow)")
                closeUDPControlStream(client: client, state: state, reason: "decode_bad_len_window_fail_closed")
                return
            }
            if (state.decoderFailureCount >= effectiveDecodeFailureCloseThreshold() || density >= effectiveDecoderCloseDensity()) && !hasAnyProtectionGrace() {
                recordDecoderError(decodeError, hardFailure: true)
                udpDecodeCloseAfterFailureThreshold += 1
                decoderErrorDensityCloses += 1
                log.log("UDP_DECODER stream=\(state.id) event=close_after_failures reason=\(reasonCode) threshold=\(BubbleConstants.udpDecodeFailureCloseThreshold)")
                closeUDPControlStream(client: client, state: state, reason: "decode_\(reasonCode)_threshold_exceeded")
                return
            }
            readUDPControlStream(client: client, state: state)
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
        let decodedFromRecovery = state.recoveredFramesPending > 0
        if decodedFromRecovery {
            state.recoveredFramesPending = max(0, state.recoveredFramesPending - 1)
        }
        state.dnsStartupDrainIdleCloseWorkItem?.cancel()
        state.dnsStartupDrainIdleCloseWorkItem = nil
        state.processingFrame = true
        state.processingRecoveredFrame = decodedFromRecovery
        state.processingStartedAt = Date()
        state.lastActivityAt = Date()

        guard let parsed = parseUDPPayload(decodedFrame.payload, streamID: state.id) else {
            udpDecodeBadPayload += 1
            log.log("UDP_DECODER stream=\(state.id) event=decode_error reason=bad_payload_soft_drop")
            if state.seenDNSPort {
                dnsMalformedCloses += 1
                udpReclaimsByReason["dns_malformed_one_shot_retire", default: 0] += 1
                log.log("UDP_DNS malformed_close stream=\(state.id) reason=bad_payload_soft_drop")
                closeDNSControlStream(client: client, state: state, reason: "dns_malformed_one_shot_retire")
                return
            }
            state.processingFrame = false
            state.processingRecoveredFrame = false
            state.processingStartedAt = nil
            readUDPControlStream(client: client, state: state)
            return
        }

        state.lastHost = parsed.addr.host
        state.lastPort = parsed.addr.port
        if parsed.addr.port == 53 {
            state.seenDNSPort = true
        }
        log.log("UDP #\(state.id): dest=\(parsed.addr.host):\(parsed.addr.port), payload=\(parsed.payload.count)B")
        if parsed.addr.port == 53, decodedFromRecovery {
            state.recoveredDNSFrameProcessed = true
            log.log("UDP_DNS recovered_frame_one_shot stream=\(state.id) pending=\(state.pendingFrames.count)")
        }

        let safeMode = currentUDPForwardingMode() == .selectiveSafeMode
        if safeMode,
           case .reject(let reason) = Self.selectiveSafeModeUDPDecision(destinationPort: parsed.addr.port) {
            recordSelectiveSafeModeUDPReject(streamID: state.id, host: parsed.addr.host, port: parsed.addr.port, reason: reason)
            closeUDPControlStream(client: client, state: state, reason: reason)
            return
        }
        statsUDP += 1
        let policyEvaluation = evaluateUDPPolicy(
            host: parsed.addr.host,
            port: parsed.addr.port,
            payloadBytes: parsed.payload.count,
            selectiveSafeMode: safeMode
        )
        let decision = policyEvaluation.decision
        let resolvedClass = classifyTrafficClass(host: parsed.addr.host, decision: decision, port: parsed.addr.port)
        if state.trafficClass != resolvedClass {
            state.trafficClass = resolvedClass
            var classState = classState(for: resolvedClass)
            classState.activeUDP = countActiveUDPStreams(for: resolvedClass)
            setClassState(classState, for: resolvedClass)
        }
        state.preservesMessagingControl = preservesMessagingOrControl(decision: decision, port: parsed.addr.port)
        state.lastDecisionReason = decision.reason
        if !state.hardeningEnabled, shouldUseHardenedPath(decision) {
            state.hardeningEnabled = true
            state.hardeningBucket = decision.classification.bucket
            tiktokHardeningActions["stream_promoted_to_tiktok_hardening", default: 0] += 1
        }
        log.log(
            "UDP_POLICY stream=\(state.id) class=\(resolvedClass.rawValue) host=\(parsed.addr.host) port=\(parsed.addr.port) " +
            "action=\(decision.action.rawValue) reason=\(decision.reason) bucket=\(decision.classification.bucket.rawValue)" +
            "\(policyEvaluation.source.map { " source=\($0)" } ?? "")"
        )
        if decision.action == .blockNow {
            let blockedDecisionCount = state.blockedDecisionsInWindow(
                now: Date(),
                window: BubbleConstants.blockedStormRetireWindowSeconds
            )
            if safeMode, isKnownBlockedVideoDecision(decision) {
                safeModeTargetedUDPBlocks += 1
            }
            let blockedTargetCount = state.blockedDatagramsForTargetInWindow(
                host: parsed.addr.host,
                port: parsed.addr.port,
                bucket: decision.classification.bucket,
                now: Date(),
                window: BubbleConstants.blockedStormRetireWindowSeconds
            )
            if safeMode,
               isKnownBlockedVideoDecision(decision),
               blockedTargetCount >= BubbleConstants.selectiveSafeModeBlockedDatagramsBeforeRetire {
                statsBlocked += 1
                recordEvent(type: .blocked, connId: state.id, host: parsed.addr.host, port: parsed.addr.port, detail: "UDP blocked by policy", decision: decision)
                tiktokHardeningActions["selective_safe_mode_blocked_target_retire", default: 0] += 1
                udpReclaimsByReason["selective_safe_mode_blocked_target_retire", default: 0] += 1
                closeUDPControlStream(client: client, state: state, reason: "selective_safe_mode_blocked_target_retire")
                return
            }
            let gate = evaluateProtectionGate(
                host: parsed.addr.host,
                port: parsed.addr.port,
                decision: decision,
                transport: "udp",
                stage: .admission
            )
            if gate == .rejectNewStream || gate == .dropFast {
                blockedSuppressedUDP += 1
                admissionRejectsByReason["udp_\(resolvedClass.rawValue)_drop_fast", default: 0] += 1
                state.processingFrame = false
                state.processingRecoveredFrame = false
                processNextUDPFrame(client: client, state: state)
                return
            }
            if gate == .suppress {
                blockedSuppressedUDP += 1
                admissionRejectsByReason["udp_\(resolvedClass.rawValue)_suppressed", default: 0] += 1
                state.processingFrame = false
                state.processingRecoveredFrame = false
                processNextUDPFrame(client: client, state: state)
                return
            }
            statsBlocked += 1
            recordEvent(type: .blocked, connId: state.id, host: parsed.addr.host, port: parsed.addr.port, detail: "UDP blocked by policy", decision: decision)
            if shouldRetireBlockedStormStream(state: state, blockedDecisionCount: blockedDecisionCount) {
                tiktokHardeningActions["blocked_storm_retire", default: 0] += 1
                udpReclaimsByReason["blocked_storm_retire", default: 0] += 1
                closeUDPControlStream(client: client, state: state, reason: "blocked_storm_retire")
                return
            }
            state.processingFrame = false
            state.processingRecoveredFrame = false
            processNextUDPFrame(client: client, state: state)
            return
        }
        if safeMode,
           parsed.addr.port != 53,
           policyEvaluation.source == nil,
           isUnknownUDPAllow(decision) {
            safeModeUnknownUDPAllowed += 1
            log.log(
                "UDP_SAFE_MODE allow reason=unknown_udp_fail_open stream=\(state.id) " +
                "host=\(parsed.addr.host) port=\(parsed.addr.port) bucket=\(decision.classification.bucket.rawValue)"
            )
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
                state.timeoutStreak = 0
                state.markProgress(now: Date())
                let completesConnection = state.lastPort == 53
                client.send(
                    content: responseFrame,
                    contentContext: .defaultMessage,
                    isComplete: completesConnection,
                    completion: .contentProcessed { [weak self] sendError in
                    guard let self = self else { return }
                    guard !state.closed else { return }
                    state.processingStartedAt = nil
                    if state.lastPort == 53 {
                        if let sendError {
                            self.log.logAndFlush("UDP_DNS response_send_error stream=\(state.id) error=\(sendError)")
                        }
                        if self.shouldUseDNSStartupDrain(state: state) {
                            self.continueDNSStartupDrain(client: client, state: state)
                            return
                        }
                        self.dnsOneShotCloses += 1
                        self.udpReclaimsByReason["dns_response_one_shot_retire", default: 0] += 1
                        self.log.log("UDP_DNS one_shot_close stream=\(state.id) reason=dns_response_one_shot_retire")
                        self.closeDNSControlStream(client: client, state: state, reason: "dns_response_one_shot_retire")
                        return
                    }
                    state.processingRecoveredFrame = false
                    self.processNextUDPFrame(client: client, state: state)
                })
            } else {
                state.timeoutStreak += 1
                if state.lastPort == 53 {
                    self.dnsTimeoutCloses += 1
                    self.udpReclaimsByReason["dns_timeout_one_shot_retire", default: 0] += 1
                    self.log.log("UDP_DNS timeout_close stream=\(state.id) reason=dns_timeout_one_shot_retire")
                    self.closeDNSControlStream(client: client, state: state, reason: "dns_timeout_one_shot_retire")
                    return
                }
                let timeoutThreshold = state.hardeningEnabled
                    ? BubbleConstants.tiktokHardeningTimeoutStreakCloseThreshold
                    : BubbleConstants.udpGlobalTimeoutStreakCloseThreshold
                if state.timeoutStreak >= effectiveTimeoutStreakCloseThreshold(base: timeoutThreshold),
                   shouldCloseStreamForTimeout(state: state, now: Date()) {
                    let reason = state.hardeningEnabled ? "tiktok_timeout_streak_reclaim" : "global_timeout_streak_reclaim"
                    self.tiktokHardeningActions["timeout_streak_reclaim", default: 0] += 1
                    self.udpReclaimsByReason[reason, default: 0] += 1
                    self.closeUDPControlStream(client: client, state: state, reason: reason)
                    return
                }
                state.processingStartedAt = nil
                state.processingRecoveredFrame = false
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
        let resolvedHost = effectiveResolverHost(originalHost: host, port: port)
        if currentUDPForwardingMode() == .selectiveSafeMode {
            guard port == 53 else {
                log.log(
                    "UDP_SAFE_MODE generic_udp_relay_blocked stream=\(streamID) host=\(host):\(port) reason=\(Self.selectiveSafeModeUDPRejectReason(destinationPort: port) ?? "udp_non_dns_rejected_safe_mode")"
                )
                completion(nil)
                return
            }
            recordProviderPhase("dns_tcp_relay_send")
            relayDNSOverTCPDatagram(
                streamID: streamID,
                host: resolvedHost,
                port: port,
                payload: payload,
                headerBytes: headerBytes,
                responseMode: responseMode,
                completion: completion
            )
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log.log("UDP #\(streamID): invalid port \(port)")
            statsErrors += 1
            completion(nil)
            return
        }

        let dedupKey = dnsDedupKey(host: resolvedHost, port: port, payload: payload)
        let dnsDedupWindow = dnsDedupWindowForStream(streamID: streamID)
        if let dedupKey, var inflight = inflightDNSRequests[dedupKey], Date().timeIntervalSince(inflight.startedAt) <= dnsDedupWindow {
            dnsDedupHits += 1
            inflight.callbacks.append(completion)
            inflightDNSRequests[dedupKey] = inflight
            return
        }

        if let dedupKey {
            if inflightDNSRequests.count >= BubbleConstants.dnsInflightMaxEntries {
                sweepInflightDNSExpirations()
                if inflightDNSRequests.count >= BubbleConstants.dnsInflightMaxEntries,
                   let oldestKey = inflightDNSRequests.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
                    inflightDNSRequests.removeValue(forKey: oldestKey)
                    dnsInflight = max(dnsInflight - 1, 0)
                    udpReclaimsByReason["dns_inflight_cap_trim", default: 0] += 1
                }
            }
            dnsInflight += 1
            inflightDNSRequests[dedupKey] = InflightDNSRequest(startedAt: Date(), callbacks: [completion])
        }

        let poolKey = "\(resolvedHost):\(port)"
        let allowReuse = shouldReuseUDPSocket(for: port)
        let udp = pooledUDPConnection(host: resolvedHost, port: nwPort, poolKey: poolKey, allowReuse: allowReuse)
        if port == 53 {
            recordProviderPhase("dns_udp_relay_send")
        }

        var completed = false
        var timeoutWorkItem: DispatchWorkItem?
        let finishOnQueue: (Data?) -> Void = { [weak self] responseFrame in
            guard let self else { return }
            guard !completed else { return }
            completed = true
            timeoutWorkItem?.cancel()
            if !allowReuse {
                udp.cancel()
            }
            if let dedupKey, var inflight = self.inflightDNSRequests.removeValue(forKey: dedupKey) {
                self.dnsInflight = max(self.dnsInflight - 1, 0)
                let callbacks = inflight.callbacks
                inflight.callbacks.removeAll()
                for cb in callbacks {
                    cb(responseFrame)
                }
            } else {
                completion(responseFrame)
            }
        }
        let complete: (Data?) -> Void = { [weak self] responseFrame in
            self?.queue.async {
                finishOnQueue(responseFrame)
            }
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !completed else { return }
            if !self.hasAnyProtectionGrace() || port != 53 {
                self.udpTimeoutCount += 1
            }
            self.markResolverTimeout(host: resolvedHost, port: port)
            if allowReuse {
                self.evictUDPSocket(poolKey: poolKey)
            } else {
                udp.cancel()
            }
            self.log.logAndFlush("UDP #\(streamID): TIMEOUT for \(resolvedHost):\(port)")
            finishOnQueue(nil)
        }
        timeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + BubbleConstants.udpRelayTimeout, execute: timeout)

        udp.stateUpdateHandler = { [weak self] connState in
            switch connState {
            case .ready:
                self?.log.logAndFlush("UDP #\(streamID): NWConnection ready to \(resolvedHost):\(port), sending \(payload.count)B")
                udp.send(content: payload, completion: .contentProcessed { error in
                    if let error {
                        self?.markResolverTimeout(host: resolvedHost, port: port)
                        if allowReuse {
                            self?.evictUDPSocket(poolKey: poolKey)
                        } else {
                            udp.cancel()
                        }
                        self?.log.logAndFlush("UDP #\(streamID): send FAILED to \(resolvedHost):\(port): \(error)")
                        complete(nil)
                        return
                    }

                    self?.log.logAndFlush("UDP #\(streamID): send_complete to \(resolvedHost):\(port), arming receive")
                    udp.receiveMessage { respData, _, _, recvError in
                        if let respData, !respData.isEmpty {
                            self?.markResolverSuccess(host: resolvedHost, port: port)
                            self?.log.logAndFlush("UDP #\(streamID): got \(respData.count)B response from \(resolvedHost):\(port)")
                            if port == 53 {
                                self?.recordDNSHints(from: respData)
                            }
                            guard let framedData = UDPControlFrameCodec.buildResponseFrame(
                                mode: responseMode,
                                headerBytes: headerBytes,
                                responsePayload: respData,
                                maxFrameSize: BubbleConstants.maxUDPFrameSize
                            ) else {
                                self?.statsErrors += 1
                                self?.log.logAndFlush("UDP #\(streamID): response frame too large for \(resolvedHost):\(port)")
                                complete(nil)
                                return
                            }
                            if port == 53 {
                                self?.recordProviderPhase("dns_response_send")
                            }
                            complete(framedData)
                        } else {
                            self?.markResolverTimeout(host: resolvedHost, port: port)
                            if allowReuse {
                                self?.evictUDPSocket(poolKey: poolKey)
                            } else {
                                udp.cancel()
                            }
                            self?.log.logAndFlush("UDP #\(streamID): empty/nil response from \(resolvedHost):\(port), error=\(String(describing: recvError))")
                            complete(nil)
                        }
                    }
                })

            case .failed(let error):
                self?.markResolverTimeout(host: resolvedHost, port: port)
                self?.log.logAndFlush("UDP #\(streamID): NWConnection FAILED to \(resolvedHost):\(port): \(error)")
                if allowReuse {
                    self?.evictUDPSocket(poolKey: poolKey)
                } else {
                    udp.cancel()
                }
                complete(nil)

            case .waiting(let error):
                self?.log.logAndFlush("UDP #\(streamID): NWConnection WAITING to \(resolvedHost):\(port): \(error)")

            default:
                break
            }
        }

        if allowReuse {
            startUDPConnectionIfNeeded(udp, for: poolKey)
        } else {
            udp.start(queue: queue)
        }
    }

    private func relayDNSOverTCPDatagram(
        streamID: Int,
        host: String,
        port: UInt16,
        payload: Data,
        headerBytes: [UInt8],
        responseMode: UDPControlFramingMode,
        completion: @escaping (Data?) -> Void
    ) {
        guard port == 53 else {
            completion(nil)
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            log.log("UDP_SAFE_MODE dns_over_tcp invalid_port stream=\(streamID) host=\(host) port=\(port)")
            statsErrors += 1
            completion(nil)
            return
        }

        let dedupKey = dnsDedupKey(host: host, port: port, payload: payload)
        let dnsDedupWindow = dnsDedupWindowForStream(streamID: streamID)
        if let dedupKey, var inflight = inflightDNSRequests[dedupKey], Date().timeIntervalSince(inflight.startedAt) <= dnsDedupWindow {
            dnsDedupHits += 1
            inflight.callbacks.append(completion)
            inflightDNSRequests[dedupKey] = inflight
            return
        }
        if let dedupKey {
            if inflightDNSRequests.count >= BubbleConstants.dnsInflightMaxEntries {
                sweepInflightDNSExpirations()
                if inflightDNSRequests.count >= BubbleConstants.dnsInflightMaxEntries,
                   let oldestKey = inflightDNSRequests.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
                    inflightDNSRequests.removeValue(forKey: oldestKey)
                    dnsInflight = max(dnsInflight - 1, 0)
                    udpReclaimsByReason["dns_inflight_cap_trim", default: 0] += 1
                }
            }
            dnsInflight += 1
            inflightDNSRequests[dedupKey] = InflightDNSRequest(startedAt: Date(), callbacks: [completion])
        }

        safeModeDNSOverTCP += 1
        let tcp = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        var completed = false
        var timeoutWorkItem: DispatchWorkItem?

        let finishOnQueue: (Data?) -> Void = { [weak self] responseFrame in
            guard let self else { return }
            guard !completed else { return }
            completed = true
            timeoutWorkItem?.cancel()
            tcp.cancel()
            if responseFrame == nil {
                self.safeModeDNSFailures += 1
            }
            if let dedupKey, var inflight = self.inflightDNSRequests.removeValue(forKey: dedupKey) {
                self.dnsInflight = max(self.dnsInflight - 1, 0)
                let callbacks = inflight.callbacks
                inflight.callbacks.removeAll()
                for cb in callbacks {
                    cb(responseFrame)
                }
            } else {
                completion(responseFrame)
            }
        }
        let complete: (Data?) -> Void = { [weak self] responseFrame in
            self?.queue.async {
                finishOnQueue(responseFrame)
            }
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !completed else { return }
            self.udpTimeoutCount += 1
            self.markResolverTimeout(host: host, port: port)
            self.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp timeout stream=\(streamID) host=\(host):\(port)")
            finishOnQueue(nil)
        }
        timeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + BubbleConstants.udpRelayTimeout, execute: timeout)

        tcp.stateUpdateHandler = { [weak self] connState in
            switch connState {
            case .ready:
                guard payload.count <= UInt16.max else {
                    self?.queue.async {
                        self?.log.log("UDP_SAFE_MODE dns_over_tcp payload_too_large stream=\(streamID) bytes=\(payload.count)")
                        complete(nil)
                    }
                    return
                }
                var query = Data()
                query.append(UInt8(payload.count >> 8))
                query.append(UInt8(payload.count & 0xFF))
                query.append(payload)
                self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp send stream=\(streamID) host=\(host):\(port) bytes=\(payload.count)")
                tcp.send(content: query, completion: .contentProcessed { error in
                    if let error {
                        self?.markResolverTimeout(host: host, port: port)
                        self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp send_failed stream=\(streamID) host=\(host):\(port) error=\(error)")
                        complete(nil)
                        return
                    }
                    tcp.receive(minimumIncompleteLength: 2, maximumLength: 2) { lengthData, _, _, lengthError in
                        guard let lengthData, lengthData.count == 2, lengthError == nil else {
                            self?.markResolverTimeout(host: host, port: port)
                            self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp length_failed stream=\(streamID) host=\(host):\(port) error=\(String(describing: lengthError))")
                            complete(nil)
                            return
                        }
                        let responseLength = (Int(lengthData[lengthData.startIndex]) << 8) |
                            Int(lengthData[lengthData.index(after: lengthData.startIndex)])
                        guard responseLength > 0, responseLength <= BubbleConstants.maxUDPFrameSize else {
                            self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp invalid_length stream=\(streamID) length=\(responseLength)")
                            complete(nil)
                            return
                        }
                        tcp.receive(minimumIncompleteLength: responseLength, maximumLength: responseLength) { respData, _, _, recvError in
                            guard let respData, respData.count == responseLength, recvError == nil else {
                                self?.markResolverTimeout(host: host, port: port)
                                self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp response_failed stream=\(streamID) host=\(host):\(port) error=\(String(describing: recvError))")
                                complete(nil)
                                return
                            }
                            self?.markResolverSuccess(host: host, port: port)
                            self?.recordDNSHints(from: respData)
                            guard let framedData = UDPControlFrameCodec.buildResponseFrame(
                                mode: responseMode,
                                headerBytes: headerBytes,
                                responsePayload: respData,
                                maxFrameSize: BubbleConstants.maxUDPFrameSize
                            ) else {
                                self?.statsErrors += 1
                                self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp response_too_large stream=\(streamID) host=\(host):\(port) bytes=\(respData.count)")
                                complete(nil)
                                return
                            }
                            self?.recordProviderPhase("dns_response_send")
                            self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp response stream=\(streamID) host=\(host):\(port) bytes=\(respData.count)")
                            complete(framedData)
                        }
                    }
                })
            case .failed(let error):
                self?.markResolverTimeout(host: host, port: port)
                self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp failed stream=\(streamID) host=\(host):\(port) error=\(error)")
                complete(nil)
            case .waiting(let error):
                self?.log.logAndFlush("UDP_SAFE_MODE dns_over_tcp waiting stream=\(streamID) host=\(host):\(port) error=\(error)")
            default:
                break
            }
        }
        tcp.start(queue: queue)
    }

    private func shouldUseDNSStartupDrain(state: UDPStreamState, now: Date = Date()) -> Bool {
        Self.shouldUseDNSStartupDrain(
            stabilityFirstModeEnabled: stabilityFirstModeEnabled,
            startupDrainWindowActive: isDNSStartupDrainWindowActive(now: now),
            startupGraceActive: isStartupGraceActive(now: now),
            startupGuardActive: isUDPStartupSerialModeActive(now: now),
            crashGuardActive: isUDPCrashGuardActive(now: now),
            lastPort: state.lastPort,
            reason: "dns_response_one_shot_retire"
        )
    }

    private func continueDNSStartupDrain(client: NWConnection, state: UDPStreamState, now: Date = Date()) {
        if state.dnsStartupDrainStartedAt == nil {
            state.dnsStartupDrainStartedAt = now
            recordProviderPhase("dns_startup_drain_active")
            log.log(
                "UDP_DNS startup_drain_start stream=\(state.id) window_s=\(String(format: "%.2f", BubbleConstants.dnsStartupDrainWindowSeconds)) idle_s=\(String(format: "%.2f", BubbleConstants.dnsStartupDrainIdleSeconds))"
            )
        }
        state.dnsStartupDrainFramesProcessed += 1
        dnsStartupDrainFramesProcessed += 1
        persistDNSStartupDrainState(now: now)
        state.processingRecoveredFrame = false
        state.processingStartedAt = nil

        if let startedAt = state.dnsStartupDrainStartedAt,
           now.timeIntervalSince(startedAt) >= BubbleConstants.dnsStartupDrainMaxAgeSeconds {
            closeDNSControlStream(client: client, state: state, reason: "dns_startup_drain_max_age_retire")
            return
        }

        if !state.pendingFrames.isEmpty {
            log.log("UDP_DNS startup_drain_process_queued stream=\(state.id) queued=\(state.pendingFrames.count)")
            processNextUDPFrame(client: client, state: state)
            return
        }

        scheduleDNSStartupDrainIdleClose(client: client, state: state)
        readUDPControlStream(client: client, state: state)
    }

    private func scheduleDNSStartupDrainIdleClose(client: NWConnection, state: UDPStreamState) {
        state.dnsStartupDrainIdleCloseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state, !state.closed else { return }
            if let startedAt = state.dnsStartupDrainStartedAt,
               Date().timeIntervalSince(startedAt) >= BubbleConstants.dnsStartupDrainMaxAgeSeconds {
                self.closeDNSControlStream(client: client, state: state, reason: "dns_startup_drain_max_age_retire")
                return
            }
            if state.processingFrame || !state.pendingFrames.isEmpty {
                self.scheduleDNSStartupDrainIdleClose(client: client, state: state)
                if !state.processingFrame {
                    self.processNextUDPFrame(client: client, state: state)
                }
                return
            }
            self.closeDNSControlStream(client: client, state: state, reason: "dns_startup_drain_idle_retire")
        }
        state.dnsStartupDrainIdleCloseWorkItem = work
        queue.asyncAfter(deadline: .now() + BubbleConstants.dnsStartupDrainIdleSeconds, execute: work)
    }

    private func closeDNSControlStream(client: NWConnection, state: UDPStreamState, reason: String) {
        state.dnsStartupDrainIdleCloseWorkItem?.cancel()
        state.dnsStartupDrainIdleCloseWorkItem = nil
        let isStartupDrainClose = reason.hasPrefix("dns_startup_drain_")
        if isStartupDrainClose, !state.dnsStartupDrainCloseRecorded {
            state.dnsStartupDrainCloseRecorded = true
            dnsStartupDrainCloses += 1
            persistDNSStartupDrainState()
        }
        recordProviderPhase(isStartupDrainClose ? "dns_startup_drain_close" : "dns_one_shot_close")
        let discardPlan = discardPendingDNSFramesIfNeeded(state: state, reason: reason)
        let closePlan = Self.udpControlClosePlan(lastPort: state.lastPort, reason: reason)
        if closePlan.sendWithConnectionCompletion {
            udpGracefulDNSCloses += 1
        }
        if discardPlan.recoveredOneShotClose {
            dnsRecoveredOneShotCloses += 1
        }
        closeUDPControlStream(client: client, state: state, reason: reason, plan: closePlan)
        persistDNSStartupDrainState()
        recordLastDNSClose(
            state: state,
            reason: reason,
            trailingDiscarded: discardPlan.trailingDiscarded,
            recoveredDiscarded: discardPlan.recoveredDiscarded
        )
    }

    @discardableResult
    private func discardPendingDNSFramesIfNeeded(state: UDPStreamState, reason: String) -> DNSFrameDiscardPlan {
        let plan = Self.dnsFrameDiscardPlan(
            pendingFrameCount: state.pendingFrames.count,
            recoveredFramesPending: state.recoveredFramesPending,
            processingRecoveredDNSFrame: state.processingRecoveredFrame || state.recoveredDNSFrameProcessed
        )
        guard plan.trailingDiscarded > 0 else {
            state.recoveredFramesPending = 0
            return plan
        }
        dnsTrailingFramesDiscarded += plan.trailingDiscarded
        dnsRecoveredFramesDiscarded += plan.recoveredDiscarded
        udpReclaimsByReason["dns_trailing_frames_discarded", default: 0] += plan.trailingDiscarded
        log.log("UDP_DNS trailing_frames_discarded stream=\(state.id) count=\(plan.trailingDiscarded) recovered=\(plan.recoveredDiscarded) reason=\(reason)")
        state.pendingFrames.removeAll()
        state.recoveredFramesPending = 0
        recordLastDecoderEvent(
            reason: "dns_trailing_frames_discarded",
            hexPrefix: "",
            recoveredFrames: 0,
            discardedFrames: plan.trailingDiscarded
        )
        return plan
    }

    private func closeUDPControlStream(
        client: NWConnection,
        state: UDPStreamState,
        reason: String,
        plan: UDPControlClosePlan? = nil
    ) {
        guard !state.closed else { return }
        if shouldBlockCloseDuringGrace(state: state, reason: reason) {
            log.log("TRANSPORT_PROTECTION grace_close_blocked stream=\(state.id) reason=\(reason)")
            state.closeReason = reason
            state.closePhase = .graceBlocked
            lastUDPClosePhase = state.closePhase
            recordLastControlStream(state: state, reason: reason)
            state.processingFrame = false
            state.processingRecoveredFrame = false
            state.processingStartedAt = nil
            return
        }
        let closePlan = plan ?? Self.udpControlClosePlan(lastPort: state.lastPort, reason: reason)
        state.closed = true
        state.closeReason = reason
        state.closePhase = closePlan.phase
        lastUDPClosePhase = state.closePhase
        recordLastControlStream(state: state, reason: reason)
        udpStreamsByID.removeValue(forKey: state.id)
        activeConnectionCount = max(activeConnectionCount - 1, 0)
        activeUDPStreams = max(activeUDPStreams - 1, 0)
        var classState = classState(for: state.trafficClass)
        classState.activeUDP = countActiveUDPStreams(for: state.trafficClass)
        setClassState(classState, for: state.trafficClass)
        totalUDPStreamsClosed += 1
        streamCloseReasonCounts[reason, default: 0] += 1
        log.logAndFlush("UDP_DECODER stream=\(state.id) event=close reason=\(reason) queued=\(state.pendingFrames.count) decode_failures=\(state.decoderFailureCount) recoveries=\(state.decoderRecoveryCount)")
        scheduleUDPControlCancelAndDrain(client: client, state: state, reason: reason, plan: closePlan)
    }

    private func scheduleUDPControlCancelAndDrain(
        client: NWConnection,
        state: UDPStreamState,
        reason: String,
        plan: UDPControlClosePlan
    ) {
        guard !state.cancelScheduled else { return }
        state.cancelScheduled = true
        state.closePhase = .cancelScheduled
        lastUDPClosePhase = state.closePhase
        udpDeferredCancels += 1
        udpCloseFinalizationsInFlight += 1
        recordLastControlStream(state: state, reason: reason)

        let finalize = { [weak self] in
            guard let self else { return }
            if state.closePhase != .cancelled {
                if plan.cancelAsWatchdog {
                    self.udpCancelWatchdogFires += 1
                }
                client.cancel()
                state.closePhase = .cancelled
                self.lastUDPClosePhase = state.closePhase
                self.recordLastControlStream(state: state, reason: reason)
            }
            self.udpCloseFinalizationsInFlight = max(self.udpCloseFinalizationsInFlight - 1, 0)
            self.scheduleUDPControlQueueDrainAfterClose(state: state, reason: reason)
        }

        if plan.cancelDelaySeconds > 0 {
            queue.asyncAfter(deadline: .now() + plan.cancelDelaySeconds) {
                finalize()
            }
        } else {
            queue.async {
                finalize()
            }
        }
    }

    private func scheduleUDPControlQueueDrainAfterClose(state: UDPStreamState, reason: String) {
        guard !state.drainScheduled else { return }
        state.drainScheduled = true
        state.closePhase = .drainScheduled
        lastUDPClosePhase = state.closePhase
        recordLastControlStream(state: state, reason: reason)
        queue.async { [weak self] in
            self?.drainQueuedUDPControlStreamsIfNeeded()
        }
    }

    private func shouldBlockCloseDuringGrace(state: UDPStreamState, reason: String, now: Date = Date()) -> Bool {
        guard hasAnyProtectionGrace(now: now) else { return false }
        if Self.shouldBypassGraceForDNSClose(
            lastPort: state.lastPort,
            reason: reason,
            startupGuardActive: isUDPStartupSerialModeActive(now: now),
            crashGuardActive: isUDPCrashGuardActive(now: now)
        ) {
            return false
        }
        if currentPressureIsCritical(now: now),
           state.lastPort == 53,
           (reason.contains("extension_pressure") || reason.hasPrefix("emergency_reclaim_") || reason == "critical_extension_pressure_reclaim") {
            return false
        }
        if shouldBypassGraceForStreamUnderPressure(state: state, now: now) {
            return false
        }
        if Self.shouldBypassGraceForStartupGuardLowConfidenceReclaim(
            reason: reason,
            startupGuardActive: isUDPStartupSerialModeActive(now: now),
            queueDepth: pendingUDPControlQueue.count,
            trafficClass: state.trafficClass,
            lastPort: state.lastPort,
            preservesMessagingControl: state.preservesMessagingControl
        ) {
            return false
        }
        let guardedReasons: Set<String> = [
            "stuck_processing_reclaim",
            "global_idle_timeout_reclaim",
            "tiktok_idle_timeout_reclaim",
            "global_max_lifetime_reclaim",
            "tiktok_max_lifetime_reclaim",
            "global_timeout_streak_reclaim",
            "tiktok_timeout_streak_reclaim",
            "storm_dns_timeout_retire",
            "storm_dns_one_shot_retire",
        ]
        if guardedReasons.contains(reason) || reason.hasPrefix("emergency_reclaim_") {
            return true
        }
        if activeUDPStreams <= minimumUDPControlStreamsDuringGrace, state.lastPort == 53 {
            return true
        }
        return false
    }

    private func drainQueuedUDPControlStreamsIfNeeded() {
        let now = Date()
        if isUDPStartupSerialModeActive(now: now), udpCloseFinalizationsInFlight > 0 {
            return
        }
        let stormMode = isStormMode()
        let effectiveMax = effectiveMaxActiveUDPStreamsForDrain(
            now: now,
            stormMode: stormMode,
            safeMode: currentUDPForwardingMode() == .selectiveSafeMode
        )
        if !isUDPStartupSerialModeActive(now: now),
           activeUDPStreams > 0,
           activeUDPStreams < effectiveMax,
           !pendingUDPControlQueue.isEmpty {
            log.log(
                "UDP_STARTUP_GUARD serial_expired_drain active_udp=\(activeUDPStreams) queue_depth=\(pendingUDPControlQueue.count) target_active=\(effectiveMax)"
            )
        }
        while activeUDPStreams < effectiveMax, !pendingUDPControlQueue.isEmpty {
            guard let next = dequeueNextPendingUDPControl() else { return }
            queuedUDPControlIDs.remove(next.id)
            var classState = classState(for: next.trafficClass)
            classState.queuedUDP = countQueuedUDPStreams(for: next.trafficClass)
            setClassState(classState, for: next.trafficClass)
            startAcceptedUDPControlStream(
                client: next.client,
                id: next.id,
                trafficClass: next.trafficClass,
                initialBytes: next.initialBytes,
                requestHadTail: next.requestHadTail
            )
        }
    }

    private func dequeueNextPendingUDPControl() -> PendingUDPControl? {
        let priority: [TrafficClass] = [.generic, .instagram, .x, .tiktok, .unknown]
        for trafficClass in priority {
            if let idx = pendingUDPControlQueue.firstIndex(where: { $0.trafficClass == trafficClass }) {
                return pendingUDPControlQueue.remove(at: idx)
            }
        }
        return pendingUDPControlQueue.isEmpty ? nil : pendingUDPControlQueue.removeFirst()
    }

    private func isProtectedBlockedBucket(_ bucket: ContentBucket) -> Bool {
        bucket == .tiktokVideo || bucket == .reels || bucket == .xFeedMedia || bucket == .xFeedAPI
    }

    private func shouldUseHardenedPath(_ decision: PolicyDecision) -> Bool {
        isProtectedBlockedBucket(decision.classification.bucket)
    }

    private func currentPressureIsCritical(now: Date = Date()) -> Bool {
        currentTransportPressurePhase(now: now) == .critical || extensionPressureLevel == .critical
    }

    private func currentPressureIsDegradedOrCritical(now: Date = Date()) -> Bool {
        let phase = currentTransportPressurePhase(now: now)
        return phase == .degraded || phase == .critical
    }

    private func preservesMessagingOrControl(decision: PolicyDecision, port: UInt16) -> Bool {
        Self.isMessagingOrControlPreserving(
            reason: decision.reason,
            bucket: decision.classification.bucket,
            port: port
        )
    }

    private func maybeTriggerUDPStartupGuardEscapeHatch(reason: String, now: Date = Date()) -> Bool {
        guard isUDPStartupSerialModeActive(now: now) else { return false }
        guard activeUDPStreams == 1 else { return false }
        guard pendingUDPControlQueue.count >= BubbleConstants.safeModeMaxQueuedUDPControlStreams else { return false }
        guard let state = udpStreamsByID.values.first(where: { !$0.closed }) else { return false }
        guard Self.shouldTriggerUDPStartupGuardEscapeHatch(
            startupGuardActive: true,
            activeUDPStreams: activeUDPStreams,
            queueDepth: pendingUDPControlQueue.count,
            trafficClass: state.trafficClass,
            lastPort: state.lastPort,
            preservesMessagingControl: state.preservesMessagingControl
        ) else {
            return false
        }

        let queueDepth = pendingUDPControlQueue.count
        let streamAgeMS = Int(max(0, now.timeIntervalSince(state.createdAt) * 1000.0))
        log.log(
            "UDP_STARTUP_GUARD escape_hatch stream=\(state.id) class=\(state.trafficClass.rawValue) last_port=\(state.lastPort.map(String.init) ?? "unknown") queue_depth=\(queueDepth) age_ms=\(streamAgeMS) reason=\(reason)"
        )
        udpReclaimsByReason["startup_guard_escape_hatch", default: 0] += 1
        closeUDPControlStream(client: state.client, state: state, reason: "startup_guard_escape_hatch_reclaim")
        return true
    }

    private func shouldBypassGraceForStreamUnderPressure(state: UDPStreamState, now: Date = Date()) -> Bool {
        Self.shouldBypassGraceForStreamUnderPressure(
            criticalPressure: currentPressureIsCritical(now: now),
            hardeningEnabled: state.hardeningEnabled,
            hardeningBucket: state.hardeningBucket,
            preservesMessagingControl: state.preservesMessagingControl,
            lastPort: state.lastPort
        )
    }

    private func reclaimPriority(for state: UDPStreamState, now: Date = Date()) -> Int {
        Self.reclaimPriority(
            criticalPressure: currentPressureIsCritical(now: now),
            degradedOrCriticalPressure: currentPressureIsDegradedOrCritical(now: now),
            hardeningEnabled: state.hardeningEnabled,
            hardeningBucket: state.hardeningBucket,
            trafficClass: state.trafficClass,
            preservesMessagingControl: state.preservesMessagingControl,
            lastPort: state.lastPort
        )
    }

    private func shouldRetireBlockedStormStream(state: UDPStreamState, blockedDecisionCount: Int, now: Date = Date()) -> Bool {
        let secondsSinceLastSuccess = state.lastSuccessfulResponseAt.map { now.timeIntervalSince($0) }
        return Self.shouldRetireBlockedStormStream(
            blockedDecisionCount: blockedDecisionCount,
            secondsSinceLastSuccess: secondsSinceLastSuccess,
            noProgressSeconds: now.timeIntervalSince(state.lastProgressAt),
            degradedOrCriticalPressure: currentPressureIsDegradedOrCritical(now: now),
            stormMode: isStormMode(),
            hardeningEnabled: state.hardeningEnabled,
            hardeningBucket: state.hardeningBucket,
            preservesMessagingControl: state.preservesMessagingControl
        )
    }

    private func dnsDedupWindowForStream(streamID: Int) -> TimeInterval {
        guard let state = udpStreamsByID[streamID], state.hardeningEnabled else {
            return BubbleConstants.dnsDedupWindow
        }
        return BubbleConstants.tiktokHardeningDNSDedupWindow
    }

    private func runUDPMaintenanceSweep() {
        _ = maybeTriggerUDPStartupGuardEscapeHatch(reason: "maintenance", now: Date())
        closeStaleQueuedUDPControlStreams()
        sweepInflightDNSExpirations()
        sweepUDPControlStreams()
        reclaimUDPStreamsUnderPressure(reason: "maintenance")
        pruneHostCooldowns()
        drainQueuedUDPControlStreamsIfNeeded()
    }

    private func sweepUDPControlStreams() {
        let now = Date()
        for state in udpStreamsByID.values where !state.closed {
            if hasAnyProtectionGrace(now: now), state.lastPort == 53 {
                continue
            }
            if let started = state.processingStartedAt,
               now.timeIntervalSince(started) > watchdogTimeoutForState() {
                if now.timeIntervalSince(lastStuckProcessingReclaimAt) < BubbleConstants.udpEmergencyReclaimMinInterval {
                    continue
                }
                lastStuckProcessingReclaimAt = now
                udpReclaimsByReason["stuck_processing_reclaim", default: 0] += 1
                closeUDPControlStream(client: state.client, state: state, reason: "stuck_processing_reclaim")
                continue
            }

            let maxLifetime: TimeInterval
            if isStormMode() && (state.trafficClass == .unknown || state.trafficClass == .generic) {
                maxLifetime = BubbleConstants.udpStormLowConfidenceMaxLifetime
            } else {
                maxLifetime = state.hardeningEnabled ? BubbleConstants.tiktokHardeningMaxLifetime : BubbleConstants.udpGlobalMaxLifetime
            }
            if now.timeIntervalSince(state.createdAt) > effectiveMaxLifetime(base: maxLifetime) {
                let reason = state.hardeningEnabled ? "tiktok_max_lifetime_reclaim" : "global_max_lifetime_reclaim"
                tiktokHardeningActions["max_lifetime_reclaim", default: 0] += 1
                udpReclaimsByReason[reason, default: 0] += 1
                if shouldAllowReclaim(reason: reason, now: now) {
                    closeUDPControlStream(client: state.client, state: state, reason: reason)
                } else {
                    log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reason)")
                }
                continue
            }

            let idleTimeout: TimeInterval
            if isStormMode() && (state.trafficClass == .unknown || state.trafficClass == .generic) {
                idleTimeout = BubbleConstants.udpStormLowConfidenceIdleTimeout
            } else {
                idleTimeout = state.hardeningEnabled ? BubbleConstants.tiktokHardeningIdleTimeout : BubbleConstants.udpGlobalIdleTimeout
            }
            if now.timeIntervalSince(state.lastActivityAt) > effectiveIdleTimeout(base: idleTimeout) {
                let reason = state.hardeningEnabled ? "tiktok_idle_timeout_reclaim" : "global_idle_timeout_reclaim"
                tiktokHardeningActions["idle_timeout_reclaim", default: 0] += 1
                udpReclaimsByReason[reason, default: 0] += 1
                if shouldSkipIdleReclaimDueToRecentSuccess(state: state, now: now) {
                    log.log("TRANSPORT_PROTECTION reclaim_skipped_recent_success stream=\(state.id) reason=\(reason)")
                    continue
                }
                if shouldAllowReclaim(reason: reason, now: now) {
                    closeUDPControlStream(client: state.client, state: state, reason: reason)
                } else {
                    log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reason)")
                }
            }
        }
        updateTransportDegradedState()
    }

    private func closeStaleQueuedUDPControlStreams() {
        let now = Date()
        if hasAnyProtectionGrace(now: now) && !currentPressureIsCritical(now: now) {
            return
        }
        let maxQueueAge = isStormMode() ? BubbleConstants.udpStormQueueMaxAge : BubbleConstants.udpQueuedStreamMaxAge
        var retained: [PendingUDPControl] = []
        retained.reserveCapacity(pendingUDPControlQueue.count)
        for item in pendingUDPControlQueue {
            let allowTrimDuringGrace = currentPressureIsCritical(now: now) && !item.preserveDuringPressure
            if now.timeIntervalSince(item.enqueuedAt) > maxQueueAge && (!hasAnyProtectionGrace(now: now) || allowTrimDuringGrace) {
                udpReclaimsByReason["queue_age_reclaim", default: 0] += 1
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                queuedUDPControlIDs.remove(item.id)
                item.client.cancel()
            } else {
                retained.append(item)
            }
        }
        pendingUDPControlQueue = retained
        for trafficClass in TrafficClass.allCases {
            var state = classState(for: trafficClass)
            state.queuedUDP = countQueuedUDPStreams(for: trafficClass)
            setClassState(state, for: trafficClass)
        }
    }

    private func sweepInflightDNSExpirations() {
        let now = Date()
        for (key, inflight) in inflightDNSRequests where now.timeIntervalSince(inflight.startedAt) > BubbleConstants.dnsInflightMaxAge {
            inflightDNSRequests.removeValue(forKey: key)
            dnsInflight = max(dnsInflight - 1, 0)
            for callback in inflight.callbacks {
                callback(nil)
            }
        }
    }

    private func updateTransportDegradedState() {
        let now = Date()
        sampleStateSeconds(now: now)
        sampleStormModeDuration(now: now)
        let timeoutRate = statsUDP > 0 ? Double(udpTimeoutCount) / Double(statsUDP) : 0
        let badLenRate = badLenHardFailRate(now: now)
        updateStormModeState(now: now, timeoutRate: timeoutRate)
        let isSaturated = pendingUDPControlQueue.count >= effectiveDegradedEnterQueueDepth()
        let isRecoveringDepth = pendingUDPControlQueue.count <= BubbleConstants.degradedRecoverQueueDepth
        let timeoutStorm = timeoutRate >= effectiveDegradedTimeoutRateEnter()
        let timeoutRecovered = timeoutRate <= BubbleConstants.degradedTimeoutRateRecover
        let badLenStorm = badLenRate >= BubbleConstants.degradedBadLenRateEnter
        let badLenRecovered = badLenRate <= BubbleConstants.degradedBadLenRateRecover
        let recentEmergencyReclaims = countRecentEmergencyReclaims(windowSeconds: BubbleConstants.trippedWindowSeconds)
        let severeSaturation = pendingUDPControlQueue.count >= effectiveTrippedEnterQueueDepth()
        let severeTimeoutStorm = timeoutRate >= effectiveTrippedEnterTimeoutRate()
        let severeBadLenStorm = badLenRate >= BubbleConstants.trippedBadLenRateEnter
        let severeReclaims = recentEmergencyReclaims >= BubbleConstants.trippedEnterEmergencyReclaims
        let severeCondition = Self.shouldTripFromSevereSignals(
            severeSaturation: severeSaturation,
            severeTimeoutStorm: severeTimeoutStorm,
            severeBadLenStorm: severeBadLenStorm,
            severeReclaims: severeReclaims
        )
        if severeCondition {
            if severeSignalSince == nil {
                severeSignalSince = now
            }
        } else {
            severeSignalSince = nil
        }
        let severeSustained = severeSignalSince.map {
            now.timeIntervalSince($0) >= effectiveTrippedEnterMinDegradedSeconds()
        } ?? false
        let trippedRecovered = timeoutRate <= BubbleConstants.trippedRecoverTimeoutRate &&
            pendingUDPControlQueue.count <= BubbleConstants.trippedRecoverQueueDepth &&
            badLenRate <= BubbleConstants.trippedBadLenRateRecover
        let previous = degradedState
        let degradedConditionActive = isSaturated || timeoutStorm || badLenStorm
        switch degradedState {
        case .healthy:
            if degradedConditionActive {
                degradedState = .degraded
                degradedEnteredAt = now
                degradedStableSince = nil
            }
        case .degraded:
            let degradedDwellMet = now.timeIntervalSince(degradedEnteredAt) >= effectiveTrippedEnterMinDegradedSeconds()
            if severeCondition && severeSustained && degradedDwellMet {
                if hasAnyProtectionGrace() {
                    log.log("TRANSPORT_PROTECTION state_transition_blocked_by_grace attempted=\(TransportDegradedState.tripped.rawValue)")
                } else {
                    degradedState = .tripped
                    trippedEnteredAt = now
                    degradedStableSince = nil
                    severeSignalSince = nil
                }
            } else if isRecoveringDepth && timeoutRecovered && badLenRecovered {
                if degradedStableSince == nil {
                    degradedStableSince = now
                }
                if let stableSince = degradedStableSince,
                   now.timeIntervalSince(stableSince) >= BubbleConstants.degradedRecoverStabilizationSeconds {
                    degradedState = .recovering
                    recoveringEnteredAt = now
                    degradedStableSince = nil
                }
            } else {
                degradedStableSince = nil
            }
        case .recovering:
            if isRecoveringDepth && timeoutRecovered && badLenRecovered &&
                now.timeIntervalSince(recoveringEnteredAt) >= BubbleConstants.degradedRecoverStabilizationSeconds {
                degradedState = .healthy
                severeSignalSince = nil
            } else if degradedConditionActive {
                degradedState = .degraded
                degradedEnteredAt = now
                degradedStableSince = nil
            }
        case .tripped:
            let stabilizedSeconds = now.timeIntervalSince(trippedEnteredAt)
            if trippedRecovered && stabilizedSeconds >= BubbleConstants.trippedRecoverStabilizationSeconds {
                degradedState = .recovering
                trippedSecondsTotal += stabilizedSeconds
                recoveringEnteredAt = now
                if stabilityFirstModeEnabled {
                    recoveryGraceUntil = now.addingTimeInterval(BubbleConstants.stabilityFirstRecoveryGraceSeconds)
                }
            }
        }
        if degradedState != previous {
            degradedTransitions += 1
            if degradedState == .tripped {
                trippedTransitions += 1
            }
            log.log("TRANSPORT_PROTECTION state_transition from=\(previous.rawValue) to=\(degradedState.rawValue) timeoutRate=\(String(format: "%.2f", timeoutRate)) badLenRate=\(String(format: "%.2f", badLenRate)) queueDepth=\(pendingUDPControlQueue.count) recentEmergencyReclaims=\(recentEmergencyReclaims)")
        }
        emitPressureDiagnosticsIfNeeded(now: now, timeoutRate: timeoutRate, badLenRate: badLenRate)
        updateProtectedTransportDegradedState()
    }

    private func emitPressureDiagnosticsIfNeeded(now: Date, timeoutRate: Double, badLenRate: Double) {
        let phase = currentTransportPressurePhase(now: now)
        guard phase != .normal else { return }
        guard now.timeIntervalSince(lastPressureDiagnosticsAt) >= BubbleConstants.transportPressureDiagnosticsInterval else { return }
        lastPressureDiagnosticsAt = now
        log.log(
            "TRANSPORT_PROTECTION pressure phase=\(phase.rawValue) state=\(degradedState.rawValue) queue=\(pendingUDPControlQueue.count) activeUDP=\(activeUDPStreams) timeoutRate=\(String(format: "%.2f", timeoutRate)) badLenRate=\(String(format: "%.2f", badLenRate)) grace=\(hasAnyProtectionGrace(now: now))"
        )
    }

    private func sampleStateSeconds(now: Date) {
        let delta = max(0, now.timeIntervalSince(lastStateSampleAt))
        guard delta > 0 else { return }
        stateSecondsByMode[degradedState.rawValue, default: 0] += delta
        lastStateSampleAt = now
    }

    private func updateProtectedTransportDegradedState() {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let now = Date()
        recentProtectedBlockEvents = recentProtectedBlockEvents.filter { now.timeIntervalSince($0) <= 60 }
        let hasProtectedPressureSignal = !recentProtectedBlockEvents.isEmpty || udpStreamsByID.values.contains { !$0.closed && $0.hardeningEnabled }
        guard hasProtectedPressureSignal else {
            defaults?.set(false, forKey: BubbleConstants.vpnLifecycleTransportDegradedKey)
            defaults?.set("", forKey: BubbleConstants.vpnLifecycleTransportDegradedReasonKey)
            defaults?.set(now.timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleTransportDegradedTSKey)
            return
        }
        let degradedReason: String?
        switch degradedState {
        case .healthy:
            degradedReason = nil
        case .degraded:
            degradedReason = pendingUDPControlQueue.count >= effectiveDegradedEnterQueueDepth() ? "udp_queue_saturation" : "udp_timeout_storm"
        case .tripped:
            degradedReason = "tripped_overload_guard"
        case .recovering:
            degradedReason = "recovering"
        }
        defaults?.set(degradedReason != nil, forKey: BubbleConstants.vpnLifecycleTransportDegradedKey)
        defaults?.set(degradedReason ?? "", forKey: BubbleConstants.vpnLifecycleTransportDegradedReasonKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: BubbleConstants.vpnLifecycleTransportDegradedTSKey)
    }

    func applyExtensionPressureLevel(_ level: ExtensionPressureLevel) {
        queue.async { [weak self] in
            self?.applyExtensionPressureLevelOnQueue(level)
        }
    }

    private func applyExtensionPressureLevelOnQueue(_ level: ExtensionPressureLevel, now: Date = Date()) {
        var effectiveLevel = level
        if level == .normal, extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank, now < extensionPressureRecoveryNotBefore {
            effectiveLevel = .soft
        }
        extensionPressureLevel = effectiveLevel
        if effectiveLevel.rank >= ExtensionPressureLevel.hard.rank {
            extensionPressureRecoveryNotBefore = now.addingTimeInterval(3.0)
        }
        guard effectiveLevel != .normal else { return }

        trimRetainedDiagnostics(now: now)
        closeStaleQueuedUDPControlStreams()

        switch effectiveLevel {
        case .normal:
            break
        case .soft:
            reclaimUDPStreamsUnderPressure(reason: "extension_pressure")
        case .hard:
            dropQueuedUDPControlStreamsUnderPressure(limit: max(1, pendingUDPControlQueue.count / 3), includeTargetClasses: false)
            reclaimUDPStreamsUnderPressure(reason: "extension_pressure")
            trimRetainedDiagnostics(now: now, aggressive: true)
        case .critical:
            extensionPressureDiagnosticsMutedUntil = now.addingTimeInterval(BubbleConstants.extensionPressureCriticalSnapshotMuteSeconds)
            dropQueuedUDPControlStreamsUnderPressure(limit: pendingUDPControlQueue.count, includeTargetClasses: true)
            reclaimUDPStreamsUnderPressure(reason: "extension_pressure")
            reclaimLowValueUDPStreamsUnderPressure(targetActive: BubbleConstants.extensionPressureCriticalTargetActiveUDP, now: now)
            trimRetainedDiagnostics(now: now, aggressive: true)
        }

        UserDefaults(suiteName: BubbleConstants.appGroupID)?
            .set(extensionPressureReclaimBlockedCount, forKey: BubbleConstants.vpnLifecycleExtensionPressureReclaimBlockedCountKey)
        updateTransportDegradedState()
    }

    static func extensionPressureLevel(memoryMB: Double?, activeUDP: Int, queuedUDP: Int, degradedState: String) -> ExtensionPressureLevel {
        if let memoryMB, memoryMB >= BubbleConstants.extensionPressureCriticalMemoryMB {
            return .critical
        }
        if queuedUDP >= BubbleConstants.extensionPressureCriticalQueuedUDP || activeUDP >= BubbleConstants.extensionPressureCriticalActiveUDP || degradedState == "tripped" {
            return .critical
        }
        if let memoryMB, memoryMB >= BubbleConstants.extensionPressureHardMemoryMB {
            return .hard
        }
        if queuedUDP >= BubbleConstants.extensionPressureHardQueuedUDP || activeUDP >= BubbleConstants.extensionPressureHardActiveUDP || degradedState == "degraded" {
            return .hard
        }
        if let memoryMB, memoryMB >= BubbleConstants.extensionPressureSoftMemoryMB {
            return .soft
        }
        if queuedUDP >= max(1, BubbleConstants.maxQueuedUDPControlStreams / 2) || degradedState == "recovering" {
            return .soft
        }
        return .normal
    }

    private func extensionPressureRejectReason(for trafficClass: TrafficClass) -> String? {
        if extensionPressureLevel == .critical && (trafficClass == .unknown || trafficClass == .generic) {
            return "critical_extension_pressure_low_confidence"
        }
        if extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank, (trafficClass == .unknown || trafficClass == .generic) {
            return "hard_extension_pressure_low_confidence"
        }
        return nil
    }

    private func reclaimLowValueUDPStreamsUnderPressure(targetActive: Int, now: Date) {
        guard activeUDPStreams > targetActive else { return }
        let candidates = udpStreamsByID.values
            .filter {
                !$0.closed &&
                !$0.processingFrame &&
                $0.pendingFrames.isEmpty &&
                (!$0.preservesMessagingControl || $0.lastPort == 53)
            }
            .sorted {
                let lhsPriority = reclaimPriority(for: $0, now: now)
                let rhsPriority = reclaimPriority(for: $1, now: now)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.lastActivityAt < $1.lastActivityAt
            }
        for state in candidates {
            guard activeUDPStreams > targetActive else { break }
            let reason = "critical_extension_pressure_reclaim"
            if extensionPressureLevel == .critical || shouldAllowReclaim(reason: reason, now: now) {
                udpReclaimsByReason[reason, default: 0] += 1
                hardPressureUDPReclaims += 1
                log.log("UDP_PRESSURE reclaim stream=\(state.id) class=\(state.trafficClass.rawValue) last_port=\(state.lastPort.map(String.init) ?? "unknown") pressure=\(extensionPressureLevel.rawValue) reason=\(reason) active_udp=\(activeUDPStreams) target_active=\(targetActive)")
                closeUDPControlStream(client: state.client, state: state, reason: reason)
            }
        }
    }

    private func dropQueuedUDPControlStreamsUnderPressure(limit: Int, includeTargetClasses: Bool) {
        guard limit > 0, !pendingUDPControlQueue.isEmpty else { return }
        var dropped = 0
        var retained: [PendingUDPControl] = []
        retained.reserveCapacity(pendingUDPControlQueue.count)

        for item in pendingUDPControlQueue {
            let lowPriority = item.trafficClass == .unknown || item.trafficClass == .generic
            let eligible = !item.preserveDuringPressure && (includeTargetClasses || lowPriority || item.lowConfidence)
            if dropped < limit, eligible {
                dropped += 1
                queuedUDPControlIDs.remove(item.id)
                activeConnectionCount = max(activeConnectionCount - 1, 0)
                udpForcedRejects += 1
                udpReclaimsByReason["extension_pressure_queue_trim", default: 0] += 1
                admissionRejectsByReason["extension_pressure_queue_trim", default: 0] += 1
                item.client.cancel()
            } else {
                retained.append(item)
            }
        }

        pendingUDPControlQueue = retained
        for trafficClass in TrafficClass.allCases {
            var state = classState(for: trafficClass)
            state.queuedUDP = countQueuedUDPStreams(for: trafficClass)
            setClassState(state, for: trafficClass)
        }
    }

    private func trimRetainedDiagnostics(now: Date = Date(), aggressive: Bool = false) {
        let hintLimit = aggressive ? max(16, BubbleConstants.extensionPressureMaxClassHints / 2) : BubbleConstants.extensionPressureMaxClassHints
        if recentClassHintsByHost.count > hintLimit {
            let overflow = recentClassHintsByHost.count - hintLimit
            for key in recentClassHintsByHost.sorted(by: { $0.value.ts < $1.value.ts }).prefix(overflow).map(\.key) {
                recentClassHintsByHost.removeValue(forKey: key)
            }
        }

        let suppressionLimit = aggressive ? max(16, BubbleConstants.extensionPressureMaxSuppressionEntries / 2) : BubbleConstants.extensionPressureMaxSuppressionEntries
        if blockedSuppression.count > suppressionLimit {
            let overflow = blockedSuppression.count - suppressionLimit
            for key in blockedSuppression.sorted(by: { $0.value.lastSeen < $1.value.lastSeen }).prefix(overflow).map(\.key) {
                blockedSuppression.removeValue(forKey: key)
            }
        }

        recentBlockedByHost = recentBlockedByHost.filter { now.timeIntervalSince($0.value) <= BubbleConstants.aggressiveBlockSuppressionStormCooldown }
        hostCooldownUntilByKey = hostCooldownUntilByKey.filter { now < $0.value }
        recentBadLenHardFailTimestamps = recentBadLenHardFailTimestamps.filter { now.timeIntervalSince($0) <= BubbleConstants.badLenRateWindowSeconds }
        recentFailOpenCandidateBlockEvents = recentFailOpenCandidateBlockEvents.filter { now.timeIntervalSince($0) <= BubbleConstants.protectedBlockFailOpenWindowSeconds }
        emergencyReclaimTimestamps = emergencyReclaimTimestamps.filter { now.timeIntervalSince($0) <= BubbleConstants.trippedWindowSeconds }
        maintenanceReclaimTimestamps = maintenanceReclaimTimestamps.filter { now.timeIntervalSince($0) <= BubbleConstants.udpMaintenanceReclaimWindowSeconds }
        pruneKnownBadUDPCache(now: now)

        if snapshotHistory.count > maxSnapshotHistory {
            snapshotHistory.removeFirst(snapshotHistory.count - maxSnapshotHistory)
        }
        if eventLog.count > maxEvents {
            eventLog.removeFirst(eventLog.count - maxEvents)
        }
    }

    private func areExpensiveDiagnosticsMuted(now: Date = Date()) -> Bool {
        now < extensionPressureDiagnosticsMutedUntil
    }

    private func applyLockSafeProtection(to fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private func reclaimUDPStreamsUnderPressure(reason: String) {
        let extensionPressureReclaim = reason == "extension_pressure"
        guard reason == "maintenance" || extensionPressureReclaim else { return }
        let allowCriticalOverride = currentPressureIsCritical() &&
            (reason == "extension_pressure" || reason == "maintenance")
        if hasAnyProtectionGrace() && !allowCriticalOverride {
            extensionPressureReclaimBlockedCount += 1
            UserDefaults(suiteName: BubbleConstants.appGroupID)?
                .set(extensionPressureReclaimBlockedCount, forKey: BubbleConstants.vpnLifecycleExtensionPressureReclaimBlockedCountKey)
            log.log("TRANSPORT_PROTECTION grace_active=true reclaim_blocked reason=\(reason)")
            return
        }
        guard extensionPressureReclaim || isStormMode() else { return }
        guard extensionPressureReclaim ? activeUDPStreams > 0 : activeUDPStreams >= BubbleConstants.maxActiveUDPControlStreams else { return }
        let now = Date()
        let aggressivePressure = extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank
        let includeDNS = aggressivePressure || extensionPressureLevel == .critical
        if !aggressivePressure {
            guard now >= maintenanceReclaimCooldownUntil else { return }
        }
        if let oldest = pendingUDPControlQueue.first,
           now.timeIntervalSince(oldest.enqueuedAt) < 0.25 {
            return
        }
        maintenanceReclaimTimestamps = maintenanceReclaimTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.udpMaintenanceReclaimWindowSeconds
        }
        if !aggressivePressure, maintenanceReclaimTimestamps.count >= BubbleConstants.udpMaintenanceReclaimBudgetPerWindow {
            maintenanceReclaimBudgetExhaustedCount += 1
            let extraCooldown = Double(maintenanceReclaimBudgetExhaustedCount) * BubbleConstants.udpEmergencyReclaimMinInterval
            maintenanceReclaimCooldownUntil = now.addingTimeInterval(BubbleConstants.udpEmergencyReclaimMinInterval + min(extraCooldown, 3.0))
            return
        }
        if !aggressivePressure {
            guard now.timeIntervalSince(lastEmergencyReclaimAt) >= BubbleConstants.udpEmergencyReclaimMinInterval else { return }
        }
        lastEmergencyReclaimAt = now
        let hardQueuePressure = extensionPressureReclaim || pendingUDPControlQueue.count >= BubbleConstants.maxQueuedUDPControlStreams
        var candidates = udpStreamsByID.values
            .filter {
                let isDNS = $0.lastPort == 53
                return !$0.closed &&
                !$0.processingFrame &&
                $0.pendingFrames.isEmpty &&
                now.timeIntervalSince($0.lastProgressAt) > 1.0 &&
                (includeDNS || !isDNS) &&
                (!$0.preservesMessagingControl || (includeDNS && isDNS))
            }
            .sorted {
                let lhsPriority = reclaimPriority(for: $0, now: now)
                let rhsPriority = reclaimPriority(for: $1, now: now)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return $0.lastActivityAt < $1.lastActivityAt
            }
        if candidates.isEmpty && hardQueuePressure {
            candidates = udpStreamsByID.values
                .filter {
                    let isDNS = $0.lastPort == 53
                    return !$0.closed &&
                    !$0.processingFrame &&
                    $0.pendingFrames.isEmpty &&
                    now.timeIntervalSince($0.lastProgressAt) > 1.0 &&
                    (!$0.preservesMessagingControl || (includeDNS && isDNS))
                }
                .sorted {
                    let lhsPriority = reclaimPriority(for: $0, now: now)
                    let rhsPriority = reclaimPriority(for: $1, now: now)
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    return $0.lastActivityAt < $1.lastActivityAt
                }
        }
        let batch = Self.pressureReclaimBatchSize(
            activeUDP: activeUDPStreams,
            candidateCount: candidates.count,
            pressureLevel: aggressivePressure ? extensionPressureLevel : .normal,
            stormMode: isStormMode()
        )
        guard batch > 0 else { return }
        maintenanceReclaimTimestamps.append(now)
        for state in candidates.prefix(batch) {
            udpReclaimsByReason["emergency_reclaim", default: 0] += 1
            emergencyReclaimTimestamps.append(now)
            let reclaimReason = "emergency_reclaim_\(reason)"
            if aggressivePressure || shouldAllowReclaim(reason: reclaimReason, now: now) {
                if aggressivePressure {
                    hardPressureUDPReclaims += 1
                    udpReclaimsByReason["hard_pressure_udp_reclaim", default: 0] += 1
                    log.log("UDP_PRESSURE reclaim stream=\(state.id) class=\(state.trafficClass.rawValue) last_port=\(state.lastPort.map(String.init) ?? "unknown") pressure=\(extensionPressureLevel.rawValue) reason=\(reclaimReason) active_udp=\(activeUDPStreams)")
                }
                closeUDPControlStream(client: state.client, state: state, reason: reclaimReason)
            } else {
                log.log("TRANSPORT_PROTECTION reclaim_cooldown_active reason=\(reclaimReason)")
            }
        }
    }

    private func pooledUDPConnection(host: String, port: NWEndpoint.Port, poolKey: String, allowReuse: Bool) -> NWConnection {
        if !allowReuse {
            udpSocketReuseMisses += 1
            return NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        }
        if let existing = udpSocketPool[poolKey] {
            udpSocketReuseHits += 1
            return existing
        }
        udpSocketReuseMisses += 1
        let created = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        udpSocketPool[poolKey] = created
        udpSocketPoolOrder.append(poolKey)
        if udpSocketPoolOrder.count > udpSocketPoolMaxEntries {
            let evicted = udpSocketPoolOrder.removeFirst()
            udpSocketPool.removeValue(forKey: evicted)?.cancel()
            startedUDPSocketKeys.remove(evicted)
        }
        return created
    }

    private func shouldReuseUDPSocket(for port: UInt16) -> Bool {
        // Keep UDP/DNS relays single-shot until pooled receive handlers are stream-safe.
        false
    }

    private func startUDPConnectionIfNeeded(_ connection: NWConnection, for poolKey: String) {
        if !startedUDPSocketKeys.contains(poolKey) {
            startedUDPSocketKeys.insert(poolKey)
            connection.start(queue: queue)
        }
    }

    private func evictUDPSocket(poolKey: String) {
        udpSocketPool.removeValue(forKey: poolKey)?.cancel()
        udpSocketPoolOrder.removeAll { $0 == poolKey }
        startedUDPSocketKeys.remove(poolKey)
    }

    private func watchdogTimeoutForState() -> TimeInterval {
        switch degradedState {
        case .degraded, .tripped:
            return BubbleConstants.udpProcessingWatchdogTimeoutDegraded
        case .healthy, .recovering:
            return BubbleConstants.udpProcessingWatchdogTimeout
        }
    }

    private func isStormMode() -> Bool {
        stormModeEnabled
    }

    private func effectiveMaxActiveUDPStreams(stormMode: Bool, safeMode: Bool = false) -> Int {
        Self.effectiveMaxActiveUDPStreams(stormMode: stormMode, safeMode: safeMode)
    }

    static func effectiveMaxActiveUDPStreams(stormMode: Bool, safeMode: Bool) -> Int {
        if safeMode {
            return BubbleConstants.safeModeMaxActiveUDPControlStreams
        }
        guard stormMode else { return BubbleConstants.maxActiveUDPControlStreams }
        return max(1, BubbleConstants.maxActiveUDPControlStreams - BubbleConstants.udpStormReservedSlots)
    }

    private func sampleStormModeDuration(now: Date) {
        if isStormMode() {
            if stormModeActiveSince == nil {
                stormModeActiveSince = now
            }
        } else if let since = stormModeActiveSince {
            stormModeActiveSecondsTotal += now.timeIntervalSince(since)
            stormModeActiveSince = nil
        }
    }

    private func stormModeActiveSeconds(now: Date = Date()) -> Double {
        if let since = stormModeActiveSince {
            return stormModeActiveSecondsTotal + now.timeIntervalSince(since)
        }
        return stormModeActiveSecondsTotal
    }

    private func dnsReservedSlotsInUse() -> Int {
        udpStreamsByID.values.filter { !$0.closed && $0.lastPort == 53 }.count
    }

    private func decoderReasonCode(_ error: UDPControlDecoderError) -> String {
        switch error {
        case .badPrefix:
            return "bad_prefix"
        case .badLength:
            return "bad_len"
        }
    }

    private func hexPrefix(_ data: Data) -> String {
        data.prefix(BubbleConstants.udpRecoveryHexDumpMaxBytes)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct BlockSuppressionState {
        var lastSeen: Date
        var suppressedHits: Int
    }

    private struct UDPDisabledRejectLogState {
        var windowStartedAt: Date
        var lastSeen: Date
        var suppressedHits: Int
    }

    private struct DNSIPHint {
        let domain: String
        let bucket: ContentBucket
        let expiresAt: Date
        let addedAt: Date
    }

    private struct TikTokIPHint {
        let domain: String?
        let source: String
        let expiresAt: Date
        let addedAt: Date
        let confidence: Double
    }

    private struct KnownBadUDPCacheEntry {
        let decision: PolicyDecision
        let bucket: ContentBucket
        let expiresAt: Date
        let addedAt: Date
    }

    private struct UDPPolicyEvaluation {
        let decision: PolicyDecision
        let source: String?
        let knownBadCacheHit: Bool
        let cacheExpiresAt: Date?
    }

    private struct DNSAddressAnswer {
        let domain: String
        let ip: String
        let ttl: UInt32
    }

    private struct DNSMessageSummary {
        let questions: [String]
        let addressAnswers: [DNSAddressAnswer]
    }

    private final class TCPSNIGateState {
        var buffer = Data()
        var completed = false
        var probeTimedOut = false
        var timeoutWorkItem: DispatchWorkItem?
    }

    private enum TLSClientHelloProbe {
        case needsMore
        case nonTLS
        case noSNI
        case sni(String)
    }

    private enum ProtectionGateStage {
        case admission
        case streamBlock
    }

    private enum ProtectionGateResult {
        case allow
        case suppress
        case dropFast
        case rejectNewStream
        case failOpen
    }

    private func suppressionKey(host: String, port: UInt16, reason: String) -> String {
        "\(host.lowercased()):\(port):\(reason)"
    }

    private func hostCooldownKey(host: String, port: UInt16, bucket: ContentBucket) -> String {
        "\(host.lowercased()):\(port):\(bucket.rawValue)"
    }

    private func classifyEarly(host: String, port: UInt16) -> ClassifiedFlow {
        let lower = host.lowercased()
        if port == 53 || lower.contains("dns") || lower.contains("mqtt") {
            return ClassifiedFlow(trafficClass: .generic, confidence: 0.95, reason: "control_or_dns")
        }
        for manifest in classManifests {
            if manifest.hostTokens.contains(where: { lower.contains($0) }) {
                return ClassifiedFlow(
                    trafficClass: manifest.appId,
                    confidence: manifest.appId == .tiktok ? 0.98 : 0.95,
                    reason: "host_match_\(manifest.appId.rawValue)"
                )
            }
        }
        if let hinted = classHint(for: lower) {
            return hinted
        }
        return ClassifiedFlow(trafficClass: .unknown, confidence: 0.20, reason: "no_signal")
    }

    private func classifyTrafficClass(host: String, decision: PolicyDecision? = nil, port: UInt16? = nil) -> TrafficClass {
        if let decision {
            return decision.trafficClass
        }
        guard let port else { return .generic }
        let classified = classifyEarly(host: host, port: port)
        return Self.admissionTrafficClass(for: classified)
    }

    private func classHint(for host: String, now: Date = Date()) -> ClassifiedFlow? {
        guard let hint = recentClassHintsByHost[host] else { return nil }
        if now.timeIntervalSince(hint.ts) > BubbleConstants.classHintTTLSeconds {
            recentClassHintsByHost.removeValue(forKey: host)
            return nil
        }
        return ClassifiedFlow(trafficClass: hint.trafficClass, confidence: min(0.75, hint.confidence), reason: "recent_hint")
    }

    private func recordClassHint(host: String, trafficClass: TrafficClass, confidence: Double, now: Date = Date()) {
        guard trafficClass != .generic && trafficClass != .unknown else { return }
        recentClassHintsByHost[host.lowercased()] = (trafficClass: trafficClass, confidence: confidence, ts: now)
        if recentClassHintsByHost.count > BubbleConstants.extensionPressureMaxClassHints {
            let overflow = recentClassHintsByHost.count - BubbleConstants.extensionPressureMaxClassHints
            for key in recentClassHintsByHost.sorted(by: { $0.value.ts < $1.value.ts }).prefix(overflow).map(\.key) {
                recentClassHintsByHost.removeValue(forKey: key)
            }
        }
    }

    private func evaluateUDPPolicy(
        host: String,
        port: UInt16,
        payloadBytes: Int,
        selectiveSafeMode: Bool = false,
        now: Date = Date()
    ) -> UDPPolicyEvaluation {
        if selectiveSafeMode, let cacheEntry = knownBadUDPCacheEntry(host: host, port: port, now: now) {
            safeModeKnownBadUDPCacheHits += 1
            return UDPPolicyEvaluation(
                decision: cacheEntry.decision,
                source: "known_bad_cache",
                knownBadCacheHit: true,
                cacheExpiresAt: cacheEntry.expiresAt
            )
        }

        if port == 443, let hint = dnsHint(for: host, now: now) {
            let decision = filter.evaluateStream(
                host: hint.domain,
                sni: hint.domain,
                port: port,
                bytesDown: payloadBytes,
                connectionAge: 0,
                parallelConnections: 1
            )
            if isDecisionCompatibleWithDNSHint(decision, hint: hint) {
                if hint.bucket == .tiktokVideo {
                    tiktokUDPBlocksFromDNSHints += 1
                } else if hint.bucket == .reels {
                    instagramUDPBlocksFromDNSHints += 1
                }
                if selectiveSafeMode {
                    cacheKnownBadUDP(
                        host: host,
                        port: port,
                        decision: decision,
                        expiresAt: hint.expiresAt,
                        now: now
                    )
                }
                return UDPPolicyEvaluation(
                    decision: decision,
                    source: "dns_hint",
                    knownBadCacheHit: false,
                    cacheExpiresAt: hint.expiresAt
                )
            }
        }

        let decision = filter.evaluateUDP(host: host, port: port, payloadBytes: payloadBytes)
        if selectiveSafeMode, port == 443, isKnownBlockedVideoDecision(decision) {
            let expiresAt = now.addingTimeInterval(BubbleConstants.dnsTikTokHintMaxTTLSeconds)
            cacheKnownBadUDP(
                host: host,
                port: port,
                decision: decision,
                expiresAt: expiresAt,
                now: now
            )
            return UDPPolicyEvaluation(
                decision: decision,
                source: "direct_host",
                knownBadCacheHit: false,
                cacheExpiresAt: expiresAt
            )
        }

        return UDPPolicyEvaluation(
            decision: decision,
            source: nil,
            knownBadCacheHit: false,
            cacheExpiresAt: nil
        )
    }

    private func isDecisionCompatibleWithDNSHint(_ decision: PolicyDecision, hint: DNSIPHint) -> Bool {
        guard decision.action == .blockNow else { return false }
        switch hint.bucket {
        case .tiktokVideo:
            return decision.reason == "tiktok_video_block_now" &&
                decision.classification.bucket == .tiktokVideo &&
                decision.trafficClass == .tiktok
        case .reels:
            return decision.reason == "reels_media_block_now" &&
                decision.classification.bucket == .reels &&
                decision.trafficClass == .instagram
        default:
            return false
        }
    }

    private func isKnownBlockedVideoDecision(_ decision: PolicyDecision) -> Bool {
        Self.isKnownBlockedVideoDecision(decision)
    }

    private func isUnknownUDPAllow(_ decision: PolicyDecision) -> Bool {
        decision.classification.bucket == .unknown ||
            decision.classification.confidence < BubbleConstants.classifyConfidenceLow
    }

    static func isKnownBlockedVideoDecision(_ decision: PolicyDecision) -> Bool {
        guard decision.action == .blockNow else { return false }
        if decision.reason == "tiktok_video_block_now" ||
            decision.reason == "tiktok_ip_hint_block_now" {
            return decision.classification.bucket == .tiktokVideo && decision.trafficClass == .tiktok
        }
        if decision.reason == "reels_media_block_now" ||
            decision.reason == "reels_media_hint_block_now" ||
            decision.reason == "reels_strict_media_block_now" {
            return decision.classification.bucket == .reels && decision.trafficClass == .instagram
        }
        if decision.reason == "x_feed_media_block_now" {
            return decision.classification.bucket == .xFeedMedia && decision.trafficClass == .x
        }
        if decision.reason == "x_strict_feed_api_block_now" {
            return decision.classification.bucket == .xFeedAPI && decision.trafficClass == .x
        }
        return false
    }

    private func knownBadUDPCacheKey(host: String, port: UInt16, bucket: ContentBucket) -> String {
        "\(host.lowercased()):\(port):\(bucket.rawValue)"
    }

    private func knownBadUDPCacheEntry(host: String, port: UInt16, now: Date = Date()) -> KnownBadUDPCacheEntry? {
        pruneKnownBadUDPCache(now: now)
        for bucket in [ContentBucket.tiktokVideo, ContentBucket.reels] {
            let key = knownBadUDPCacheKey(host: host, port: port, bucket: bucket)
            if let entry = knownBadUDPCache[key], now < entry.expiresAt {
                return entry
            }
        }
        return nil
    }

    private func cacheKnownBadUDP(
        host: String,
        port: UInt16,
        decision: PolicyDecision,
        expiresAt requestedExpiresAt: Date,
        now: Date = Date()
    ) {
        guard isKnownBlockedVideoDecision(decision) else { return }
        let cap = now.addingTimeInterval(BubbleConstants.dnsTikTokHintMaxTTLSeconds)
        let expiresAt = requestedExpiresAt < cap ? requestedExpiresAt : cap
        guard expiresAt > now else { return }
        let key = knownBadUDPCacheKey(host: host, port: port, bucket: decision.classification.bucket)
        knownBadUDPCache[key] = KnownBadUDPCacheEntry(
            decision: decision,
            bucket: decision.classification.bucket,
            expiresAt: expiresAt,
            addedAt: now
        )
        if knownBadUDPCache.count > BubbleConstants.extensionPressureMaxDNSHints {
            let overflow = knownBadUDPCache.count - BubbleConstants.extensionPressureMaxDNSHints
            for oldKey in knownBadUDPCache.sorted(by: { $0.value.addedAt < $1.value.addedAt }).prefix(overflow).map(\.key) {
                knownBadUDPCache.removeValue(forKey: oldKey)
            }
        }
    }

    private func pruneKnownBadUDPCache(now: Date = Date()) {
        knownBadUDPCache = knownBadUDPCache.filter { now < $0.value.expiresAt }
    }

    private func dnsHint(for host: String, now: Date = Date()) -> DNSIPHint? {
        pruneExpiredDNSHints(now: now)
        let key = host.lowercased()
        guard let hint = dnsHintsByIP[key] else { return nil }
        if now >= hint.expiresAt {
            dnsHintsByIP.removeValue(forKey: key)
            recordDNSHintExpired(ip: key, hint: hint)
            return nil
        }
        return hint
    }

    private func recordDNSHintExpired(ip: String, hint: DNSIPHint) {
        switch hint.bucket {
        case .tiktokVideo:
            tiktokDNSHintsExpired += 1
            log.log("UDP_DNS_HINT expired ip=\(ip) host=\(hint.domain) bucket=tiktok_video")
        case .reels:
            instagramDNSHintsExpired += 1
            log.log("IG_DNS_HINT expired ip=\(ip) host=\(hint.domain) bucket=reels_video")
        default:
            break
        }
    }

    private func recordDNSHints(from payload: Data, now: Date = Date()) {
        pruneExpiredDNSHints(now: now)
        guard let summary = Self.parseDNSMessage(payload) else { return }
        let classifiedQuestionDomains = summary.questions.compactMap { classifiedVideoHintDomain($0) }
        for answer in summary.addressAnswers where answer.ttl > 0 {
            let matched = classifiedVideoHintDomain(answer.domain) ?? classifiedQuestionDomains.first
            guard let matched else { continue }
            let ttl = min(TimeInterval(answer.ttl), BubbleConstants.dnsTikTokHintMaxTTLSeconds)
            guard ttl > 0 else { continue }
            let key = answer.ip.lowercased()
            dnsHintsByIP[key] = DNSIPHint(
                domain: matched.domain,
                bucket: matched.bucket,
                expiresAt: now.addingTimeInterval(ttl),
                addedAt: now
            )
            if matched.bucket == .tiktokVideo {
                tiktokDNSHintsAdded += 1
                recordClassHint(host: key, trafficClass: .tiktok, confidence: 0.90, now: now)
                recordTikTokIPHint(
                    ip: key,
                    port: 443,
                    domain: matched.domain,
                    source: "dns",
                    ttl: ttl,
                    confidence: 0.90,
                    now: now
                )
                log.log("UDP_DNS_HINT host=\(matched.domain) ip=\(key) bucket=tiktok_video ttl_s=\(Int(ttl))")
            } else if matched.bucket == .reels {
                instagramDNSHintsAdded += 1
                recordClassHint(host: key, trafficClass: .instagram, confidence: 0.90, now: now)
                log.log("IG_DNS_HINT host=\(matched.domain) ip=\(key) bucket=reels_video ttl_s=\(Int(ttl))")
            }
        }
        if dnsHintsByIP.count > BubbleConstants.extensionPressureMaxDNSHints {
            let overflow = dnsHintsByIP.count - BubbleConstants.extensionPressureMaxDNSHints
            for key in dnsHintsByIP.sorted(by: { $0.value.addedAt < $1.value.addedAt }).prefix(overflow).map(\.key) {
                dnsHintsByIP.removeValue(forKey: key)
            }
        }
    }

    private func classifiedVideoHintDomain(_ domain: String) -> (domain: String, bucket: ContentBucket)? {
        if isTikTokVideoBlockedDomain(domain) {
            return (domain, .tiktokVideo)
        }
        if isInstagramReelsVideoBlockedDomain(domain) {
            return (domain, .reels)
        }
        return nil
    }

    private func isTikTokVideoBlockedDomain(_ domain: String) -> Bool {
        let decision = filter.evaluateStream(
            host: domain,
            sni: domain,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1
        )
        return decision.action == .blockNow &&
            decision.reason == "tiktok_video_block_now" &&
            decision.classification.bucket == .tiktokVideo &&
            decision.trafficClass == .tiktok
    }

    private func isInstagramReelsVideoBlockedDomain(_ domain: String) -> Bool {
        let decision = filter.evaluateStream(
            host: domain,
            sni: domain,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1
        )
        return decision.action == .blockNow &&
            decision.reason == "reels_media_block_now" &&
            decision.classification.bucket == .reels &&
            decision.trafficClass == .instagram
    }

    private func pruneExpiredDNSHints(now: Date = Date()) {
        let expiredKeys = dnsHintsByIP.filter { now >= $0.value.expiresAt }.map(\.key)
        guard !expiredKeys.isEmpty else { return }
        for key in expiredKeys {
            if let hint = dnsHintsByIP.removeValue(forKey: key) {
                recordDNSHintExpired(ip: key, hint: hint)
            }
        }
    }

    private func activeDNSHintCount(bucket: ContentBucket) -> Int {
        let now = Date()
        return dnsHintsByIP.values.filter { $0.bucket == bucket && now < $0.expiresAt }.count
    }

    private func instagramMediaHintCounters(now: Date = Date()) -> InstagramMediaHintCounterSnapshot {
        (filter as? InstagramMediaHintReporting)?.instagramMediaHintCounterSnapshot(now: now) ?? .zero
    }

    func tiktokIPHintCounterSnapshot(now: Date = Date()) -> TikTokIPHintCounterSnapshot {
        pruneTikTokIPHints(now: now)
        return TikTokIPHintCounterSnapshot(
            added: tiktokIPHintsAdded,
            expired: tiktokIPHintsExpired,
            active: tiktokIPHintsByKey.count,
            blocks: tiktokIPHintBlocks
        )
    }

    private func tiktokIPHintKey(ip: String, port: UInt16) -> String {
        "\(ip.lowercased()):\(port)"
    }

    private func isIPAddressLiteral(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized.split(separator: ".").count == 4 {
            return normalized.split(separator: ".").allSatisfy { part in
                guard let value = Int(part), value >= 0, value <= 255 else { return false }
                return String(value) == String(part) || (part.count > 1 && part.first == "0")
            }
        }
        guard normalized.contains(":") else { return false }
        return normalized.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(Int(scalar.value)) ||
            (97...102).contains(Int(scalar.value)) ||
            scalar.value == 58 || scalar.value == 46
        }
    }

    private func isDirectTikTokIPHintCandidate(host: String, port: UInt16) -> Bool {
        port == 443 && isIPAddressLiteral(host)
    }

    private func recordTikTokIPHint(
        ip: String,
        port: UInt16,
        domain: String?,
        source: String,
        ttl: TimeInterval,
        confidence: Double,
        now: Date = Date()
    ) {
        guard isDirectTikTokIPHintCandidate(host: ip, port: port) else { return }
        let cappedTTL = min(ttl, source == "retry_burst" ? BubbleConstants.tiktokRetryBurstIPHintTTLSeconds : BubbleConstants.tiktokIPHintTTLSeconds)
        guard cappedTTL > 0 else { return }
        let key = tiktokIPHintKey(ip: ip, port: port)
        let expiresAt = now.addingTimeInterval(cappedTTL)
        if let existing = tiktokIPHintsByKey[key],
           now < existing.expiresAt,
           existing.expiresAt >= expiresAt,
           existing.source == source,
           existing.domain == domain?.lowercased() {
            return
        }

        tiktokIPHintsByKey[key] = TikTokIPHint(
            domain: domain?.lowercased(),
            source: source,
            expiresAt: expiresAt,
            addedAt: now,
            confidence: confidence
        )
        tiktokIPHintsAdded += 1
        log.log(
            "TT_IP_HINT added ip=\(ip.lowercased()) port=\(port) host=\(domain?.lowercased() ?? "n/a") source=\(source) ttl_s=\(Int(cappedTTL))"
        )
        pruneTikTokIPHintsToLimit()
    }

    private func recordTikTokIPHintFromSNI(ip: String, port: UInt16, sni: String, decision: PolicyDecision, now: Date = Date()) {
        guard isDirectTikTokIPHintCandidate(host: ip, port: port) else { return }
        guard decision.reason == "tiktok_video_block_now",
              decision.classification.bucket == .tiktokVideo,
              decision.trafficClass == .tiktok else {
            return
        }
        recordTikTokIPHint(
            ip: ip,
            port: port,
            domain: sni,
            source: "sni",
            ttl: BubbleConstants.tiktokIPHintTTLSeconds,
            confidence: 0.95,
            now: now
        )
    }

    private func tiktokIPHint(for ip: String, port: UInt16, now: Date) -> TikTokIPHint? {
        pruneTikTokIPHints(now: now)
        guard isDirectTikTokIPHintCandidate(host: ip, port: port) else { return nil }
        let key = tiktokIPHintKey(ip: ip, port: port)
        guard let hint = tiktokIPHintsByKey[key] else { return nil }
        if now >= hint.expiresAt {
            tiktokIPHintsByKey.removeValue(forKey: key)
            tiktokIPHintsExpired += 1
            log.log("TT_IP_HINT expired ip=\(ip.lowercased()) port=\(port) host=\(hint.domain ?? "n/a") source=\(hint.source)")
            return nil
        }
        return hint
    }

    private func pruneTikTokIPHints(now: Date = Date()) {
        let expiredKeys = tiktokIPHintsByKey.compactMap { key, hint in
            now >= hint.expiresAt ? key : nil
        }
        guard !expiredKeys.isEmpty else { return }
        for key in expiredKeys {
            if let hint = tiktokIPHintsByKey.removeValue(forKey: key) {
                tiktokIPHintsExpired += 1
                log.log("TT_IP_HINT expired ip=\(key) host=\(hint.domain ?? "n/a") source=\(hint.source)")
            }
        }
    }

    private func pruneTikTokIPHintsToLimit() {
        guard tiktokIPHintsByKey.count > BubbleConstants.maxTikTokIPHints else { return }
        let overflow = tiktokIPHintsByKey.count - BubbleConstants.maxTikTokIPHints
        for key in tiktokIPHintsByKey.sorted(by: { $0.value.addedAt < $1.value.addedAt }).prefix(overflow).map(\.key) {
            tiktokIPHintsByKey.removeValue(forKey: key)
        }
    }

    private func recordTikTokVideoBlockEventIfNeeded(_ decision: PolicyDecision, now: Date) {
        guard decision.reason == "tiktok_video_block_now",
              decision.classification.bucket == .tiktokVideo,
              decision.trafficClass == .tiktok else {
            return
        }
        recentTikTokVideoBlockEvents = recentTikTokVideoBlockEvents.filter {
            now.timeIntervalSince($0) <= BubbleConstants.tiktokRetryBurstBlockedHostWindow
        }
        recentTikTokVideoBlockEvents.append(now)
    }

    private func hasTikTokVideoBlockBurst(now: Date) -> Bool {
        recentTikTokVideoBlockEvents = recentTikTokVideoBlockEvents.filter {
            now.timeIntervalSince($0) <= BubbleConstants.tiktokRetryBurstBlockedHostWindow
        }
        return recentTikTokVideoBlockEvents.count >= BubbleConstants.tiktokRetryBurstBlockedHostThreshold
    }

    private func isUnknownDirectIPAttempt(_ decision: PolicyDecision) -> Bool {
        decision.action != .blockNow &&
            (decision.classification.bucket == .unknown ||
             decision.trafficClass == .generic ||
             decision.trafficClass == .unknown ||
             decision.classification.confidence < BubbleConstants.classifyConfidenceLow)
    }

    private func recordUnknownTikTokDirectIPAttemptAndMaybeHint(host: String, port: UInt16, decision: PolicyDecision, now: Date) {
        guard isDirectTikTokIPHintCandidate(host: host, port: port) else { return }
        guard isUnknownDirectIPAttempt(decision), hasTikTokVideoBlockBurst(now: now) else { return }

        let key = tiktokIPHintKey(ip: host, port: port)
        var attempts = recentUnknownTikTokDirectIPAttemptsByKey[key] ?? []
        attempts = attempts.filter {
            now.timeIntervalSince($0) <= BubbleConstants.tiktokRetryBurstUnknownIPAttemptWindow
        }
        attempts.append(now)
        recentUnknownTikTokDirectIPAttemptsByKey[key] = attempts

        guard attempts.count >= BubbleConstants.tiktokRetryBurstUnknownIPAttemptThreshold else { return }
        recordTikTokIPHint(
            ip: host,
            port: port,
            domain: nil,
            source: "retry_burst",
            ttl: BubbleConstants.tiktokRetryBurstIPHintTTLSeconds,
            confidence: 0.66,
            now: now
        )
    }

    private func buildTikTokIPHintDecision(host: String, port: UInt16, hint: TikTokIPHint) -> PolicyDecision? {
        let policyHost = hint.domain ?? "v16.tiktokcdn.com"
        let policyDecision = filter.evaluateStream(
            host: policyHost,
            sni: policyHost,
            port: port,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: activeRelays.count
        )
        guard policyDecision.action == .blockNow,
              policyDecision.reason == "tiktok_video_block_now",
              policyDecision.classification.bucket == .tiktokVideo,
              policyDecision.trafficClass == .tiktok else {
            return nil
        }

        return PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(
                bucket: .tiktokVideo,
                confidence: hint.confidence,
                reasons: ["tiktok_ip_hint", "source_\(hint.source)"]
            ),
            reason: "tiktok_ip_hint_block_now",
            toggleSnapshot: policyDecision.toggleSnapshot,
            policyVersion: policyDecision.policyVersion,
            intendedAction: nil,
            appStrategy: policyDecision.appStrategy,
            trafficClass: .tiktok
        )
    }

    private func evaluateTikTokDirectIPDecision(host: String, port: UInt16, initialDecision: PolicyDecision, now: Date = Date()) -> PolicyDecision? {
        guard isDirectTikTokIPHintCandidate(host: host, port: port) else { return nil }
        recordUnknownTikTokDirectIPAttemptAndMaybeHint(host: host, port: port, decision: initialDecision, now: now)
        guard let hint = tiktokIPHint(for: host, port: port, now: now),
              let decision = buildTikTokIPHintDecision(host: host, port: port, hint: hint) else {
            return nil
        }

        tiktokIPHintBlocks += 1
        log.log(
            "TT_POLICY ip=\(host.lowercased()) host=\(hint.domain ?? "n/a") bucket=tiktok_video action=block_now reason=tiktok_ip_hint_block_now source=\(hint.source)"
        )
        return decision
    }

    private func shouldDropFromHostCooldown(host: String, port: UInt16, bucket: ContentBucket, now: Date = Date()) -> Bool {
        let key = hostCooldownKey(host: host, port: port, bucket: bucket)
        guard let until = hostCooldownUntilByKey[key], now < until else { return false }
        return true
    }

    private func markHostCooldown(host: String, port: UInt16, bucket: ContentBucket, now: Date = Date()) {
        let key = hostCooldownKey(host: host, port: port, bucket: bucket)
        hostCooldownUntilByKey[key] = now.addingTimeInterval(BubbleConstants.hostCooldownDropSeconds)
    }

    private func shouldSuppressBlockedFlow(host: String, port: UInt16, reason: String, transport: String) -> Bool {
        let now = Date()
        let key = suppressionKey(host: host, port: port, reason: reason)
        let cooldown = suppressionCooldown(for: reason)
        if var state = blockedSuppression[key] {
            if now.timeIntervalSince(state.lastSeen) <= cooldown {
                state.lastSeen = now
                state.suppressedHits += 1
                blockedSuppression[key] = state
                if state.suppressedHits >= blockSuppressionLogCap && state.suppressedHits % blockSuppressionSummaryEvery == 0 {
                    log.log("POLICY_SUPPRESSION transport=\(transport) host=\(host.lowercased()) port=\(port) reason=\(reason) suppressed=\(state.suppressedHits)")
                }
                return true
            }
            blockedSuppression[key] = BlockSuppressionState(lastSeen: now, suppressedHits: 0)
            return false
        }
        blockedSuppression[key] = BlockSuppressionState(lastSeen: now, suppressedHits: 0)
        return false
    }

    private func evaluateProtectionGate(
        host: String,
        port: UInt16,
        decision: PolicyDecision,
        transport: String,
        stage: ProtectionGateStage
    ) -> ProtectionGateResult {
        guard decision.action == .blockNow else {
            return .allow
        }

        let now = Date()
        recentProtectedBlockEvents.append(now)
        recordTikTokVideoBlockEventIfNeeded(decision, now: now)
        if shouldFailOpenProtectedBlock(host: host, port: port, decision: decision, transport: transport, now: now) {
            return .failOpen
        }

        guard shouldUseHardenedPath(decision) else {
            return .allow
        }

        if stage == .admission && shouldRejectNewProtectedUDPControlStream() {
            return .rejectNewStream
        }
        if shouldDropFromHostCooldown(host: host, port: port, bucket: decision.classification.bucket) {
            logProtectedFastDrop(host: host, port: port, decision: decision, transport: transport, reason: "retry_storm_cooldown")
            return .dropFast
        }
        if shouldDropProtectedRetryByTokenBucket(host: host, port: port, decision: decision, transport: transport) {
            tokenBucketDrops += 1
            var classState = classState(for: decision.trafficClass)
            classState.tokenDrops += 1
            setClassState(classState, for: decision.trafficClass)
            markHostCooldown(host: host, port: port, bucket: decision.classification.bucket)
            logProtectedFastDrop(host: host, port: port, decision: decision, transport: transport, reason: "tiktok_retry_storm")
            return .dropFast
        }
        if shouldSuppressBlockedFlow(host: host, port: port, reason: decision.reason, transport: transport) {
            return .suppress
        }
        return .allow
    }

    private func logProtectedFastDrop(host: String, port: UInt16, decision: PolicyDecision, transport: String, reason: String) {
        if decision.classification.bucket == .tiktokVideo {
            log.log(
                "TCP_POLICY_FAST_DROP host=\(host.lowercased()) reason=tiktok_retry_storm port=\(port) transport=\(transport) bucket=tiktok_video"
            )
        } else if decision.classification.bucket == .reels {
            log.log(
                "IG_POLICY_FAST_DROP host=\(host.lowercased()) reason=\(reason) port=\(port) transport=\(transport) bucket=reels_video"
            )
        }
    }

    private func shouldFailOpenProtectedBlock(host: String, port: UInt16, decision: PolicyDecision, transport: String, now: Date = Date()) -> Bool {
        guard Self.isFailOpenCandidate(decision) else { return false }
        if now < protectedBlockFailOpenUntil {
            protectedBlockFailOpenAllows += 1
            return true
        }
        recentFailOpenCandidateBlockEvents = recentFailOpenCandidateBlockEvents.filter {
            now.timeIntervalSince($0) <= BubbleConstants.protectedBlockFailOpenWindowSeconds
        }
        recentFailOpenCandidateBlockEvents.append(now)
        guard recentFailOpenCandidateBlockEvents.count >= BubbleConstants.protectedBlockFailOpenTriggerCount else {
            return false
        }
        protectedBlockFailOpenUntil = now.addingTimeInterval(BubbleConstants.protectedBlockFailOpenSeconds)
        protectedBlockFailOpenActivations += 1
        protectedBlockFailOpenAllows += 1
        admissionRejectsByReason["protected_block_fail_open", default: 0] += 1
        log.log(
            "PROTECTED_BLOCK_FAIL_OPEN activated host=\(host.lowercased()) port=\(port) transport=\(transport) " +
            "reason=\(decision.reason) recent_blocks=\(recentFailOpenCandidateBlockEvents.count) duration_s=\(Int(BubbleConstants.protectedBlockFailOpenSeconds))"
        )
        return true
    }

    static func isFailOpenCandidate(_ decision: PolicyDecision) -> Bool {
        guard decision.action == .blockNow else { return false }
        guard !isKnownBlockedVideoDecision(decision) else { return false }
        if decision.classification.bucket == .unknown {
            return true
        }
        if decision.trafficClass == .unknown || decision.trafficClass == .generic {
            return true
        }
        return decision.classification.confidence < BubbleConstants.classifyConfidenceLow
    }

    private func suppressionCooldown(for reason: String) -> TimeInterval {
        if reason == "tiktok_video_block_now" ||
            reason == "tiktok_ip_hint_block_now" ||
            reason == "reels_media_block_now" ||
            reason == "reels_media_hint_block_now" ||
            reason == "reels_strict_media_block_now" {
            if extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank {
                return BubbleConstants.aggressiveBlockSuppressionStormCooldown
            }
            switch degradedState {
            case .healthy:
                return aggressiveBlockSuppressionCooldown
            case .degraded, .tripped:
                return BubbleConstants.aggressiveBlockSuppressionStormCooldown
            case .recovering:
                return aggressiveBlockSuppressionCooldown * 1.5
            }
        }
        return blockSuppressionCooldown
    }

    private func countRecentEmergencyReclaims(windowSeconds: TimeInterval) -> Int {
        let now = Date()
        emergencyReclaimTimestamps = emergencyReclaimTimestamps.filter { now.timeIntervalSince($0) <= windowSeconds }
        return emergencyReclaimTimestamps.count
    }

    private func shouldRejectNewProtectedUDPControlStream() -> Bool {
        let now = Date()
        if hasAnyProtectionGrace(now: now) {
            return false
        }
        guard isProtectedRetryStormActive() else { return false }
        let phase = currentTransportPressurePhase(now: now)
        if phase == .critical {
            // Invariant: avoid full rejection unless we're truly at hard cap.
            return Self.shouldForceGlobalUDPReject(
                active: activeUDPStreams,
                queued: pendingUDPControlQueue.count,
                maxActive: BubbleConstants.maxActiveUDPControlStreams,
                maxQueued: BubbleConstants.maxQueuedUDPControlStreams
            )
        }
        if phase == .degraded {
            return pendingUDPControlQueue.count >= BubbleConstants.degradedTikTokUDPRejectQueueDepth
        }
        return false
    }

    private func shouldDropProtectedRetryByTokenBucket(host: String, port: UInt16, decision: PolicyDecision, transport: String) -> Bool {
        guard decision.action == .blockNow, isProtectedBlockedBucket(decision.classification.bucket) else {
            return false
        }
        let key = "\(host.lowercased()):\(port):\(decision.classification.bucket.rawValue)"
        let now = Date()
        var bucket = tokenBucketsByHost[key] ?? TokenBucketState(
            tokens: BubbleConstants.tiktokRetryTokenBucketCapacity,
            lastRefillAt: now
        )
        let elapsed = max(0, now.timeIntervalSince(bucket.lastRefillAt))
        let refill = elapsed * BubbleConstants.tiktokRetryTokenBucketRefillPerSecond
        bucket.tokens = min(BubbleConstants.tiktokRetryTokenBucketCapacity, bucket.tokens + refill)
        bucket.lastRefillAt = now

        if bucket.tokens < 1.0 {
            tokenBucketsByHost[key] = bucket
            return true
        }

        bucket.tokens -= 1.0
        tokenBucketsByHost[key] = bucket
        return false
    }

    private func isProtectedRetryStormActive(now: Date = Date()) -> Bool {
        recentProtectedBlockEvents = recentProtectedBlockEvents.filter { now.timeIntervalSince($0) <= 15 }
        return recentProtectedBlockEvents.count >= 8
    }

    private func recentBadLenHardFailCount(now: Date = Date()) -> Int {
        recentBadLenHardFailTimestamps = recentBadLenHardFailTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.badLenRateWindowSeconds
        }
        return recentBadLenHardFailTimestamps.count
    }

    private func badLenHardFailRate(now: Date = Date()) -> Double {
        let count = recentBadLenHardFailCount(now: now)
        let denom = max(1.0, BubbleConstants.badLenRateWindowSeconds)
        return Double(count) / denom
    }

    private func isStartupGraceActive(now: Date = Date()) -> Bool {
        stabilityFirstModeEnabled && now < protectionStartupGraceUntil
    }

    private func isRecoveryGraceActive(now: Date = Date()) -> Bool {
        stabilityFirstModeEnabled && now < recoveryGraceUntil
    }

    private func hasAnyProtectionGrace(now: Date = Date()) -> Bool {
        isStartupGraceActive(now: now) || isRecoveryGraceActive(now: now)
    }

    private func isDNSStartupDrainWindowActive(now: Date = Date()) -> Bool {
        guard stabilityFirstModeEnabled else { return false }
        guard udpSessionStartedAt > .distantPast else { return false }
        return now.timeIntervalSince(udpSessionStartedAt) <= BubbleConstants.dnsStartupDrainWindowSeconds
    }

    private func isDNSStartupDrainActive(now: Date = Date()) -> Bool {
        _ = now
        return udpStreamsByID.values.contains { state in
            !state.closed && state.dnsStartupDrainStartedAt != nil
        }
    }

    private func persistDNSStartupDrainState(now: Date = Date()) {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        defaults?.set(isDNSStartupDrainActive(now: now), forKey: BubbleConstants.vpnLifecycleDNSStartupDrainActiveKey)
        defaults?.set(dnsStartupDrainCloses, forKey: BubbleConstants.vpnLifecycleDNSStartupDrainClosesKey)
        defaults?.set(dnsStartupDrainFramesProcessed, forKey: BubbleConstants.vpnLifecycleDNSStartupDrainFramesProcessedKey)
    }

    private func currentTransportPressurePhase(now: Date = Date()) -> TransportPressurePhase {
        if degradedState == .tripped || extensionPressureLevel == .critical {
            return .critical
        }
        if degradedState == .degraded || degradedState == .recovering || extensionPressureLevel.rank >= ExtensionPressureLevel.hard.rank {
            return .degraded
        }
        return .normal
    }

    private func effectiveDegradedEnterQueueDepth() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.degradedEnterQueueDepth + 8 : BubbleConstants.degradedEnterQueueDepth
    }

    private func effectiveTrippedEnterQueueDepth() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.trippedEnterQueueDepth + 8 : BubbleConstants.trippedEnterQueueDepth
    }

    private func effectiveDegradedTimeoutRateEnter() -> Double {
        stabilityFirstModeEnabled ? 0.65 : BubbleConstants.degradedTimeoutRateEnter
    }

    private func effectiveTrippedEnterTimeoutRate() -> Double {
        stabilityFirstModeEnabled ? 0.80 : BubbleConstants.trippedEnterTimeoutRate
    }

    private func effectiveTrippedEnterMinDegradedSeconds() -> TimeInterval {
        stabilityFirstModeEnabled ? max(BubbleConstants.trippedCriticalDwellSeconds, BubbleConstants.trippedEnterMinDegradedSeconds * 2.0) : BubbleConstants.trippedEnterMinDegradedSeconds
    }

    private func effectiveDecodeFailureCloseThreshold() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.udpDecodeFailureCloseThreshold + 2 : BubbleConstants.udpDecodeFailureCloseThreshold
    }

    private func effectiveBadLenSoftFailureLimit() -> Int {
        stabilityFirstModeEnabled ? BubbleConstants.udpDecodeBadLenSoftFailureLimit + 4 : BubbleConstants.udpDecodeBadLenSoftFailureLimit
    }

    private func effectiveRecoveredDecoderCloseDensity() -> Double {
        stabilityFirstModeEnabled ? 7.0 : 4.0
    }

    private func effectiveDecoderCloseDensity() -> Double {
        stabilityFirstModeEnabled ? 8.0 : 5.0
    }

    private func effectiveTimeoutStreakCloseThreshold(base: Int) -> Int {
        stabilityFirstModeEnabled ? base + 2 : base
    }

    private func effectiveMaxLifetime(base: TimeInterval) -> TimeInterval {
        stabilityFirstModeEnabled ? base * 1.5 : base
    }

    private func effectiveIdleTimeout(base: TimeInterval) -> TimeInterval {
        stabilityFirstModeEnabled ? base * 2.0 : base
    }

    private func shouldCloseStreamForTimeout(state: UDPStreamState, now: Date) -> Bool {
        if hasAnyProtectionGrace(now: now) {
            return false
        }
        guard stabilityFirstModeEnabled else { return true }
        let lifetimeOK = now.timeIntervalSince(state.createdAt) >= BubbleConstants.selectiveReclaimMinLifetimeSeconds
        let idleOK = now.timeIntervalSince(state.lastActivityAt) >= BubbleConstants.selectiveReclaimMinIdleSeconds
        let noRecentSuccess = state.lastSuccessfulResponseAt.map { now.timeIntervalSince($0) > 2.0 } ?? true
        return lifetimeOK && idleOK && noRecentSuccess
    }

    private func shouldSkipIdleReclaimDueToRecentSuccess(state: UDPStreamState, now: Date) -> Bool {
        guard stabilityFirstModeEnabled else { return false }
        if let recent = state.lastSuccessfulResponseAt, now.timeIntervalSince(recent) <= 3.0 {
            return true
        }
        return false
    }

    private func shouldAllowReclaim(reason: String, now: Date) -> Bool {
        if let until = reclaimCooldownUntilByReason[reason], now < until {
            return false
        }
        reclaimCooldownUntilByReason[reason] = now.addingTimeInterval(BubbleConstants.reclaimReasonCooldownSeconds)
        return true
    }

    private func pruneSuppressionState(now: Date) {
        let maxWindow = max(blockSuppressionCooldown, BubbleConstants.aggressiveBlockSuppressionStormCooldown)
        blockedSuppression = blockedSuppression.filter { now.timeIntervalSince($0.value.lastSeen) <= (maxWindow * 4.0) }
    }

    private func pruneHostCooldowns(now: Date = Date()) {
        hostCooldownUntilByKey = hostCooldownUntilByKey.filter { now < $0.value }
    }

    private func assertQueueInvariants() {
        let queuedIDs = Set(pendingUDPControlQueue.map { $0.id })
        if queuedIDs.count != pendingUDPControlQueue.count {
            queueInvariantViolationCount += 1
            log.log("QUEUE_INVARIANT duplicate_ids_detected count=\(pendingUDPControlQueue.count) unique=\(queuedIDs.count)")
        }
        let activeIDs = Set(udpStreamsByID.keys)
        if !queuedIDs.isDisjoint(with: activeIDs) {
            queueInvariantViolationCount += 1
            log.log("QUEUE_INVARIANT active_and_queued_overlap overlap=\(queuedIDs.intersection(activeIDs).count)")
        }
    }

    private func healthVerdict() -> String {
        if queueInvariantViolationCount > 0 {
            return "critical_invariant_violation"
        }
        if requeueChurnCount > 50 {
            return "degraded_queue_churn"
        }
        if degradedState == .tripped {
            return "tripped_pressure"
        }
        if degradedState == .degraded {
            return "degraded_pressure"
        }
        return "healthy"
    }

    private func reconnectBreakerCooldownRemainingSec(now: Date = Date()) -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        let until = defaults?.double(forKey: BubbleConstants.vpnLifecycleReconnectBreakerUntilTSKey) ?? 0
        guard until > now.timeIntervalSince1970 else { return 0 }
        return Int(ceil(until - now.timeIntervalSince1970))
    }

    private func reconnectBreakerTrips() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerTripsKey) ?? 0
    }

    private func reconnectSuppressedByBreakerCount() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectSuppressedByBreakerKey) ?? 0
    }

    private func reconnectBreakerBackoffStep() -> Int {
        let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        return defaults?.integer(forKey: BubbleConstants.vpnLifecycleReconnectBreakerBackoffStepKey) ?? 0
    }

    private func updateStormModeState(now: Date, timeoutRate: Double) {
        recentUDPCreateTimestamps = recentUDPCreateTimestamps.filter {
            now.timeIntervalSince($0) <= BubbleConstants.udpStormWindowSeconds
        }
        if pendingUDPControlQueue.count > BubbleConstants.udpStormQueueThreshold {
            highQueuedPressureConsecutiveSamples += 1
        } else {
            highQueuedPressureConsecutiveSamples = 0
        }
        let reclaimBlockedDelta = max(0, extensionPressureReclaimBlockedCount - lastObservedReclaimBlockedCount)
        lastObservedReclaimBlockedCount = extensionPressureReclaimBlockedCount

        if !stormModeEnabled {
            if Self.shouldEnterStormMode(
                recentUDPCreateCount: recentUDPCreateTimestamps.count,
                timeoutRate: timeoutRate,
                reclaimBlockedDelta: reclaimBlockedDelta,
                consecutiveQueuePressureSamples: highQueuedPressureConsecutiveSamples
            ) {
                stormModeEnabled = true
                stormModeStableSince = nil
                log.log("TRANSPORT_PROTECTION storm_mode=entered opens=\(recentUDPCreateTimestamps.count) timeout_rate=\(String(format: "%.2f", timeoutRate)) reclaim_blocked_delta=\(reclaimBlockedDelta) queue_samples=\(highQueuedPressureConsecutiveSamples)")
            }
            return
        }

        if activeUDPStreams < BubbleConstants.udpStormRecoveryActiveThreshold &&
            pendingUDPControlQueue.count < BubbleConstants.udpStormRecoveryQueuedThreshold &&
            timeoutRate < BubbleConstants.udpStormRecoveryTimeoutRateThreshold {
            if stormModeStableSince == nil {
                stormModeStableSince = now
            }
        } else {
            stormModeStableSince = nil
        }

        let stableSeconds = stormModeStableSince.map { now.timeIntervalSince($0) } ?? 0
        if Self.shouldExitStormMode(
            activeUDP: activeUDPStreams,
            queuedUDP: pendingUDPControlQueue.count,
            timeoutRate: timeoutRate,
            stableSeconds: stableSeconds
        ) {
            stormModeEnabled = false
            stormModeStableSince = nil
            highQueuedPressureConsecutiveSamples = 0
            log.log("TRANSPORT_PROTECTION storm_mode=exited active_udp=\(activeUDPStreams) queued_udp=\(pendingUDPControlQueue.count) timeout_rate=\(String(format: "%.2f", timeoutRate))")
        }
    }

    private func recordDecoderError(_ error: UDPControlDecoderError, hardFailure: Bool) {
        switch error {
        case .badPrefix:
            udpDecodeBadPrefix += 1
        case .badLength:
            udpDecodeBadLength += 1
            if hardFailure {
                udpDecodeBadLengthHardFail += 1
                recentBadLenHardFailTimestamps.append(Date())
            }
        }
    }

    private struct ResolverHealth {
        var timeoutStreak = 0
        var failoverScore = 0
        var lastSuccessfulResponseAt: Date?
        var lastSuccessAt = Date.distantPast
    }

    private struct TokenBucketState {
        var tokens: Double
        var lastRefillAt: Date
    }

    private enum TransportDegradedState: String {
        case healthy
        case degraded
        case tripped
        case recovering
    }

    private enum TransportPressurePhase: String {
        case normal
        case degraded
        case critical
    }

    static func isMessagingOrControlPreserving(reason: String?, bucket: ContentBucket?, port: UInt16?) -> Bool {
        if port == 53 {
            return true
        }
        if bucket == .messages || bucket == .tiktokControl || bucket == .instagramControl || bucket == .xControl {
            return true
        }
        switch reason {
        case "messages_allow", "tiktok_messages_allow", "instagram_control_allow", "x_control_allow":
            return true
        default:
            return false
        }
    }

    static func isPreservedQueuedTrafficClass(_ trafficClass: TrafficClass) -> Bool {
        trafficClass == .tiktok || trafficClass == .instagram || trafficClass == .x
    }

    static func shouldBypassGraceForStreamUnderPressure(
        criticalPressure: Bool,
        hardeningEnabled: Bool,
        hardeningBucket: ContentBucket?,
        preservesMessagingControl: Bool,
        lastPort: UInt16?
    ) -> Bool {
        guard criticalPressure else { return false }
        guard hardeningEnabled, let hardeningBucket, (hardeningBucket == .tiktokVideo || hardeningBucket == .reels) else {
            return false
        }
        guard !preservesMessagingControl else { return false }
        guard lastPort != 53 else { return false }
        return true
    }

    static func shouldBypassGraceForStartupGuardLowConfidenceReclaim(
        reason: String,
        startupGuardActive: Bool,
        queueDepth: Int,
        trafficClass: TrafficClass,
        lastPort: UInt16?,
        preservesMessagingControl: Bool
    ) -> Bool {
        guard startupGuardActive else { return false }
        guard queueDepth >= BubbleConstants.safeModeMaxQueuedUDPControlStreams else { return false }
        guard reason == "stuck_processing_reclaim" ||
            reason == "global_idle_timeout_reclaim" ||
            reason == "global_max_lifetime_reclaim" else {
            return false
        }
        guard trafficClass == .unknown || trafficClass == .generic else { return false }
        guard !preservesMessagingControl else { return false }
        guard lastPort != 53 else { return false }
        return true
    }

    static func shouldTriggerUDPStartupGuardEscapeHatch(
        startupGuardActive: Bool,
        activeUDPStreams: Int,
        queueDepth: Int,
        trafficClass: TrafficClass,
        lastPort: UInt16?,
        preservesMessagingControl: Bool
    ) -> Bool {
        guard startupGuardActive else { return false }
        guard activeUDPStreams >= BubbleConstants.udpStartupSerialMaxActiveStreams else { return false }
        guard queueDepth >= BubbleConstants.safeModeMaxQueuedUDPControlStreams else { return false }
        guard trafficClass == .unknown || trafficClass == .generic else { return false }
        guard !preservesMessagingControl else { return false }
        guard lastPort != 53 else { return false }
        return true
    }

    static func reclaimPriority(
        criticalPressure: Bool,
        degradedOrCriticalPressure: Bool,
        hardeningEnabled: Bool,
        hardeningBucket: ContentBucket?,
        trafficClass: TrafficClass,
        preservesMessagingControl: Bool,
        lastPort: UInt16?
    ) -> Int {
        if lastPort == 53 {
            if criticalPressure { return 1 }
            if degradedOrCriticalPressure { return 1 }
            return 3
        }
        if preservesMessagingControl {
            return criticalPressure ? 4 : 3
        }
        let hardenedBlocked = hardeningEnabled && (hardeningBucket == .tiktokVideo || hardeningBucket == .reels)
        let lowConfidence = trafficClass == .unknown || trafficClass == .generic
        if criticalPressure {
            if hardenedBlocked { return 0 }
            if lowConfidence { return 1 }
            return 2
        }
        if degradedOrCriticalPressure {
            if lowConfidence { return 0 }
            if hardenedBlocked { return 1 }
            return 2
        }
        if lowConfidence { return 0 }
        if hardenedBlocked { return 1 }
        return 2
    }

    static func shouldCloseDNSOneShot(lastPort: UInt16?, pendingFrameCount: Int, processingFrame: Bool) -> Bool {
        _ = pendingFrameCount
        return lastPort == 53 && !processingFrame
    }

    static func selectiveSafeModeUDPDecision(destinationPort: UInt16) -> SelectiveSafeModeUDPDecision {
        if destinationPort == 53 {
            return .dnsFastLane
        }
        return .reject(reason: selectiveSafeModeUDPRejectReason(destinationPort: destinationPort) ?? "udp_non_dns_rejected_safe_mode")
    }

    static func selectiveSafeModeUDPRejectReason(destinationPort: UInt16) -> String? {
        guard destinationPort != 53 else { return nil }
        return destinationPort == 443 ? "udp_quic_rejected_safe_mode" : "udp_non_dns_rejected_safe_mode"
    }

    static func shouldUseDNSFastLane(mode: UDPForwardingMode, destinationPort: UInt16) -> Bool {
        mode == .selectiveSafeMode && destinationPort == 53
    }

    static func shouldUseGenericUDPRelay(mode: UDPForwardingMode, destinationPort: UInt16) -> Bool {
        _ = destinationPort
        return mode == .nativeForwarding
    }

    static func isValidDNSFastLanePayload(_ payload: Data) -> Bool {
        payload.count >= 12 && payload.count <= BubbleConstants.maxUDPFrameSize
    }

    static func udpControlClosePlan(lastPort: UInt16?, reason: String) -> UDPControlClosePlan {
        let isDNS = lastPort == 53
        let isDNSResponse = isDNS && reason == "dns_response_one_shot_retire"
        let isDNSTimeoutOrMalformed = isDNS &&
            (reason == "dns_timeout_one_shot_retire" || reason == "dns_malformed_one_shot_retire")
        let isDNSStartupDrainRetire = isDNS && reason.hasPrefix("dns_startup_drain_")
        return UDPControlClosePlan(
            phase: .retiring,
            sendWithConnectionCompletion: isDNSResponse,
            discardTrailingFrames: isDNSResponse || isDNSTimeoutOrMalformed || isDNSStartupDrainRetire,
            cancelDelaySeconds: isDNSResponse
                ? BubbleConstants.udpDNSResponseCancelWatchdogDelaySeconds
                : ((isDNSTimeoutOrMalformed || isDNSStartupDrainRetire) ? BubbleConstants.udpDNSDeferredCancelDelaySeconds : 0),
            deferDrainUntilCancel: true,
            cancelAsWatchdog: isDNSResponse
        )
    }

    static func dnsFrameDiscardPlan(
        pendingFrameCount: Int,
        recoveredFramesPending: Int,
        processingRecoveredDNSFrame: Bool
    ) -> DNSFrameDiscardPlan {
        let recoveredDiscarded = min(max(0, recoveredFramesPending), max(0, pendingFrameCount))
        return DNSFrameDiscardPlan(
            trailingDiscarded: max(0, pendingFrameCount),
            recoveredDiscarded: recoveredDiscarded,
            recoveredOneShotClose: processingRecoveredDNSFrame || recoveredDiscarded > 0
        )
    }

    static func shouldBypassGraceForDNSClose(
        lastPort: UInt16?,
        reason: String,
        startupGuardActive: Bool = false,
        crashGuardActive: Bool = false
    ) -> Bool {
        guard lastPort == 53 else { return false }
        if reason == "dns_response_one_shot_retire", startupGuardActive || crashGuardActive {
            return false
        }
        return reason == "dns_response_one_shot_retire" ||
            reason == "dns_timeout_one_shot_retire" ||
            reason == "dns_malformed_one_shot_retire" ||
            reason == "control_stream_completed"
    }

    static func shouldUseDNSStartupDrain(
        stabilityFirstModeEnabled: Bool,
        startupDrainWindowActive: Bool,
        startupGraceActive: Bool,
        startupGuardActive: Bool,
        crashGuardActive: Bool,
        lastPort: UInt16?,
        reason: String,
        dnsFastLane: Bool = false
    ) -> Bool {
        guard !dnsFastLane else { return false }
        guard stabilityFirstModeEnabled else { return false }
        guard startupDrainWindowActive else { return false }
        guard lastPort == 53, reason == "dns_response_one_shot_retire" else { return false }
        return startupGraceActive || startupGuardActive || crashGuardActive
    }

    static func shouldActivateUDPStartupCrashGuard(
        previousStopCause: String,
        lastProviderPhase: String,
        lastDecoderEventJSON: String
    ) -> Bool {
        guard previousStopCause == "status_drop_without_stop_callback" else { return false }
        let guardedPhases: Set<String> = [
            "udp_accept",
            "dns_response_send",
            "dns_fast_lane_response_send_start",
            "dns_fast_lane_response_sent",
            "dns_fast_lane_close",
            "dns_one_shot_close",
            "dns_startup_drain_close",
            "decoder_recovery",
        ]
        return guardedPhases.contains(lastProviderPhase) || !lastDecoderEventJSON.isEmpty
    }

    static func udpStartupCrashGuardReason(
        previousStopCause: String,
        lastProviderPhase: String,
        lastDecoderEventJSON: String
    ) -> String {
        guard previousStopCause == "status_drop_without_stop_callback" else { return "" }
        if lastProviderPhase == "dns_one_shot_close" ||
            lastProviderPhase == "dns_startup_drain_close" ||
            lastProviderPhase == "dns_response_send" ||
            lastProviderPhase == "dns_fast_lane_response_send_start" ||
            lastProviderPhase == "dns_fast_lane_response_sent" ||
            lastProviderPhase == "dns_fast_lane_close" {
            return "prior_dns_udp_close_falloff"
        }
        if lastProviderPhase == "decoder_recovery" || !lastDecoderEventJSON.isEmpty {
            return "prior_decoder_recovery_falloff"
        }
        if lastProviderPhase == "udp_accept" {
            return "prior_udp_accept_falloff"
        }
        return "prior_udp_startup_falloff"
    }

    static func classifyLifecycleFalloff(
        finalCause: String,
        providerLastPhase: String,
        tun2socksExitObserved: Bool,
        lastDecoderEventJSON: String,
        lastHeartbeatSnapshotJSON: String = ""
    ) -> String {
        _ = lastDecoderEventJSON
        if finalCause == "tun2socks_exit" || tun2socksExitObserved {
            return "tun2socks_native_exit"
        }
        guard finalCause == "status_drop_without_stop_callback" else {
            return finalCause.isEmpty ? "unknown" : finalCause
        }
        let heartbeatFields = providerHeartbeatSnapshotFields(lastHeartbeatSnapshotJSON)
        let snapshotPhaseField = heartbeatFields["provider_phase"] ?? "unknown"
        let snapshotPhase = snapshotPhaseField == "unknown" ? providerLastPhase : snapshotPhaseField
        let queueDepth = heartbeatFields["queued_udp"].flatMap(Int.init) ?? -1
        let lastUDPClosePhase = heartbeatFields["last_udp_close_phase"] ?? ""
        if queueDepth >= BubbleConstants.safeModeMaxQueuedUDPControlStreams &&
            lastUDPClosePhase == UDPControlClosePhase.graceBlocked.rawValue {
            return "suspected_udp_startup_guard_saturation"
        }
        let dnsChurnPhases: Set<String> = [
            "dns_one_shot_close",
            "dns_startup_drain_close",
            "dns_response_send",
            "dns_fast_lane_response_send_start",
            "dns_fast_lane_response_sent",
            "dns_fast_lane_close",
            "decoder_recovery",
        ]
        if dnsChurnPhases.contains(snapshotPhase) || dnsChurnPhases.contains(providerLastPhase) {
            return "suspected_ios_watchdog_or_external_kill_after_udp_dns_churn"
        }
        return "suspected_provider_silent_exit"
    }

    static func providerHeartbeatSnapshotFields(_ raw: String) -> [String: String] {
        let snapshot = decodeJSONObject(raw)
        let pathState = snapshot["path_state"] as? [String: Any] ?? [:]
        return [
            "provider_phase": stringValue(from: snapshot["provider_phase"], fallback: "unknown"),
            "startup_stability_phase": stringValue(from: snapshot["startup_stability_phase"], fallback: "unknown"),
            "startup_probe_completed": stringValue(from: snapshot["startup_probe_completed"], fallback: "false"),
            "proxy_ready": stringValue(from: snapshot["proxy_ready"], fallback: "false"),
            "memory_mb": stringValue(from: snapshot["memory_mb"], fallback: "unknown"),
            "tun2socks_up_packets": stringValue(from: snapshot["tun2socks_up_packets"], fallback: "unknown"),
            "tun2socks_down_packets": stringValue(from: snapshot["tun2socks_down_packets"], fallback: "unknown"),
            "active_udp": stringValue(from: snapshot["active_udp"], fallback: "unknown"),
            "queued_udp": stringValue(from: snapshot["queued_udp"], fallback: "unknown"),
            "last_udp_close_phase": stringValue(from: snapshot["last_udp_close_phase"], fallback: "unknown"),
            "dns_startup_drain_active": stringValue(from: snapshot["dns_startup_drain_active"], fallback: "false"),
            "dns_startup_drain_closes": stringValue(from: snapshot["dns_startup_drain_closes"], fallback: "0"),
            "dns_startup_drain_frames_processed": stringValue(from: snapshot["dns_startup_drain_frames_processed"], fallback: "0"),
            "dns_fast_lane_requests": stringValue(from: snapshot["dns_fast_lane_requests"], fallback: "0"),
            "dns_fast_lane_responses": stringValue(from: snapshot["dns_fast_lane_responses"], fallback: "0"),
            "dns_fast_lane_failures": stringValue(from: snapshot["dns_fast_lane_failures"], fallback: "0"),
            "dns_fast_lane_parse_failed": stringValue(from: snapshot["dns_fast_lane_parse_failed"], fallback: "0"),
            "dns_fast_lane_close": stringValue(from: snapshot["dns_fast_lane_close"], fallback: "0"),
            "dns_fast_lane_disabled": stringValue(from: snapshot["dns_fast_lane_disabled"], fallback: "false"),
            "dns_fast_lane_disabled_reason": stringValue(from: snapshot["dns_fast_lane_disabled_reason"], fallback: ""),
            "udp_non_dns_rejects": stringValue(from: snapshot["udp_non_dns_rejects"], fallback: "0"),
            "udp_quic_rejects": stringValue(from: snapshot["udp_quic_rejects"], fallback: "0"),
            "early_reconnect_suppressed": stringValue(from: snapshot["early_reconnect_suppressed"], fallback: "false"),
            "ios_safe_mode_reason": stringValue(from: snapshot["ios_safe_mode_reason"], fallback: ""),
            "last_decoder_event": jsonString(from: snapshot["last_decoder_event"], fallback: "{}"),
            "last_dns_close": jsonString(from: snapshot["last_dns_close"], fallback: "{}"),
            "app_lifecycle": stringValue(from: snapshot["app_lifecycle"], fallback: "unknown"),
            "path_status": stringValue(from: pathState["status"], fallback: "unknown"),
            "path_unsatisfied_reason": stringValue(from: pathState["unsatisfied_reason"], fallback: "unknown"),
        ]
    }

    static func drainActiveLimitDuringStartupGuard(
        startupGuardActive: Bool,
        stormMode: Bool,
        safeMode: Bool
    ) -> Int {
        if startupGuardActive {
            return BubbleConstants.udpStartupSerialMaxActiveStreams
        }
        return effectiveMaxActiveUDPStreams(stormMode: stormMode, safeMode: safeMode)
    }

    static func resolveStabilityFirstMode(storedValue: Bool?) -> Bool {
        storedValue ?? true
    }

    static func startupGraceAdjustedUDPLimits(
        trafficClass: TrafficClass,
        maxActive: Int,
        maxQueued: Int,
        globalMaxActive: Int,
        globalMaxQueued: Int,
        graceActive: Bool,
        safeMode: Bool = false
    ) -> (maxActive: Int, maxQueued: Int) {
        if safeMode {
            return (
                max(1, min(maxActive, BubbleConstants.safeModeMaxActiveUDPControlStreams)),
                max(0, min(maxQueued, BubbleConstants.safeModeMaxQueuedUDPControlStreams))
            )
        }
        guard graceActive, trafficClass == .unknown || trafficClass == .generic else {
            return (maxActive, maxQueued)
        }
        return (
            min(globalMaxActive, max(maxActive, BubbleConstants.startupGraceUnknownGenericMinActiveUDP)),
            min(globalMaxQueued, max(maxQueued, BubbleConstants.startupGraceUnknownGenericMinQueuedUDP))
        )
    }

    static func startupGraceAdjustedUDPCreateRateCapacity(
        trafficClass: TrafficClass,
        createRateCapacity: Int,
        globalCreateRateCapacity: Int,
        graceActive: Bool,
        safeMode: Bool = false
    ) -> Int {
        if safeMode {
            return max(1, min(createRateCapacity, BubbleConstants.safeModeUDPAdmissionCreateRateCapacity))
        }
        guard graceActive, trafficClass == .unknown || trafficClass == .generic else {
            return createRateCapacity
        }
        return min(globalCreateRateCapacity, max(createRateCapacity, BubbleConstants.startupGraceUnknownGenericMinActiveUDP))
    }

    static func pressureReclaimBatchSize(
        activeUDP: Int,
        candidateCount: Int,
        pressureLevel: ExtensionPressureLevel,
        stormMode: Bool
    ) -> Int {
        guard candidateCount > 0 else { return 0 }
        let maxPerSweep = stormMode ? BubbleConstants.udpStormSelectiveReclaimMaxPerSweep : BubbleConstants.selectiveReclaimMaxPerSweep
        let emergencyBatch = BubbleConstants.udpEmergencyReclaimBatchSize + (stormMode ? 2 : 0)
        guard pressureLevel.rank >= ExtensionPressureLevel.hard.rank else {
            return min(candidateCount, min(maxPerSweep, emergencyBatch))
        }
        let target = pressureLevel == .critical
            ? BubbleConstants.extensionPressureCriticalTargetActiveUDP
            : BubbleConstants.extensionPressureHardTargetActiveUDP
        let overTarget = max(1, activeUDP - target)
        return min(candidateCount, max(maxPerSweep, max(emergencyBatch, overTarget)))
    }

    static func shouldRetireBlockedStormStream(
        blockedDecisionCount: Int,
        secondsSinceLastSuccess: TimeInterval?,
        noProgressSeconds: TimeInterval,
        degradedOrCriticalPressure: Bool,
        stormMode: Bool,
        hardeningEnabled: Bool,
        hardeningBucket: ContentBucket?,
        preservesMessagingControl: Bool
    ) -> Bool {
        guard degradedOrCriticalPressure || stormMode else { return false }
        guard hardeningEnabled, let hardeningBucket, (hardeningBucket == .tiktokVideo || hardeningBucket == .reels) else {
            return false
        }
        guard !preservesMessagingControl else { return false }
        if blockedDecisionCount < BubbleConstants.blockedStormRetireThreshold {
            return false
        }
        if let secondsSinceLastSuccess, secondsSinceLastSuccess <= BubbleConstants.blockedStormRetireNoProgressSeconds {
            return false
        }
        return noProgressSeconds >= BubbleConstants.blockedStormRetireNoProgressSeconds
    }

    static func shouldTripFromSevereSignals(
        severeSaturation: Bool,
        severeTimeoutStorm: Bool,
        severeBadLenStorm: Bool,
        severeReclaims: Bool
    ) -> Bool {
        let severeDecodeAndNetwork = severeBadLenStorm && (severeTimeoutStorm || severeSaturation)
        let severeReclaimAndStress = severeReclaims && (severeTimeoutStorm || severeSaturation || severeBadLenStorm)
        return severeDecodeAndNetwork || severeReclaimAndStress
    }

    static func shouldInferCrashFromLifecycle(stopSource: String, runningMarker: Bool, heartbeatAgeSeconds: TimeInterval, staleThresholdSeconds: TimeInterval) -> Bool {
        if stopSource == "stopTunnel" || stopSource == "tun2socks_exit" || stopSource == "cancelTunnelWithError" || stopSource == "inferred_crash" {
            return false
        }
        return runningMarker && heartbeatAgeSeconds >= staleThresholdSeconds
    }

    static func shouldBypassGraceForExtensionPressure(reason: String, pressureLevel: ExtensionPressureLevel) -> Bool {
        reason == "extension_pressure" && pressureLevel == .critical
    }

    private static func decodeJSONObject(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return parsed
    }

    private static func stringValue(from value: Any?, fallback: String) -> String {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(Int(double))
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return fallback
    }

    private static func jsonString(from value: Any?, fallback: String) -> String {
        guard let value else { return fallback }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return json
    }

    static func shouldEnterStormMode(
        recentUDPCreateCount: Int,
        timeoutRate: Double,
        reclaimBlockedDelta: Int,
        consecutiveQueuePressureSamples: Int
    ) -> Bool {
        var signals = 0
        if recentUDPCreateCount > BubbleConstants.udpStormOpenCountThreshold {
            signals += 1
        }
        if timeoutRate > BubbleConstants.udpStormTimeoutRateThreshold {
            signals += 1
        }
        if reclaimBlockedDelta > 0 {
            signals += 1
        }
        if consecutiveQueuePressureSamples >= BubbleConstants.udpStormQueueConsecutiveSamples {
            signals += 1
        }
        return signals >= 2
    }

    static func shouldExitStormMode(activeUDP: Int, queuedUDP: Int, timeoutRate: Double, stableSeconds: TimeInterval) -> Bool {
        stableSeconds >= BubbleConstants.udpStormExitStabilizationSeconds &&
            activeUDP < BubbleConstants.udpStormRecoveryActiveThreshold &&
            queuedUDP < BubbleConstants.udpStormRecoveryQueuedThreshold &&
            timeoutRate < BubbleConstants.udpStormRecoveryTimeoutRateThreshold
    }

    static func effectiveActiveLimit(baseLimit: Int, reservedSlots: Int, stormMode: Bool) -> Int {
        guard stormMode else { return baseLimit }
        return max(1, baseLimit - reservedSlots)
    }

    static func shouldForceGlobalUDPReject(active: Int, queued: Int, maxActive: Int, maxQueued: Int) -> Bool {
        active >= maxActive && queued >= maxQueued
    }

    static func shouldEarlyBlockFromSNIDecision(_ decision: PolicyDecision) -> Bool {
        guard decision.action == .blockNow else { return false }
        if decision.reason == "tiktok_video_block_now" ||
            decision.reason == "tiktok_ip_hint_block_now" {
            return decision.classification.bucket == .tiktokVideo && decision.trafficClass == .tiktok
        }
        if decision.reason == "reels_media_block_now" ||
            decision.reason == "reels_media_hint_block_now" ||
            decision.reason == "reels_strict_media_block_now" {
            return decision.classification.bucket == .reels && decision.trafficClass == .instagram
        }
        if decision.reason == "x_feed_media_block_now" {
            return decision.classification.bucket == .xFeedMedia && decision.trafficClass == .x
        }
        if decision.reason == "x_strict_feed_api_block_now" {
            return decision.classification.bucket == .xFeedAPI && decision.trafficClass == .x
        }
        return false
    }

    static func admissionTrafficClass(for classified: ClassifiedFlow) -> TrafficClass {
        if classified.trafficClass == .generic {
            return .generic
        }
        if classified.confidence < BubbleConstants.classifyConfidenceLow || classified.trafficClass == .unknown {
            return .unknown
        }
        return classified.trafficClass
    }

#if DEBUG
    static func testParseDNSAddressAnswers(_ data: Data) -> [(domain: String, ip: String, ttl: UInt32)] {
        parseDNSMessage(data)?.addressAnswers.map { ($0.domain, $0.ip, $0.ttl) } ?? []
    }

    func testRecordTCPSNIBlockForProtectionOnly(sni: String, port: UInt16, decision: PolicyDecision) -> String {
        let gate = applyTCPSNIBlockProtection(sni: sni, port: port, decision: decision)
        if gate == .allow {
            tcpEarlySNIBlocks += 1
            statsBlocked += 1
        }
        switch gate {
        case .allow:
            return "allow"
        case .failOpen:
            return "fail_open"
        case .suppress:
            return "suppress"
        case .dropFast:
            return "drop_fast"
        case .rejectNewStream:
            return "reject_new_stream"
        }
    }

    func testRecordBlockedStreamObservation(host: String, sni: String?, port: UInt16, decision: PolicyDecision, bytesDown: Int, now: Date = Date()) {
        queue.sync {
            (filter as? StreamObservationRecorder)?.recordBlockedStream(
                host: host,
                sni: sni,
                port: port,
                decision: decision,
                bytesDown: bytesDown,
                now: now
            )
        }
    }

    func testSeedTikTokIPHint(ip: String, port: UInt16 = 443, domain: String? = "v16.tiktokcdn-us.com", source: String = "dns", ttl: TimeInterval = BubbleConstants.tiktokIPHintTTLSeconds, now: Date = Date()) {
        queue.sync {
            recordTikTokIPHint(
                ip: ip,
                port: port,
                domain: domain,
                source: source,
                ttl: ttl,
                confidence: source == "retry_burst" ? 0.66 : 0.90,
                now: now
            )
        }
    }

    func testRecordTikTokSNIHint(ip: String, port: UInt16 = 443, sni: String, now: Date = Date()) {
        queue.sync {
            let decision = filter.evaluateStream(
                host: ip,
                sni: sni,
                port: port,
                bytesDown: 0,
                connectionAge: 0,
                parallelConnections: 0
            )
            recordTikTokIPHintFromSNI(ip: ip, port: port, sni: sni, decision: decision, now: now)
        }
    }

    func testRecordTikTokVideoBlockEvent(now: Date = Date()) {
        queue.sync {
            recordTikTokVideoBlockEventIfNeeded(protectedTikTokVideoDecisionForTest(), now: now)
        }
    }

    func testEvaluateTCPAdmissionDecision(host: String, port: UInt16 = 443, now: Date = Date()) -> (action: String, reason: String) {
        queue.sync {
            let initial = filter.evaluateConnection(host: host, port: port)
            let decision = evaluateTikTokDirectIPDecision(host: host, port: port, initialDecision: initial, now: now) ?? initial
            return (decision.action.rawValue, decision.reason)
        }
    }

    func testEvaluateTCPAdmissionProtection(host: String, port: UInt16 = 443, now: Date = Date()) -> (action: String, reason: String, gate: String) {
        queue.sync {
            let initial = filter.evaluateConnection(host: host, port: port)
            let decision = evaluateTikTokDirectIPDecision(host: host, port: port, initialDecision: initial, now: now) ?? initial
            let gate = evaluateProtectionGate(host: host, port: port, decision: decision, transport: "tcp", stage: .admission)
            return (decision.action.rawValue, decision.reason, Self.testGateName(gate))
        }
    }

    func testTikTokIPHintCounterSnapshot(now: Date = Date()) -> TikTokIPHintCounterSnapshot {
        queue.sync {
            tiktokIPHintCounterSnapshot(now: now)
        }
    }

    private func protectedTikTokVideoDecisionForTest() -> PolicyDecision {
        PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(bucket: .tiktokVideo, confidence: 0.99, reasons: ["test_tiktok_video_block"]),
            reason: "tiktok_video_block_now",
            toggleSnapshot: ["video_block": true],
            policyVersion: 1,
            intendedAction: nil,
            appStrategy: AppTransportStrategy.hardenedVideo.rawValue,
            trafficClass: .tiktok
        )
    }

    private static func testGateName(_ gate: ProtectionGateResult) -> String {
        switch gate {
        case .allow:
            return "allow"
        case .failOpen:
            return "fail_open"
        case .suppress:
            return "suppress"
        case .dropFast:
            return "drop_fast"
        case .rejectNewStream:
            return "reject_new_stream"
        }
    }

    func testProtectionCounterSnapshot() -> (
        statsBlocked: Int,
        tcpEarlySNIBlocks: Int,
        blockedSuppressedTCP: Int,
        tcpSNIBlockSuppressed: Int,
        tcpSNIBlockTokenDrops: Int,
        protectedBlockSuppressionKeys: Int
    ) {
        (
            statsBlocked: statsBlocked,
            tcpEarlySNIBlocks: tcpEarlySNIBlocks,
            blockedSuppressedTCP: blockedSuppressedTCP,
            tcpSNIBlockSuppressed: tcpSNIBlockSuppressed,
            tcpSNIBlockTokenDrops: tcpSNIBlockTokenDrops,
            protectedBlockSuppressionKeys: blockedSuppression.count
        )
    }

    func testRecordTikTokDNSHints(response: Data, now: Date = Date()) {
        queue.sync {
            recordDNSHints(from: response, now: now)
        }
    }

    func testRecordInstagramDNSHints(response: Data, now: Date = Date()) {
        queue.sync {
            recordDNSHints(from: response, now: now)
        }
    }

    func testSeedDNSHint(ip: String, domain: String, expiresAt: Date, bucket: ContentBucket = .tiktokVideo) {
        queue.sync {
            dnsHintsByIP[ip.lowercased()] = DNSIPHint(
                domain: domain,
                bucket: bucket,
                expiresAt: expiresAt,
                addedAt: Date()
            )
        }
    }

    func testEvaluateUDPPolicy(
        host: String,
        port: UInt16,
        payloadBytes: Int = 0,
        selectiveSafeMode: Bool = false,
        now: Date = Date()
    ) -> (action: String, reason: String, source: String?, knownBadCacheHit: Bool, cacheExpiresAt: Date?) {
        queue.sync {
            let result = evaluateUDPPolicy(
                host: host,
                port: port,
                payloadBytes: payloadBytes,
                selectiveSafeMode: selectiveSafeMode,
                now: now
            )
            return (
                result.decision.action.rawValue,
                result.decision.reason,
                result.source,
                result.knownBadCacheHit,
                result.cacheExpiresAt
            )
        }
    }

    func testSeedKnownBadUDPCache(host: String, port: UInt16, decision: PolicyDecision, expiresAt: Date, now: Date = Date()) {
        queue.sync {
            cacheKnownBadUDP(host: host, port: port, decision: decision, expiresAt: expiresAt, now: now)
        }
    }

    func testKnownBadUDPCacheHitCount() -> Int {
        queue.sync { safeModeKnownBadUDPCacheHits }
    }

    func testDNSHintCounterSnapshot() -> (
        added: Int,
        expired: Int,
        active: Int,
        udpBlocks: Int,
        instagramAdded: Int,
        instagramExpired: Int,
        instagramActive: Int,
        instagramUDPBlocks: Int
    ) {
        queue.sync {
            (
                added: tiktokDNSHintsAdded,
                expired: tiktokDNSHintsExpired,
                active: activeDNSHintCount(bucket: .tiktokVideo),
                udpBlocks: tiktokUDPBlocksFromDNSHints,
                instagramAdded: instagramDNSHintsAdded,
                instagramExpired: instagramDNSHintsExpired,
                instagramActive: activeDNSHintCount(bucket: .reels),
                instagramUDPBlocks: instagramUDPBlocksFromDNSHints
            )
        }
    }

    func testProductionSnapshotAccessFromInternalQueue(timeout: TimeInterval = 1.0) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            _ = self.currentActiveUDPStreams
            _ = self.currentQueuedUDPStreams
            _ = self.currentPressureSnapshot
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }

    func testStopFromInternalQueueCompletes(timeout: TimeInterval = 1.0) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            self?.stop()
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
#endif

    static func isTargetTrafficClass(_ trafficClass: TrafficClass) -> Bool {
        trafficClass == .tiktok || trafficClass == .instagram || trafficClass == .x
    }

    private struct AppClassConfig {
        let maxActive: Int
        let maxQueued: Int
        let createRatePerSecond: Double
        let createRateCapacity: Int
    }

    private struct ClassTransportState {
        var activeUDP = 0
        var queuedUDP = 0
        var forcedRejects = 0
        var tokenDrops = 0
        var timeouts = 0
        var reclaims = 0
    }

    private func classConfig(for trafficClass: TrafficClass) -> AppClassConfig {
        switch trafficClass {
        case .generic:
            return AppClassConfig(
                maxActive: max(4, BubbleConstants.maxActiveUDPControlStreams - BubbleConstants.genericReservedUDPActiveSlots),
                maxQueued: max(4, BubbleConstants.maxQueuedUDPControlStreams - BubbleConstants.genericReservedUDPQueueSlots),
                createRatePerSecond: BubbleConstants.udpAdmissionCreateRatePerSecond,
                createRateCapacity: BubbleConstants.udpAdmissionCreateRateCapacity
            )
        case .unknown:
            return AppClassConfig(
                maxActive: max(2, min(4, BubbleConstants.maxActiveUDPControlStreams / 4)),
                maxQueued: 4,
                createRatePerSecond: max(2.0, BubbleConstants.udpAdmissionCreateRatePerSecond * 0.25),
                createRateCapacity: max(2, BubbleConstants.udpAdmissionCreateRateCapacity / 4)
            )
        case .tiktok:
            return AppClassConfig(
                maxActive: max(2, BubbleConstants.maxActiveUDPControlStreams / 2),
                maxQueued: max(2, BubbleConstants.maxQueuedUDPControlStreams / 2),
                createRatePerSecond: BubbleConstants.udpAdmissionCreateRatePerSecond * 0.5,
                createRateCapacity: max(2, BubbleConstants.udpAdmissionCreateRateCapacity / 2)
            )
        case .instagram, .x:
            return AppClassConfig(
                maxActive: max(2, BubbleConstants.maxActiveUDPControlStreams / 2),
                maxQueued: max(2, BubbleConstants.maxQueuedUDPControlStreams / 2),
                createRatePerSecond: BubbleConstants.udpAdmissionCreateRatePerSecond * 0.8,
                createRateCapacity: max(2, BubbleConstants.udpAdmissionCreateRateCapacity / 2)
            )
        }
    }

    private func classState(for trafficClass: TrafficClass) -> ClassTransportState {
        classTransportStateByClass[trafficClass] ?? ClassTransportState()
    }

    private func setClassState(_ state: ClassTransportState, for trafficClass: TrafficClass) {
        classTransportStateByClass[trafficClass] = state
    }

    private func countActiveUDPStreams(for trafficClass: TrafficClass) -> Int {
        udpStreamsByID.values.filter { !$0.closed && $0.trafficClass == trafficClass }.count
    }

    private func countQueuedUDPStreams(for trafficClass: TrafficClass) -> Int {
        pendingUDPControlQueue.filter { $0.trafficClass == trafficClass }.count
    }

    private func queuedUDPControlP95AgeMs(now: Date = Date()) -> Int {
        guard !pendingUDPControlQueue.isEmpty else { return 0 }
        let ages = pendingUDPControlQueue
            .map { max(0, now.timeIntervalSince($0.enqueuedAt) * 1000.0) }
            .sorted()
        let idx = min(ages.count - 1, Int(Double(ages.count - 1) * 0.95))
        return Int(ages[idx])
    }

    private func udpSocketReuseHitRate() -> Double {
        let total = udpSocketReuseHits + udpSocketReuseMisses
        guard total > 0 else { return 0 }
        return Double(udpSocketReuseHits) / Double(total)
    }

    private struct PendingUDPControl {
        let client: NWConnection
        let id: Int
        let enqueuedAt: Date
        var trafficClass: TrafficClass
        let preserveDuringPressure: Bool
        let lowConfidence: Bool
        let initialBytes: Data
        let requestHadTail: Bool
    }

    private final class UDPAdmissionController {
        private var rejectUntil = Date.distantPast
        private var createTokens = Double(BubbleConstants.udpAdmissionCreateRateCapacity)
        private var lastRefillAt = Date.distantPast

        func decide(
            active: Int,
            queued: Int,
            stormMode: Bool,
            maxActive: Int,
            maxQueued: Int,
            createRatePerSecond: Double,
            createRateCapacity: Int,
            pressurePhase: TransportPressurePhase,
            preferQueueing: Bool,
            graceActive: Bool,
            now: Date
        ) -> UDPAdmissionDecision {
            refillTokens(
                now: now,
                stormMode: stormMode,
                createRatePerSecond: createRatePerSecond,
                createRateCapacity: createRateCapacity
            )
            if now < rejectUntil {
                return .reject(reason: "cooldown")
            }
            if stormMode && pressurePhase != .normal && !preferQueueing && queued > 0 {
                return .reject(reason: "storm_mode_low_confidence_reject")
            }
            if createTokens < 1 {
                if preferQueueing && queued < maxQueued {
                    return .queue
                }
                return .reject(reason: "rate_limited")
            }
            if active >= maxActive && queued >= maxQueued {
                if graceActive || preferQueueing {
                    return .queue
                }
                rejectUntil = now.addingTimeInterval(1.5)
                return .reject(reason: "hard_saturation")
            }
            if active >= maxActive {
                return .queue
            }
            if pressurePhase == .critical && queued >= maxQueued {
                return .reject(reason: "critical_backpressure")
            }
            if pressurePhase == .degraded && queued >= max(1, maxQueued - 1) {
                return .queue
            }
            if queued > (maxQueued / 2) && active >= (maxActive - 1) {
                if preferQueueing {
                    return .queue
                }
                return .reject(reason: "preemptive_backpressure")
            }
            createTokens -= 1
            return .accept
        }

        private func refillTokens(now: Date, stormMode: Bool, createRatePerSecond: Double, createRateCapacity: Int) {
            if lastRefillAt == .distantPast {
                lastRefillAt = now
                createTokens = min(createTokens, Double(createRateCapacity))
                return
            }
            let elapsed = max(0, now.timeIntervalSince(lastRefillAt))
            let refillRate = stormMode ? (createRatePerSecond * 0.4) : createRatePerSecond
            let refill = elapsed * refillRate
            createTokens = min(Double(createRateCapacity), createTokens + refill)
            lastRefillAt = now
        }
    }

    private struct InflightDNSRequest {
        let startedAt: Date
        var callbacks: [(Data?) -> Void]
    }

    private static func parseDNSMessage(_ data: Data) -> DNSMessageSummary? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }
        let questionCount = Int(readUInt16(bytes, offset: 4))
        let answerCount = Int(readUInt16(bytes, offset: 6))
        var offset = 12
        var questions: [String] = []

        for _ in 0..<questionCount {
            guard let parsed = readDNSName(bytes, offset: offset) else { return nil }
            questions.append(parsed.name.lowercased())
            offset = parsed.nextOffset
            guard offset + 4 <= bytes.count else { return nil }
            offset += 4
        }

        var answers: [DNSAddressAnswer] = []
        for _ in 0..<answerCount {
            guard let parsed = readDNSName(bytes, offset: offset) else { return nil }
            let domain = parsed.name.lowercased()
            offset = parsed.nextOffset
            guard offset + 10 <= bytes.count else { return nil }
            let type = readUInt16(bytes, offset: offset)
            let ttl = readUInt32(bytes, offset: offset + 4)
            let dataLength = Int(readUInt16(bytes, offset: offset + 8))
            offset += 10
            guard offset + dataLength <= bytes.count else { return nil }

            if type == 1, dataLength == 4 {
                let ip = "\(bytes[offset]).\(bytes[offset + 1]).\(bytes[offset + 2]).\(bytes[offset + 3])"
                answers.append(DNSAddressAnswer(domain: domain, ip: ip, ttl: ttl))
            } else if type == 28, dataLength == 16 {
                let parts = (0..<8).map { i in
                    String(format: "%02x%02x", bytes[offset + i * 2], bytes[offset + i * 2 + 1])
                }
                answers.append(DNSAddressAnswer(domain: domain, ip: parts.joined(separator: ":"), ttl: ttl))
            }
            offset += dataLength
        }

        return DNSMessageSummary(questions: questions, addressAnswers: answers)
    }

    private static func readDNSName(_ bytes: [UInt8], offset: Int, depth: Int = 0) -> (name: String, nextOffset: Int)? {
        guard depth < 8, offset < bytes.count else { return nil }
        var labels: [String] = []
        var cursor = offset
        var nextOffset = offset
        var jumped = false

        while cursor < bytes.count {
            let length = Int(bytes[cursor])
            if length == 0 {
                if !jumped {
                    nextOffset = cursor + 1
                }
                return (labels.joined(separator: "."), nextOffset)
            }
            if (length & 0xC0) == 0xC0 {
                guard cursor + 1 < bytes.count else { return nil }
                let pointer = ((length & 0x3F) << 8) | Int(bytes[cursor + 1])
                if !jumped {
                    nextOffset = cursor + 2
                    jumped = true
                }
                guard let pointed = readDNSName(bytes, offset: pointer, depth: depth + 1) else { return nil }
                if !pointed.name.isEmpty {
                    labels.append(pointed.name)
                }
                return (labels.joined(separator: "."), nextOffset)
            }
            guard (length & 0xC0) == 0, length <= 63 else { return nil }
            let labelStart = cursor + 1
            let labelEnd = labelStart + length
            guard labelEnd <= bytes.count else { return nil }
            guard let label = String(bytes: Array(bytes[labelStart..<labelEnd]), encoding: .utf8) else { return nil }
            labels.append(label)
            cursor = labelEnd
            if !jumped {
                nextOffset = cursor
            }
        }

        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) |
            (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) |
            UInt32(bytes[offset + 3])
    }

    private func dnsDedupKey(host: String, port: UInt16, payload: Data) -> String? {
        guard port == 53 else { return nil }
        return "\(host):\(port):\(payload.hashValue)"
    }

    private func effectiveResolverHost(originalHost: String, port: UInt16) -> String {
        guard port == 53, originalHost == "8.8.8.8" || originalHost == "1.1.1.1" else {
            return originalHost
        }
        let googleScore = resolverHealth["8.8.8.8"]?.failoverScore ?? 0
        let cloudflareScore = resolverHealth["1.1.1.1"]?.failoverScore ?? 0
        if googleScore >= BubbleConstants.dnsFailoverScoreThreshold, cloudflareScore < googleScore {
            return "1.1.1.1"
        }
        if cloudflareScore >= BubbleConstants.dnsFailoverScoreThreshold, googleScore < cloudflareScore {
            return "8.8.8.8"
        }
        let preferred = preferredResolverHost()
        return preferred ?? originalHost
    }

    private func preferredResolverHost() -> String? {
        let google = resolverHealth["8.8.8.8"] ?? ResolverHealth()
        let cloudflare = resolverHealth["1.1.1.1"] ?? ResolverHealth()
        let now = Date()
        let selected: String
        if google.failoverScore >= BubbleConstants.dnsFailoverScoreThreshold, cloudflare.failoverScore < google.failoverScore {
            selected = "1.1.1.1"
        } else if cloudflare.failoverScore >= BubbleConstants.dnsFailoverScoreThreshold, google.failoverScore < cloudflare.failoverScore {
            selected = "8.8.8.8"
        } else {
            selected = google.lastSuccessAt >= cloudflare.lastSuccessAt ? "8.8.8.8" : "1.1.1.1"
        }
        let isReturnToPreviousHealthy = selected != currentPreferredResolver &&
            (resolverHealth[selected]?.failoverScore ?? 0) == 0
        let minSwitchDelay = isReturnToPreviousHealthy
            ? max(BubbleConstants.resolverSwitchCooldown, BubbleConstants.dnsFailoverReturnDelaySeconds)
            : BubbleConstants.resolverSwitchCooldown
        if selected != currentPreferredResolver, now.timeIntervalSince(lastResolverSwitchAt) >= minSwitchDelay {
            currentPreferredResolver = selected
            lastResolverSwitchAt = now
            resolverSwitchCount += 1
        }
        return currentPreferredResolver
    }

    private func markResolverSuccess(host: String, port: UInt16) {
        guard port == 53 else { return }
        var health = resolverHealth[host] ?? ResolverHealth()
        health.timeoutStreak = 0
        health.failoverScore = max(0, health.failoverScore - BubbleConstants.dnsFailoverScoreDecayPerSuccess)
        health.lastSuccessAt = Date()
        resolverHealth[host] = health
    }

    private func markResolverTimeout(host: String, port: UInt16) {
        guard port == 53 else { return }
        var health = resolverHealth[host] ?? ResolverHealth()
        health.timeoutStreak += 1
        health.failoverScore += 1
        resolverHealth[host] = health
        if host == currentPreferredResolver {
            let fallback = host == "8.8.8.8" ? "1.1.1.1" : "8.8.8.8"
            currentPreferredResolver = fallback
            lastResolverSwitchAt = Date()
            resolverSwitchCount += 1
        }
    }

    private func isDNSResolverStormActive() -> Bool {
        let googleScore = resolverHealth["8.8.8.8"]?.failoverScore ?? 0
        let cloudflareScore = resolverHealth["1.1.1.1"]?.failoverScore ?? 0
        return googleScore >= BubbleConstants.dnsFailoverScoreThreshold &&
            cloudflareScore >= BubbleConstants.dnsFailoverScoreThreshold
    }

    // MARK: - Target Connection (TCP)

    private func connectToTarget(
        client: NWConnection,
        host: String,
        port: UInt16,
        id: Int,
        initialClientData: Data? = nil,
        socksReplyAlreadySent: Bool = false,
        initialSNI: String? = nil
    ) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            self.log.log("SOCKS5 #\(id): invalid port \(port)")
            self.statsErrors += 1
            self.activeConnectionCount -= 1
            if socksReplyAlreadySent {
                client.cancel()
            } else {
                self.sendSocksError(client: client, reply: 0x05)
            }
            return
        }

        let target = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        // Track bytes for diagnostic logging
        let tracker = RelayTracker(id: id, host: host, port: port)
        activeRelays[id] = tracker
        if let initialSNI {
            recordSNI(initialSNI, tracker: tracker)
        } else if let initialClientData, !initialClientData.isEmpty {
            recordUploadMetadataIfNeeded(initialClientData, tracker: tracker)
        }

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
                if socksReplyAlreadySent {
                    self.startTCPRelays(
                        client: client,
                        target: target,
                        tracker: tracker,
                        timeout: timeout,
                        initialClientData: initialClientData
                    )
                    return
                }
                let reply = self.buildSocksReply(reply: 0x00, atyp: 0x01, addr: [0, 0, 0, 0], port: 0)
                client.send(content: reply, completion: .contentProcessed { error in
                    if error != nil {
                        timeout.cancel()
                        self.logRelayEnd(tracker: tracker, reason: "send-error")
                        client.cancel()
                        target.cancel()
                        return
                    }
                    self.startTCPRelays(
                        client: client,
                        target: target,
                        tracker: tracker,
                        timeout: timeout,
                        initialClientData: initialClientData
                    )
                })

            case .failed(let error):
                timeout.cancel()
                self.log.log("SOCKS5 #\(id): target failed \(host):\(port) — \(error)")
                self.statsErrors += 1
                self.recordEvent(type: .error, connId: id, host: host, port: port, detail: "Target connection failed: \(error.localizedDescription)")
                self.logRelayEnd(tracker: tracker, reason: "target-failed")
                if socksReplyAlreadySent {
                    client.cancel()
                } else {
                    self.sendSocksError(client: client, reply: 0x05)
                }
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

    private func startTCPRelays(
        client: NWConnection,
        target: NWConnection,
        tracker: RelayTracker,
        timeout: DispatchWorkItem,
        initialClientData: Data?
    ) {
        guard let initialClientData, !initialClientData.isEmpty else {
            relay(from: client, to: target, tracker: tracker, direction: .upload)
            relay(from: target, to: client, tracker: tracker, direction: .download)
            return
        }

        tracker.bytesUp += initialClientData.count
        target.send(content: initialClientData, completion: .contentProcessed { [weak self] sendError in
            guard let self else { return }
            if sendError != nil {
                timeout.cancel()
                self.logRelayEnd(tracker: tracker, reason: "initial-send-error")
                client.cancel()
                target.cancel()
                return
            }
            self.relay(from: client, to: target, tracker: tracker, direction: .upload)
            self.relay(from: target, to: client, tracker: tracker, direction: .download)
        })
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
        let client: NWConnection
        var trafficClass: TrafficClass
        let createdAt = Date()
        var lastActivityAt = Date()
        var timeoutStreak = 0
        var hardeningEnabled = false
        var hardeningBucket: ContentBucket?
        var lastHost: String?
        var lastPort: UInt16?
        var mode: UDPControlFramingMode?
        var socksRequestHadTail = false
        var dnsFastLanePendingRawBytes = Data()
        var pendingFrames: [UDPControlFrame] = []
        var processingFrame = false
        var processingRecoveredFrame = false
        var processingStartedAt: Date?
        var closed = false
        var closePhase = UDPControlClosePhase.open
        var closeReason: String?
        var cancelScheduled = false
        var drainScheduled = false
        var lastProgressAt = Date()
        var lastSuccessfulResponseAt: Date?
        var preservesMessagingControl = false
        var lastDecisionReason: String?
        var seenDNSPort = false
        var recoveredDNSFrameProcessed = false
        var dnsStartupDrainStartedAt: Date?
        var dnsStartupDrainIdleCloseWorkItem: DispatchWorkItem?
        var dnsStartupDrainFramesProcessed = 0
        var dnsStartupDrainCloseRecorded = false
        var blockedDecisionTimestamps: [Date] = []
        private var blockedDatagramTimestampsByTarget: [String: [Date]] = [:]
        var decoderFailureCount = 0
        var decoderRecoveryCount = 0
        var recoveredFramesPending = 0
        var firstDecoderFailureAt: Date?
        private var decoderFailureTimestamps: [Date] = []
        private var decoderErrorDensity = 0.0
        private var lastDecoderDensityAt = Date()

        init(id: Int, client: NWConnection, decoder: UDPControlStreamDecoder, trafficClass: TrafficClass) {
            self.id = id
            self.client = client
            self.decoder = decoder
            self.trafficClass = trafficClass
        }

        func decoderFailuresInWindow(now: Date, window: TimeInterval) -> Int {
            decoderFailureTimestamps = decoderFailureTimestamps.filter { now.timeIntervalSince($0) <= window }
            decoderFailureTimestamps.append(now)
            return decoderFailureTimestamps.count
        }

        func markProgress(now: Date) {
            let elapsed = max(0, now.timeIntervalSince(lastDecoderDensityAt))
            decoderErrorDensity = max(0, decoderErrorDensity - (elapsed * 0.7))
            lastDecoderDensityAt = now
            lastProgressAt = now
            lastSuccessfulResponseAt = now
        }

        func bumpDecoderErrorDensity(now: Date) -> Double {
            let elapsed = max(0, now.timeIntervalSince(lastDecoderDensityAt))
            decoderErrorDensity = max(0, decoderErrorDensity - (elapsed * 0.5))
            decoderErrorDensity += 1.0
            lastDecoderDensityAt = now
            return decoderErrorDensity
        }

        func blockedDecisionsInWindow(now: Date, window: TimeInterval) -> Int {
            blockedDecisionTimestamps = blockedDecisionTimestamps.filter { now.timeIntervalSince($0) <= window }
            blockedDecisionTimestamps.append(now)
            return blockedDecisionTimestamps.count
        }

        func blockedDatagramsForTargetInWindow(host: String, port: UInt16, bucket: ContentBucket, now: Date, window: TimeInterval) -> Int {
            let key = "\(host.lowercased()):\(port):\(bucket.rawValue)"
            var timestamps = blockedDatagramTimestampsByTarget[key] ?? []
            timestamps = timestamps.filter { now.timeIntervalSince($0) <= window }
            timestamps.append(now)
            blockedDatagramTimestampsByTarget[key] = timestamps
            return timestamps.count
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

    private func recordSNI(_ sni: String, tracker: RelayTracker) {
        guard tracker.sni == nil else { return }
        tracker.sni = sni
        tracker.sniProbeAttempts += 1
        log.logConnection("TCP #\(tracker.id): SNI=\(sni) IP=\(tracker.host):\(tracker.port)")
        TunnelLogger.connectionLog.log("[SNI] \(sni, privacy: .public)")
        let hintedClass = classifyEarly(host: sni, port: tracker.port)
        recordClassHint(host: tracker.host, trafficClass: hintedClass.trafficClass, confidence: hintedClass.confidence)
        recordClassHint(host: sni, trafficClass: hintedClass.trafficClass, confidence: hintedClass.confidence)
        if isDirectTikTokIPHintCandidate(host: tracker.host, port: tracker.port) {
            let sniDecision = filter.evaluateStream(
                host: tracker.host,
                sni: sni,
                port: tracker.port,
                bytesDown: tracker.bytesDown,
                connectionAge: Date().timeIntervalSince(tracker.startTime),
                parallelConnections: activeRelays.count
            )
            recordTikTokIPHintFromSNI(ip: tracker.host, port: tracker.port, sni: sni, decision: sniDecision)
        }
    }

    private func recordUploadMetadataIfNeeded(_ data: Data, tracker: RelayTracker) {
        guard tracker.sni == nil && tracker.sniProbeAttempts < BubbleConstants.maxSNIProbePackets else { return }
        if let sni = extractSNI(from: data) {
            recordSNI(sni, tracker: tracker)
        } else {
            tracker.sniProbeAttempts += 1
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
                    self.recordUploadMetadataIfNeeded(data, tracker: tracker)
                case .download:
                    let projectedBytesDown = tracker.bytesDown + data.count

                    let streamDecision = self.filter.evaluateStream(
                        host: tracker.host,
                        sni: tracker.sni,
                        port: tracker.port,
                        bytesDown: projectedBytesDown,
                        connectionAge: Date().timeIntervalSince(tracker.startTime),
                        parallelConnections: self.activeRelays.count
                    )

                    let threshold = streamDecision.blockAfterBytes
                    let shouldBlockNow = streamDecision.action == .blockNow
                    let shouldBlockAfter = streamDecision.action == .blockAfterBytes && threshold != nil && projectedBytesDown > threshold!
                    if shouldBlockNow || shouldBlockAfter {
                        let gate = self.evaluateProtectionGate(
                            host: tracker.sni ?? tracker.host,
                            port: tracker.port,
                            decision: streamDecision,
                            transport: "tcp_stream",
                            stage: .streamBlock
                        )
                        if gate == .failOpen {
                            tracker.bytesDown = projectedBytesDown
                            self.log.log("STREAM BLOCK #\(tracker.id): fail_open \((tracker.sni ?? tracker.host)) at \(tracker.bytesDown)B reason=\(streamDecision.reason)")
                        } else if gate == .dropFast || gate == .suppress {
                            if gate == .dropFast {
                                self.streamBlockTokenDrops += 1
                            } else {
                                self.streamBlockSuppressed += 1
                            }
                            self.blockedSuppressedTCP += 1
                            self.logRelayEnd(tracker: tracker, reason: "stream-blocked-suppressed")
                            source.cancel()
                            destination.cancel()
                            return
                        } else {
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
                            (self.filter as? StreamObservationRecorder)?.recordBlockedStream(
                                host: tracker.host,
                                sni: tracker.sni,
                                port: tracker.port,
                                decision: streamDecision,
                                bytesDown: tracker.bytesDown,
                                now: Date()
                            )
                            self.logRelayEnd(tracker: tracker, reason: "stream-blocked")
                            source.cancel()
                            destination.cancel()
                            return
                        }
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

}
