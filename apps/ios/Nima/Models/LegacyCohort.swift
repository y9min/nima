import CryptoKit
import Foundation
import Observation
import StoreKit

enum ExperienceRoute: Equatable {
    case checking
    case legacy
    case new
}

/// Membership and paid access are deliberately separate decisions.
enum LegacyRoutePolicy {
    static func route(
        verifiedTransactionMatched: Bool,
        hasUnverifiedTransactions: Bool,
        identity: String?,
        identityResolved: Bool,
        matchesIdentity: (String) -> Bool
    ) -> ExperienceRoute {
        if verifiedTransactionMatched {
            return .legacy
        }
        if identityResolved, let identity, matchesIdentity(identity) {
            return .legacy
        }
        // A failed verification or unresolved identity is not evidence of non-membership.
        guard !hasUnverifiedTransactions, identityResolved else { return .checking }
        return .new
    }
}

/// Cohort membership is independent of the current subscription entitlement.
enum LegacyCohort {
    private static let transactionHashes: Set<String> = [
        "961ac0e9b7b90c207b849fb34e32bdfecb19790f129e3efee83663e0356a0cb9",
        "a175adec938351fbd0aa84cb298b2f8e84e1664138fad67c62a143ab4201a1b4",
        "a842d7206920550edaf950dbf823d3f5a143c4dd4799fd26829b65f73b66e05d",
    ]
    private static let identityHashes: Set<String> = [
        "329ff90334912ef03cae1abe4860b0c3dbfb9f6e580df9cd3d1d37b9dcf584e6",
        "355505a7d17dc58789730789ab46b38d95840c00071cd3424badb07f6d4bd1db",
        "54d06fbfd17ad4dc26fce7cb1d3d528fda67edc6a2ffd8c13b1f0e0be6911d54",
        "60a14aeea75b87f6b6d2277b02490aee3f0e3fde20f45c127023314071cbfebc",
        "ccf8a0a613be7ebfc97f92dd519b68897192c6123fff840c3f2421ee73c0a24d",
        "d6ece487610f75dea526e62116d0f58d558dd56b3cdd76bd446ac5b3382ed796",
    ]

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func matches(originalTransactionID: UInt64) -> Bool {
        transactionHashes.contains(digest(String(originalTransactionID)))
    }

    static func matches(revenueCatIdentity: String) -> Bool {
        identityHashes.contains(digest(revenueCatIdentity))
    }

    struct TransactionCheck {
        var matchedHash: String?
        var hasUnverifiedTransactions = false
    }

    static func checkTransactions() async -> TransactionCheck {
        var check = TransactionCheck()
        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                if transaction.environment == .production,
                   matches(originalTransactionID: transaction.originalID) {
                    check.matchedHash = digest(String(transaction.originalID))
                }
            case .unverified:
                check.hasUnverifiedTransactions = true
            }
        }
        return check
    }

    static func containsTransactionHash(_ hash: String) -> Bool {
        transactionHashes.contains(hash)
    }
}

/// Only a verified purchase can populate the cache. Cache entries are scoped to
/// the current RevenueCat identity so an identity switch cannot inherit access.
@MainActor
@Observable
final class ExperienceRouter {
    private(set) var route: ExperienceRoute = .checking
    private let defaults: UserDefaults
    private let checkTransactions: () async -> LegacyCohort.TransactionCheck
    private let matchesIdentity: (String) -> Bool
    private let containsTransactionHash: (String) -> Bool
    private var generation = 0
    private let cachePrefix = "legacy.cohort.transaction."

    init(
        defaults: UserDefaults = .standard,
        checkTransactions: @escaping () async -> LegacyCohort.TransactionCheck = LegacyCohort.checkTransactions,
        matchesIdentity: @escaping (String) -> Bool = LegacyCohort.matches(revenueCatIdentity:),
        containsTransactionHash: @escaping (String) -> Bool = LegacyCohort.containsTransactionHash
    ) {
        self.defaults = defaults
        self.checkTransactions = checkTransactions
        self.matchesIdentity = matchesIdentity
        self.containsTransactionHash = containsTransactionHash
    }

    func resolveCachedIdentity(_ identity: String?) {
        generation += 1
        let validIdentity = identity.flatMap { $0.isEmpty ? nil : $0 }
        guard let validIdentity else {
            route = .checking
            return
        }
        let key = cachePrefix + LegacyCohort.digest(validIdentity)
        let cachedHash = defaults.string(forKey: key)
        route = matchesIdentity(validIdentity) || cachedHash.map(containsTransactionHash) == true
            ? .legacy : .new
    }

    func checkHistoricalPurchases(identity: String?) async {
        guard let identity, !identity.isEmpty, route == .new else { return }
        let currentGeneration = generation
        let check = await checkTransactions()
        guard generation == currentGeneration, let hash = check.matchedHash,
              containsTransactionHash(hash) else { return }
        defaults.set(hash, forKey: cachePrefix + LegacyCohort.digest(identity))
        route = .legacy
    }
}
