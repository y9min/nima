import XCTest
@testable import Nima

final class InstagramNavigationPolicyTests: XCTestCase {
    func testLoginIntroductionIsRememberedAfterContinuing() throws {
        let suiteName = "InstagramLoginIntroductionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(InstagramLoginIntroduction.hasBeenSeen(defaults: defaults))
        InstagramLoginIntroduction.markSeen(defaults: defaults)
        XCTAssertTrue(InstagramLoginIntroduction.hasBeenSeen(defaults: defaults))
    }

    func testLoginURLUsesInstagramOfficialLoginPage() {
        XCTAssertEqual(InstagramNavigationPolicy.loginURL.scheme, "https")
        XCTAssertTrue(InstagramNavigationPolicy.isInstagramHost(InstagramNavigationPolicy.loginURL.host))
        XCTAssertEqual(InstagramNavigationPolicy.loginURL.path, "/accounts/login")
    }

    func testInstagramClipboardLinkValidation() {
        XCTAssertEqual(
            InstagramNavigationPolicy.instagramURL(
                from: "  https://www.instagram.com/reel/DbLSxt9NgV0/?utm_source=ig_web_copy_link  "
            )?.path,
            "/reel/DbLSxt9NgV0"
        )
        XCTAssertEqual(
            InstagramNavigationPolicy.instagramURL(from: "instagram.com/p/ABC123/")?.host,
            "instagram.com"
        )

        for invalidValue in [
            "",
            "not a link",
            "https://example.com/reel/DbLSxt9NgV0/",
            "https://instagram.com.evil.example/reel/DbLSxt9NgV0/",
            "javascript:alert(1)"
        ] {
            XCTAssertNil(InstagramNavigationPolicy.instagramURL(from: invalidValue), invalidValue)
        }
    }

    func testCleanAllowsUsefulInstagramDestinations() {
        let allowed = [
            "https://www.instagram.com/",
            "https://www.instagram.com/explore/",
            "https://www.instagram.com/direct/inbox/",
            "https://www.instagram.com/some_profile/",
            "https://www.instagram.com/p/ABC123/",
            "https://www.instagram.com/accounts/login/"
        ]

        for rawURL in allowed {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .clean,
                    sourceURL: InstagramNavigationPolicy.homeURL
                ),
                .allow,
                rawURL
            )
        }
    }

    func testReelsFeedIsAlwaysBlocked() {
        for rawURL in [
            "https://www.instagram.com/reels/",
            "https://instagram.com/reels/audio/123",
            "https://m.instagram.com/reels?next=1",
            "https://www.instagram.com/reels/?utm_source=message"
        ] {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .clean,
                    sourceURL: InstagramNavigationPolicy.inboxURL
                ),
                .block
            )
        }
    }

    func testProfileURLRecognitionIncludesProfileTabsButNotInstagramSections() {
        for rawURL in [
            "https://www.instagram.com/nima/",
            "https://www.instagram.com/nima/reels/",
            "https://m.instagram.com/nima/tagged/"
        ] {
            XCTAssertTrue(
                InstagramNavigationPolicy.isProfileURL(URL(string: rawURL)),
                rawURL
            )
        }

        for rawURL in [
            "https://www.instagram.com/",
            "https://www.instagram.com/explore/",
            "https://www.instagram.com/direct/inbox/",
            "https://www.instagram.com/accounts/login/",
            "https://example.com/nima/"
        ] {
            XCTAssertFalse(
                InstagramNavigationPolicy.isProfileURL(URL(string: rawURL)),
                rawURL
            )
        }
    }

    func testIndividualReelRequiresExactConversationGrant() {
        let reel = URL(string: "https://www.instagram.com/reel/ABC123/")!
        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: reel,
                mode: .dmOnly,
                sourceURL: InstagramNavigationPolicy.inboxURL
            ),
            .block
        )
        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: reel,
                mode: .dmOnly,
                sourceURL: InstagramNavigationPolicy.inboxURL,
                grantedSharedURL: reel
            ),
            .allow
        )
        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: URL(string: "https://www.instagram.com/reel/DIFFERENT/")!,
                mode: .dmOnly,
                sourceURL: reel,
                grantedSharedURL: reel
            ),
            .block
        )
    }

    func testCopiedReelGrantIgnoresTrackingParametersButNotTheReelID() {
        let copiedReel = URL(string: "https://www.instagram.com/reel/DbLSxt9NgV0/?utm_source=ig_web_copy_link&obrf=MzRlODBiNWFlZA%3D%3D")!

        XCTAssertEqual(
            [
                "https://www.instagram.com/reel/DbLSxt9NgV0/",
                "https://instagram.com/reel/DbLSxt9NgV0/",
                "https://m.instagram.com/reel/DbLSxt9NgV0/"
            ].map { rawURL in
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .clean,
                    sourceURL: InstagramNavigationPolicy.homeURL,
                    grantedSharedURL: copiedReel
                )
            },
            [.allow, .allow, .allow]
        )
        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: URL(string: "https://www.instagram.com/reel/A-DIFFERENT-REEL/")!,
                mode: .clean,
                sourceURL: copiedReel,
                grantedSharedURL: copiedReel
            ),
            .block
        )
    }

    func testDMOnlyFailsClosedOutsideConversationDestinations() {
        for rawURL in [
            "https://www.instagram.com/",
            "https://www.instagram.com/explore/",
            "https://www.instagram.com/stories/"
        ] {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .dmOnly,
                    sourceURL: InstagramNavigationPolicy.inboxURL
                ),
                .block
            )
        }
    }

    func testDMOnlyPermitsOnlyTheExactSharedPostOrProfile() {
        let destinations = [
            URL(string: "https://www.instagram.com/p/ABC123/?utm_source=ig_web_copy_link")!,
            URL(string: "https://www.instagram.com/some_profile/")!,
            URL(string: "https://www.instagram.com/stories/some_profile/123/")!
        ]

        for destination in destinations {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: destination,
                    mode: .dmOnly,
                    sourceURL: InstagramNavigationPolicy.inboxURL,
                    grantedSharedURL: destination
                ),
                .allow
            )
        }

        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: URL(string: "https://www.instagram.com/p/DIFFERENT/")!,
                mode: .dmOnly,
                sourceURL: InstagramNavigationPolicy.inboxURL,
                grantedSharedURL: destinations[0]
            ),
            .block
        )
    }

    func testRecognisedAuthenticationRedirectsStayInsideClient() {
        for rawURL in [
            "https://www.instagram.com/challenge/123/",
            "https://www.instagram.com/accounts/login/two_factor/",
            "https://www.facebook.com/dialog/oauth/?client_id=1",
            "https://m.facebook.com/login/?next=instagram",
            "https://www.facebook.com/instagram/login_sync/?next=https%3A%2F%2Fwww.instagram.com%2F"
        ] {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .dmOnly,
                    sourceURL: InstagramNavigationPolicy.inboxURL
                ),
                .allow,
                rawURL
            )
        }
    }

    func testAuthenticationURLsAreNotTreatedAsCompletedLogin() {
        for rawURL in [
            "https://www.instagram.com/accounts/login/",
            "https://www.instagram.com/accounts/login/two_factor/",
            "https://www.instagram.com/challenge/123/",
            "https://www.instagram.com/checkpoint/required/",
            "https://m.facebook.com/login/?next=instagram",
            "https://www.facebook.com/dialog/oauth/?client_id=1",
            "https://www.facebook.com/instagram/login_sync/"
        ] {
            XCTAssertTrue(
                InstagramNavigationPolicy.isAuthenticationURL(URL(string: rawURL)!),
                rawURL
            )
        }

        for rawURL in [
            "https://www.instagram.com/",
            "https://www.instagram.com/direct/inbox/",
            "https://www.instagram.com/some_profile/"
        ] {
            XCTAssertFalse(
                InstagramNavigationPolicy.isAuthenticationURL(URL(string: rawURL)!),
                rawURL
            )
        }
    }

    func testGuidedPracticeWaitsForAuthenticatedHealthyCleanMode() {
        XCTAssertTrue(
            InstagramGuidedPracticePolicy.isReadyForControlsExplanation(
                sessionStatus: .authenticated,
                mode: .clean,
                filteringHealth: .healthy
            )
        )

        XCTAssertFalse(
            InstagramGuidedPracticePolicy.isReadyForControlsExplanation(
                sessionStatus: .signingIn,
                mode: .clean,
                filteringHealth: .healthy
            )
        )
        XCTAssertFalse(
            InstagramGuidedPracticePolicy.isReadyForControlsExplanation(
                sessionStatus: .authenticated,
                mode: .dmOnly,
                filteringHealth: .healthy
            )
        )
        XCTAssertFalse(
            InstagramGuidedPracticePolicy.isReadyForControlsExplanation(
                sessionStatus: .authenticated,
                mode: .clean,
                filteringHealth: .limited
            )
        )
    }

    func testNonAuthenticationMetaAndLookalikeHostsLeaveTheClient() {
        for rawURL in [
            "https://www.facebook.com/some-page/",
            "https://about.meta.com/",
            "https://instagram.com.evil.example/reels/",
            "mailto:help@example.com"
        ] {
            XCTAssertEqual(
                InstagramNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    mode: .clean,
                    sourceURL: InstagramNavigationPolicy.homeURL
                ),
                .openExternal,
                rawURL
            )
        }
    }

    func testExternalLinksLeaveTheClient() {
        XCTAssertEqual(
            InstagramNavigationPolicy.action(
                for: URL(string: "https://example.com/")!,
                mode: .clean,
                sourceURL: InstagramNavigationPolicy.homeURL
            ),
            .openExternal
        )
    }

    func testInstagramPaidAdsPixelIsRecognisedForSilentBlocking() {
        for rawURL in [
            "https://www.fbsbx.com/paid_ads_pixel/iframe/?caller=ig_paid_ads",
            "https://fbsbx.com/paid_ads_pixel/iframe?is_remarketing",
            "https://edge.fbsbx.com/paid_ads_pixel/iframe/next"
        ] {
            XCTAssertTrue(
                InstagramNavigationPolicy.isPaidAdsTrackingURL(URL(string: rawURL)!),
                rawURL
            )
        }

        for rawURL in [
            "https://www.fbsbx.com/other/",
            "https://fbsbx.com.evil.example/paid_ads_pixel/iframe/",
            "https://www.instagram.com/paid_ads_pixel/iframe/"
        ] {
            XCTAssertFalse(
                InstagramNavigationPolicy.isPaidAdsTrackingURL(URL(string: rawURL)!),
                rawURL
            )
        }
    }
}
