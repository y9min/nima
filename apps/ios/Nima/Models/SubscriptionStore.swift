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

struct SubscriptionCustomerStatus: Equatable {
    let activeEntitlementIDs: [String]
    let activeSubscriptionIDs: [String]

    init(activeEntitlementIDs: some Sequence<String>, activeSubscriptionIDs: some Sequence<String>) {
        self.activeEntitlementIDs = Array(activeEntitlementIDs)
        self.activeSubscriptionIDs = Array(activeSubscriptionIDs)
    }
}

struct RevenueCatClient {
    typealias CustomerStatusCompletion = (SubscriptionCustomerStatus?, Error?) -> Void
    typealias OfferingsCompletion = (RevenueCat.Offerings?, Error?) -> Void
    typealias PurchaseCompletion = (SubscriptionCustomerStatus?, Error?, Bool) -> Void
    typealias CustomerStatusUpdate = (SubscriptionCustomerStatus) -> Void

    let configure: (String, String, @escaping CustomerStatusUpdate) -> Void
    let currentAppUserID: () -> String?
    let getCustomerInfo: (Bool, @escaping CustomerStatusCompletion) -> Void
    let getOfferings: (@escaping OfferingsCompletion) -> Void
    let purchase: (RevenueCat.Package, @escaping PurchaseCompletion) -> Void
    let restorePurchases: (@escaping CustomerStatusCompletion) -> Void
    let syncPurchases: (@escaping CustomerStatusCompletion) -> Void
    let logIn: (String, @escaping CustomerStatusCompletion) -> Void

    static let live = RevenueCatClient(
        configure: { apiKey, appUserID, customerStatusUpdate in
            #if DEBUG
            Purchases.logLevel = .debug
            #else
            Purchases.logLevel = .warn
            #endif
            Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
            RevenueCatRuntime.delegate.onUpdate = customerStatusUpdate
            Purchases.shared.delegate = RevenueCatRuntime.delegate
        },
        currentAppUserID: {
            Purchases.shared.appUserID
        },
        getCustomerInfo: { forceRefresh, completion in
            let fetchPolicy: CacheFetchPolicy = forceRefresh ? .fetchCurrent : .default
            Purchases.shared.getCustomerInfo(fetchPolicy: fetchPolicy) { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        getOfferings: { completion in
            Purchases.shared.getOfferings(completion: completion)
        },
        purchase: { package, completion in
            Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error, userCancelled)
            }
        },
        restorePurchases: { completion in
            Purchases.shared.restorePurchases { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        syncPurchases: { completion in
            Purchases.shared.syncPurchases { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        logIn: { appUserID, completion in
            Purchases.shared.logIn(appUserID) { customerInfo, _, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        }
    )
}

private final class RevenueCatCustomerInfoDelegate: NSObject, PurchasesDelegate {
    var onUpdate: RevenueCatClient.CustomerStatusUpdate?

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
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
            activeSubscriptionIDs: customerInfo.activeSubscriptions
        )
    }
}

@Observable
final class SubscriptionStore {
    static let premiumEntitlementID = "nima Pro"
    static let requestTimeoutNanoseconds: UInt64 = 10_000_000_000
    private static let lastBoundAppUserIDKey = "subscription.lastBoundAppUserID"
    private static let migrationKeyPrefix = "subscription.identityMigration.v1."
    private static let cachedPremiumKeyPrefix = "subscription.hasPremium."

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

    var hasPendingPurchase: Bool {
        purchaseRequestID != nil
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
        }
    }

    deinit {
        customerInfoTimeoutTask?.cancel()
        offeringsTimeoutTask?.cancel()
        restoreTimeoutTask?.cancel()
    }

    func bindAuthenticatedUser(userID: UUID) {
        let appUserID = userID.uuidString.lowercased()
        let previousAppUserID = defaults.string(forKey: Self.lastBoundAppUserIDKey)

        if intendedAppUserID != appUserID {
            cancelAllRequests()
            intendedAppUserID = appUserID
            hasConfirmedIdentity = false
            needsReceiptSync = previousAppUserID != appUserID
                || !defaults.bool(forKey: Self.migrationKey(for: appUserID))
            hasPremium = defaults.bool(forKey: Self.cachedPremiumKey(for: appUserID))
            verificationState = .loading
        }

        if !isConfigured {
            configure(appUserID: appUserID)
            guard isConfigured else { return }
            hasConfirmedIdentity = true
            continueAfterIdentityBinding(appUserID: appUserID)
        } else if client.currentAppUserID() == appUserID {
            hasConfirmedIdentity = true
            continueAfterIdentityBinding(appUserID: appUserID)
        } else {
            logIn(appUserID: appUserID)
        }

        loadOfferings()
    }

    private func configure(appUserID: String) {
        guard !isConfigured else { return }
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
            verificationState = .failed("Missing RevenueCat API key.")
            return
        }

        client.configure(apiKey, appUserID) { [weak self] status in
            Task { @MainActor in
                guard let self,
                      self.intendedAppUserID == appUserID,
                      !self.needsReceiptSync,
                      self.client.currentAppUserID() == appUserID else { return }
                _ = self.apply(status)
            }
        }
        isConfigured = true
    }

    private func logIn(appUserID: String) {
        let requestID = beginCustomerInfoRequest()
        client.logIn(appUserID) { [weak self] status, error in
            Task { @MainActor in
                guard let self,
                      self.customerInfoRequestID == requestID,
                      self.intendedAppUserID == appUserID else { return }
                if let error {
                    self.markVerificationFailedIfNeeded(error.localizedDescription)
                    self.finishCustomerInfoRequest(result: nil)
                    return
                }
                self.hasConfirmedIdentity = true
                if self.needsReceiptSync {
                    self.finishCustomerInfoRequest(result: nil)
                    self.syncReceipt(appUserID: appUserID)
                } else {
                    let access = self.apply(status)
                    self.defaults.set(appUserID, forKey: Self.lastBoundAppUserIDKey)
                    self.finishCustomerInfoRequest(result: access)
                }
            }
        }
    }

    private func continueAfterIdentityBinding(appUserID: String) {
        if needsReceiptSync {
            syncReceipt(appUserID: appUserID)
        } else {
            refreshCustomerInfo()
        }
    }

    func retrySubscriptionCheck() {
        guard isConfigured, let appUserID = intendedAppUserID else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return
        }
        if !hasConfirmedIdentity, client.currentAppUserID() != appUserID {
            logIn(appUserID: appUserID)
        } else if needsReceiptSync {
            syncReceipt(appUserID: appUserID)
        } else {
            refreshCustomerInfo(forceRefresh: true)
        }
        loadOfferings()
    }

    func refreshAfterForeground() {
        guard isConfigured, intendedAppUserID != nil, hasConfirmedIdentity else { return }
        refreshCustomerInfo(forceRefresh: true, updatesVerificationState: false)
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

    func activateDemoAnnualPlan() {
        finishCustomerInfoRequest(result: nil)
        intendedAppUserID = nil
        hasConfirmedIdentity = false
        needsReceiptSync = false
        verificationState = .verified
        purchaseErrorMessage = nil
        restoreErrorMessage = nil
        hasPremium = true
    }

    func unbindUser() {
        cancelAllRequests()
        clearLocalAccess()
        intendedAppUserID = nil
        hasConfirmedIdentity = false
        needsReceiptSync = false
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
            markVerificationFailedIfNeeded("Sign in again to check your subscription.")
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
                self.defaults.set(true, forKey: Self.migrationKey(for: appUserID))
                self.defaults.set(appUserID, forKey: Self.lastBoundAppUserIDKey)
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
        guard let access = Self.premiumAccess(from: status) else {
            verificationState = .failed("We couldn’t check your subscription. Please try again.")
            return nil
        }

        verificationState = .verified
        setPremiumAccess(access)
        return access
    }

    private func cancelAllRequests() {
        finishCustomerInfoRequest(result: nil)
        finishOfferingsRequest()
        finishPurchaseRequest()
        finishRestoreRequest()
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

    private func clearLocalAccess() {
        hasPremium = false
        verificationState = .idle
        offeringsState = .idle
        currentOffering = nil
        monthlyPackage = nil
        yearlyPackage = nil
        purchaseErrorMessage = nil
        restoreErrorMessage = nil
    }

    private func setPremiumAccess(_ hasAccess: Bool) {
        hasPremium = hasAccess
        guard let appUserID = intendedAppUserID else { return }
        defaults.set(hasAccess, forKey: Self.cachedPremiumKey(for: appUserID))
    }

    private static func premiumAccess(from status: SubscriptionCustomerStatus?) -> Bool? {
        guard let status else { return nil }
        return resolvesPremiumAccess(
            activeEntitlementIDs: status.activeEntitlementIDs,
            activeSubscriptionIDs: status.activeSubscriptionIDs
        )
    }

    private static func migrationKey(for appUserID: String) -> String {
        migrationKeyPrefix + appUserID
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
