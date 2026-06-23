import Foundation
import Observation
import RevenueCat

@Observable
final class SubscriptionStore {
    static let premiumEntitlementID = "nima Pro"
    private static let cachedPremiumKey = "subscription.hasPremium"

    var hasPremium: Bool
    var hasCheckedCustomerInfo: Bool = false
    var isLoadingOfferings: Bool = false
    var isPurchasing: Bool = false
    var isRestoring: Bool = false
    var monthlyPackage: RevenueCat.Package?
    var yearlyPackage: RevenueCat.Package?
    var errorMessage: String?
    var isReadyForPaywallDecision: Bool {
        hasPremium || hasCheckedCustomerInfo || hasUnrecoverableConfigurationError
    }

    private let defaults: UserDefaults
    private var isConfigured = false
    private var hasUnrecoverableConfigurationError = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasPremium = defaults.bool(forKey: Self.cachedPremiumKey)
    }

    func configure() {
        guard !isConfigured else { return }
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
            hasUnrecoverableConfigurationError = true
            errorMessage = "Missing RevenueCat API key."
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

    func identify(appUserID: String) {
        guard isConfigured, !appUserID.isEmpty else { return }
        Purchases.shared.logIn(appUserID) { [weak self] customerInfo, _, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    self?.refreshCustomerInfo()
                    return
                }
                self?.apply(customerInfo)
            }
        }
    }

    func activateDemoAnnualPlan() {
        hasCheckedCustomerInfo = true
        hasUnrecoverableConfigurationError = false
        errorMessage = nil
        setPremiumAccess(true)
    }

    func logOut() {
        clearLocalAccess()
        guard isConfigured else { return }
        Purchases.shared.logOut { [weak self] customerInfo, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.apply(customerInfo)
            }
        }
    }

    func refreshCustomerInfo() {
        guard isConfigured else { return }
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.apply(customerInfo)
            }
        }
    }

    func loadOfferings() {
        guard isConfigured else { return }
        isLoadingOfferings = true
        Purchases.shared.getOfferings { [weak self] offerings, error in
            Task { @MainActor in
                self?.isLoadingOfferings = false
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                let current = offerings?.current
                self?.monthlyPackage = current?.monthly ?? current?.availablePackages.first
                self?.yearlyPackage = current?.annual ?? current?.availablePackages.last
            }
        }
    }

    func purchase(_ package: RevenueCat.Package, onUnlocked: @escaping () -> Void) {
        guard isConfigured else { return }
        isPurchasing = true
        errorMessage = nil
        Purchases.shared.purchase(package: package) { [weak self] _, customerInfo, error, userCancelled in
            Task { @MainActor in
                self?.isPurchasing = false
                if userCancelled { return }
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                self?.apply(customerInfo)
                if self?.hasPremium == true {
                    onUnlocked()
                }
            }
        }
    }

    func restore(onUnlocked: @escaping () -> Void) {
        guard isConfigured else { return }
        isRestoring = true
        errorMessage = nil
        Purchases.shared.restorePurchases { [weak self] customerInfo, error in
            Task { @MainActor in
                self?.isRestoring = false
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                self?.apply(customerInfo)
                if self?.hasPremium == true {
                    onUnlocked()
                } else {
                    self?.errorMessage = "No active subscription was found."
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

    private func apply(_ customerInfo: CustomerInfo?) {
        guard let customerInfo else { return }
        hasCheckedCustomerInfo = true
        errorMessage = nil
        setPremiumAccess(Self.resolvesPremiumAccess(
            activeEntitlementIDs: customerInfo.entitlements.active.keys,
            activeSubscriptionIDs: customerInfo.activeSubscriptions
        ))
    }

    private func clearLocalAccess() {
        hasPremium = false
        hasCheckedCustomerInfo = false
        errorMessage = nil
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
