import XCTest
@testable import Nima

final class TikTokNavigationPolicyTests: XCTestCase {
    func testDMOnlyAllowsMessagesButBlocksNotificationsAndOtherSurfaces() {
        for rawURL in [
            "https://www.tiktok.com/inbox",
            "https://www.tiktok.com/following",
            "https://www.tiktok.com/friends",
            "https://www.tiktok.com/search?q=nima",
            "https://www.tiktok.com/profile",
            "https://www.tiktok.com/@nima",
            "https://www.tiktok.com/setting",
        ] {
            XCTAssertEqual(
                TikTokNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: TikTokNavigationPolicy.messagesURL,
                    mode: .dmOnly
                ),
                .block,
                rawURL
            )
        }
        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: TikTokNavigationPolicy.messagesURL,
                sourceURL: TikTokNavigationPolicy.messagesURL,
                mode: .dmOnly
            ),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: TikTokNavigationPolicy.loginURL,
                sourceURL: TikTokNavigationPolicy.messagesURL,
                mode: .dmOnly
            ),
            .allow
        )
    }

    func testDMOnlyGrantsOnlyTheSelectedConversationVideoOrProfile() {
        let video = URL(string: "https://www.tiktok.com/@nima/video/123")!
        let otherVideo = URL(string: "https://www.tiktok.com/@nima/video/456")!
        let profile = URL(string: "https://www.tiktok.com/@nima")!
        let otherProfile = URL(string: "https://www.tiktok.com/@other")!
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: video, sourceURL: TikTokNavigationPolicy.messagesURL, mode: .dmOnly),
            .block
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: video, sourceURL: TikTokNavigationPolicy.messagesURL,
                                          grantedVideoURL: video, mode: .dmOnly),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: otherVideo, sourceURL: video,
                                          grantedVideoURL: video, mode: .dmOnly),
            .block
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: profile, sourceURL: TikTokNavigationPolicy.messagesURL,
                                          mode: .dmOnly, grantedProfileURL: profile),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: otherProfile, sourceURL: profile,
                                          mode: .dmOnly, grantedProfileURL: profile),
            .block
        )
    }

    func testForYouAndDiscoverySurfacesAreBlocked() {
        for rawURL in [
            "https://www.tiktok.com/",
            "https://www.tiktok.com/foryou",
            "https://www.tiktok.com/live",
            "https://www.tiktok.com/shop",
            "https://www.tiktok.com/explore",
        ] {
            XCTAssertEqual(
                TikTokNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: TikTokNavigationPolicy.followingURL
                ),
                .block,
                rawURL
            )
        }
    }

    func testSocialDestinationsRemainAvailable() {
        for rawURL in [
            "https://www.tiktok.com/following",
            "https://www.tiktok.com/friends",
            "https://www.tiktok.com/search?q=nima",
            "https://www.tiktok.com/messages",
            "https://www.tiktok.com/inbox",
            "https://www.tiktok.com/profile",
            "https://www.tiktok.com/@nima",
        ] {
            XCTAssertEqual(
                TikTokNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: TikTokNavigationPolicy.followingURL
                ),
                .allow,
                rawURL
            )
        }
    }

    func testIndividualVideoRequiresExactOneShotGrant() {
        let video = URL(string: "https://www.tiktok.com/@nima/video/123")!
        let neighbour = URL(string: "https://www.tiktok.com/@nima/video/456")!

        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: video,
                sourceURL: TikTokNavigationPolicy.messagesURL
            ),
            .block
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: video,
                sourceURL: TikTokNavigationPolicy.messagesURL,
                grantedVideoURL: video
            ),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: neighbour,
                sourceURL: video,
                grantedVideoURL: video
            ),
            .block
        )
    }

    func testNotificationVideoGrantAllowsOnlySelectedPost() {
        let inbox = URL(string: "https://www.tiktok.com/inbox")!
        let selected = URL(string: "https://www.tiktok.com/@7686217091351151638/video/123")!
        let canonical = URL(string: "https://www.tiktok.com/@creator/video/123")!
        let next = URL(string: "https://www.tiktok.com/@creator/video/124")!

        XCTAssertTrue(TikTokNavigationPolicy.mayGrantVideo(from: inbox))
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: selected, sourceURL: inbox, grantedVideoURL: selected),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: canonical, sourceURL: selected, grantedVideoURL: selected),
            .allow
        )
        XCTAssertEqual(
            TikTokNavigationPolicy.action(for: next, sourceURL: selected, grantedVideoURL: selected),
            .block
        )
    }

    func testScrollableFeedsCannotGrantSingleVideoViewer() {
        XCTAssertFalse(TikTokNavigationPolicy.mayGrantVideo(from: TikTokNavigationPolicy.followingURL))
        XCTAssertFalse(TikTokNavigationPolicy.mayGrantVideo(from: TikTokNavigationPolicy.friendsURL))
        XCTAssertTrue(TikTokNavigationPolicy.mayGrantVideo(from: TikTokNavigationPolicy.searchURL))
        XCTAssertTrue(TikTokNavigationPolicy.mayGrantVideo(from: TikTokNavigationPolicy.messagesURL))
        XCTAssertTrue(
            TikTokNavigationPolicy.mayGrantVideo(
                from: URL(string: "https://www.tiktok.com/@nima")!
            )
        )
    }

    func testExternalHostOpensOutsideClient() {
        XCTAssertEqual(
            TikTokNavigationPolicy.action(
                for: URL(string: "https://example.com/")!,
                sourceURL: TikTokNavigationPolicy.followingURL
            ),
            .openExternal
        )
    }

    func testParsesOnlyTikTokLinksForOpenLinkControl() {
        XCTAssertEqual(
            TikTokNavigationPolicy.tiktokURL(from: "www.tiktok.com/@nima/video/123")?.path,
            "/@nima/video/123"
        )
        XCTAssertNil(TikTokNavigationPolicy.tiktokURL(from: "https://example.com/video/123"))
        XCTAssertNil(TikTokNavigationPolicy.tiktokURL(from: "not a link"))
    }
}
