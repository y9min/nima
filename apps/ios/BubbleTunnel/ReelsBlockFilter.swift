import Foundation

enum ContentBucket: String, Codable, CaseIterable {
    case reels
    case instagramControl = "instagram_control"
    case tiktokVideo = "tiktok_video"
    case tiktokControl = "tiktok_control"
    case messages
    case unknown
}

enum AppTransportStrategy: String, Codable {
    case legacyReels = "legacy_reels"
    case hardenedVideo = "hardened_video"
}

struct FeaturePolicyV1: Codable {
    let version: Int
    var transportStabilityMode: Bool
    var appToggles: [String: [String: Bool]]
    var appStrategies: [String: AppTransportStrategy]
    var revision: Int
    var updatedAt: TimeInterval
    var updatedBy: String

    init(
        version: Int = 1,
        transportStabilityMode: Bool = true,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles,
        appStrategies: [String: AppTransportStrategy] = FeaturePolicyV1.defaultStrategies,
        revision: Int = 0,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        updatedBy: String = "tunnel.default"
    ) {
        self.version = version
        self.transportStabilityMode = transportStabilityMode
        self.appToggles = appToggles
        self.appStrategies = appStrategies
        self.revision = revision
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false,
            "strict_reels": false,
        ],
        "tiktok": [
            "video_block": false,
        ]
    ]

    static let defaultStrategies: [String: AppTransportStrategy] = [
        "instagram": .legacyReels,
        "tiktok": .hardenedVideo,
    ]

    static func defaultPolicy() -> FeaturePolicyV1 {
        FeaturePolicyV1()
    }

    mutating func set(appId: String, optionId: String, isEnabled: Bool) {
        if appToggles[appId] == nil {
            appToggles[appId] = [:]
        }
        appToggles[appId]?[optionId] = isEnabled
    }

    mutating func mergeDefaults() {
        for (appId, defaults) in Self.defaultToggles {
            if appToggles[appId] == nil {
                appToggles[appId] = defaults
                continue
            }
            for (optionId, value) in defaults where appToggles[appId]?[optionId] == nil {
                appToggles[appId]?[optionId] = value
            }
        }
        for (appId, strategy) in Self.defaultStrategies where appStrategies[appId] == nil {
            appStrategies[appId] = strategy
        }
        normalizeInstagramStrictReels()
    }

    @discardableResult
    mutating func normalizeInstagramStrictReels() -> Bool {
        let legacyWasEnabled = appToggles["instagram"]?["reels"] == true
        let strictWasEnabled = appToggles["instagram"]?["strict_reels"] == true
        guard legacyWasEnabled || strictWasEnabled else { return false }

        if appToggles["instagram"] == nil {
            appToggles["instagram"] = Self.defaultToggles["instagram"] ?? [:]
        }
        appToggles["instagram"]?["strict_reels"] = true
        appToggles["instagram"]?["reels"] = false
        return legacyWasEnabled || !strictWasEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case transportStabilityMode = "transport_stability_mode"
        case appToggles
        case appStrategies = "app_strategies"
        case revision
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        transportStabilityMode = try c.decodeIfPresent(Bool.self, forKey: .transportStabilityMode) ?? true
        appToggles = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .appToggles) ?? Self.defaultToggles
        appStrategies = try c.decodeIfPresent([String: AppTransportStrategy].self, forKey: .appStrategies) ?? Self.defaultStrategies
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? "unknown"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(transportStabilityMode, forKey: .transportStabilityMode)
        try c.encode(appToggles, forKey: .appToggles)
        try c.encode(appStrategies, forKey: .appStrategies)
        try c.encode(revision, forKey: .revision)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
    }
}

final class ReelsBlockFilter: ConnectionFilter, StreamObservationRecorder, InstagramMediaHintReporting {

    private let sharedDefaults: UserDefaults?
    private var cachedPolicy: FeaturePolicyV1 = .defaultPolicy()
    private var highestSeenPolicyRevision = 0
    private var lastPolicyReload = Date.distantPast
    private let policyReloadInterval: TimeInterval = 1.0
    private var policyDecisionSuppression: [String: (lastSeen: Date, suppressedHits: Int)] = [:]
    private let policyDecisionSuppressionWindow: TimeInterval = 1.5
    private let policyDecisionSummaryEvery = 250
    private var instagramMediaHints: [String: InstagramMediaHint] = [:]
    private var instagramMediaHintsAdded = 0
    private var instagramMediaHintsExpired = 0
    private var instagramMediaHintBlocks = 0

    private struct InstagramMediaHint {
        let expiresAt: Date
        let addedAt: Date
        let confidence: Double
    }

    init(sharedDefaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID)) {
        self.sharedDefaults = sharedDefaults
        reloadPolicyIfNeeded(force: true)
    }

    // MARK: - ConnectionFilter

    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        return evaluateHostPolicy(host: host, port: port, isStreamEvaluation: false, bytesDown: 0, now: Date())
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        return evaluateHostPolicy(host: host, port: port, isStreamEvaluation: false, bytesDown: payloadBytes, now: Date())
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        evaluateStream(host: host, sni: sni, port: port, bytesDown: bytesDown, connectionAge: connectionAge, parallelConnections: parallelConnections, now: Date())
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int, now: Date) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        let domain = (sni ?? host).lowercased()
        return evaluateHostPolicy(host: domain, port: port, isStreamEvaluation: true, bytesDown: bytesDown, now: now)
    }

    // MARK: - Deterministic Policy

    private func evaluateHostPolicy(host: String, port: UInt16, isStreamEvaluation: Bool, bytesDown: Int, now: Date) -> PolicyDecision {
        let lowerHost = host.lowercased()
        let instagramToggles = instagramToggleSnapshot()
        let tiktokToggles = tiktokToggleSnapshot()
        let classification = classify(host: lowerHost, port: port)
        let instagramStrategy = strategy(forAppId: "instagram")
        let tiktokStrategy = strategy(forAppId: "tiktok")

        if classification.bucket == .messages {
            return allowDecision(
                classification: classification,
                toggles: instagramToggles,
                reason: "messages_allow",
                strategy: instagramStrategy,
                host: lowerHost
            )
        }

        if isTikTokHost(lowerHost) {
            return evaluateTikTokPolicy(
                host: lowerHost,
                classification: classification,
                toggles: tiktokToggles,
                strategy: tiktokStrategy
            )
        }

        if !isInstagramReelsEnabled(instagramToggles) {
            clearInstagramMediaHints()
            return allowDecision(
                classification: classification,
                toggles: instagramToggles,
                reason: "reels_toggle_off",
                strategy: instagramStrategy,
                host: lowerHost
            )
        }

        guard shouldEvaluateInstagram(host: lowerHost) else {
            return allowDecision(
                classification: classification,
                toggles: instagramToggles,
                reason: "non_instagram_traffic",
                strategy: instagramStrategy
            )
        }

        if isInstagramControlOrMessagingDomain(lowerHost) {
            return allowDecision(
                classification: classification,
                toggles: instagramToggles,
                reason: "instagram_control_allow",
                strategy: instagramStrategy,
                host: lowerHost
            )
        }

        if isConfidentInstagramReelsVideoDomain(lowerHost) {
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "reels_media_block_now",
                toggles: instagramToggles,
                host: lowerHost,
                strategy: instagramStrategy
            )
        }

        if instagramToggles["strict_reels"] == true, isAmbiguousInstagramMediaCDNDomain(lowerHost) {
            let strictMediaClassification = FlowClassification(
                bucket: .reels,
                confidence: 0.78,
                reasons: ["strict_instagram_media_cdn"]
            )
            return buildDecision(
                action: .blockNow,
                classification: strictMediaClassification,
                reason: "reels_strict_media_block_now",
                toggles: instagramToggles,
                host: lowerHost,
                strategy: instagramStrategy
            )
        }

        if isStreamEvaluation, let hint = instagramMediaHint(for: lowerHost, port: port, now: now) {
            instagramMediaHintBlocks += 1
            let hintClassification = FlowClassification(
                bucket: .reels,
                confidence: hint.confidence,
                reasons: ["instagram_media_hint"]
            )
            return buildDecision(
                action: .blockNow,
                classification: hintClassification,
                reason: "reels_media_hint_block_now",
                toggles: instagramToggles,
                host: lowerHost,
                strategy: instagramStrategy
            )
        }

        if isLargeAmbiguousInstagramMediaStream(lowerHost, isStreamEvaluation: isStreamEvaluation, bytesDown: bytesDown) {
            let largeMediaClassification = FlowClassification(
                bucket: .reels,
                confidence: 0.62,
                reasons: ["ambiguous_instagram_media_cdn_large_stream"]
            )
            return buildDecision(
                action: .blockNow,
                classification: largeMediaClassification,
                reason: "reels_media_block_now",
                toggles: instagramToggles,
                host: lowerHost,
                strategy: instagramStrategy
            )
        }

        if isUnknownMetaCDNDomain(lowerHost) {
            return allowDecision(
                classification: classification,
                toggles: instagramToggles,
                reason: "unknown_meta_default_allow",
                strategy: instagramStrategy,
                host: lowerHost
            )
        }

        let reason = isStreamEvaluation ? "policy_allow_stream" : "policy_allow"
        return allowDecision(classification: classification, toggles: instagramToggles, reason: reason, strategy: instagramStrategy)
    }

    private func evaluateTikTokPolicy(
        host: String,
        classification: FlowClassification,
        toggles: [String: Bool],
        strategy: AppTransportStrategy
    ) -> PolicyDecision {
        if isTikTokMessageOrControlDomain(host) {
            return allowDecision(classification: classification, toggles: toggles, reason: "tiktok_messages_allow", strategy: strategy, host: host)
        }

        if toggles["video_block"] != true {
            return allowDecision(classification: classification, toggles: toggles, reason: "tiktok_video_toggle_off", strategy: strategy, host: host)
        }

        if isTikTokVideoDomain(host) {
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "tiktok_video_block_now",
                toggles: toggles,
                host: host,
                strategy: strategy
            )
        }

        return allowDecision(classification: classification, toggles: toggles, reason: "unknown_tiktok_default_allow", strategy: strategy, host: host)
    }

    // MARK: - Instagram Media Hints

    func recordBlockedStream(host: String, sni: String?, port: UInt16, decision: PolicyDecision, bytesDown: Int, now: Date = Date()) {
        pruneInstagramMediaHints(now: now)
        guard isInstagramReelsEnabled(instagramToggleSnapshot()) else { return }
        guard decision.reason == "reels_media_block_now" else { return }
        guard decision.classification.bucket == .reels,
              decision.trafficClass == .instagram,
              decision.classification.reasons.contains("ambiguous_instagram_media_cdn_large_stream") else {
            return
        }
        guard bytesDown > BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold else { return }
        guard let sniHost = sni?.lowercased(), isAmbiguousInstagramMediaCDNDomain(sniHost) else { return }

        let key = instagramMediaHintKey(host: sniHost, port: port)
        if let existing = instagramMediaHints[key], now < existing.expiresAt {
            return
        }

        instagramMediaHints[key] = InstagramMediaHint(
            expiresAt: now.addingTimeInterval(BubbleConstants.instagramMediaHintTTLSeconds),
            addedAt: now,
            confidence: 0.70
        )
        instagramMediaHintsAdded += 1
        TunnelLogger.shared.log(
            "IG_MEDIA_HINT added host=\(sniHost) port=\(port) ttl_s=\(Int(BubbleConstants.instagramMediaHintTTLSeconds)) source=large_stream"
        )
        pruneInstagramMediaHintsToLimit()
    }

    func instagramMediaHintCounterSnapshot(now: Date = Date()) -> InstagramMediaHintCounterSnapshot {
        pruneInstagramMediaHints(now: now)
        return InstagramMediaHintCounterSnapshot(
            added: instagramMediaHintsAdded,
            expired: instagramMediaHintsExpired,
            active: instagramMediaHints.count,
            blocks: instagramMediaHintBlocks
        )
    }

    private func instagramMediaHint(for host: String, port: UInt16, now: Date) -> InstagramMediaHint? {
        pruneInstagramMediaHints(now: now)
        guard isAmbiguousInstagramMediaCDNDomain(host) else { return nil }
        return instagramMediaHints[instagramMediaHintKey(host: host, port: port)]
    }

    private func instagramMediaHintKey(host: String, port: UInt16) -> String {
        "\(host.lowercased()):\(port)"
    }

    private func pruneInstagramMediaHints(now: Date) {
        let expiredKeys = instagramMediaHints.compactMap { key, hint in
            now >= hint.expiresAt ? key : nil
        }
        guard !expiredKeys.isEmpty else { return }
        for key in expiredKeys {
            instagramMediaHints.removeValue(forKey: key)
        }
        instagramMediaHintsExpired += expiredKeys.count
    }

    private func pruneInstagramMediaHintsToLimit() {
        guard instagramMediaHints.count > BubbleConstants.maxInstagramMediaHints else { return }
        let overflow = instagramMediaHints.count - BubbleConstants.maxInstagramMediaHints
        for key in instagramMediaHints.sorted(by: { $0.value.addedAt < $1.value.addedAt }).prefix(overflow).map(\.key) {
            instagramMediaHints.removeValue(forKey: key)
        }
    }

    private func clearInstagramMediaHints() {
        instagramMediaHints.removeAll()
    }

    private func allowDecision(
        classification: FlowClassification,
        toggles: [String: Bool],
        reason: String,
        strategy: AppTransportStrategy,
        host: String? = nil
    ) -> PolicyDecision {
        if let host {
            logPolicyDecision(action: .allow, classification: classification, reason: reason, host: host)
        }
        return PolicyDecision.allow(
            reason: reason,
            classification: classification,
            toggles: toggles,
            policyVersion: cachedPolicy.version,
            appStrategy: strategy.rawValue,
            trafficClass: trafficClass(for: classification)
        )
    }

    private func buildDecision(
        action: PolicyAction,
        classification: FlowClassification,
        reason: String,
        toggles: [String: Bool],
        host: String,
        strategy: AppTransportStrategy
    ) -> PolicyDecision {
        logPolicyDecision(action: action, classification: classification, reason: reason, host: host)

        return PolicyDecision(
            action: action,
            blockAfterBytes: nil,
            classification: classification,
            reason: reason,
            toggleSnapshot: toggles,
            policyVersion: cachedPolicy.version,
            intendedAction: nil,
            appStrategy: strategy.rawValue,
            trafficClass: trafficClass(for: classification)
        )
    }

    private func logPolicyDecision(action: PolicyAction, classification: FlowClassification, reason: String, host: String) {
        let bucketLogName = logBucketName(for: classification, reason: reason)
        if classification.bucket == .tiktokVideo || classification.bucket == .tiktokControl || reason == "unknown_tiktok_default_allow" {
            TunnelLogger.shared.log(
                "TCP_POLICY host=\(host) action=\(action.rawValue) reason=\(reason) bucket=\(bucketLogName) confidence=\(String(format: "%.2f", classification.confidence))"
            )
        }
        if classification.bucket == .reels || classification.bucket == .instagramControl || reason == "unknown_meta_default_allow" {
            TunnelLogger.shared.log(
                "IG_POLICY host=\(host) bucket=\(bucketLogName) action=\(action.rawValue) reason=\(reason) confidence=\(String(format: "%.2f", classification.confidence))"
            )
        }

        let line = "POLICY DECISION: rule=\(reason) action=\(action.rawValue) reason=\(reason) host=\(host) " +
            "bucket=\(classification.bucket.rawValue) confidence=\(String(format: "%.2f", classification.confidence))"

        guard reason == "tiktok_video_block_now" else {
            TunnelLogger.shared.log(line)
            return
        }

        let now = Date()
        let key = "\(reason)|\(host)|\(classification.bucket.rawValue)"
        if var state = policyDecisionSuppression[key],
           now.timeIntervalSince(state.lastSeen) <= policyDecisionSuppressionWindow {
            state.lastSeen = now
            state.suppressedHits += 1
            policyDecisionSuppression[key] = state
            if state.suppressedHits % policyDecisionSummaryEvery == 0 {
                TunnelLogger.shared.log(
                    "POLICY DECISION SUPPRESSED: rule=\(reason) host=\(host) bucket=\(classification.bucket.rawValue) suppressed=\(state.suppressedHits)"
                )
            }
            return
        }

        policyDecisionSuppression[key] = (lastSeen: now, suppressedHits: 0)
        if policyDecisionSuppression.count > BubbleConstants.extensionPressureMaxSuppressionEntries {
            let overflow = policyDecisionSuppression.count - BubbleConstants.extensionPressureMaxSuppressionEntries
            for oldKey in policyDecisionSuppression.sorted(by: { $0.value.lastSeen < $1.value.lastSeen }).prefix(overflow).map(\.key) {
                policyDecisionSuppression.removeValue(forKey: oldKey)
            }
        }
        TunnelLogger.shared.log(line)
    }

    private func logBucketName(for classification: FlowClassification, reason: String) -> String {
        if classification.bucket == .reels {
            return "reels_video"
        }
        if classification.bucket == .instagramControl || reason == "instagram_control_allow" {
            return "control"
        }
        if reason == "unknown_meta_default_allow" {
            return "unknown_meta"
        }
        return classification.bucket.rawValue
    }

    private func trafficClass(for classification: FlowClassification) -> TrafficClass {
        switch classification.bucket {
        case .tiktokVideo, .tiktokControl:
            return .tiktok
        case .reels, .instagramControl:
            return .instagram
        case .messages, .unknown:
            return .generic
        }
    }

    // MARK: - Classification

    private func classify(host: String, port: UInt16) -> FlowClassification {
        if isMessageHost(host, port: port) {
            return FlowClassification(bucket: .messages, confidence: 0.99, reasons: ["message_transport"])
        }

        if isTikTokMessageOrControlDomain(host) {
            return FlowClassification(bucket: .tiktokControl, confidence: 0.96, reasons: ["tiktok_control_domain"])
        }

        if isTikTokVideoDomain(host) {
            return FlowClassification(bucket: .tiktokVideo, confidence: 0.99, reasons: ["tiktok_video_domain"])
        }

        if isConfidentInstagramReelsVideoDomain(host) {
            return FlowClassification(bucket: .reels, confidence: 0.99, reasons: ["reels_media_domain"])
        }

        if isControlPlaneDomain(host) || isInstagramControlOrMessagingDomain(host) {
            return FlowClassification(bucket: .instagramControl, confidence: 0.95, reasons: ["instagram_control_domain"])
        }

        if isUnknownMetaCDNDomain(host) {
            return FlowClassification(bucket: .unknown, confidence: 0.35, reasons: ["unknown_meta_cdn_default_allow"])
        }

        return FlowClassification(bucket: .unknown, confidence: 0.0, reasons: ["non_reels_domain"])
    }

    // MARK: - Helpers

    private func instagramToggleSnapshot() -> [String: Bool] {
        var toggles = FeaturePolicyV1.defaultToggles["instagram"] ?? [:]
        for (key, value) in cachedPolicy.appToggles["instagram"] ?? [:] {
            toggles[key] = value
        }
        return toggles
    }

    private func isInstagramReelsEnabled(_ toggles: [String: Bool]) -> Bool {
        toggles["strict_reels"] == true || toggles["reels"] == true
    }

    private func tiktokToggleSnapshot() -> [String: Bool] {
        var toggles = FeaturePolicyV1.defaultToggles["tiktok"] ?? [:]
        for (key, value) in cachedPolicy.appToggles["tiktok"] ?? [:] {
            toggles[key] = value
        }
        return toggles
    }

    private func strategy(forAppId appId: String) -> AppTransportStrategy {
        cachedPolicy.appStrategies[appId] ?? FeaturePolicyV1.defaultStrategies[appId] ?? .legacyReels
    }

    private func shouldEvaluateInstagram(host: String) -> Bool {
        host.contains("instagram") || host.contains("facebook") || host.contains("fbcdn") || host.contains("fbvideo")
    }

    private func isConfidentInstagramReelsVideoDomain(_ host: String) -> Bool {
        guard shouldEvaluateInstagram(host: host) || host.contains("cdninstagram") || host.contains("fbvideo") else {
            return false
        }
        return host.contains("reels")
            || host.contains("reel")
            || host.contains("clips")
            || host.contains("ig-video")
            || host.contains("instagram-video")
            || host.contains("reels-video")
            || host.contains("fbvideo.net")
            || (host.contains("video") && (host.contains("instagram") || host.contains("cdninstagram") || host.contains("fbcdn") || host.contains("facebook")))
    }

    private func isUnknownMetaCDNDomain(_ host: String) -> Bool {
        host.contains("scontent-")
            || host.contains(".cdninstagram.com")
            || host.contains("cdninstagram.com")
            || host.contains("fbcdn.net")
            || host.contains("static.xx.fbcdn.net")
    }

    private func isLargeAmbiguousInstagramMediaStream(_ host: String, isStreamEvaluation: Bool, bytesDown: Int) -> Bool {
        guard isStreamEvaluation else { return false }
        guard isAmbiguousInstagramMediaCDNDomain(host) else { return false }
        return bytesDown > BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold
    }

    private func isAmbiguousInstagramMediaCDNDomain(_ host: String) -> Bool {
        host.hasPrefix("scontent-") &&
            host.contains(".cdninstagram.com")
    }

    private func isControlPlaneDomain(_ host: String) -> Bool {
        host.contains("i.instagram.com")
            || host.contains("gateway.instagram.com")
            || host.contains("test-gateway.instagram.com")
    }

    private func isInstagramControlOrMessagingDomain(_ host: String) -> Bool {
        host.contains("i.instagram.com")
            || host == "instagram.com"
            || host == "www.instagram.com"
            || host.contains("accounts.instagram.com")
            || host.contains("accountscenter.instagram.com")
            || host.contains("gateway.instagram.com")
            || host.contains("test-gateway.instagram.com")
            || host.contains("graph.instagram.com")
            || host.contains("graph.facebook.com")
            || host.contains("b-graph.facebook.com")
            || host.contains("edge-mqtt.facebook.com")
            || host.contains("mqtt")
    }

    private func isMessageHost(_ host: String, port: UInt16) -> Bool {
        if port == 5222 {
            return true
        }
        return host.contains("edge-mqtt.facebook.com") || host.contains("mqtt")
    }

    private func isTikTokHost(_ host: String) -> Bool {
        host.contains("tiktok")
            || host.contains("musical.ly")
            || host.contains("byteoversea")
            || host.contains("bytecdn")
            || host.contains("ibytedtos")
            || host.contains("ibyteimg")
    }

    private func isTikTokVideoDomain(_ host: String) -> Bool {
        host.contains("tiktokcdn")
            || host.contains("tiktokv.com")
            || host.contains("tiktokv.eu")
            || host.contains("bytecdn")
            || host.contains("ibytedtos")
            || host.contains("video.tiktok")
            || host.contains("sf16-")
            || host.contains("sf19-")
            || (host.contains("akamaized.net") && host.contains("tiktok"))
    }

    private func isTikTokMessageOrControlDomain(_ host: String) -> Bool {
        if (host == "tiktok.com" || host == "www.tiktok.com" || host == "m.tiktok.com" || host.hasSuffix(".tiktok.com")),
           !isTikTokVideoDomain(host) {
            return true
        }
        return host.contains("api.tiktokv.com")
            || host.contains("api.tiktokv.eu")
            || host.contains("api16-normal-c-useast1a.tiktokv.com")
            || (host.contains("api") && host.contains("tiktokv.com"))
            || (host.contains("api") && host.contains("tiktokv.eu"))
            || host.contains("im.tiktok.com")
            || host.contains("inbox.tiktok.com")
            || host.contains("search.tiktok.com")
            || host.contains("login.tiktok.com")
            || host.contains("webcast.tiktok.com")
            || host.contains("mon16-normal-useast5.us.tiktokv.com")
            || host.contains("mon.tiktokv.com")
            || host.contains("mon.tiktokv.eu")
            || host.contains("mssdk.tiktok.com")
            || host.contains("log.tiktokv.com")
            || host.contains("log.tiktokv.eu")
            || host.contains("oauth.tiktok.com")
            || host.contains("isnssdk.com")
            || host.contains("musical.ly")
            || host.contains("byteoversea.com")
    }

    private func reloadPolicyIfNeeded(force: Bool) {
        let now = Date()
        if !force, now.timeIntervalSince(lastPolicyReload) < policyReloadInterval {
            return
        }
        lastPolicyReload = now

        var policySource = "cached"
        if let data = sharedDefaults?.data(forKey: BubbleConstants.featurePolicyKey) {
            if let decoded = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) {
                var merged = decoded
                merged.mergeDefaults()
                if merged.revision < highestSeenPolicyRevision {
                    TunnelLogger.shared.log(
                        "POLICY RELOAD: stale revision rejected incoming=\(merged.revision) highest=\(highestSeenPolicyRevision) writer=\(merged.updatedBy)"
                    )
                } else {
                    cachedPolicy = merged
                    highestSeenPolicyRevision = merged.revision
                    policySource = "featurePolicyV1"
                }
            } else {
                TunnelLogger.shared.log("POLICY RELOAD: featurePolicyV1 decode failed; keeping cached policy")
            }
        } else {
            if force {
                cachedPolicy = .defaultPolicy()
                policySource = "default_policy"
            } else {
                TunnelLogger.shared.log("POLICY RELOAD: featurePolicyV1 missing; keeping cached policy")
            }
        }

        let toggles = instagramToggleSnapshot()
        let tiktokToggles = tiktokToggleSnapshot()
        if isInstagramReelsEnabled(toggles) {
            pruneInstagramMediaHints(now: now)
        } else {
            clearInstagramMediaHints()
        }
        TunnelLogger.shared.log(
            "POLICY SNAPSHOT: instagram toggles " +
            "reels=\(toggles["reels"] == true) " +
            "strict_reels=\(toggles["strict_reels"] == true) " +
            "tiktok.video_block=\(tiktokToggles["video_block"] == true) " +
            "revision=\(cachedPolicy.revision) " +
            "writer=\(cachedPolicy.updatedBy) " +
            "all_toggles=\(cachedPolicy.appToggles) " +
            "source=\(policySource)"
        )
    }
}
