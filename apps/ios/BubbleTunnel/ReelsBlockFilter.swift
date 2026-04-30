import Foundation

enum ContentBucket: String, Codable, CaseIterable {
    case reels
    case messages
    case unknown
}

struct FeaturePolicyV1: Codable {
    let version: Int
    var appToggles: [String: [String: Bool]]

    init(
        version: Int = 1,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles
    ) {
        self.version = version
        self.appToggles = appToggles
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false,
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
}

final class ReelsBlockFilter: ConnectionFilter {

    private let sharedDefaults: UserDefaults?
    private var cachedPolicy: FeaturePolicyV1 = .defaultPolicy()
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
        let toggles = instagramToggleSnapshot()
        let classification = classify(host: lowerHost, port: port)

        if classification.bucket == .messages {
            return allowDecision(classification: classification, toggles: toggles, reason: "messages_allow")
        }

        if toggles["reels"] != true {
            return allowDecision(classification: classification, toggles: toggles, reason: "reels_toggle_off")
        }

        guard shouldEvaluateInstagram(host: lowerHost) else {
            return allowDecision(classification: classification, toggles: toggles, reason: "non_instagram_traffic")
        }

        if isMediaDomain(lowerHost) {
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "reels_media_block_now",
                toggles: toggles,
                host: lowerHost
            )
        }

        if isControlPlaneDomain(lowerHost) {
            if isEssentialControlDomain(lowerHost) {
                return allowDecision(classification: classification, toggles: toggles, reason: "essential_control_allow")
            }
            return buildDecision(
                action: .blockNow,
                classification: classification,
                reason: "reels_control_block_now",
                toggles: toggles,
                host: lowerHost
            )
        }

        let reason = isStreamEvaluation ? "policy_allow_stream" : "policy_allow"
        return allowDecision(classification: classification, toggles: toggles, reason: reason)
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
                cachedPolicy = merged
                policySource = "featurePolicyV1"
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
        TunnelLogger.shared.log(
            "POLICY SNAPSHOT: instagram toggles " +
            "reels=\(toggles["reels"] == true) " +
            "source=\(policySource)"
        )
    }
}
