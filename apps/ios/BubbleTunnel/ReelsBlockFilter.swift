import Foundation

enum ContentBucket: String, Codable, CaseIterable {
    case reels
    case tiktokVideo = "tiktok_video"
    case tiktokControl = "tiktok_control"
    case messages
    case unknown
}

struct FeaturePolicyV1: Codable {
    let version: Int
    var transportStabilityMode: Bool
    var appToggles: [String: [String: Bool]]
    var revision: Int
    var updatedAt: TimeInterval
    var updatedBy: String

    init(
        version: Int = 1,
        transportStabilityMode: Bool = true,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles,
        revision: Int = 0,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        updatedBy: String = "tunnel.default"
    ) {
        self.version = version
        self.transportStabilityMode = transportStabilityMode
        self.appToggles = appToggles
        self.revision = revision
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false,
        ],
        "tiktok": [
            "video_block": false,
        ]
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
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case transportStabilityMode = "transport_stability_mode"
        case appToggles
        case revision
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        transportStabilityMode = try c.decodeIfPresent(Bool.self, forKey: .transportStabilityMode) ?? true
        appToggles = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .appToggles) ?? Self.defaultToggles
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? "unknown"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(transportStabilityMode, forKey: .transportStabilityMode)
        try c.encode(appToggles, forKey: .appToggles)
        try c.encode(revision, forKey: .revision)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
    }
}

final class ReelsBlockFilter: ConnectionFilter {

    private let sharedDefaults: UserDefaults?
    private var cachedPolicy: FeaturePolicyV1 = .defaultPolicy()
    private var highestSeenPolicyRevision = 0
    private var lastPolicyReload = Date.distantPast
    private let policyReloadInterval: TimeInterval = 1.0

    init(sharedDefaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID)) {
        self.sharedDefaults = sharedDefaults
        reloadPolicyIfNeeded(force: true)
    }

    // MARK: - ConnectionFilter

    func evaluateConnection(host: String, port: UInt16) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        return evaluateHostPolicy(host: host, port: port, isStreamEvaluation: false)
    }

    func evaluateUDP(host: String, port: UInt16, payloadBytes: Int) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        return evaluateHostPolicy(host: host, port: port, isStreamEvaluation: false)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        let domain = (sni ?? host).lowercased()
        return evaluateHostPolicy(host: domain, port: port, isStreamEvaluation: true)
    }

    // MARK: - Deterministic Policy

    private func evaluateHostPolicy(host: String, port: UInt16, isStreamEvaluation: Bool) -> PolicyDecision {
        let lowerHost = host.lowercased()
        let instagramToggles = instagramToggleSnapshot()
        let tiktokToggles = tiktokToggleSnapshot()
        let classification = classify(host: lowerHost, port: port)

        if classification.bucket == .messages {
            return allowDecision(classification: classification, toggles: instagramToggles, reason: "messages_allow")
        }

        if isTikTokHost(lowerHost) {
            return evaluateTikTokPolicy(
                host: lowerHost,
                classification: classification,
                toggles: tiktokToggles
            )
        }

        if instagramToggles["reels"] != true {
            return allowDecision(classification: classification, toggles: instagramToggles, reason: "reels_toggle_off")
        }

        guard shouldEvaluateInstagram(host: lowerHost) else {
            return allowDecision(classification: classification, toggles: instagramToggles, reason: "non_instagram_traffic")
        }

        if isMediaDomain(lowerHost) {
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "reels_media_block_now",
                toggles: instagramToggles,
                host: lowerHost
            )
        }

        if isControlPlaneDomain(lowerHost) {
            if isEssentialControlDomain(lowerHost) {
                return allowDecision(classification: classification, toggles: instagramToggles, reason: "essential_control_allow")
            }
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "reels_control_block_now",
                toggles: instagramToggles,
                host: lowerHost
            )
        }

        let reason = isStreamEvaluation ? "policy_allow_stream" : "policy_allow"
        return allowDecision(classification: classification, toggles: instagramToggles, reason: reason)
    }

    private func evaluateTikTokPolicy(
        host: String,
        classification: FlowClassification,
        toggles: [String: Bool]
    ) -> PolicyDecision {
        if isTikTokMessageOrControlDomain(host) {
            return allowDecision(classification: classification, toggles: toggles, reason: "tiktok_messages_allow")
        }

        if toggles["video_block"] != true {
            return allowDecision(classification: classification, toggles: toggles, reason: "tiktok_video_toggle_off")
        }

        if isTikTokVideoDomain(host) {
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "tiktok_video_block_now",
                toggles: toggles,
                host: host
            )
        }

        return allowDecision(classification: classification, toggles: toggles, reason: "non_tiktok_traffic")
    }

    private func allowDecision(classification: FlowClassification, toggles: [String: Bool], reason: String) -> PolicyDecision {
        PolicyDecision.allow(
            reason: reason,
            classification: classification,
            toggles: toggles,
            policyVersion: cachedPolicy.version
        )
    }

    private func buildDecision(
        action: PolicyAction,
        classification: FlowClassification,
        reason: String,
        toggles: [String: Bool],
        host: String
    ) -> PolicyDecision {
        TunnelLogger.shared.log(
            "POLICY DECISION: rule=\(reason) action=\(action.rawValue) reason=\(reason) host=\(host) " +
            "bucket=\(classification.bucket.rawValue) confidence=\(String(format: "%.2f", classification.confidence))"
        )

        return PolicyDecision(
            action: action,
            blockAfterBytes: nil,
            classification: classification,
            reason: reason,
            toggleSnapshot: toggles,
            policyVersion: cachedPolicy.version,
            intendedAction: nil
        )
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

        if isMediaDomain(host) {
            return FlowClassification(bucket: .reels, confidence: 0.99, reasons: ["reels_media_domain"])
        }

        if isControlPlaneDomain(host) {
            return FlowClassification(bucket: .reels, confidence: 0.95, reasons: ["reels_control_domain"])
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

    private func tiktokToggleSnapshot() -> [String: Bool] {
        var toggles = FeaturePolicyV1.defaultToggles["tiktok"] ?? [:]
        for (key, value) in cachedPolicy.appToggles["tiktok"] ?? [:] {
            toggles[key] = value
        }
        return toggles
    }

    private func shouldEvaluateInstagram(host: String) -> Bool {
        host.contains("instagram") || host.contains("facebook") || host.contains("fbcdn") || host.contains("fbvideo")
    }

    private func isMediaDomain(_ host: String) -> Bool {
        host.contains("scontent-")
            || host.contains(".cdninstagram.com")
            || host.contains("cdninstagram.com")
            || host.contains("fbcdn.net")
            || host.contains("fbvideo.net")
    }

    private func isControlPlaneDomain(_ host: String) -> Bool {
        host.contains("i.instagram.com")
            || host.contains("gateway.instagram.com")
            || host.contains("test-gateway.instagram.com")
    }

    private func isEssentialControlDomain(_ host: String) -> Bool {
        host.contains("i.instagram.com")
            || host.contains("test-gateway.instagram.com")
    }

    private func isMessageHost(_ host: String, port: UInt16) -> Bool {
        if port == 5222 {
            return true
        }
        return host.contains("edge-mqtt.facebook.com") || host.contains("mqtt")
    }

    private func isTikTokHost(_ host: String) -> Bool {
        host.contains("tiktok") || host.contains("musical.ly") || host.contains("byteoversea")
    }

    private func isTikTokVideoDomain(_ host: String) -> Bool {
        host.contains("tiktokcdn")
            || host.contains("tiktokv.com")
            || host.contains("bytecdn")
            || host.contains("ibytedtos")
            || host.contains("video.tiktok")
            || host.contains("sf16-")
            || host.contains("sf19-")
            || host.contains("akamaized.net")
    }

    private func isTikTokMessageOrControlDomain(_ host: String) -> Bool {
        host.contains("api.tiktokv.com")
            || host.contains("api16-normal-c-useast1a.tiktokv.com")
            || host.contains("im.tiktok.com")
            || host.contains("webcast.tiktok.com")
            || host.contains("mon16-normal-useast5.us.tiktokv.com")
            || host.contains("mssdk.tiktok.com")
            || host.contains("log.tiktokv.com")
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
        TunnelLogger.shared.log(
            "POLICY SNAPSHOT: instagram toggles " +
            "reels=\(toggles["reels"] == true) " +
            "tiktok.video_block=\(tiktokToggles["video_block"] == true) " +
            "revision=\(cachedPolicy.revision) " +
            "writer=\(cachedPolicy.updatedBy) " +
            "all_toggles=\(cachedPolicy.appToggles) " +
            "source=\(policySource)"
        )
    }
}
