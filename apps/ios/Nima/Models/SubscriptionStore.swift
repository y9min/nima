import Foundation
import Observation
import RevenueCat

enum SubscriptionVerificationState: Equatable {
    case idle
    case loading
    case verified
    case failed(String)
}

enum OfferingsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

typealias FeatureAccessAuthorizer = (@escaping @MainActor () -> Void) -> Void

enum FeatureAccessGate {
    static let unrestricted: FeatureAccessAuthorizer = { action in
        MainActor.assumeIsolated {
            action()
        }
    }
}

struct SubscriptionCustomerStatus: Equatable {
    let activeEntitlementIDs: [String]
    let activeSubscriptionIDs: [String]
    let premiumExpirationDate: Date?

    init(activeEntitlementIDs: some Sequence<String>, activeSubscriptionIDs: some Sequence<String>, premiumExpirationDate: Date? = nil) {
        self.activeEntitlementIDs = Array(activeEntitlementIDs)
        self.activeSubscriptionIDs = Array(activeSubscriptionIDs)
        self.premiumExpirationDate = premiumExpirationDate
    }
}

struct RevenueCatClient {
    typealias CustomerStatusCompletion = (SubscriptionCustomerStatus?, Error?) -> Void
    typealias OfferingsCompletion = (RevenueCat.Offerings?, Error?) -> Void
    typealias PurchaseCompletion = (SubscriptionCustomerStatus?, Error?, Bool) -> Void
    typealias CustomerStatusUpdate = (SubscriptionCustomerStatus) -> Void

    let configure: (String, String?, @escaping CustomerStatusUpdate) -> Void
    let currentAppUserID: () -> String?
    let getCustomerInfo: (Bool, @escaping CustomerStatusCompletion) -> Void
    let getOfferings: (@escaping OfferingsCompletion) -> Void
    let purchase: (RevenueCat.Package, @escaping PurchaseCompletion) -> Void
    let restorePurchases: (@escaping CustomerStatusCompletion) -> Void
    let syncPurchases: (@escaping CustomerStatusCompletion) -> Void
    let setAttributes: ([String: String]) -> Void

    static let live = RevenueCatClient(
        configure: { apiKey, appUserID, customerStatusUpdate in
            #if DEBUG
            Purchases.logLevel = .debug
            #else
            Purchases.logLevel = .warn
            #endif
            if let appUserID {
                Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
            } else {
                Purchases.configure(withAPIKey: apiKey)
            }
            RevenueCatRuntime.delegate.onUpdate = customerStatusUpdate
            Purchases.shared.delegate = RevenueCatRuntime.delegate
            MainActor.assumeIsolated { MetaAdsService.shared.updateRevenueCatAttribution() }
        },
        currentAppUserID: {
            Purchases.shared.appUserID
        },
        getCustomerInfo: { forceRefresh, completion in
            let fetchPolicy: CacheFetchPolicy = forceRefresh ? .fetchCurrent : .default
            Purchases.shared.getCustomerInfo(fetchPolicy: fetchPolicy) { customerInfo, error in
                if error == nil, let customerInfo {
                    Task { @MainActor in AcquisitionTrackingService.shared.subscriptionUpdated(customerInfo) }
                }
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        getOfferings: { completion in
            Purchases.shared.getOfferings(completion: completion)
        },
        purchase: { package, completion in
            MainActor.assumeIsolated { MetaAdsService.shared.updateRevenueCatAttribution() }
            Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                if error == nil, !userCancelled, let customerInfo {
                    Task { @MainActor in AcquisitionTrackingService.shared.purchaseCompleted(customerInfo) }
                }
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error, userCancelled)
            }
        },
        restorePurchases: { completion in
            MainActor.assumeIsolated { MetaAdsService.shared.updateRevenueCatAttribution() }
            Purchases.shared.restorePurchases { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        syncPurchases: { completion in
            MainActor.assumeIsolated { MetaAdsService.shared.updateRevenueCatAttribution() }
            Purchases.shared.syncPurchases { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        setAttributes: { attributes in
            Purchases.shared.attribution.setAttributes(attributes)
        }
    )
}

private final class RevenueCatCustomerInfoDelegate: NSObject, PurchasesDelegate {
    var onUpdate: RevenueCatClient.CustomerStatusUpdate?

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in AcquisitionTrackingService.shared.subscriptionUpdated(customerInfo) }
        onUpdate?(SubscriptionCustomerStatus(customerInfo))
    }
}

private enum RevenueCatRuntime {
    static let delegate = RevenueCatCustomerInfoDelegate()
}

private extension SubscriptionCustomerStatus {
    init(_ customerInfo: CustomerInfo) {
        self.init(
            activeEntitlementIDs: customerInfo.entitlements.active.keys,
            activeSubscriptionIDs: customerInfo.activeSubscriptions,
            premiumExpirationDate: customerInfo.entitlements.active.first {
                $0.key.lowercased().filter(\.isLetter) == "nimapro"
            }?.value.expirationDate
        )
    }
}

@Observable
final class SubscriptionStore {
    static let premiumEntitlementID = "nima Pro"
    static let requestTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let cachedPremiumKeyPrefix = "subscription.hasPremium."
    private static let entitlementExpiryKeyPrefix = "subscription.entitlementExpiry."
    private static let temporaryPremiumUntilKey = "subscription.temporaryPremiumUntil"
    static let offlineGraceDuration: TimeInterval = 72 * 60 * 60

    var hasPremium: Bool
    var verificationState: SubscriptionVerificationState = .idle
    var offeringsState: OfferingsLoadState = .idle
    var isPurchasing: Bool = false
    var isRestoring: Bool = false
    var currentOffering: RevenueCat.Offering?
    var monthlyPackage: RevenueCat.Package?
    var yearlyPackage: RevenueCat.Package?
    var purchaseErrorMessage: String?
    var restoreErrorMessage: String?
    private(set) var cohortCheckRevision = 0

    var cohortIdentity: String? {
        guard isConfigured, hasConfirmedIdentity,
              let intendedAppUserID, client.currentAppUserID() == intendedAppUserID else { return nil }
        return intendedAppUserID
    }

    var hasPendingPurchase: Bool {
        purchaseRequestID != nil
    }

    var hasTemporaryPremiumAccess: Bool {
        guard let expiry = defaults.object(forKey: Self.temporaryPremiumUntilKey) as? Date else { return false }
        return expiry > Date()
    }

    var hasAccessForRouting: Bool {
        hasPremium && hasTemporaryPremiumAccess && cohortIdentity != nil
    }

    var isLoadingOfferings: Bool {
        offeringsState == .loading
    }

    var offeringsErrorMessage: String? {
        guard case .failed(let message) = offeringsState else { return nil }
        return message
    }

    private let defaults: UserDefaults
    private let client: RevenueCatClient
    private let timeoutNanoseconds: UInt64
    private var isConfigured: Bool

    private var customerInfoRequestID: UUID?
    private var offeringsRequestID: UUID?
    private var purchaseRequestID: UUID?
    private var restoreRequestID: UUID?
    private var restoreTimedOutRequestID: UUID?

    private var customerInfoTimeoutTask: Task<Void, Never>?
    private var premiumExpiryTask: Task<Void, Never>?
    private var offeringsTimeoutTask: Task<Void, Never>?
    private var restoreTimeoutTask: Task<Void, Never>?
    private var customerInfoCompletion: ((Bool?) -> Void)?
    private var customerInfoRequestUpdatesVerificationState = true
    private var intendedAppUserID: String?
    private var hasConfirmedIdentity = false
    private var needsReceiptSync = false
    private var isReconcilingPurchase = false

    init(
        defaults: UserDefaults = .standard,
        client: RevenueCatClient? = nil,
        timeoutNanoseconds: UInt64 = SubscriptionStore.requestTimeoutNanoseconds
    ) {
        self.defaults = defaults
        self.hasPremium = false
        self.client = client ?? .live
        self.timeoutNanoseconds = timeoutNanoseconds
        self.isConfigured = client != nil
        if client != nil {
            let testAppUserID = "test-user"
            self.intendedAppUserID = testAppUserID
            self.hasConfirmedIdentity = true
            self.hasPremium = defaults.bool(forKey: Self.cachedPremiumKey(for: testAppUserID))
            expireCachedPremiumAccessIfNeeded()
        }
    }

    deinit {
        customerInfoTimeoutTask?.cancel()
        premiumExpiryTask?.cancel()
        offeringsTimeoutTask?.cancel()
        restoreTimeoutTask?.cancel()
    }

    func configureAnonymousUser() {
        guard intendedAppUserID == nil else { return }

        if !isConfigured {
            guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
                verificationState = .failed("Missing RevenueCat API key.")
                return
            }
            client.configure(apiKey, nil) { [weak self] status in
                Task { @MainActor in
                    guard let self,
                          self.intendedAppUserID == self.client.currentAppUserID() else { return }
                    _ = self.apply(status)
                }
            }
            isConfigured = true
        }

        guard let appUserID = client.currentAppUserID(), !appUserID.isEmpty else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return
        }
        intendedAppUserID = appUserID
        hasConfirmedIdentity = true
        cohortCheckRevision += 1
        hasPremium = defaults.bool(forKey: Self.cachedPremiumKey(for: appUserID))
        let expiredCachedAccess = expireCachedPremiumAccessIfNeeded()
        schedulePremiumExpiry()
        let knownExpired = expiredCachedAccess && verificationState == .verified
        if !knownExpired { verificationState = .loading }
        refreshCustomerInfo(updatesVerificationState: !knownExpired)
        loadOfferings()
        if let postHogUserID = AnalyticsService.shared.distinctID {
            client.setAttributes(["$posthogUserId": postHogUserID])
        }
    }
    func retrySubscriptionCheck() {
        guard isConfigured, let appUserID = intendedAppUserID else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return
        }
        guard hasConfirmedIdentity, client.currentAppUserID() == appUserID else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            loadOfferings()
            return
        }
        if needsReceiptSync {
            syncReceipt(appUserID: appUserID)
        } else {
            refreshCustomerInfo(forceRefresh: true)
        }
        loadOfferings()
    }

    func refreshAfterForeground() {
        guard isConfigured, intendedAppUserID != nil, hasConfirmedIdentity else { return }
        guard let currentIdentity = client.currentAppUserID(), !currentIdentity.isEmpty else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            cohortCheckRevision += 1
            return
        }
        if currentIdentity != intendedAppUserID {
            intendedAppUserID = currentIdentity
            // The older grace deadline was shared across identities. Require a
            // fresh check rather than applying another identity's deadline here.
            hasPremium = false
            defaults.removeObject(forKey: Self.temporaryPremiumUntilKey)
            premiumExpiryTask?.cancel()
            verificationState = .loading
            cohortCheckRevision += 1
            expireCachedPremiumAccessIfNeeded()
            schedulePremiumExpiry()
            refreshCustomerInfo(forceRefresh: true)
            return
        }
        let expiredCachedAccess = expireCachedPremiumAccessIfNeeded()
        refreshCustomerInfo(
            forceRefresh: true,
            updatesVerificationState: expiredCachedAccess && verificationState != .verified
        )
    }

    @MainActor
    func authorizeFeatureAction(_ action: @escaping @MainActor () -> Void) {
        expireCachedPremiumAccessIfNeeded()
        guard !hasAccessForRouting else {
            action()
            return
        }

        refreshCustomerInfo(forceRefresh: true) { access in
            guard access == true else { return }
            action()
        }
    }

    func recoverExistingAppStorePurchase() {
        guard isConfigured, let appUserID = intendedAppUserID, hasConfirmedIdentity else { return }
        needsReceiptSync = true
        syncReceipt(appUserID: appUserID)
    }

    func reconcilePendingPurchaseAfterForeground() {
        guard hasPendingPurchase, !isReconcilingPurchase else { return }
        reconcilePendingPurchase()
    }

    func retryPurchaseConfirmation() {
        guard hasPendingPurchase, !isReconcilingPurchase else { return }
        isPurchasing = true
        purchaseErrorMessage = nil
        reconcilePendingPurchase()
    }

    func retryOfferings() {
        loadOfferings()
    }

    func refreshCustomerInfo(
        forceRefresh: Bool = false,
        updatesVerificationState: Bool = true,
        completion: ((Bool?) -> Void)? = nil
    ) {
        guard isConfigured else {
            if updatesVerificationState {
                verificationState = .failed("Subscriptions are unavailable right now.")
            }
            completion?(nil)
            return
        }
        let requestID = beginCustomerInfoRequest(
            updatesVerificationState: updatesVerificationState,
            completion: completion
        )

        guard intendedAppUserID != nil, hasConfirmedIdentity else {
            markVerificationFailedIfNeeded("Try again to check your subscription.")
            finishCustomerInfoRequest(result: nil)
            return
        }

        client.getCustomerInfo(forceRefresh) { [weak self] status, error in
            Task { @MainActor in
                guard let self, self.customerInfoRequestID == requestID else { return }

                if let error {
                    self.markVerificationFailedIfNeeded(error.localizedDescription)
                    self.finishCustomerInfoRequest(result: nil)
                    return
                }
                let access = self.apply(status)
                self.finishCustomerInfoRequest(result: access)
            }
        }
    }

    private func syncReceipt(appUserID: String) {
        let requestID = beginCustomerInfoRequest()
        client.syncPurchases { [weak self] status, error in
            Task { @MainActor in
                guard let self,
                      self.customerInfoRequestID == requestID,
                      self.intendedAppUserID == appUserID,
                      self.client.currentAppUserID() == appUserID else { return }

                if let error {
                    self.markVerificationFailedIfNeeded(error.localizedDescription)
                    self.finishCustomerInfoRequest(result: nil)
                    return
                }

                guard let access = self.apply(status) else {
                    self.finishCustomerInfoRequest(result: nil)
                    return
                }
                self.needsReceiptSync = false
                self.finishCustomerInfoRequest(result: access)
            }
        }
    }

    func loadOfferings() {
        guard isConfigured else {
            offeringsState = .failed("Plans are unavailable right now.")
            return
        }

        let requestID = UUID()
        offeringsRequestID = requestID
        offeringsTimeoutTask?.cancel()
        currentOffering = nil
        monthlyPackage = nil
        yearlyPackage = nil
        offeringsState = .loading

        offeringsTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.offeringsRequestID == requestID else { return }
            self.offeringsRequestID = nil
            self.offeringsTimeoutTask = nil
            self.offeringsState = .failed("Plans are taking too long to load.")
        }

        client.getOfferings { [weak self] offerings, error in
            Task { @MainActor in
                guard let self, self.offeringsRequestID == requestID else { return }
                self.finishOfferingsRequest()

                if let error {
                    self.offeringsState = .failed(error.localizedDescription)
                    return
                }

                let current = offerings?.current
                self.currentOffering = current
                self.monthlyPackage = current?.monthly ?? current?.availablePackages.first
                self.yearlyPackage = current?.annual ?? current?.availablePackages.last

                if self.monthlyPackage == nil, self.yearlyPackage == nil {
                    self.offeringsState = .failed("No subscription plans are available right now.")
                } else {
                    self.offeringsState = .loaded
                }
            }
        }
    }

    func purchase(_ package: RevenueCat.Package, onUnlocked: @escaping () -> Void) {
        guard isConfigured else {
            purchaseErrorMessage = "Purchases are unavailable right now."
            return
        }

        guard purchaseRequestID == nil else { return }
        let requestID = UUID()
        purchaseRequestID = requestID
        isPurchasing = true
        purchaseErrorMessage = nil

        client.purchase(package) { [weak self] status, error, userCancelled in
            Task { @MainActor in
                guard let self, self.purchaseRequestID == requestID else { return }
                self.finishPurchaseRequest()

                if userCancelled { return }
                if let error {
                    self.purchaseErrorMessage = error.localizedDescription
                    return
                }

                self.purchaseErrorMessage = nil
                _ = self.apply(status)
                if self.hasPremium {
                    onUnlocked()
                }
            }
        }
    }

    func handlePaywallCustomerInfo(_ customerInfo: CustomerInfo) {
        guard let appUserID = intendedAppUserID, client.currentAppUserID() == appUserID else { return }
        _ = apply(SubscriptionCustomerStatus(customerInfo))
    }

    func restore(onUnlocked: @escaping () -> Void) {
        guard isConfigured else {
            restoreErrorMessage = "Restore is unavailable right now."
            return
        }

        let requestID = UUID()
        restoreRequestID = requestID
        restoreTimedOutRequestID = nil
        restoreTimeoutTask?.cancel()
        isRestoring = true
        restoreErrorMessage = nil

        restoreTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.restoreRequestID == requestID else { return }
            self.restoreTimeoutTask = nil
            self.restoreTimedOutRequestID = requestID
            self.isRestoring = false
            self.restoreErrorMessage = "Restore is taking too long. Please try again."
        }

        client.restorePurchases { [weak self] status, error in
            Task { @MainActor in
                guard let self, self.restoreRequestID == requestID else { return }
                let didTimeOut = self.restoreTimedOutRequestID == requestID
                self.finishRestoreRequest()

                if let error {
                    if !didTimeOut {
                        self.restoreErrorMessage = error.localizedDescription
                    }
                    return
                }

                let access = Self.premiumAccess(from: status)
                if access == true {
                    self.restoreErrorMessage = nil
                    _ = self.apply(status)
                    onUnlocked()
                } else if !didTimeOut {
                    _ = self.apply(status)
                    self.restoreErrorMessage = "No active subscription was found."
                }
            }
        }
    }

    private static var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private func beginCustomerInfoRequest(
        updatesVerificationState: Bool = true,
        completion: ((Bool?) -> Void)? = nil
    ) -> UUID {
        let requestID = UUID()
        customerInfoCompletion?(nil)
        customerInfoRequestID = requestID
        customerInfoCompletion = completion
        customerInfoRequestUpdatesVerificationState = updatesVerificationState
        customerInfoTimeoutTask?.cancel()
        if updatesVerificationState {
            verificationState = .loading
        }

        customerInfoTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.customerInfoRequestID == requestID else { return }
            self.customerInfoRequestID = nil
            self.customerInfoTimeoutTask = nil
            self.markVerificationFailedIfNeeded("We couldn’t check your subscription. Please try again.")
            let completion = self.customerInfoCompletion
            self.customerInfoCompletion = nil
            completion?(nil)
        }
        return requestID
    }

    private func finishCustomerInfoRequest(result: Bool?) {
        customerInfoRequestID = nil
        customerInfoTimeoutTask?.cancel()
        customerInfoTimeoutTask = nil
        customerInfoRequestUpdatesVerificationState = true
        let completion = customerInfoCompletion
        customerInfoCompletion = nil
        completion?(result)
    }

    private func finishOfferingsRequest() {
        offeringsRequestID = nil
        offeringsTimeoutTask?.cancel()
        offeringsTimeoutTask = nil
    }

    private func finishPurchaseRequest() {
        purchaseRequestID = nil
        isPurchasing = false
        isReconcilingPurchase = false
    }

    private func finishRestoreRequest() {
        restoreRequestID = nil
        restoreTimedOutRequestID = nil
        restoreTimeoutTask?.cancel()
        restoreTimeoutTask = nil
        isRestoring = false
    }

    private func timeoutTask(action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let timeoutNanoseconds = timeoutNanoseconds
        return Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            action()
        }
    }

    @discardableResult
    private func apply(_ status: SubscriptionCustomerStatus?) -> Bool? {
        guard cohortIdentity != nil else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return nil
        }
        guard let resolvedAccess = Self.premiumAccess(from: status) else {
            verificationState = .failed("We couldn’t check your subscription. Please try again.")
            return nil
        }

        cohortCheckRevision += 1
        verificationState = .verified
        let unexpired = status?.premiumExpirationDate.map { $0 > Date() } ?? true
        let access = resolvedAccess && unexpired
        setPremiumAccess(access, expiresAt: status?.premiumExpirationDate)
        return access
    }

    private func reconcilePendingPurchase() {
        isReconcilingPurchase = true
        refreshCustomerInfo(
            forceRefresh: true,
            updatesVerificationState: false
        ) { [weak self] access in
            guard let self, self.hasPendingPurchase else { return }
            self.isReconcilingPurchase = false
            self.isPurchasing = false

            switch access {
            case true:
                self.finishPurchaseRequest()
                self.purchaseErrorMessage = nil
            case false:
                self.purchaseErrorMessage = "Purchase could not be confirmed. Try checking again."
            case nil:
                self.purchaseErrorMessage = "We couldn’t confirm your purchase. Try checking again."
            }
        }
    }

    private func markVerificationFailedIfNeeded(_ message: String) {
        if customerInfoRequestUpdatesVerificationState {
            verificationState = .failed(message)
        }
    }

    private func setPremiumAccess(_ hasAccess: Bool, expiresAt: Date? = nil) {
        hasPremium = hasAccess
        if hasAccess {
            defaults.set(
                min(Date().addingTimeInterval(Self.offlineGraceDuration), expiresAt ?? .distantFuture),
                forKey: Self.temporaryPremiumUntilKey
            )
        } else {
            defaults.removeObject(forKey: Self.temporaryPremiumUntilKey)
        }
        guard let appUserID = intendedAppUserID else { return }
        defaults.set(hasAccess, forKey: Self.cachedPremiumKey(for: appUserID))
        let expiryKey = Self.entitlementExpiryKeyPrefix + appUserID
        if hasAccess, let expiresAt {
            defaults.set(expiresAt, forKey: expiryKey)
        } else {
            defaults.removeObject(forKey: expiryKey)
        }
        schedulePremiumExpiry()
    }

    private func schedulePremiumExpiry() {
        premiumExpiryTask?.cancel()
        guard hasPremium, let expiry = defaults.object(forKey: Self.temporaryPremiumUntilKey) as? Date else { return }
        premiumExpiryTask = Task { @MainActor [weak self] in
            let delay = max(0, expiry.timeIntervalSinceNow)
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self else { return }
            let entitlementExpiry = self.intendedAppUserID.flatMap {
                self.defaults.object(forKey: Self.entitlementExpiryKeyPrefix + $0) as? Date
            }
            let entitlementExpired = entitlementExpiry.map { $0 <= Date() } ?? false
            if self.expireCachedPremiumAccessIfNeeded() {
                if entitlementExpired { self.verificationState = .verified }
                self.cohortCheckRevision += 1
                self.refreshCustomerInfo(forceRefresh: true, updatesVerificationState: !entitlementExpired)
            }
        }
    }

    @discardableResult
    private func expireCachedPremiumAccessIfNeeded() -> Bool {
        guard hasPremium, !hasTemporaryPremiumAccess else { return false }
        let entitlementExpired = intendedAppUserID.flatMap {
            defaults.object(forKey: Self.entitlementExpiryKeyPrefix + $0) as? Date
        }.map { $0 <= Date() } ?? false
        setPremiumAccess(false)
        verificationState = entitlementExpired ? .verified : .loading
        return true
    }

    private static func premiumAccess(from status: SubscriptionCustomerStatus?) -> Bool? {
        guard let status else { return nil }
        if let expirationDate = status.premiumExpirationDate, expirationDate <= Date() { return false }
        return resolvesPremiumAccess(
            activeEntitlementIDs: status.activeEntitlementIDs,
            activeSubscriptionIDs: status.activeSubscriptionIDs
        )
    }

    private static func cachedPremiumKey(for appUserID: String) -> String {
        cachedPremiumKeyPrefix + appUserID
    }

    static func resolvesPremiumAccess(
        activeEntitlementIDs: some Sequence<String>,
        activeSubscriptionIDs: some Sequence<String>
    ) -> Bool {
        let expectedEntitlement = normalizedRevenueCatIdentifier(premiumEntitlementID)
        let hasMatchingEntitlement = activeEntitlementIDs.contains { entitlementID in
            normalizedRevenueCatIdentifier(entitlementID) == expectedEntitlement
        }
        return hasMatchingEntitlement
    }

    private static func normalizedRevenueCatIdentifier(_ identifier: String) -> String {
        var normalized = ""
        for scalar in identifier.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            normalized.unicodeScalars.append(scalar)
        }
        return normalized
    }
}
