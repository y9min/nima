import StoreKit
import XCTest
@testable import Nima

final class AcquisitionTrackingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "acquisition-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testConversionRetriesUntilAcknowledgedAndCannotDowngrade() {
        let state = AcquisitionConversionState(defaults: defaults)
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(state.pendingUpdate(now: now)?.milestone, .installed)
        state.advance(to: .trialStarted)
        XCTAssertEqual(state.pendingUpdate(now: now)?.milestone, .trialStarted)
        // A failed request does not consume the update.
        XCTAssertEqual(state.pendingUpdate(now: now)?.milestone, .trialStarted)
        state.markDelivered(.trialStarted, day: 0)
        XCTAssertNil(state.pendingUpdate(now: now))
        state.advance(to: .paywallViewed)
        XCTAssertEqual(state.milestone, .trialStarted)
        XCTAssertNil(state.pendingUpdate(now: now))
        state.advance(to: .paidSubscription)
        XCTAssertEqual(state.pendingUpdate(now: now)?.milestone, .paidSubscription)
    }

    func testConversionReassertsDailyAndStopsAfter35Days() {
        let state = AcquisitionConversionState(defaults: defaults)
        let now = Date(timeIntervalSince1970: 100)
        _ = state.pendingUpdate(now: now)
        state.advance(to: .paidSubscription)
        state.markDelivered(.paidSubscription, day: 0)
        XCTAssertEqual(state.pendingUpdate(now: now.addingTimeInterval(2 * 86_400))?.day, 2)
        state.markDelivered(.paidSubscription, day: 2)
        XCTAssertNil(state.pendingUpdate(now: now.addingTimeInterval(2 * 86_400 + 10)))
        XCTAssertEqual(state.pendingUpdate(now: now.addingTimeInterval(7 * 86_400))?.day, 7)
        XCTAssertNil(state.pendingUpdate(now: now.addingTimeInterval(35 * 86_400)))
    }

    func testAdvertisingBoundaryExcludesBrowsingDiagnosticsAndClientPurchaseSuccess() {
        for event in ["instagram_client_opened", "tiktok_navigation_blocked", "permission_resolved",
                      AnalyticsEvent.purchaseSucceeded, AnalyticsEvent.restoreSucceeded,
                      AnalyticsEvent.entitlementActivated, AnalyticsEvent.guidedPracticeStepViewed] {
            XCTAssertNil(AcquisitionMilestone.from(productEvent: event))
        }
        XCTAssertEqual(AcquisitionMilestone.from(productEvent: AnalyticsEvent.purchaseStarted), .checkoutStarted)
        XCTAssertNil(AcquisitionMilestone.trialStarted.tenjinEvent)
        XCTAssertNil(AcquisitionMilestone.paidSubscription.tenjinEvent)
        XCTAssertEqual(AcquisitionMilestone.trialStarted.coarseValue, .medium)
        XCTAssertEqual(AcquisitionMilestone.paidSubscription.coarseValue, .high)
    }

    func testAttributionContextDoesNotForwardDeviceIdentifiersOrURLs() {
        let properties = AcquisitionContext.properties(from: [
            "ad_network": "test-network", "campaign_name": "Creative test",
            "advertising_id": "must-not-leave", "deferred_deeplink_url": "https://example.com/private",
            "ip_address": "192.0.2.1", "creative_name": String(repeating: "a", count: 300),
        ])
        XCTAssertEqual(properties["acquisition_ad_network"], "test-network")
        XCTAssertEqual(properties.count, 3)
        XCTAssertEqual(properties["acquisition_creative_name"]?.count, 200)
        XCTAssertFalse(properties.values.contains("must-not-leave"))
    }

    func testRestrictedMetaCampaignDataDoesNotEnrichProductAnalyticsProfiles() {
        for network in ["Meta", "Facebook Ads", "Instagram", "meta_ads"] {
            XCTAssertTrue(AcquisitionContext.properties(from: [
                "ad_network": network, "campaign_name": "Restricted campaign",
            ]).isEmpty)
        }
        XCTAssertTrue(AcquisitionContext.properties(from: ["campaign_name": "Unknown source"]).isEmpty)
    }

    func testPlaceholderOrDisabledTenjinConfigurationCannotStartSDK() {
        for info: [String: Any] in [[:], ["TENJIN_ENABLED": "YES"],
            ["TENJIN_ENABLED": "YES", "TENJIN_SDK_KEY": "$(TENJIN_SDK_KEY)"],
            ["TENJIN_ENABLED": "YES", "TENJIN_SDK_KEY": "your-tenjin-ios-sdk-key"],
            ["TENJIN_ENABLED": "NO", "TENJIN_SDK_KEY": "client-key"]] {
            XCTAssertFalse(TenjinConfiguration(info: info).isValid)
        }
        XCTAssertTrue(TenjinConfiguration(info: ["TENJIN_ENABLED": "YES", "TENJIN_SDK_KEY": "client-key"]).isValid)
    }

    func testLifecycleDoesNotCountTemporaryInactivityAsNewSessions() {
        var state = AnalyticsLifecycleState(defaults: defaults)
        let now = Date(timeIntervalSince1970: 100)
        let first = state.enterForeground(now: now, existingInstallation: true)!
        XCTAssertTrue(first.isFirstObservation)
        XCTAssertEqual(first.properties["measurement_cohort"] as? String, "existing")
        XCTAssertNil(state.enterForeground(now: now, existingInstallation: false))
        XCTAssertEqual(state.leaveForeground(now: now.addingTimeInterval(10)), 10_000)
        XCTAssertNil(state.leaveForeground(now: now.addingTimeInterval(11)))
        let resumed = state.enterForeground(now: now.addingTimeInterval(20), existingInstallation: true)!
        XCTAssertFalse(resumed.isNewSession)
        XCTAssertEqual(first.properties["session_id"] as? String, resumed.properties["session_id"] as? String)
        _ = state.leaveForeground(now: now.addingTimeInterval(30))
        let next = state.enterForeground(now: now.addingTimeInterval(2_000), existingInstallation: true)!
        XCTAssertTrue(next.isNewSession)
        XCTAssertNotEqual(first.properties["session_id"] as? String, next.properties["session_id"] as? String)
    }

    func testRetentionAnchorAndActivationSurviveProcessRestart() {
        let now = Date(timeIntervalSince1970: 100)
        var first = AnalyticsLifecycleState(defaults: defaults)
        _ = first.enterForeground(now: now, existingInstallation: false)
        XCTAssertTrue(first.markActivation())
        var restarted = AnalyticsLifecycleState(defaults: defaults)
        let update = restarted.enterForeground(now: now.addingTimeInterval(7 * 86_400), existingInstallation: true)!
        XCTAssertFalse(update.isFirstObservation)
        XCTAssertEqual(update.properties["days_since_first_observed"] as? Int, 7)
        XCTAssertEqual(update.properties["measurement_cohort"] as? String, "new_or_incomplete")
        XCTAssertFalse(restarted.markActivation())
    }
}
