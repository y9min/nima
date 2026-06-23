import XCTest
@testable import Nima

final class SubscriptionStoreTests: XCTestCase {
    func testAnnualDemoAccountsResolveAfterNormalization() {
        XCTAssertTrue(AuthStore.isAnnualDemoAccount(email: " ya@nima.so "))
        XCTAssertTrue(AuthStore.isAnnualDemoAccount(email: "REVIEW@NIMA.SO"))
        XCTAssertFalse(AuthStore.isAnnualDemoAccount(email: "customer@nima.so"))
    }

    func testDemoAnnualPlanMarksPremiumReady() {
        let suiteName = "SubscriptionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SubscriptionStore(defaults: defaults)
        XCTAssertFalse(store.hasPremium)
        XCTAssertFalse(store.hasCheckedCustomerInfo)

        store.activateDemoAnnualPlan()

        XCTAssertTrue(store.hasPremium)
        XCTAssertTrue(store.hasCheckedCustomerInfo)
        XCTAssertTrue(defaults.bool(forKey: "subscription.hasPremium"))
    }

    func testPremiumAccessResolvesExactEntitlementID() {
        XCTAssertTrue(SubscriptionStore.resolvesPremiumAccess(
            activeEntitlementIDs: ["nima Pro"],
            activeSubscriptionIDs: []
        ))
    }

    func testPremiumAccessNormalizesEntitlementIDFormatting() {
        XCTAssertTrue(SubscriptionStore.resolvesPremiumAccess(
            activeEntitlementIDs: ["nima_pro"],
            activeSubscriptionIDs: []
        ))
    }

    func testPremiumAccessAllowsActiveSubscriptionFallback() {
        XCTAssertTrue(SubscriptionStore.resolvesPremiumAccess(
            activeEntitlementIDs: [],
            activeSubscriptionIDs: ["nima_monthly"]
        ))
    }

    func testPremiumAccessRejectsEmptyRevenueCatState() {
        XCTAssertFalse(SubscriptionStore.resolvesPremiumAccess(
            activeEntitlementIDs: [],
            activeSubscriptionIDs: []
        ))
    }
}
