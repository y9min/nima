import Foundation

enum ContentBucket: String, Codable, CaseIterable {
    case reels
    case messages
    case unknown
}

struct FilterHealthMetrics {
    let retryStormEvents: Int
    let backoffActiveHosts: Int
}

struct FeaturePolicyV1: Codable {
    enum ReelsBlockMode: String, Codable {
        case legacySafe = "legacy_safe"
        case strict
        case hardPreload = "hard_preload"
    }

    struct AppMetaIPGuardConfig: Codable {
        var enabled: Bool

        init(enabled: Bool = true) {
            self.enabled = enabled
        }
    }

    struct MetaIPGuardConfig: Codable {
        var instagram: AppMetaIPGuardConfig
        var facebook: AppMetaIPGuardConfig

        init(
            instagram: AppMetaIPGuardConfig = AppMetaIPGuardConfig(enabled: true),
            facebook: AppMetaIPGuardConfig = AppMetaIPGuardConfig(enabled: true)
        ) {
            self.instagram = instagram
            self.facebook = facebook
        }
    }

    struct ReelsPolicyConfig: Codable {
        var instagramMode: ReelsBlockMode
        var facebookMode: ReelsBlockMode

        init(instagramMode: ReelsBlockMode = .legacySafe, facebookMode: ReelsBlockMode = .hardPreload) {
            self.instagramMode = instagramMode
            self.facebookMode = facebookMode
        }
    }

    let version: Int
    var profile: String
    var shadowModeEnabled: Bool
    var adaptiveBackoffEnabled: Bool
    var udpDecoderFailOpenEnabled: Bool
    var retryStormThreshold: Int
    var retryStormWindowSec: Int
    var backoffMinSec: Int
    var backoffMaxSec: Int
    var udpDecodeMode: UDPDecodeMode
    var udpCircuitBreakerThreshold: Int
    var udpCircuitBreakerWindowSec: Int
    var udpCircuitBreakerCooldownSec: Int
    var quicHandling: QUICHandlingMode
    var metaIpGuardMode: MetaIPGuardMode
    var metaIpGuard: MetaIPGuardConfig
    var reelsPolicy: ReelsPolicyConfig
    var thermalGuardEnabled: Bool
    var appToggles: [String: [String: Bool]]

    init(
        version: Int = 2,
        profile: String = "minimal-impact",
        shadowModeEnabled: Bool = false,
        adaptiveBackoffEnabled: Bool = true,
        udpDecoderFailOpenEnabled: Bool = true,
        retryStormThreshold: Int = 8,
        retryStormWindowSec: Int = 3,
        backoffMinSec: Int = 10,
        backoffMaxSec: Int = 30,
        udpDecodeMode: UDPDecodeMode = .adaptive,
        udpCircuitBreakerThreshold: Int = 3,
        udpCircuitBreakerWindowSec: Int = 5,
        udpCircuitBreakerCooldownSec: Int = 20,
        quicHandling: QUICHandlingMode = .classifyOnly,
        metaIpGuardMode: MetaIPGuardMode = .fallbackOnly,
        metaIpGuard: MetaIPGuardConfig = MetaIPGuardConfig(),
        reelsPolicy: ReelsPolicyConfig = ReelsPolicyConfig(),
        thermalGuardEnabled: Bool = true,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles
    ) {
        self.version = version
        self.profile = profile
        self.shadowModeEnabled = shadowModeEnabled
        self.adaptiveBackoffEnabled = adaptiveBackoffEnabled
        self.udpDecoderFailOpenEnabled = udpDecoderFailOpenEnabled
        self.retryStormThreshold = retryStormThreshold
        self.retryStormWindowSec = retryStormWindowSec
        self.backoffMinSec = backoffMinSec
        self.backoffMaxSec = backoffMaxSec
        self.udpDecodeMode = udpDecodeMode
        self.udpCircuitBreakerThreshold = max(1, udpCircuitBreakerThreshold)
        self.udpCircuitBreakerWindowSec = max(1, udpCircuitBreakerWindowSec)
        self.udpCircuitBreakerCooldownSec = max(1, udpCircuitBreakerCooldownSec)
        self.quicHandling = quicHandling
        self.metaIpGuardMode = metaIpGuardMode
        self.metaIpGuard = metaIpGuard
        self.reelsPolicy = reelsPolicy
        self.thermalGuardEnabled = thermalGuardEnabled
        self.appToggles = appToggles
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false,
        ],
        "facebook": [
            "reels": false,
        ],
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

    enum CodingKeys: String, CodingKey {
        case version
        case profile
        case shadowModeEnabled
        case adaptiveBackoffEnabled
        case udpDecoderFailOpenEnabled
        case retryStormThreshold
        case retryStormWindowSec
        case backoffMinSec
        case backoffMaxSec
        case udpDecodeMode
        case udpCircuitBreakerThreshold
        case udpCircuitBreakerWindowSec
        case udpCircuitBreakerCooldownSec
        case quicHandling
        case metaIpGuardMode
        case metaIpGuard
        case reelsPolicy
        case thermalGuardEnabled
        case appToggles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? "minimal-impact"
        shadowModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .shadowModeEnabled) ?? false
        adaptiveBackoffEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveBackoffEnabled) ?? true
        udpDecoderFailOpenEnabled = try container.decodeIfPresent(Bool.self, forKey: .udpDecoderFailOpenEnabled) ?? true
        retryStormThreshold = max(1, try container.decodeIfPresent(Int.self, forKey: .retryStormThreshold) ?? 8)
        retryStormWindowSec = max(1, try container.decodeIfPresent(Int.self, forKey: .retryStormWindowSec) ?? 3)
        backoffMinSec = max(1, try container.decodeIfPresent(Int.self, forKey: .backoffMinSec) ?? 10)
        backoffMaxSec = max(backoffMinSec, try container.decodeIfPresent(Int.self, forKey: .backoffMaxSec) ?? 30)
        udpDecodeMode = try container.decodeIfPresent(UDPDecodeMode.self, forKey: .udpDecodeMode)
            ?? (udpDecoderFailOpenEnabled ? .adaptive : .strict)
        udpCircuitBreakerThreshold = max(1, try container.decodeIfPresent(Int.self, forKey: .udpCircuitBreakerThreshold) ?? 3)
        udpCircuitBreakerWindowSec = max(1, try container.decodeIfPresent(Int.self, forKey: .udpCircuitBreakerWindowSec) ?? 5)
        udpCircuitBreakerCooldownSec = max(1, try container.decodeIfPresent(Int.self, forKey: .udpCircuitBreakerCooldownSec) ?? 20)
        quicHandling = try container.decodeIfPresent(QUICHandlingMode.self, forKey: .quicHandling) ?? .classifyOnly
        metaIpGuardMode = try container.decodeIfPresent(MetaIPGuardMode.self, forKey: .metaIpGuardMode) ?? .fallbackOnly
        metaIpGuard = try container.decodeIfPresent(MetaIPGuardConfig.self, forKey: .metaIpGuard) ?? MetaIPGuardConfig()
        reelsPolicy = try container.decodeIfPresent(ReelsPolicyConfig.self, forKey: .reelsPolicy) ?? ReelsPolicyConfig()
        thermalGuardEnabled = try container.decodeIfPresent(Bool.self, forKey: .thermalGuardEnabled) ?? true
        appToggles = try container.decodeIfPresent([String: [String: Bool]].self, forKey: .appToggles) ?? FeaturePolicyV1.defaultToggles
    }
}

final class ReelsBlockFilter: ConnectionFilter {

    private let sharedDefaults: UserDefaults?
    private var cachedPolicy: FeaturePolicyV1 = .defaultPolicy()
    private var didLoadPolicyForSession = false
    private let strictUDPBlockEnabled: Bool
    private var recentMetaIPFallbackByHostByApp: [String: [String: Date]] = [:]
    private let metaIPFallbackWindowSec: TimeInterval = 1.0
    private var recentBlockedHosts: [String: Date] = [:]
    private let blockedHostCooldown: TimeInterval = 5.0
    private var retryStormAttemptsByHost: [String: [Date]] = [:]
    private var backoffUntilByHost: [String: Date] = [:]
    private var backoffDurationSecByHost: [String: TimeInterval] = [:]
    private var pendingBackoffExitHosts: Set<String> = []
    private var retryStormEventsCount = 0

    init(sharedDefaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID)) {
        self.sharedDefaults = sharedDefaults
        self.strictUDPBlockEnabled = sharedDefaults?.bool(forKey: BubbleConstants.strictUDPBlockEnabledKey) ?? false
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

    func evaluateEarlyTLS(host: String, sni: String, port: UInt16) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        return evaluateHostPolicy(host: sni.lowercased(), port: port, isStreamEvaluation: true)
    }

    func evaluateStream(host: String, sni: String?, port: UInt16, bytesDown: Int, connectionAge: TimeInterval, parallelConnections: Int) -> PolicyDecision {
        reloadPolicyIfNeeded(force: false)
        let domain = (sni ?? host).lowercased()
        return evaluateHostPolicy(host: domain, port: port, isStreamEvaluation: true)
    }

    func healthMetrics() -> FilterHealthMetrics {
        reloadPolicyIfNeeded(force: false)
        return FilterHealthMetrics(
            retryStormEvents: retryStormEventsCount,
            backoffActiveHosts: backoffUntilByHost.count
        )
    }

    func runtimePolicy() -> RuntimePolicyTuning {
        reloadPolicyIfNeeded(force: false)
        return RuntimePolicyTuning(
            udpDecodeMode: cachedPolicy.udpDecodeMode,
            udpCircuitBreakerThreshold: max(cachedPolicy.udpCircuitBreakerThreshold, 1),
            udpCircuitBreakerWindowSec: max(cachedPolicy.udpCircuitBreakerWindowSec, 1),
            udpCircuitBreakerCooldownSec: max(cachedPolicy.udpCircuitBreakerCooldownSec, 1),
            quicHandling: cachedPolicy.quicHandling,
            metaIPGuardMode: cachedPolicy.metaIpGuardMode,
            thermalGuardEnabled: cachedPolicy.thermalGuardEnabled
        )
    }

    // MARK: - Deterministic Policy

    private func evaluateHostPolicy(host: String, port: UInt16, isStreamEvaluation: Bool) -> PolicyDecision {
        let lowerHost = host.lowercased()
        let instagramReelsEnabled = instagramToggleSnapshot()["reels"] == true
        let facebookReelsEnabled = facebookToggleSnapshot()["reels"] == true

        if isKnownMessageTransport(host: lowerHost, port: port) {
            return allowDecision(
                classification: FlowClassification(bucket: .messages, confidence: 0.99, reasons: ["message_transport_allowlist"]),
                toggles: combinedToggleSnapshot(),
                reason: "messages_allow"
            )
        }

        if shouldEvaluateInstagram(
            host: lowerHost,
            instagramReelsEnabled: instagramReelsEnabled,
            facebookReelsEnabled: facebookReelsEnabled
        ) {
            return evaluateInstagramPolicy(host: lowerHost, port: port, isStreamEvaluation: isStreamEvaluation)
        }

        if shouldEvaluateFacebook(host: lowerHost) {
            return evaluateFacebookPolicy(host: lowerHost, port: port)
        }

        if isLikelyMetaIPAddress(lowerHost), port == 443 {
            if shouldSkipFacebookMetaIPFallback(
                host: lowerHost,
                instagramReelsEnabled: instagramReelsEnabled,
                facebookReelsEnabled: facebookReelsEnabled
            ) {
                let reason = isStreamEvaluation ? "policy_allow_stream" : "policy_allow"
                return allowDecision(
                    classification: FlowClassification(bucket: .unknown, confidence: 0.0, reasons: ["meta_ip_fallback_skipped"]),
                    toggles: combinedToggleSnapshot(),
                    reason: reason
                )
            }
            if facebookReelsEnabled,
               cachedPolicy.metaIpGuard.facebook.enabled,
               cachedPolicy.reelsPolicy.facebookMode == .hardPreload {
                return evaluateMetaIPFallback(host: lowerHost, appId: "facebook", toggles: facebookToggleSnapshot(), reasonPrefix: "facebook")
            }
        }

        let reason = isStreamEvaluation ? "policy_allow_stream" : "policy_allow"
        return allowDecision(
            classification: FlowClassification(bucket: .unknown, confidence: 0.0, reasons: ["non_reels_domain"]),
            toggles: combinedToggleSnapshot(),
            reason: reason
        )
    }

    private func evaluateInstagramPolicy(host: String, port: UInt16, isStreamEvaluation: Bool) -> PolicyDecision {
        let toggles = instagramToggleSnapshot()

        if isInstagramMessageHost(host, port: port) {
            return allowDecision(
                classification: FlowClassification(bucket: .messages, confidence: 0.99, reasons: ["message_transport"]),
                toggles: toggles,
                reason: "messages_allow"
            )
        }

        if toggles["reels"] != true {
            return allowDecision(
                classification: FlowClassification(bucket: .unknown, confidence: 0.0, reasons: ["reels_toggle_off"]),
                toggles: toggles,
                reason: "reels_toggle_off"
            )
        }

        if isInstagramMediaDomain(host) {
            return buildDecision(
                action: .blockNow,
                classification: FlowClassification(bucket: .reels, confidence: 0.99, reasons: ["reels_media_domain"]),
                reason: "reels_media_block_now",
                toggles: toggles,
                host: host,
                intendedAction: nil
            )
        }

        if isInstagramControlPlaneDomain(host) {
            return buildDecision(
                action: .blockNow,
                classification: FlowClassification(bucket: .reels, confidence: 0.95, reasons: ["reels_control_domain"]),
                reason: "reels_control_block_now",
                toggles: toggles,
                host: host,
                intendedAction: nil
            )
        }

        let reason = isStreamEvaluation ? "instagram_unknown_allow_stream" : "instagram_unknown_allow"
        return allowDecision(
            classification: FlowClassification(bucket: .unknown, confidence: 0.20, reasons: ["instagram_unknown_allow"]),
            toggles: toggles,
            reason: reason
        )
    }

    private func evaluateFacebookPolicy(host: String, port: UInt16) -> PolicyDecision {
        let toggles = facebookToggleSnapshot()

        if isFacebookMessageHost(host, port: port) {
            return allowDecision(
                classification: FlowClassification(bucket: .messages, confidence: 0.99, reasons: ["facebook_message_transport"]),
                toggles: toggles,
                reason: "facebook_messages_allow"
            )
        }

        if toggles["reels"] != true {
            return allowDecision(
                classification: FlowClassification(bucket: .unknown, confidence: 0.0, reasons: ["facebook_reels_toggle_off"]),
                toggles: toggles,
                reason: "facebook_reels_toggle_off"
            )
        }

        if isFacebookReelsMediaDomain(host) {
            return buildBlockOrShadowDecision(
                shadowReason: "facebook_reels_media_shadow",
                blockReason: "facebook_early_media_block_now",
                classification: FlowClassification(bucket: .reels, confidence: 0.99, reasons: ["facebook_reels_media_domain"]),
                toggles: toggles,
                host: host
            )
        }

        if isFacebookReelsControlDomain(host) {
            let now = Date()
            let didExitBackoff = consumeBackoffExit(host: host, now: now)
            let didEnterBackoff = registerControlPlaneBlock(host: host, now: now)
            let blockReason: String
            let ruleReason: String
            if didEnterBackoff {
                blockReason = "retry_storm_enter"
                ruleReason = "retry_storm_threshold_reached"
            } else if didExitBackoff {
                blockReason = "retry_storm_exit"
                ruleReason = "retry_storm_backoff_elapsed"
            } else if isAdaptiveBackoffActive(host: host, now: now) {
                blockReason = "retry_storm_cooldown_block"
                ruleReason = "retry_storm_backoff_active"
            } else if !cachedPolicy.adaptiveBackoffEnabled, shouldCooldownBlock(host: host) {
                blockReason = "facebook_reels_recent_block_cooldown"
                ruleReason = "facebook_recent_block_cooldown"
            } else {
                blockReason = "facebook_reels_control_block_now"
                ruleReason = "facebook_reels_control_domain"
            }
            return buildBlockOrShadowDecision(
                shadowReason: "facebook_reels_control_shadow",
                blockReason: blockReason,
                classification: FlowClassification(bucket: .reels, confidence: 0.95, reasons: [ruleReason]),
                toggles: toggles,
                host: host
            )
        }

        return allowDecision(
            classification: FlowClassification(bucket: .unknown, confidence: 0.20, reasons: ["facebook_unknown_allow"]),
            toggles: toggles,
            reason: "facebook_unknown_allow"
        )
    }

    private func allowDecision(classification: FlowClassification, toggles: [String: Bool], reason: String) -> PolicyDecision {
        PolicyDecision.allow(
            reason: reason,
            classification: classification,
            toggles: toggles,
            policyVersion: cachedPolicy.version
        )
    }

    private func buildBlockOrShadowDecision(
        shadowReason: String,
        blockReason: String,
        classification: FlowClassification,
        toggles: [String: Bool],
        host: String
    ) -> PolicyDecision {
        if cachedPolicy.shadowModeEnabled {
            return buildDecision(
                action: .shadowAllow,
                classification: classification,
                reason: shadowReason,
                toggles: toggles,
                host: host,
                intendedAction: .blockNow
            )
        }

        return buildDecision(
            action: .blockNow,
            classification: classification,
            reason: blockReason,
            toggles: toggles,
            host: host,
            intendedAction: nil
        )
    }

    private func buildDecision(
        action: PolicyAction,
        classification: FlowClassification,
        reason: String,
        toggles: [String: Bool],
        host: String,
        intendedAction: PolicyAction?
    ) -> PolicyDecision {
        let intended = intendedAction?.rawValue ?? "none"
        TunnelLogger.shared.log(
            "POLICY DECISION: rule=\(reason) action=\(action.rawValue) intended=\(intended) reason=\(reason) host=\(host) " +
            "bucket=\(classification.bucket.rawValue) confidence=\(String(format: "%.2f", classification.confidence))"
        )

        if action == .blockNow {
            recordRecentBlock(host: host)
        }

        return PolicyDecision(
            action: action,
            blockAfterBytes: nil,
            classification: classification,
            reason: reason,
            toggleSnapshot: toggles,
            policyVersion: cachedPolicy.version,
            intendedAction: intendedAction
        )
    }

    // MARK: - Helpers

    private func instagramToggleSnapshot() -> [String: Bool] {
        var toggles = FeaturePolicyV1.defaultToggles["instagram"] ?? [:]
        for (key, value) in cachedPolicy.appToggles["instagram"] ?? [:] {
            toggles[key] = value
        }
        return toggles
    }

    private func facebookToggleSnapshot() -> [String: Bool] {
        var toggles = FeaturePolicyV1.defaultToggles["facebook"] ?? [:]
        for (key, value) in cachedPolicy.appToggles["facebook"] ?? [:] {
            toggles[key] = value
        }
        return toggles
    }

    private func combinedToggleSnapshot() -> [String: Bool] {
        [
            "instagram.reels": instagramToggleSnapshot()["reels"] == true,
            "facebook.reels": facebookToggleSnapshot()["reels"] == true,
        ]
    }

    private func shouldEvaluateInstagram(host: String, instagramReelsEnabled: Bool, facebookReelsEnabled: Bool) -> Bool {
        if host.contains("instagram") || host.contains("cdninstagram.com") {
            return true
        }
        // Last-push behavior treated shared Meta video CDNs as IG-reels candidates.
        if (host.contains("fbcdn") || host.contains("fbvideo")) && instagramReelsEnabled && !facebookReelsEnabled {
            return true
        }
        return false
    }

    private func shouldEvaluateFacebook(host: String) -> Bool {
        host.contains("facebook") || host.contains("fbcdn") || host.contains("fbvideo") || host.contains("fbsbx")
    }

    private func shouldSkipFacebookMetaIPFallback(
        host: String,
        instagramReelsEnabled: Bool,
        facebookReelsEnabled: Bool
    ) -> Bool {
        if !facebookReelsEnabled && instagramReelsEnabled {
            return true
        }
        if host.contains("instagram") || host.contains("cdninstagram.com") {
            return true
        }
        return false
    }

    private func isKnownMessageTransport(host: String, port: UInt16) -> Bool {
        if port == 5222 {
            return true
        }
        if host.contains("mqtt") {
            return true
        }
        if host.contains("courier.push.apple.com") {
            return true
        }
        return false
    }

    private func isInstagramMediaDomain(_ host: String) -> Bool {
        (host.contains("scontent-") && host.contains("cdninstagram.com"))
            || host.contains(".cdninstagram.com")
            || host.contains("cdninstagram.com")
            || host.contains("fbcdn.net")
            || host.contains("fbvideo.net")
    }

    private func isInstagramControlPlaneDomain(_ host: String) -> Bool {
        host.contains("i.instagram.com")
            || host.contains("i-fallback.instagram.com")
            || host.contains("gateway.instagram.com")
            || host.contains("test-gateway.instagram.com")
    }

    private func isInstagramMessageHost(_ host: String, port: UInt16) -> Bool {
        if port == 5222, host.contains("instagram") {
            return true
        }
        return host.contains("mqtt") && host.contains("instagram")
    }

    private func isFacebookReelsMediaDomain(_ host: String) -> Bool {
        host.contains("fbcdn.net")
            || host.contains("fbvideo.net")
    }

    private func isFacebookReelsControlDomain(_ host: String) -> Bool {
        host.contains("graph.facebook.com")
            || host.contains("b-graph.facebook.com")
            || host.contains("api.facebook.com")
            || host.contains("m.facebook.com")
            || host.contains("www.facebook.com")
    }

    private func isFacebookMessageHost(_ host: String, port: UInt16) -> Bool {
        if port == 5222 {
            return true
        }
        return host.contains("edge-mqtt.facebook.com") || host.contains("mqtt")
    }

    private func reloadPolicyIfNeeded(force: Bool) {
        let now = Date()
        cleanupExpiredBlockedHosts(now: now)
        cleanupStormTracking(now: now)
        if didLoadPolicyForSession && !force {
            return
        }
        didLoadPolicyForSession = true

        var policySource = "cached"
        if let data = sharedDefaults?.data(forKey: BubbleConstants.featurePolicyKey) {
            if let decoded = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) {
                var merged = decoded
                merged.mergeDefaults()
                if strictUDPBlockEnabled {
                    merged.udpDecoderFailOpenEnabled = false
                    merged.udpDecodeMode = .strict
                }
                cachedPolicy = merged
                policySource = "featurePolicyV1"
            } else {
                TunnelLogger.shared.log("POLICY RELOAD: featurePolicyV1 decode failed; keeping cached policy")
            }
        } else {
            if force {
                cachedPolicy = .defaultPolicy()
                if strictUDPBlockEnabled {
                    cachedPolicy.udpDecoderFailOpenEnabled = false
                    cachedPolicy.udpDecodeMode = .strict
                }
                policySource = "default_policy"
            } else {
                TunnelLogger.shared.log("POLICY RELOAD: featurePolicyV1 missing; keeping cached policy")
            }
        }

        let instagramToggles = instagramToggleSnapshot()
        let facebookToggles = facebookToggleSnapshot()
        TunnelLogger.shared.log(
            "POLICY SNAPSHOT: instagram reels=\(instagramToggles["reels"] == true) facebook reels=\(facebookToggles["reels"] == true) " +
            "shadow=\(cachedPolicy.shadowModeEnabled) adaptive=\(cachedPolicy.adaptiveBackoffEnabled) udpFailOpen=\(cachedPolicy.udpDecoderFailOpenEnabled) " +
            "udpMode=\(cachedPolicy.udpDecodeMode.rawValue) breaker=\(cachedPolicy.udpCircuitBreakerThreshold)/\(cachedPolicy.udpCircuitBreakerWindowSec)s " +
            "cooldown=\(cachedPolicy.udpCircuitBreakerCooldownSec)s thermal=\(cachedPolicy.thermalGuardEnabled) " +
            "metaGuardIG=\(cachedPolicy.metaIpGuard.instagram.enabled) metaGuardFB=\(cachedPolicy.metaIpGuard.facebook.enabled) " +
            "igMode=\(cachedPolicy.reelsPolicy.instagramMode.rawValue) fbMode=\(cachedPolicy.reelsPolicy.facebookMode.rawValue) source=\(policySource)"
        )
    }

    private func isLikelyMetaIPAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        guard let a = Int(parts[0]), let b = Int(parts[1]) else { return false }
        return (a == 157 && b == 240) || (a == 163 && b == 70) || (a == 57 && b == 144) || (a == 31 && b == 13)
    }

    private func evaluateMetaIPFallback(host: String, appId: String, toggles: [String: Bool], reasonPrefix: String) -> PolicyDecision {
        let now = Date()
        let appHistory = recentMetaIPFallbackByHostByApp[appId] ?? [:]
        let elapsed = now.timeIntervalSince(appHistory[host] ?? .distantPast)
        var nextHistory = appHistory
        nextHistory[host] = now
        recentMetaIPFallbackByHostByApp[appId] = nextHistory
        let confidence = elapsed < metaIPFallbackWindowSec ? 0.70 : 0.90
        let reason = elapsed < metaIPFallbackWindowSec
            ? "\(reasonPrefix)_meta_ip_tls_guard_fallback_rate_limited"
            : "\(reasonPrefix)_meta_ip_tls_guard_block_now"
        return buildDecision(
            action: .blockNow,
            classification: FlowClassification(bucket: .reels, confidence: confidence, reasons: ["\(reasonPrefix)_meta_ip_tls_guard_fallback"]),
            reason: reason,
            toggles: toggles,
            host: host,
            intendedAction: nil
        )
    }

    private func shouldCooldownBlock(host: String) -> Bool {
        guard let blockedAt = recentBlockedHosts[host] else { return false }
        return Date().timeIntervalSince(blockedAt) <= blockedHostCooldown
    }

    private func recordRecentBlock(host: String) {
        recentBlockedHosts[host] = Date()
    }

    private func cleanupExpiredBlockedHosts(now: Date) {
        recentBlockedHosts = recentBlockedHosts.filter { _, blockedAt in
            now.timeIntervalSince(blockedAt) <= blockedHostCooldown
        }
    }

    private func cleanupStormTracking(now: Date) {
        let window = TimeInterval(max(cachedPolicy.retryStormWindowSec, 1))
        retryStormAttemptsByHost = retryStormAttemptsByHost
            .mapValues { attempts in attempts.filter { now.timeIntervalSince($0) <= window } }
            .filter { !$0.value.isEmpty }

        for (host, until) in backoffUntilByHost where until <= now {
            backoffUntilByHost.removeValue(forKey: host)
            backoffDurationSecByHost.removeValue(forKey: host)
            pendingBackoffExitHosts.insert(host)
        }
    }

    private func isAdaptiveBackoffActive(host: String, now: Date) -> Bool {
        guard cachedPolicy.adaptiveBackoffEnabled else { return false }
        cleanupStormTracking(now: now)
        guard let until = backoffUntilByHost[host] else { return false }
        return until > now
    }

    private func consumeBackoffExit(host: String, now: Date) -> Bool {
        guard cachedPolicy.adaptiveBackoffEnabled else { return false }
        cleanupStormTracking(now: now)
        guard pendingBackoffExitHosts.contains(host) else { return false }
        pendingBackoffExitHosts.remove(host)
        return true
    }

    private func registerControlPlaneBlock(host: String, now: Date) -> Bool {
        guard cachedPolicy.adaptiveBackoffEnabled else { return false }

        let threshold = max(cachedPolicy.retryStormThreshold, 1)
        let window = TimeInterval(max(cachedPolicy.retryStormWindowSec, 1))
        var attempts = retryStormAttemptsByHost[host] ?? []
        attempts = attempts.filter { now.timeIntervalSince($0) <= window }
        attempts.append(now)
        retryStormAttemptsByHost[host] = attempts

        guard attempts.count >= threshold else { return false }

        let previousBackoff = backoffDurationSecByHost[host] ?? TimeInterval(max(cachedPolicy.backoffMinSec, 1))
        let nextBackoff = min(TimeInterval(max(cachedPolicy.backoffMaxSec, cachedPolicy.backoffMinSec)), max(TimeInterval(max(cachedPolicy.backoffMinSec, 1)), previousBackoff * 2))
        let firstBackoff = backoffDurationSecByHost[host] == nil
            ? TimeInterval(max(cachedPolicy.backoffMinSec, 1))
            : nextBackoff
        backoffDurationSecByHost[host] = firstBackoff
        backoffUntilByHost[host] = now.addingTimeInterval(firstBackoff)
        retryStormAttemptsByHost[host] = []
        retryStormEventsCount += 1
        return true
    }
}
