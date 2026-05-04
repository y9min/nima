import XCTest
import Darwin
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

    // Policy baseline: reels media block criteria must not regress.
    func testPolicyBaselineReelsOnMediaHostBlocksNow() {
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

    func testPolicyBaselineReelsOffMediaHostAllows() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
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
        XCTAssertEqual(iDecision.reason, "essential_control_allow")

        let testGatewayDecision = filter.evaluateStream(
            host: "test-gateway.instagram.com",
            sni: "test-gateway.instagram.com",
            port: 443,
            bytesDown: 4_000,
            connectionAge: 0.3,
            parallelConnections: 2
        )
        XCTAssertEqual(testGatewayDecision.action, .allow)
        XCTAssertEqual(testGatewayDecision.reason, "essential_control_allow")
    }

    func testReelsOnNonEssentialControlStillBlocks() {
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

    func testInstagramBehaviorInvariantForMediaAndControl() {
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "instagram", optionId: "reels", isEnabled: true)
        policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        let filter = makeFilter(policy: policy)

        let media = filter.evaluateStream(
            host: "scontent-lhr8-1.cdninstagram.com",
            sni: "scontent-lhr8-1.cdninstagram.com",
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
        XCTAssertEqual(control.action, .blockNow)
        XCTAssertEqual(control.reason, "reels_control_block_now")
    }
}
