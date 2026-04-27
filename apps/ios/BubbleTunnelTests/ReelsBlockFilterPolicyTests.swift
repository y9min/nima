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
}
