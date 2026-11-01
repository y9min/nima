import XCTest
@testable import Nima

final class XNavigationPolicyTests: XCTestCase {
    func testCleanModeAllowsFollowingSearchProfilesPostsNotificationsAndMessages() {
        for rawURL in [
            "https://x.com/home",
            "https://x.com/search?q=nima",
            "https://x.com/nima",
            "https://x.com/nima/status/123",
            "https://x.com/notifications",
            "https://x.com/messages",
            "https://x.com/settings/account",
            "https://x.com/i/profile",
            "https://twitter.com/nima/status/123",
        ] {
            XCTAssertEqual(
                XNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: XNavigationPolicy.homeURL,
                    mode: .clean
                ),
                .allow,
                rawURL
            )
        }
    }

    func testCleanModeBlocksExploreTrendingAndForYouQuery() {
        for rawURL in [
            "https://x.com/explore",
            "https://x.com/explore/tabs/trending",
            "https://x.com/i/trending",
            "https://x.com/i/explore",
            "https://x.com/topics",
            "https://x.com/home?f=for_you",
        ] {
            XCTAssertEqual(
                XNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: XNavigationPolicy.homeURL,
                    mode: .clean
                ),
                .block,
                rawURL
            )
        }
    }

    func testFollowingPeopleListIsBlockedInEveryMode() {
        let followingList = URL(string: "https://x.com/following")!
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: followingList,
                sourceURL: XNavigationPolicy.homeURL,
                mode: .clean
            ),
            .block
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: followingList,
                sourceURL: XNavigationPolicy.homeURL,
                mode: .dmOnly
            ),
            .block
        )
    }

    func testDMOnlyRequiresExactConversationLinkedPostGrant() {
        let selected = URL(string: "https://x.com/nima/status/123")!
        let canonical = URL(string: "https://twitter.com/another_name/status/123")!
        let next = URL(string: "https://x.com/nima/status/124")!
        let conversation = URL(string: "https://x.com/messages/99")!

        XCTAssertEqual(
            XNavigationPolicy.action(for: selected, sourceURL: conversation, mode: .dmOnly),
            .block
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: selected,
                sourceURL: conversation,
                mode: .dmOnly,
                grantedPostURL: selected
            ),
            .allow
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: canonical,
                sourceURL: conversation,
                mode: .dmOnly,
                grantedPostURL: selected
            ),
            .allow
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: next,
                sourceURL: selected,
                mode: .dmOnly,
                grantedPostURL: selected
            ),
            .block
        )
    }

    func testDMOnlyRequiresExactConversationLinkedProfileGrant() {
        let selected = URL(string: "https://x.com/nima")!
        let other = URL(string: "https://x.com/other")!
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: other,
                sourceURL: selected,
                mode: .dmOnly,
                grantedProfileURL: selected
            ),
            .block
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: selected,
                sourceURL: XNavigationPolicy.messagesURL,
                mode: .dmOnly,
                grantedProfileURL: selected
            ),
            .allow
        )
        XCTAssertFalse(
            XNavigationPolicy.mayGrantConversationLink(
                from: URL(string: "https://x.com/nima/status/123")
            )
        )
    }

    func testDMOnlyAllowsMessagesLoginAndEssentialAccountPagesOnly() {
        for rawURL in [
            "https://x.com/messages",
            "https://x.com/messages/123",
            "https://x.com/i/flow/login",
            "https://x.com/settings/account",
            "https://x.com/settings/privacy_and_safety",
        ] {
            XCTAssertEqual(
                XNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: XNavigationPolicy.messagesURL,
                    mode: .dmOnly
                ),
                .allow,
                rawURL
            )
        }
        for rawURL in [
            "https://x.com/home",
            "https://x.com/notifications",
            "https://x.com/nima",
            "https://x.com/nima/status/123",
        ] {
            XCTAssertEqual(
                XNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: XNavigationPolicy.messagesURL,
                    mode: .dmOnly
                ),
                .block,
                rawURL
            )
        }
    }

    func testCurrentXWebLoginOnboardingRedirectIsAllowed() {
        let loginRedirect = URL(
            string: "https://x.com/i/jf/onboarding/web?redirect_after_login=%2Fhome&mode=login"
        )!

        XCTAssertTrue(XNavigationPolicy.isAuthenticationURL(loginRedirect))
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: loginRedirect,
                sourceURL: XNavigationPolicy.homeURL,
                mode: .clean
            ),
            .allow
        )
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: loginRedirect,
                sourceURL: XNavigationPolicy.messagesURL,
                mode: .dmOnly
            ),
            .allow
        )
    }

    func testXAuthenticationHandoffRoutesRemainInsideControlledClient() {
        for rawURL in [
            "https://x.com/i/jf/web/password_reset",
            "https://x.com/i/jf/web/account_recovery",
            "https://x.com/i/oauth2_start_flow",
            "https://x.com/oauth/authorize?client_id=nima",
            "https://x.com/account/login_challenge",
            "https://x.com/account/verify_user_info",
            "https://x.com/login/email_lite_login",
            "https://api.x.com/oauth/authenticate",
            "https://x.com/sessions",
        ] {
            XCTAssertEqual(
                XNavigationPolicy.action(
                    for: URL(string: rawURL)!,
                    sourceURL: nil,
                    mode: .clean
                ),
                .allow,
                rawURL
            )
        }
    }

    func testExternalHostsOpenOutsideClient() {
        XCTAssertEqual(
            XNavigationPolicy.action(
                for: URL(string: "https://example.com/")!,
                sourceURL: XNavigationPolicy.messagesURL,
                mode: .clean
            ),
            .openExternal
        )
    }

    func testParsesOnlyXLinksForOpenLinkControl() {
        XCTAssertEqual(
            XNavigationPolicy.xURL(from: "x.com/nima/status/123")?.path,
            "/nima/status/123"
        )
        XCTAssertNil(XNavigationPolicy.xURL(from: "https://example.com/nima/status/123"))
        XCTAssertNil(XNavigationPolicy.xURL(from: "not a link"))
    }
}

final class XHomeHealthVerifierTests: XCTestCase {
    func testBriefFollowingDelayDoesNotLimitCleanMode() {
        var verifier = XHomeHealthVerifier()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            verifier.observe(observation(followingSelected: false), at: start),
            .checking
        )
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: false),
                at: start.addingTimeInterval(10)
            ),
            .checking
        )
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: true),
                at: start.addingTimeInterval(11)
            ),
            .checking
        )
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: true),
                at: start.addingTimeInterval(12)
            ),
            .healthy
        )
    }

    func testPersistentCompletedPageFailureBecomesLimited() {
        var verifier = XHomeHealthVerifier()
        let start = Date(timeIntervalSince1970: 2_000)

        for offset in stride(from: 0.0, through: 20.0, by: 5.0) {
            _ = verifier.observe(
                observation(followingSelected: false),
                at: start.addingTimeInterval(offset)
            )
        }

        XCTAssertEqual(verifier.health, .limited)
    }

    func testLoadingOrErrorPageNeverCountsAsXChanging() {
        var verifier = XHomeHealthVerifier()
        let start = Date(timeIntervalSince1970: 3_000)

        for offset in stride(from: 0.0, through: 40.0, by: 5.0) {
            _ = verifier.observe(
                observation(followingSelected: false, loading: true),
                at: start.addingTimeInterval(offset)
            )
            _ = verifier.observe(
                observation(followingSelected: false, loadError: true),
                at: start.addingTimeInterval(offset + 2)
            )
        }

        XCTAssertEqual(verifier.health, .checking)
    }

    func testLimitedModeRequiresTwoHealthyObservationsToRecover() {
        var verifier = XHomeHealthVerifier()
        let start = Date(timeIntervalSince1970: 4_000)
        for offset in stride(from: 0.0, through: 20.0, by: 5.0) {
            _ = verifier.observe(
                observation(followingSelected: false),
                at: start.addingTimeInterval(offset)
            )
        }
        XCTAssertEqual(verifier.health, .limited)

        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: true),
                at: start.addingTimeInterval(21)
            ),
            .limited
        )
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: true),
                at: start.addingTimeInterval(22)
            ),
            .healthy
        )
    }

    func testTemporaryFailureAfterHealthyDoesNotLimitCleanMode() {
        var verifier = XHomeHealthVerifier()
        let start = Date(timeIntervalSince1970: 5_000)
        _ = verifier.observe(observation(followingSelected: true), at: start)
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: true),
                at: start.addingTimeInterval(1)
            ),
            .healthy
        )
        XCTAssertEqual(
            verifier.observe(
                observation(followingSelected: false),
                at: start.addingTimeInterval(2)
            ),
            .healthy
        )
    }

    private func observation(
        followingSelected: Bool,
        loading: Bool = false,
        loadError: Bool = false
    ) -> XHomeHealthObservation {
        XHomeHealthObservation(
            path: "/home",
            documentReady: true,
            homeSurfacePresent: true,
            timelineTabsPresent: true,
            followingPresent: true,
            followingSelected: followingSelected,
            forYouPresent: true,
            isLoading: loading,
            loadError: loadError
        )
    }
}

final class XProtectionHealthTests: XCTestCase {
    @MainActor
    func testOnlyConfirmedLimitedHealthForcesDMOnly() {
        let suite = "XProtectionHealthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = XProtectionStore(defaults: defaults)
        store.setManualMode(.clean, source: "test")

        store.setFilteringHealth(.checking)
        XCTAssertEqual(store.effectiveMode, .clean)

        store.setFilteringHealth(.slow)
        XCTAssertEqual(store.effectiveMode, .clean)

        store.setFilteringHealth(.limited)
        XCTAssertEqual(store.effectiveMode, .dmOnly)

        store.setFilteringHealth(.healthy)
        XCTAssertEqual(store.effectiveMode, .clean)
    }
}

final class XProtectionMigrationTests: XCTestCase {
    @MainActor
    func testLegacyXFeedToggleMigratesToControlledClientProtection() throws {
        let defaults = makeDefaults()
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "feed_block", isEnabled: true)
        defaults.set(try JSONEncoder().encode(policy), forKey: NimaConstants.manualFeaturePolicyKey)

        XCTAssertTrue(XProtectionStore.loadProtectionEnabled(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: XProtectionStore.protectionEnabledKey))
    }

    @MainActor
    func testExplicitControlledClientChoiceWinsOverLegacyXDomainToggle() throws {
        let defaults = makeDefaults()
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.set(appId: "x", optionId: "strict_feed_block", isEnabled: true)
        defaults.set(try JSONEncoder().encode(policy), forKey: NimaConstants.manualFeaturePolicyKey)
        defaults.set(false, forKey: XProtectionStore.protectionEnabledKey)

        XCTAssertFalse(XProtectionStore.loadProtectionEnabled(defaults: defaults))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "XProtectionMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
