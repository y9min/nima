import XCTest
@testable import Nima

final class MetaAdsServiceTests: XCTestCase {
    func testMissingOrPlaceholderConfigurationNeverEnablesMeasurement() {
        for info: [String: Any] in [[:], ["META_ADS_ENABLED": "YES"],
            ["META_ADS_ENABLED": "YES", "FacebookAppID": "$(META_APP_ID)", "FacebookClientToken": "token"],
            ["META_ADS_ENABLED": "YES", "FacebookAppID": "12345", "FacebookClientToken": "your-meta-client-token"]] {
            XCTAssertFalse(MetaAdsConfiguration(info: info).isValid)
        }
        XCTAssertFalse(configuration(enabled: "NO").isValid)
        XCTAssertTrue(configuration(enabled: "YES").isValid)
    }

    func testRefusalAndRevocationPreventNewActivations() {
        var state = MetaAdsConsentState()
        XCTAssertFalse(state.shouldActivate(configured: true, authorized: false, active: true))
        XCTAssertTrue(state.shouldActivate(configured: true, authorized: true, active: true))
        state.leaveForeground()
        XCTAssertFalse(state.shouldActivate(configured: true, authorized: false, active: true))
        XCTAssertTrue(state.shouldActivate(configured: true, authorized: true, active: true))
    }

    func testRepeatedForegroundCallbacksDoNotDuplicateActivation() {
        var state = MetaAdsConsentState()
        XCTAssertTrue(state.shouldActivate(configured: true, authorized: true, active: true))
        XCTAssertFalse(state.shouldActivate(configured: true, authorized: true, active: true))
        state.leaveForeground()
        XCTAssertTrue(state.shouldActivate(configured: true, authorized: true, active: true))
    }

    func testInactiveOrUnconfiguredLaunchDoesNotConsumeActivation() {
        var state = MetaAdsConsentState()
        XCTAssertFalse(state.shouldActivate(configured: false, authorized: true, active: true))
        XCTAssertFalse(state.shouldActivate(configured: true, authorized: true, active: false))
        XCTAssertTrue(state.shouldActivate(configured: true, authorized: true, active: true))
    }

    @MainActor
    func testAttributionWaitsForConfigurationAndReappliesAfterAccountLinking() {
        let coordinator = MetaAdsAttributionCoordinator()
        var operations: [String] = []
        func update(_ identity: String?, authorized: Bool) {
            coordinator.update(identity: identity, consent: authorized ? 3 : 2, authorized: authorized,
                collect: { operations.append("collect") }, attach: { operations.append("attach") },
                clear: { operations.append("clear") }, sync: { done in operations.append("sync"); done(true) })
        }
        update(nil, authorized: true)
        XCTAssertTrue(operations.isEmpty)
        update("anonymous", authorized: true)
        XCTAssertEqual(operations, ["collect", "attach", "sync"])
        operations = []
        update("anonymous", authorized: true)
        XCTAssertTrue(operations.isEmpty)
        update("linked", authorized: true)
        XCTAssertEqual(operations, ["collect", "attach", "sync"])
        operations = []
        update("linked", authorized: false)
        XCTAssertEqual(operations, ["clear", "sync"])
    }

    private func configuration(enabled: String) -> MetaAdsConfiguration {
        MetaAdsConfiguration(info: ["META_ADS_ENABLED": enabled, "FacebookAppID": "12345", "FacebookClientToken": "client-token"])
    }
}
