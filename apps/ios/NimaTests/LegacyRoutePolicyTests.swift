import XCTest
@testable import Nima

final class LegacyRoutePolicyTests: XCTestCase {
    private func route(
        ids: [UInt64] = [], unverified: Bool = false,
        identity: String? = nil, identityResolved: Bool = true
    ) -> ExperienceRoute {
        LegacyRoutePolicy.route(
            verifiedTransactionMatched: ids.contains(42),
            hasUnverifiedTransactions: unverified,
            identity: identity,
            identityResolved: identityResolved,
            matchesIdentity: { $0 == "saved-identity" }
        )
    }

    func testVerifiedOriginalTransactionMatchesAcrossRenewals() {
        XCTAssertEqual(route(ids: [7, 42]), .legacy)
    }

    func testSavedIdentityMatches() {
        XCTAssertEqual(route(identity: "saved-identity"), .legacy)
    }

    func testNonMemberUsesNewExperience() {
        XCTAssertEqual(route(ids: [7], identity: "another-identity"), .new)
    }

    func testUnresolvedEvidenceDoesNotBecomeNonMember() {
        XCTAssertEqual(route(unverified: true), .checking)
        XCTAssertEqual(route(identityResolved: false), .checking)
        XCTAssertEqual(route(identity: "saved-identity", identityResolved: false), .checking)
    }

    func testRestoreCanChangeRoute() {
        XCTAssertEqual(route(), .new)
        XCTAssertEqual(route(ids: [42]), .legacy)
    }
}

@MainActor
final class ExperienceRouterTests: XCTestCase {
    func testOlderCheckCannotOverwriteIdentityChange() async {
        let suite = "ExperienceRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var pending: [CheckedContinuation<LegacyCohort.TransactionCheck, Never>] = []
        let router = ExperienceRouter(
            defaults: defaults,
            checkTransactions: { await withCheckedContinuation { pending.append($0) } },
            matchesIdentity: { $0 == "legacy" },
            containsTransactionHash: { _ in false }
        )
        router.resolveCachedIdentity("ordinary")
        let older = Task { await router.checkHistoricalPurchases(identity: "ordinary") }
        while pending.count < 1 { await Task.yield() }
        router.resolveCachedIdentity("new")
        let newer = Task { await router.checkHistoricalPurchases(identity: "new") }
        while pending.count < 2 { await Task.yield() }
        pending[1].resume(returning: .init())
        await newer.value
        XCTAssertEqual(router.route, .new)
        pending[0].resume(returning: .init())
        await older.value
        XCTAssertEqual(router.route, .new)
    }

    func testConfirmedPurchaseCacheIsScopedToIdentity() async {
        let suite = "ExperienceRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var check = LegacyCohort.TransactionCheck(matchedHash: "allowed")
        let router = ExperienceRouter(
            defaults: defaults,
            checkTransactions: { check },
            matchesIdentity: { _ in false },
            containsTransactionHash: { $0 == "allowed" }
        )

        router.resolveCachedIdentity("first")
        await router.checkHistoricalPurchases(identity: "first")
        XCTAssertEqual(router.route, .legacy)
        check = LegacyCohort.TransactionCheck()
        router.resolveCachedIdentity("first")
        XCTAssertEqual(router.route, .legacy)
        router.resolveCachedIdentity("second")
        XCTAssertEqual(router.route, .new)
    }

    func testUnverifiedHistoryDoesNotBlockKnownNonMember() async {
        let suite = "ExperienceRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let router = ExperienceRouter(
            defaults: defaults,
            checkTransactions: { LegacyCohort.TransactionCheck(hasUnverifiedTransactions: true) },
            matchesIdentity: { _ in false },
            containsTransactionHash: { _ in false }
        )
        router.resolveCachedIdentity("first")
        XCTAssertEqual(router.route, .new)
        await router.checkHistoricalPurchases(identity: "first")
        XCTAssertEqual(router.route, .new)
        XCTAssertNil(defaults.string(forKey: "legacy.cohort.transaction." + LegacyCohort.digest("first")))
    }

    func testKnownLegacyIdentityRoutesBeforeTransactionLookup() async {
        let router = ExperienceRouter(
            checkTransactions: { XCTFail("Purchase history should not delay known legacy users"); return .init() },
            matchesIdentity: { $0 == "legacy" },
            containsTransactionHash: { _ in false }
        )
        router.resolveCachedIdentity("legacy")
        XCTAssertEqual(router.route, .legacy)
        await router.checkHistoricalPurchases(identity: "legacy")
    }
}
