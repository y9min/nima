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

    let getCustomerInfo: (@escaping CustomerStatusCompletion) -> Void
    let getOfferings: (@escaping OfferingsCompletion) -> Void
    let purchase: (RevenueCat.Package, @escaping PurchaseCompletion) -> Void
    let restorePurchases: (@escaping CustomerStatusCompletion) -> Void
    let logIn: (String, @escaping CustomerStatusCompletion) -> Void
    let logOut: (@escaping CustomerStatusCompletion) -> Void

    static let live = RevenueCatClient(
        getCustomerInfo: { completion in
            Purchases.shared.getCustomerInfo { customerInfo, error in
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
        logIn: { appUserID, completion in
            Purchases.shared.logIn(appUserID) { customerInfo, _, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        },
        logOut: { completion in
            Purchases.shared.logOut { customerInfo, error in
                completion(customerInfo.map(SubscriptionCustomerStatus.init), error)
            }
        }
    )
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
    private static let cachedPremiumKey = "subscription.hasPremium"

    var hasPremium: Bool
    var verificationState: SubscriptionVerificationState = .idle
    var offeringsState: OfferingsLoadState = .idle
    var isPurchasing: Bool = false
    var isRestoring: Bool = false
    var monthlyPackage: RevenueCat.Package?
    var yearlyPackage: RevenueCat.Package?
    var purchaseErrorMessage: String?
    var restoreErrorMessage: String?

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

    private var customerInfoTimeoutTask: Task<Void, Never>?
    private var offeringsTimeoutTask: Task<Void, Never>?
    private var purchaseTimeoutTask: Task<Void, Never>?
    private var restoreTimeoutTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        client: RevenueCatClient? = nil,
        timeoutNanoseconds: UInt64 = SubscriptionStore.requestTimeoutNanoseconds
    ) {
        self.defaults = defaults
        self.hasPremium = defaults.bool(forKey: Self.cachedPremiumKey)
        self.client = client ?? .live
        self.timeoutNanoseconds = timeoutNanoseconds
        self.isConfigured = client != nil
    }

    deinit {
        customerInfoTimeoutTask?.cancel()
        offeringsTimeoutTask?.cancel()
        purchaseTimeoutTask?.cancel()
        restoreTimeoutTask?.cancel()
    }

    func configure() {
        guard !isConfigured else { return }
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
            verificationState = .failed("Missing RevenueCat API key.")
            return
        }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true
    }

    func refreshAfterLaunch() {
        guard isConfigured else { return }
        refreshCustomerInfo()
        loadOfferings()
    }

    func retrySubscriptionCheck() {
        guard isConfigured else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return
        }
        refreshCustomerInfo()
        loadOfferings()
    }

    func retryOfferings() {
        loadOfferings()
    }

    func identify(appUserID: String) {
        guard isConfigured, !appUserID.isEmpty else { return }
        let requestID = beginCustomerInfoRequest()

        client.logIn(appUserID) { [weak self] status, error in
            Task { @MainActor in
                guard let self, self.customerInfoRequestID == requestID else { return }
                self.finishCustomerInfoRequest()

                if let error {
                    self.verificationState = .failed(error.localizedDescription)
                    return
                }
                self.apply(status)
            }
        }
    }

    func activateDemoAnnualPlan() {
        finishCustomerInfoRequest()
        verificationState = .verified
        purchaseErrorMessage = nil
        restoreErrorMessage = nil
        setPremiumAccess(true)
    }

    func logOut() {
        cancelAllRequests()
        clearLocalAccess()
        guard isConfigured else { return }

        client.logOut { [weak self] status, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.verificationState = .failed(error.localizedDescription)
                    return
                }
                self.apply(status)
            }
        }
    }

    func refreshCustomerInfo() {
        guard isConfigured else {
            verificationState = .failed("Subscriptions are unavailable right now.")
            return
        }
        let requestID = beginCustomerInfoRequest()

        client.getCustomerInfo { [weak self] status, error in
            Task { @MainActor in
                guard let self, self.customerInfoRequestID == requestID else { return }
                self.finishCustomerInfoRequest()

                if let error {
                    self.verificationState = .failed(error.localizedDescription)
                    return
                }
                self.apply(status)
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

        let requestID = UUID()
        purchaseRequestID = requestID
        purchaseTimeoutTask?.cancel()
        isPurchasing = true
        purchaseErrorMessage = nil

        purchaseTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.purchaseRequestID == requestID else { return }
            self.purchaseRequestID = nil
            self.purchaseTimeoutTask = nil
            self.isPurchasing = false
            self.purchaseErrorMessage = "The purchase is taking too long. Please try again."
        }

        client.purchase(package) { [weak self] status, error, userCancelled in
            Task { @MainActor in
                guard let self, self.purchaseRequestID == requestID else { return }
                self.finishPurchaseRequest()

                if userCancelled { return }
                if let error {
                    self.purchaseErrorMessage = error.localizedDescription
                    return
                }

                self.apply(status)
                if self.hasPremium {
                    onUnlocked()
                }
            }
        }
    }

    func restore(onUnlocked: @escaping () -> Void) {
        guard isConfigured else {
            restoreErrorMessage = "Restore is unavailable right now."
            return
        }

        let requestID = UUID()
        restoreRequestID = requestID
        restoreTimeoutTask?.cancel()
        isRestoring = true
        restoreErrorMessage = nil

        restoreTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.restoreRequestID == requestID else { return }
            self.restoreRequestID = nil
            self.restoreTimeoutTask = nil
            self.isRestoring = false
            self.restoreErrorMessage = "Restore is taking too long. Please try again."
        }

        client.restorePurchases { [weak self] status, error in
            Task { @MainActor in
                guard let self, self.restoreRequestID == requestID else { return }
                self.finishRestoreRequest()

                if let error {
                    self.restoreErrorMessage = error.localizedDescription
                    return
                }

                self.apply(status)
                if self.hasPremium {
                    onUnlocked()
                } else {
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

    private func beginCustomerInfoRequest() -> UUID {
        let requestID = UUID()
        customerInfoRequestID = requestID
        customerInfoTimeoutTask?.cancel()
        verificationState = .loading

        customerInfoTimeoutTask = timeoutTask { [weak self] in
            guard let self, self.customerInfoRequestID == requestID else { return }
            self.customerInfoRequestID = nil
            self.customerInfoTimeoutTask = nil
            self.verificationState = .failed("We couldn’t check your subscription. Please try again.")
        }
        return requestID
    }

    private func finishCustomerInfoRequest() {
        customerInfoRequestID = nil
        customerInfoTimeoutTask?.cancel()
        customerInfoTimeoutTask = nil
    }

    private func finishOfferingsRequest() {
        offeringsRequestID = nil
        offeringsTimeoutTask?.cancel()
        offeringsTimeoutTask = nil
    }

    private func finishPurchaseRequest() {
        purchaseRequestID = nil
        purchaseTimeoutTask?.cancel()
        purchaseTimeoutTask = nil
        isPurchasing = false
    }

    private func finishRestoreRequest() {
        restoreRequestID = nil
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

    private func apply(_ status: SubscriptionCustomerStatus?) {
        guard let status else {
            verificationState = .failed("We couldn’t check your subscription. Please try again.")
            return
        }

        verificationState = .verified
        setPremiumAccess(Self.resolvesPremiumAccess(
            activeEntitlementIDs: status.activeEntitlementIDs,
            activeSubscriptionIDs: status.activeSubscriptionIDs
        ))
    }

    private func cancelAllRequests() {
        finishCustomerInfoRequest()
        finishOfferingsRequest()
        finishPurchaseRequest()
        finishRestoreRequest()
    }

    private func clearLocalAccess() {
        hasPremium = false
        verificationState = .idle
        offeringsState = .idle
        monthlyPackage = nil
        yearlyPackage = nil
        purchaseErrorMessage = nil
        restoreErrorMessage = nil
        defaults.set(false, forKey: Self.cachedPremiumKey)
    }

    private func setPremiumAccess(_ hasAccess: Bool) {
        hasPremium = hasAccess
        defaults.set(hasAccess, forKey: Self.cachedPremiumKey)
    }

    static func resolvesPremiumAccess(
        activeEntitlementIDs: some Sequence<String>,
        activeSubscriptionIDs: some Sequence<String>
    ) -> Bool {
        let expectedEntitlement = normalizedRevenueCatIdentifier(premiumEntitlementID)
        let hasMatchingEntitlement = activeEntitlementIDs.contains { entitlementID in
            normalizedRevenueCatIdentifier(entitlementID) == expectedEntitlement
        }
        return hasMatchingEntitlement || activeSubscriptionIDs.contains { !$0.isEmpty }
    }

    private static func normalizedRevenueCatIdentifier(_ identifier: String) -> String {
        var normalized = ""
        for scalar in identifier.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            normalized.unicodeScalars.append(scalar)
        }
        return normalized
    }
}
