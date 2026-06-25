import RevenueCat
import XCTest
@testable import Nima

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    func testAnnualDemoAccountsResolveAfterNormalization() {
        XCTAssertTrue(AuthStore.isAnnualDemoAccount(email: " ya@nima.so "))
        XCTAssertTrue(AuthStore.isAnnualDemoAccount(email: "REVIEW@NIMA.SO"))
        XCTAssertFalse(AuthStore.isAnnualDemoAccount(email: "customer@nima.so"))
    }

    func testDemoAnnualPlanMarksPremiumVerified() {
        let (store, defaults, suiteName) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(store.hasPremium)
        XCTAssertEqual(store.verificationState, .idle)

        store.activateDemoAnnualPlan()

        XCTAssertTrue(store.hasPremium)
        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertTrue(defaults.bool(forKey: "subscription.hasPremium"))
    }

    func testCustomerInformationRoutesPremiumUser() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        XCTAssertEqual(store.verificationState, .loading)

        mock.customerInfoCompletions[0](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertTrue(store.hasPremium)
    }

    func testCustomerInformationRoutesNonPremiumUser() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertFalse(store.hasPremium)
    }

    func testCustomerInformationErrorShowsFailure() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](nil, TestError.offline)
        await flushMainActorTasks()

        guard case .failed(let message) = store.verificationState else {
            return XCTFail("Expected customer verification to fail")
        }
        XCTAssertEqual(message, TestError.offline.localizedDescription)
    }

    func testMissingCustomerInformationCallbackTimesOut() async throws {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(
            client: mock.client,
            timeoutNanoseconds: 5_000_000
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        try await Task.sleep(nanoseconds: 30_000_000)

        guard case .failed = store.verificationState else {
            return XCTFail("Expected customer verification to time out")
        }
    }

    func testRetrySucceedsAfterInitialError() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](nil, TestError.offline)
        await flushMainActorTasks()

        store.retrySubscriptionCheck()
        XCTAssertEqual(mock.customerInfoCompletions.count, 2)
        XCTAssertEqual(mock.offeringsCompletions.count, 1)

        mock.customerInfoCompletions[1](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [],
                activeSubscriptionIDs: ["nima_monthly"]
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertTrue(store.hasPremium)
    }

    func testSignedInRetryRepeatsLoginForSameNormalizedIdentity() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.identify(appUserID: " Customer@Example.com ")
        XCTAssertEqual(mock.loginAppUserIDs, ["customer@example.com"])
        XCTAssertTrue(mock.customerInfoCompletions.isEmpty)

        mock.loginCompletions[0](nil, TestError.offline)
        await flushMainActorTasks()

        store.retrySubscriptionCheck()

        XCTAssertEqual(
            mock.loginAppUserIDs,
            ["customer@example.com", "customer@example.com"]
        )
        XCTAssertTrue(mock.customerInfoCompletions.isEmpty)
    }

    func testAccountChangeIgnoresPreviousIdentityCallback() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.identify(appUserID: "first@example.com")
        let firstCompletion = mock.loginCompletions[0]

        store.identify(appUserID: "second@example.com")
        mock.loginCompletions[1](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()

        firstCompletion(
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertFalse(store.hasPremium)
    }

    func testLateCallbackCannotOverrideNewerRetry() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        let firstCompletion = mock.customerInfoCompletions[0]

        store.retrySubscriptionCheck()
        mock.customerInfoCompletions[1](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()
        XCTAssertFalse(store.hasPremium)

        firstCompletion(
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertFalse(store.hasPremium)
    }

    func testCachedPremiumSurvivesTemporaryCustomerInformationFailure() async {
        let mock = MockRevenueCatClient()
        let suiteName = "SubscriptionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "subscription.hasPremium")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SubscriptionStore(defaults: defaults, client: mock.client)

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](nil, TestError.offline)
        await flushMainActorTasks()

        guard case .failed = store.verificationState else {
            return XCTFail("Expected customer verification to fail")
        }
        XCTAssertTrue(store.hasPremium)
        XCTAssertTrue(defaults.bool(forKey: "subscription.hasPremium"))
    }

    func testOfferingsErrorLeavesRetryAndRestoreAvailable() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.loadOfferings()
        mock.offeringsCompletions[0](nil, TestError.offline)
        await flushMainActorTasks()

        XCTAssertNotNil(store.offeringsErrorMessage)
        XCTAssertFalse(store.isLoadingOfferings)
        XCTAssertFalse(store.isRestoring)

        store.retryOfferings()
        XCTAssertEqual(mock.offeringsCompletions.count, 2)
        XCTAssertTrue(store.isLoadingOfferings)
    }

    func testOfferingsAndRestoreTimeoutsClearProgress() async throws {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(
            client: mock.client,
            timeoutNanoseconds: 5_000_000
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.loadOfferings()
        store.restore(onUnlocked: {})
        XCTAssertTrue(store.isLoadingOfferings)
        XCTAssertTrue(store.isRestoring)

        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertFalse(store.isLoadingOfferings)
        XCTAssertNotNil(store.offeringsErrorMessage)
        XCTAssertFalse(store.isRestoring)
        XCTAssertNotNil(store.restoreErrorMessage)
    }

    func testRestoreLateSuccessAfterTimeoutStillUnlocksPremium() async throws {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(
            client: mock.client,
            timeoutNanoseconds: 5_000_000
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var didUnlock = false

        store.restore {
            didUnlock = true
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(store.isRestoring)

        mock.restoreCompletions[0](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertTrue(store.hasPremium)
        XCTAssertTrue(didUnlock)
        XCTAssertNil(store.restoreErrorMessage)
    }

    func testSupersededRestoreFailureCannotOverwriteRetry() async throws {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(
            client: mock.client,
            timeoutNanoseconds: 5_000_000
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.restore(onUnlocked: {})
        let firstCompletion = mock.restoreCompletions[0]
        try await Task.sleep(nanoseconds: 30_000_000)

        store.restore(onUnlocked: {})
        mock.restoreCompletions[1](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()

        firstCompletion(nil, TestError.offline)
        await flushMainActorTasks()

        XCTAssertEqual(store.restoreErrorMessage, "No active subscription was found.")
    }

    func testRestoreClearsProgressOnSuccessAndError() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.restore(onUnlocked: {})
        mock.restoreCompletions[0](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()
        XCTAssertFalse(store.isRestoring)
        XCTAssertEqual(store.restoreErrorMessage, "No active subscription was found.")

        store.restore(onUnlocked: {})
        mock.restoreCompletions[1](nil, TestError.offline)
        await flushMainActorTasks()
        XCTAssertFalse(store.isRestoring)
        XCTAssertEqual(store.restoreErrorMessage, TestError.offline.localizedDescription)
    }

    func testPurchaseClearsProgressOnSuccessErrorAndCancellation() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let package = makePackage()
        var unlockCount = 0

        store.purchase(package) {
            unlockCount += 1
        }
        mock.purchaseCompletions[0](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil,
            false
        )
        await flushMainActorTasks()
        XCTAssertFalse(store.isPurchasing)
        XCTAssertNil(store.purchaseErrorMessage)
        XCTAssertEqual(unlockCount, 1)

        store.purchase(package, onUnlocked: {})
        mock.purchaseCompletions[1](nil, TestError.offline, false)
        await flushMainActorTasks()
        XCTAssertFalse(store.isPurchasing)
        XCTAssertEqual(store.purchaseErrorMessage, TestError.offline.localizedDescription)

        store.purchase(package, onUnlocked: {})
        mock.purchaseCompletions[2](nil, nil, true)
        await flushMainActorTasks()
        XCTAssertFalse(store.isPurchasing)
        XCTAssertNil(store.purchaseErrorMessage)
    }

    func testPurchaseHasNoTenSecondTimeoutAndLateSuccessUnlocks() async throws {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(
            client: mock.client,
            timeoutNanoseconds: 5_000_000
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.purchase(makePackage(), onUnlocked: {})
        XCTAssertTrue(store.isPurchasing)

        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(store.isPurchasing)
        XCTAssertTrue(store.hasPendingPurchase)
        XCTAssertNil(store.purchaseErrorMessage)

        mock.purchaseCompletions[0](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil,
            false
        )
        await flushMainActorTasks()

        XCTAssertFalse(store.isPurchasing)
        XCTAssertFalse(store.hasPendingPurchase)
        XCTAssertTrue(store.hasPremium)
    }

    func testForegroundReconciliationRecoversInterruptedPurchase() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()

        store.purchase(makePackage(), onUnlocked: {})
        store.reconcilePendingPurchaseAfterForeground()

        XCTAssertEqual(mock.customerInfoForceRefreshes, [false, true])
        mock.customerInfoCompletions[1](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil
        )
        await flushMainActorTasks()

        XCTAssertTrue(store.hasPremium)
        XCTAssertFalse(store.hasPendingPurchase)
        XCTAssertFalse(store.isPurchasing)
    }

    func testFailedPurchaseReconciliationKeepsLateCallbackValid() async {
        let mock = MockRevenueCatClient()
        let (store, defaults, suiteName) = makeStore(client: mock.client)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.refreshCustomerInfo()
        mock.customerInfoCompletions[0](
            SubscriptionCustomerStatus(activeEntitlementIDs: [], activeSubscriptionIDs: []),
            nil
        )
        await flushMainActorTasks()

        store.purchase(makePackage(), onUnlocked: {})
        store.reconcilePendingPurchaseAfterForeground()
        mock.customerInfoCompletions[1](nil, TestError.offline)
        await flushMainActorTasks()

        XCTAssertEqual(store.verificationState, .verified)
        XCTAssertTrue(store.hasPendingPurchase)
        XCTAssertFalse(store.isPurchasing)
        XCTAssertNotNil(store.purchaseErrorMessage)

        mock.purchaseCompletions[0](
            SubscriptionCustomerStatus(
                activeEntitlementIDs: [SubscriptionStore.premiumEntitlementID],
                activeSubscriptionIDs: []
            ),
            nil,
            false
        )
        await flushMainActorTasks()

        XCTAssertTrue(store.hasPremium)
        XCTAssertFalse(store.hasPendingPurchase)
        XCTAssertNil(store.purchaseErrorMessage)
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

    private func makeStore(
        client: RevenueCatClient? = nil,
        timeoutNanoseconds: UInt64 = SubscriptionStore.requestTimeoutNanoseconds
    ) -> (SubscriptionStore, UserDefaults, String) {
        let suiteName = "SubscriptionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (
            SubscriptionStore(
                defaults: defaults,
                client: client,
                timeoutNanoseconds: timeoutNanoseconds
            ),
            defaults,
            suiteName
        )
    }

    private func flushMainActorTasks() async {
        await Task.yield()
        await Task.yield()
    }

    private func makePackage() -> RevenueCat.Package {
        let product = TestStoreProduct(
            localizedTitle: "Nima Monthly",
            price: 4.99,
            currencyCode: "USD",
            localizedPriceString: "$4.99",
            productIdentifier: "nima_monthly",
            productType: .autoRenewableSubscription,
            localizedDescription: "Nima premium access",
            locale: Locale(identifier: "en_US")
        )
        return RevenueCat.Package(
            identifier: "$rc_monthly",
            packageType: .monthly,
            storeProduct: product.toStoreProduct(),
            offeringIdentifier: "default",
            webCheckoutUrl: nil
        )
    }
}

private enum TestError: LocalizedError {
    case offline

    var errorDescription: String? {
        "The Internet connection appears to be offline."
    }
}

private final class MockRevenueCatClient {
    var customerInfoCompletions: [RevenueCatClient.CustomerStatusCompletion] = []
    var customerInfoForceRefreshes: [Bool] = []
    var offeringsCompletions: [RevenueCatClient.OfferingsCompletion] = []
    var purchaseCompletions: [RevenueCatClient.PurchaseCompletion] = []
    var restoreCompletions: [RevenueCatClient.CustomerStatusCompletion] = []
    var loginAppUserIDs: [String] = []
    var loginCompletions: [RevenueCatClient.CustomerStatusCompletion] = []

    lazy var client = RevenueCatClient(
        getCustomerInfo: { [weak self] forceRefresh, completion in
            self?.customerInfoForceRefreshes.append(forceRefresh)
            self?.customerInfoCompletions.append(completion)
        },
        getOfferings: { [weak self] completion in
            self?.offeringsCompletions.append(completion)
        },
        purchase: { [weak self] _, completion in
            self?.purchaseCompletions.append(completion)
        },
        restorePurchases: { [weak self] completion in
            self?.restoreCompletions.append(completion)
        },
        logIn: { [weak self] appUserID, completion in
            self?.loginAppUserIDs.append(appUserID)
            self?.loginCompletions.append(completion)
        },
        logOut: { completion in
            completion(nil, nil)
        }
    )
}
