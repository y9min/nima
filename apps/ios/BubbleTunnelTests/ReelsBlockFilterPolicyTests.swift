import XCTest
import Darwin

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

    // Policy baseline: reels media block criteria must not regress.
    func testPolicyBaselineReelsOnConfidentVideoHostBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "reels-video-lhr8-1.cdninstagram.com",
            sni: "reels-video-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_media_block_now")
    }

    func testPolicyBaselineReelsOffConfidentVideoHostAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "reels-video-lhr8-1.cdninstagram.com",
            sni: "reels-video-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "reels_toggle_off")
        XCTAssertEqual(decision.trafficClass, .instagram)
    }

    func testReelsOnEssentialControlAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let iDecision = filter.evaluateStream(
            host: "i.instagram.com",
            sni: "i.instagram.com",
            port: 443,
            bytesDown: 4_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )
        XCTAssertEqual(iDecision.action, .allow)
        XCTAssertEqual(iDecision.reason, "instagram_control_allow")

        let testGatewayDecision = filter.evaluateStream(
            host: "test-gateway.instagram.com",
            sni: "test-gateway.instagram.com",
            port: 443,
            bytesDown: 4_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )
        XCTAssertEqual(testGatewayDecision.action, .allow)
        XCTAssertEqual(testGatewayDecision.reason, "instagram_control_allow")
    }

    func testReelsOnGatewayControlAllowsDMs() {
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

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "instagram_control_allow")
    }

    func testReelsOnProfileSearchAndLoginAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["www.instagram.com", "accounts.instagram.com", "accountscenter.instagram.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 4_000,
                connectionAge: 0.3,
                parallelConnections: 2
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "instagram_control_allow", host)
            XCTAssertEqual(decision.trafficClass, .instagram, host)
        }
    }

    func testReelsOnMessagesAlwaysAllowed() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateConnection(host: "edge-mqtt.facebook.com", port: 443)

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "messages_allow")
        XCTAssertEqual(decision.classification.bucket, .messages)
    }

    func testReelsOffAllowsInstagramHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let mediaDecision = filter.evaluateStream(
            host: "reels-video-lhr8-1.cdninstagram.com",
            sni: "reels-video-lhr8-1.cdninstagram.com",
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

    func testStrictReelsBlocksAmbiguousInstagramCDNAndAllowsBroadMetaCDN() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let ambiguous = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1
        )
        XCTAssertEqual(ambiguous.action, .blockNow)
        XCTAssertEqual(ambiguous.reason, "reels_strict_media_block_now")

        for host in ["static.xx.fbcdn.net", "unknown.cdninstagram.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 2
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "unknown_meta_default_allow", host)
        }
    }

    func testLegacyReelsToggleMigratesToStrictReelsBehavior() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        let filter = makeFilter(policy: policy)
        let host = "scontent-lhr8-1.cdninstagram.com"

        let decision = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_strict_media_block_now")
        XCTAssertEqual(decision.toggleSnapshot["strict_reels"], true)
        XCTAssertEqual(decision.toggleSnapshot["reels"], false)
    }

    func testStrictReelsBlocksAmbiguousInstagramCDNAtConnectionStart() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)
        let host = "scontent-lhr8-1.cdninstagram.com"

        let decision = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_strict_media_block_now")
        XCTAssertEqual(decision.classification.bucket, .reels)
        XCTAssertEqual(decision.trafficClass, .instagram)
    }

    func testStrictReelsStillAllowsControlAndAvoidsDirectIPAndBroadFBCDN() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let control = filter.evaluateStream(
            host: "gateway.instagram.com",
            sni: "gateway.instagram.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        let directIP = filter.evaluateStream(
            host: "157.240.214.63",
            sni: nil,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        let fbcdn = filter.evaluateStream(
            host: "scontent-lhr8-1.fbcdn.net",
            sni: "scontent-lhr8-1.fbcdn.net",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )

        XCTAssertEqual(control.action, .allow)
        XCTAssertEqual(control.reason, "instagram_control_allow")
        XCTAssertEqual(directIP.action, .allow)
        XCTAssertEqual(directIP.reason, "non_instagram_traffic")
        XCTAssertEqual(fbcdn.action, .allow)
        XCTAssertEqual(fbcdn.reason, "unknown_meta_default_allow")
    }

    func testStrictReelsBlocksLargeInstagramFNAFBCDNMediaGuard() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)
        let host = "instagram.flhr13-1.fna.fbcdn.net"
        let now = Date(timeIntervalSince1970: 40_000)

        let initial = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1,
            now: now
        )
        let largeMedia = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 1_000_000,
            connectionAge: 1.0,
            parallelConnections: 1,
            now: now.addingTimeInterval(1)
        )
        let cached = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1,
            now: now.addingTimeInterval(2)
        )

        XCTAssertEqual(initial.action, .allow)
        XCTAssertEqual(initial.reason, "unknown_meta_default_allow")
        XCTAssertEqual(largeMedia.action, .blockNow)
        XCTAssertEqual(largeMedia.reason, "reels_media_block_now")
        XCTAssertEqual(largeMedia.classification.bucket, .reels)
        XCTAssertTrue(largeMedia.classification.reasons.contains("strict_unknown_meta_large_media"))
        XCTAssertEqual(cached.action, .blockNow)
        XCTAssertEqual(cached.reason, "reels_media_block_now")
        XCTAssertTrue(cached.classification.reasons.contains("strict_suspect_host_cache"))
    }

    func testStrictReelsMediaGuardBlocksInstagramFNABurst() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)
        let host = "instagram.flhr13-1.fna.fbcdn.net"
        let now = Date(timeIntervalSince1970: 50_000)

        for index in 0..<3 {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 0,
                connectionAge: 0,
                parallelConnections: 1,
                now: now.addingTimeInterval(TimeInterval(index))
            )
            XCTAssertEqual(decision.action, .allow, "observation \(index)")
            XCTAssertEqual(decision.reason, "unknown_meta_default_allow", "observation \(index)")
        }

        let burst = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1,
            now: now.addingTimeInterval(3)
        )

        XCTAssertEqual(burst.action, .blockNow)
        XCTAssertEqual(burst.reason, "reels_media_block_now")
        XCTAssertTrue(burst.classification.reasons.contains("strict_unknown_meta_burst_media"))
    }

    func testStrictReelsMediaGuardBlocksInstagramFNAQUIC() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateUDP(
            host: "instagram.flhr13-1.fna.fbcdn.net",
            port: 443,
            payloadBytes: 1_200
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "reels_media_block_now")
        XCTAssertTrue(decision.classification.reasons.contains("strict_unknown_meta_quic_media"))
    }

    func testStrictReelsAllowsControlHostsEvenWithLargeTransfers() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["i.instagram.com", "gateway.instagram.com", "edge-mqtt.facebook.com", "api.facebook.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 2_000_000,
                connectionAge: 1.0,
                parallelConnections: 4
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertTrue(["instagram_control_allow", "messages_allow"].contains(decision.reason), host)
        }
    }

    func testReelsOffDisablesAmbiguousMediaBlocksAndHints() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        let filter = makeFilter(policy: policy)
        let now = Date(timeIntervalSince1970: 30_000)
        let host = "scontent-lhr8-1.cdninstagram.com"
        let largeDecision = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold + 1,
            connectionAge: 1.0,
            parallelConnections: 2,
            now: now
        )
        let blockedDecision = PolicyDecision(
            action: .blockNow,
            blockAfterBytes: nil,
            classification: FlowClassification(bucket: .reels, confidence: 0.62, reasons: ["ambiguous_instagram_media_cdn_large_stream"]),
            reason: "reels_media_block_now",
            toggleSnapshot: ["reels": true],
            policyVersion: 1,
            intendedAction: nil,
            appStrategy: AppTransportStrategy.legacyReels.rawValue,
            trafficClass: .instagram
        )

        filter.recordBlockedStream(
            host: "157.240.214.63",
            sni: host,
            port: 443,
            decision: blockedDecision,
            bytesDown: BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold + 1,
            now: now
        )
        let hintedDecision = filter.evaluateStream(
            host: "157.240.214.63",
            sni: host,
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 1,
            now: now.addingTimeInterval(1)
        )
        let counters = filter.instagramMediaHintCounterSnapshot(now: now.addingTimeInterval(1))

        XCTAssertEqual(largeDecision.action, .allow)
        XCTAssertEqual(largeDecision.reason, "reels_toggle_off")
        XCTAssertEqual(hintedDecision.action, .allow)
        XCTAssertEqual(hintedDecision.reason, "reels_toggle_off")
        XCTAssertEqual(counters.added, 0)
        XCTAssertEqual(counters.blocks, 0)
    }

    func testLargeDirectIPAndBroadFBCDNDoNotBlockFromSizeAlone() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let directIPDecision = filter.evaluateStream(
            host: "157.240.214.63",
            sni: nil,
            port: 443,
            bytesDown: BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold + 1,
            connectionAge: 1.0,
            parallelConnections: 2
        )
        let fbcdnDecision = filter.evaluateStream(
            host: "scontent-lhr8-1.fbcdn.net",
            sni: "scontent-lhr8-1.fbcdn.net",
            port: 443,
            bytesDown: BubbleConstants.instagramAmbiguousMediaStreamBlockThreshold + 1,
            connectionAge: 1.0,
            parallelConnections: 2
        )

        XCTAssertEqual(directIPDecision.action, .allow)
        XCTAssertEqual(directIPDecision.reason, "non_instagram_traffic")
        XCTAssertEqual(fbcdnDecision.action, .allow)
        XCTAssertEqual(fbcdnDecision.reason, "unknown_meta_default_allow")
    }

    func testTikTokVideoBlockOnMediaHostBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "v16.tiktokcdn-us.com",
            sni: "v16.tiktokcdn-us.com",
            port: 443,
            bytesDown: 5_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "tiktok_video_block_now")
        XCTAssertEqual(decision.classification.bucket, .tiktokVideo)
        XCTAssertEqual(decision.trafficClass, .tiktok)
    }

    func testTikTokVideoBlockOnByteCDNSNIBlocksNow() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "203.0.113.44",
            sni: "lf16-video.bytecdn.com",
            port: 443,
            bytesDown: 5_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "tiktok_video_block_now")
        XCTAssertEqual(decision.classification.bucket, .tiktokVideo)
    }

    func testTikTokVideoBlockCoversTikTokVEU() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let video = filter.evaluateStream(
            host: "v19.tiktokv.eu",
            sni: "v19.tiktokv.eu",
            port: 443,
            bytesDown: 5_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )
        XCTAssertEqual(video.action, .blockNow)
        XCTAssertEqual(video.reason, "tiktok_video_block_now")

        let control = filter.evaluateStream(
            host: "api.tiktokv.eu",
            sni: "api.tiktokv.eu",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )
        XCTAssertEqual(control.action, .allow)
        XCTAssertEqual(control.reason, "tiktok_messages_allow")
    }

    func testTikTokMediaGuardBlocksLargeUnknownMusCDNMedia() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)
        let host = "lf16-muscdn.example.net"

        let decision = filter.evaluateStream(
            host: host,
            sni: host,
            port: 443,
            bytesDown: 1_000_000,
            connectionAge: 1.0,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "tiktok_video_block_now")
        XCTAssertEqual(decision.classification.bucket, .tiktokVideo)
        XCTAssertTrue(decision.classification.reasons.contains("strict_unknown_tiktok_large_media"))
    }

    func testTikTokMediaGuardBlocksUnknownMusCDNQUIC() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateUDP(
            host: "lf16-muscdn.example.net",
            port: 443,
            payloadBytes: 1_200
        )

        XCTAssertEqual(decision.action, .blockNow)
        XCTAssertEqual(decision.reason, "tiktok_video_block_now")
        XCTAssertTrue(decision.classification.reasons.contains("strict_unknown_tiktok_quic_media"))
    }

    func testTikTokVideoBlockOnControlHostAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "api16-normal-c-useast1a.tiktokv.com",
            sni: "api16-normal-c-useast1a.tiktokv.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "tiktok_messages_allow")
        XCTAssertEqual(decision.classification.bucket, .tiktokControl)
        XCTAssertEqual(decision.trafficClass, .tiktok)
    }

    func testTikTokVideoBlockOnSearchProfileAndMessagesAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["www.tiktok.com", "search.tiktok.com", "im.tiktok.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "tiktok_messages_allow", host)
            XCTAssertEqual(decision.trafficClass, .tiktok, host)
        }
    }

    func testTikTokVideoBlockOffAllowsTikTokMedia() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "v16.tiktokcdn-us.com",
            sni: "v16.tiktokcdn-us.com",
            port: 443,
            bytesDown: 4_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "tiktok_video_toggle_off")
    }

    func testTikTokVideoBlockDoesNotCatchGenericAkamai() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["cdn.example.akamaized.net", "d111111abcdef8.cloudfront.net"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 4_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertNotEqual(decision.reason, "tiktok_video_block_now", host)
            XCTAssertEqual(decision.trafficClass, .generic, host)
        }
    }

    func testTikTokVideoBlockDoesNotCatchSafariOrWhatsAppDomains() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["web.whatsapp.com", "apple.com", "google.com", "cloudflare.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 4_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertNotEqual(decision.reason, "tiktok_video_block_now", host)
            XCTAssertEqual(decision.trafficClass, .generic, host)
        }
    }

    func testEarlySNIGateOnlyBlocksConfirmedTikTokVideo() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let video = filter.evaluateStream(
            host: "96.17.179.153",
            sni: "sf16-ies-music-va.tiktokcdn.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertTrue(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(video))

        var reelsPolicy = FeaturePolicyV1.defaultPolicy()
        reelsPolicy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let reelsFilter = makeFilter(policy: reelsPolicy)
        let reels = reelsFilter.evaluateStream(
            host: "157.240.22.63",
            sni: "reels-video-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertTrue(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(reels))

        let ambiguousInstagramCDN = reelsFilter.evaluateStream(
            host: "157.240.22.63",
            sni: "scontent-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertTrue(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(ambiguousInstagramCDN))

        let control = filter.evaluateStream(
            host: "96.17.179.153",
            sni: "api16-normal-c-useast1a.tiktokv.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertFalse(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(control))

        let generic = filter.evaluateStream(
            host: "93.184.216.34",
            sni: "web.whatsapp.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertFalse(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(generic))

        var offPolicy = FeaturePolicyV1.defaultPolicy()
        offPolicy.set(appId: "tiktok", optionId: "video_block", isEnabled: false)
        let offFilter = makeFilter(policy: offPolicy)
        let disabled = offFilter.evaluateStream(
            host: "96.17.179.153",
            sni: "sf16-ies-music-va.tiktokcdn.com",
            port: 443,
            bytesDown: 0,
            connectionAge: 0,
            parallelConnections: 0
        )
        XCTAssertFalse(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(disabled))
    }

    func testPolicyRevisionRegressionDoesNotDisableTikTokBlock() {
        let suite = makeSuiteName()
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)

        var newer = FeaturePolicyV1.defaultPolicy()
        newer.revision = 2
        newer.updatedBy = "test.newer"
        newer.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        defaults?.set(try? JSONEncoder().encode(newer), forKey: BubbleConstants.featurePolicyKey)

        let filter = ReelsBlockFilter(sharedDefaults: defaults)
        let initial = filter.evaluateStream(
            host: "sf16-teko.tiktokcdn-eu.com",
            sni: "sf16-teko.tiktokcdn-eu.com",
            port: 443,
            bytesDown: 2_000,
            connectionAge: 0.1,
            parallelConnections: 1
        )
        XCTAssertEqual(initial.action, .blockNow)

        var stale = FeaturePolicyV1.defaultPolicy()
        stale.revision = 1
        stale.updatedBy = "test.stale"
        stale.set(appId: "tiktok", optionId: "video_block", isEnabled: false)
        defaults?.set(try? JSONEncoder().encode(stale), forKey: BubbleConstants.featurePolicyKey)

        usleep(1_200_000) // exceed policy reload interval
        let afterStaleWrite = filter.evaluateStream(
            host: "sf16-teko.tiktokcdn-eu.com",
            sni: "sf16-teko.tiktokcdn-eu.com",
            port: 443,
            bytesDown: 2_000,
            connectionAge: 0.1,
            parallelConnections: 1
        )
        XCTAssertEqual(afterStaleWrite.action, .blockNow)
        XCTAssertEqual(afterStaleWrite.reason, "tiktok_video_block_now")
    }

    func testMergeDefaultsAddsXFeedBlockDisabled() {
        var policy = FeaturePolicyV1(
            appToggles: [
                "instagram": ["strict_reels": false],
                "tiktok": ["video_block": false]
            ],
            appStrategies: [
                "instagram": .legacyReels,
                "tiktok": .hardenedVideo
            ]
        )

        policy.mergeDefaults()

        XCTAssertEqual(policy.appToggles["x"]?["feed_block"], false)
        XCTAssertEqual(policy.appToggles["x"]?["strict_feed_block"], false)
        XCTAssertEqual(policy.appStrategies["x"], .dmPreservingFeed)
    }

    func testXFeedBlockOffAllowsXMediaAndSharedAPIHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: false)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: false)
        let filter = makeFilter(policy: policy)

        let hostsAndBuckets: [(String, ContentBucket)] = [
            ("api.twitter.com", .xFeedAPI),
            ("api.x.com", .xFeedAPI),
            ("pbs.twimg.com", .xFeedMedia),
            ("video.twimg.com", .xFeedMedia)
        ]

        for (host, bucket) in hostsAndBuckets {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 5_000,
                connectionAge: 0.2,
                parallelConnections: 2
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "x_feed_toggle_off", host)
            XCTAssertEqual(decision.classification.bucket, bucket, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
        }
    }

    func testXFeedBlockBlocksFeedAndMediaHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["x.com", "twitter.com", "abs.twimg.com", "pbs.twimg.com", "video.twimg.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 5_000,
                connectionAge: 0.2,
                parallelConnections: 2
            )

            XCTAssertEqual(decision.action, .blockNow, host)
            XCTAssertEqual(decision.reason, "x_feed_media_block_now", host)
            XCTAssertEqual(decision.classification.bucket, .xFeedMedia, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
            XCTAssertTrue(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(decision), host)
        }
    }

    func testXFeedBlockAllowsDMAndControlHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: false)
        let filter = makeFilter(policy: policy)

        for host in [
            "chat-ws.x.com",
            "realm-west1.x.com",
            "realm-east1.x.com",
            "realm-b.x.com",
            "api-stream.twitter.com",
            "probe.twitter.com"
        ] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "x_control_allow", host)
            XCTAssertEqual(decision.classification.bucket, .xControl, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
        }
    }

    func testXFeedBlockAllowsSharedAPIHostsWhenStrictIsOff() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: false)
        let filter = makeFilter(policy: policy)

        for host in ["api.x.com", "api.twitter.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "x_control_allow", host)
            XCTAssertEqual(decision.classification.bucket, .xFeedAPI, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
        }
    }

    func testXStrictFeedBlockBlocksSharedAPIHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in ["api.x.com", "api.twitter.com"] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .blockNow, host)
            XCTAssertEqual(decision.reason, "x_strict_feed_api_block_now", host)
            XCTAssertEqual(decision.classification.bucket, .xFeedAPI, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
            XCTAssertTrue(SOCKSProxyServer.shouldEarlyBlockFromSNIDecision(decision), host)
        }
    }

    func testXStrictFeedBlockWorksWhenFeedBlockIsOff() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: false)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let apiDecision = filter.evaluateStream(
            host: "api.twitter.com",
            sni: "api.twitter.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )
        XCTAssertEqual(apiDecision.action, .blockNow)
        XCTAssertEqual(apiDecision.reason, "x_strict_feed_api_block_now")
        XCTAssertEqual(apiDecision.classification.bucket, .xFeedAPI)

        let mediaDecision = filter.evaluateStream(
            host: "video.twimg.com",
            sni: "video.twimg.com",
            port: 443,
            bytesDown: 5_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )
        XCTAssertEqual(mediaDecision.action, .blockNow)
        XCTAssertEqual(mediaDecision.reason, "x_feed_media_block_now")
        XCTAssertEqual(mediaDecision.classification.bucket, .xFeedMedia)
    }

    func testXStrictFeedBlockAllowsPreservedDMAndControlHosts() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        for host in [
            "chat-ws.x.com",
            "realm-west1.x.com",
            "realm-east1.x.com",
            "realm-b.x.com",
            "api-stream.twitter.com",
            "probe.twitter.com"
        ] {
            let decision = filter.evaluateStream(
                host: host,
                sni: host,
                port: 443,
                bytesDown: 3_000,
                connectionAge: 0.2,
                parallelConnections: 1
            )

            XCTAssertEqual(decision.action, .allow, host)
            XCTAssertEqual(decision.reason, "x_control_allow", host)
            XCTAssertEqual(decision.classification.bucket, .xControl, host)
            XCTAssertEqual(decision.trafficClass, .x, host)
        }
    }

    func testXFeedBlockAllowsUnknownXHostByDefault() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let decision = filter.evaluateStream(
            host: "help.x.com",
            sni: "help.x.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 1
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, "unknown_x_default_allow")
    }

    func testInstagramBehaviorInvariantForMediaAndControl() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let media = filter.evaluateStream(
            host: "reels-video-lhr8-1.cdninstagram.com",
            sni: "reels-video-lhr8-1.cdninstagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )
        XCTAssertEqual(media.action, .blockNow)
        XCTAssertEqual(media.reason, "reels_media_block_now")

        let control = filter.evaluateStream(
            host: "gateway.instagram.com",
            sni: "gateway.instagram.com",
            port: 443,
            bytesDown: 3_000,
            connectionAge: 0.2,
            parallelConnections: 2
        )
        XCTAssertEqual(control.action, .allow)
        XCTAssertEqual(control.reason, "instagram_control_allow")
    }

    func testTunnelProtectionStateManualBlockerKeepsVPNRunningWithoutActiveSchedule() {
        let now = testDate(hour: 12)
        var manualPolicy = FeaturePolicyV1.defaultPolicy()
        manualPolicy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let defaults = makeProtectionDefaults(manualPolicy: manualPolicy)

        XCTAssertTrue(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStateFallsBackToEffectivePolicyWhenManualPolicyIsMissing() {
        let now = testDate(hour: 12)
        var effectivePolicy = FeaturePolicyV1.defaultPolicy()
        effectivePolicy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
        let defaults = makeProtectionDefaults(manualPolicy: nil)
        defaults?.set(try? JSONEncoder().encode(effectivePolicy), forKey: BubbleConstants.featurePolicyKey)

        XCTAssertTrue(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStateActiveScheduledBlockerKeepsVPNRunning() {
        let now = testDate(hour: 12)
        let defaults = makeProtectionDefaults(windows: [
            testWindow(id: "tw_focus", startTime: "09:00", endTime: "17:00", apps: ["instagram", "tiktok"])
        ])

        XCTAssertTrue(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStateEndedScheduledBlockerAllowsVPNStop() {
        let now = testDate(hour: 12)
        let defaults = makeProtectionDefaults(windows: [
            testWindow(id: "tw_focus", startTime: "09:00", endTime: "10:00", apps: ["instagram"])
        ])

        XCTAssertFalse(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStateEndedWindowOverrideAllowsVPNStop() {
        let now = testDate(hour: 12)
        let endDate = testDate(hour: 17)
        let defaults = makeProtectionDefaults(
            windows: [
                testWindow(id: "tw_focus", startTime: "09:00", endTime: "17:00", apps: ["instagram"])
            ],
            endedWindowUntilByID: ["tw_focus": endDate]
        )

        XCTAssertFalse(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStateOverlappingActiveWindowKeepsVPNRunning() {
        let now = testDate(hour: 12)
        let endDate = testDate(hour: 17)
        let defaults = makeProtectionDefaults(
            windows: [
                testWindow(id: "tw_ended", startTime: "09:00", endTime: "17:00", apps: ["instagram"]),
                testWindow(id: "tw_active", startTime: "11:00", endTime: "13:00", apps: ["tiktok"])
            ],
            endedWindowUntilByID: ["tw_ended": endDate]
        )

        XCTAssertTrue(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    func testTunnelProtectionStatePauseAllPreventsScheduleFromKeepingVPNRunning() {
        let now = testDate(hour: 12)
        let defaults = makeProtectionDefaults(
            windows: [
                testWindow(id: "tw_focus", startTime: "09:00", endTime: "17:00", apps: ["instagram"])
            ],
            pauseAll: true
        )

        XCTAssertFalse(TunnelProtectionState(defaults: defaults).shouldKeepVPNRunning(now: now, calendar: testCalendar))
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDate(hour: Int, minute: Int = 0) -> Date {
        DateComponents(
            calendar: testCalendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 6,
            day: 1,
            hour: hour,
            minute: minute
        ).date!
    }

    private func testWindow(
        id: String,
        startTime: String,
        endTime: String,
        apps: [String]
    ) -> TimeWindow {
        TimeWindow(
            id: id,
            name: "Focus",
            emoji: "",
            startTime: startTime,
            endTime: endTime,
            repeatDays: [.monday],
            apps: apps,
            enabled: true,
            createdAt: testDate(hour: 8),
            updatedAt: testDate(hour: 8)
        )
    }

    private func makeProtectionDefaults(
        manualPolicy: FeaturePolicyV1? = FeaturePolicyV1.defaultPolicy(),
        windows: [TimeWindow] = [],
        pauseAll: Bool = false,
        endedWindowUntilByID: [String: Date] = [:]
    ) -> UserDefaults? {
        let suite = makeSuiteName()
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        if let manualPolicy {
            defaults?.set(try? JSONEncoder().encode(manualPolicy), forKey: BubbleConstants.manualFeaturePolicyKey)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults?.set(try? encoder.encode(windows), forKey: BubbleConstants.timeWindowsKey)
        defaults?.set(pauseAll, forKey: BubbleConstants.timeWindowsPauseAllKey)

        let endedTimestamps = endedWindowUntilByID.mapValues(\.timeIntervalSince1970)
        if !endedTimestamps.isEmpty {
            defaults?.set(endedTimestamps, forKey: BubbleConstants.timeWindowsEndedUntilKey)
        }
        return defaults
    }
}
