import XCTest
@testable import BubbleTunnel

final class ReelsBlockFilterPolicyTests: XCTestCase {

    private func makeSuiteName() -> String {
        "test.reels.filter.\(UUID().uuidString)"
    }

    private func makeFilter(policy: FeaturePolicyV1) -> ReelsBlockFilter {
        let suite = makeSuiteName()
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
        return ReelsBlockFilter(sharedDefaults: defaults)
    }

    func testReelsOnMediaHostBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_media_block_now")
    }

    func testReelsOnControlPlaneBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "gateway.instagram.com",
            sni: "gateway.instagram.com",
            port: 443,
            bytesDown: 4_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_control_block_now")
    }

    func testInstagramFallbackControlPlaneBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "i-fallback.instagram.com",
            sni: "i-fallback.instagram.com",
            port: 443,
            bytesDown: 2_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_control_block_now")
    }

    func testReelsOffAllowsInstagramHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let mediaDecision = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )
        XCTAssertEqual(mediaDecision.action, .allow)
        XCTAssertEqual(mediaDecision.reason, "reels_toggle_off")

        let controlDecision = filter.evaluateStream(
            host: "i.instagram.com",
            sni: "i.instagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )
        XCTAssertEqual(controlDecision.action, .allow)
        XCTAssertEqual(controlDecision.reason, "reels_toggle_off")
    }

    func testFacebookReelsMediaBlocksNowWhenEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "video.xx.fbcdn.net",
            sni: "video.xx.fbcdn.net",
            port: 443,
            bytesDown: 2_500,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "facebook_early_media_block_now")
    }

    func testFacebookReelsControlBlocksNowWhenEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "graph.facebook.com",
            sni: "graph.facebook.com",
            port: 443,
            bytesDown: 2_500,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "facebook_reels_control_block_now")
    }

    func testInstagramControlPlaneAlwaysUsesLegacyBlockReason() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for _ in 0..<policy.retryStormThreshold + 2 {
            let decision = filter.evaluateStream(
                host: "gateway.instagram.com",
                sni: "gateway.instagram.com",
                port: 443,
                bytesDown: 128,
                connectionAge: 0.05,
                parallelConnections: 1
            )
            XCTAssertEqual(decision.action, .blockNow)
            XCTAssertEqual(decision.reason, "reels_control_block_now")
        }

        let mediaStillBlocked = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 2_000,
            connectionAge: 0.05,
            parallelConnections: 1
        )
        XCTAssertEqual(mediaStillBlocked.action, .blockNow)
        XCTAssertEqual(mediaStillBlocked.reason, "reels_media_block_now")
    }

    func testInstagramMessagingHostAllowedWhenReelsEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "mqtt.instagram.com", port: 443)
        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "messages_allow")
        XCTAssertEqual(decision.classification.bucket, .messages)
    }

    func testFacebookRetryStormEntersBackoffAndBlocksControlPlane() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        var enteredBackoff = false
        for _ in 0..<policy.retryStormThreshold {
            let decision = filter.evaluateStream(
                host: "graph.facebook.com",
                sni: "graph.facebook.com",
                port: 443,
                bytesDown: 256,
                connectionAge: 0.05,
                parallelConnections: 1
            )
            if decision.reason == "retry_storm_enter" {
                enteredBackoff = true
            }
        }

        XCTAssertTrue(enteredBackoff)
        let duringBackoff = filter.evaluateStream(
            host: "graph.facebook.com",
            sni: "graph.facebook.com",
            port: 443,
            bytesDown: 256,
            connectionAge: 0.05,
            parallelConnections: 1
        )
        XCTAssertEqual(duringBackoff.action, .blockNow)
        XCTAssertEqual(duringBackoff.reason, "retry_storm_cooldown_block")

        let mediaStillBlocked = filter.evaluateStream(
            host: "video.xx.fbcdn.net",
            sni: "video.xx.fbcdn.net",
            port: 443,
            bytesDown: 2_500,
            connectionAge: 0.05,
            parallelConnections: 1
        )
        XCTAssertEqual(mediaStillBlocked.action, .blockNow)
        XCTAssertEqual(mediaStillBlocked.reason, "facebook_early_media_block_now")
    }

    func testFacebookReelsShadowAllowWhenShadowModeEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        policy.shadowModeEnabled = true
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "video.xx.fbcdn.net",
            sni: "video.xx.fbcdn.net",
            port: 443,
            bytesDown: 2_500,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .shadowAllow)
        XCTAssertEqual(decision.intendedAction, .blockNow)
        XCTAssertEqual(decision.reason, "facebook_reels_media_shadow")
    }

    func testFacebookMessagingHostsAlwaysAllowed() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "edge-mqtt.facebook.com", port: 443)

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "facebook_messages_allow")
        XCTAssertEqual(decision.classification.bucket, .messages)
    }

    func testUnknownFacebookHostsAllowUnderLowCollateralMode() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "edge-z-mystery.facebook.com", port: 443)

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "facebook_unknown_allow")
        XCTAssertEqual(decision.classification.bucket, .unknown)
    }

    func testSessionPolicyIsLockedUntilReconnect() {
        let suite = makeSuiteName()
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)

        var initial = FeaturePolicyV1.defaultPolicy()
        initial.set(appId: "facebook", optionId: "reels", isEnabled: false)
        if let data = try? JSONEncoder().encode(initial) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
        let filter = ReelsBlockFilter(sharedDefaults: defaults)

        var changed = initial
        changed.set(appId: "facebook", optionId: "reels", isEnabled: true)
        if let data = try? JSONEncoder().encode(changed) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }

        let decision = filter.evaluateStream(
            host: "graph.facebook.com",
            sni: "graph.facebook.com",
            port: 443,
            bytesDown: 500,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "facebook_reels_toggle_off")
    }

    func testEarlyTLSDecisionBlocksFacebookControlWhenEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateEarlyTLS(host: "157.240.214.1", sni: "graph.facebook.com", port: 443)
        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "facebook_reels_control_block_now")
    }

    func testMetaIPGuardBlocksWhenFacebookReelsEnabled() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "157.240.225.63", port: 443)
        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "facebook_meta_ip_tls_guard_block_now")
    }

    func testMessageTransportAlwaysAllowedBeforeMetaFallback() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "31.13.65.50", port: 5222)
        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "messages_allow")
        XCTAssertEqual(decision.classification.bucket, .messages)
    }

    func testRuntimePolicyDefaultsToAdaptiveDecode() {
        let filter = makeFilter(policy: .defaultPolicy())
        let runtime = filter.runtimePolicy()
        XCTAssertEqual(runtime.udpDecodeMode, .adaptive)
        XCTAssertEqual(runtime.udpCircuitBreakerThreshold, 3)
        XCTAssertEqual(runtime.udpCircuitBreakerWindowSec, 5)
        XCTAssertEqual(runtime.udpCircuitBreakerCooldownSec, 20)
        XCTAssertEqual(runtime.quicHandling, .classifyOnly)
        XCTAssertEqual(runtime.metaIPGuardMode, .fallbackOnly)
        XCTAssertTrue(runtime.thermalGuardEnabled)
    }

    func testInstagramToggleDoesNotBlockFacebookHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "video.xx.fbcdn.net",
            sni: "video.xx.fbcdn.net",
            port: 443,
            bytesDown: 2_500,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "facebook_reels_toggle_off")
    }

    func testInstagramMetaIPFallbackDisabledInLegacyModeByDefault() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "157.240.225.63", port: 443)
        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "policy_allow")
    }

    func testInstagramSharedMetaCdnBlockedWhenFacebookReelsOff() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "video.xx.fbcdn.net",
            sni: "video.xx.fbcdn.net",
            port: 443,
            bytesDown: 2_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_media_block_now")
    }

    func testFacebookMetaIPFallbackStillWorksWhenFacebookReelsOn() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "157.240.225.63", port: 443)
        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertTrue(decision.reason.hasPrefix("facebook_meta_ip_tls_guard_"))
    }

    func testFacebookToggleDoesNotChangeInstagramBehavior() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        policy.set(appId: "facebook", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "reels_toggle_off")
    }
}
