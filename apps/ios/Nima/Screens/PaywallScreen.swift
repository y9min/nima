import RevenueCat
import RevenueCatUI
import SwiftUI

struct PaywallScreen: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(AppStore.self) private var appStore
    @Environment(TimeWindowStore.self) private var timeWindowStore
    @Environment(AppControlRulesStore.self) private var appControlRulesStore
    @Environment(InstagramProtectionStore.self) private var instagramProtectionStore
    @Environment(TikTokProtectionStore.self) private var tiktokProtectionStore
    @Environment(XProtectionStore.self) private var xProtectionStore
    @Environment(ExperienceRouter.self) private var experienceRouter

    @Environment(\.scenePhase) private var scenePhase
    @State private var didPrepareMeasurement = false
    @State private var loadStartedAt: Date?
    @State private var didTrackLoadResult = false

    let onUnlocked: () -> Void
    let context: String
    var onClose: (() -> Void)?

    init(
        onUnlocked: @escaping () -> Void,
        context: String = "onboarding_gate",
        onClose: (() -> Void)? = nil
    ) {
        self.onUnlocked = onUnlocked
        self.context = context
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if !didPrepareMeasurement {
                    PaywallLoadingView()
                } else {
                    switch subscriptionStore.offeringsState {
                    case .idle, .loading:
                        PaywallLoadingView()
                    case .loaded:
                        if let offering = subscriptionStore.currentOffering, offering.hasPaywall {
                            RevenueCatPaywallView(offering: offering, context: context)
                        } else {
                            PaywallUnavailableView(
                                message: "The subscription screen is unavailable right now.",
                                onRetry: retryOfferings
                            )
                        }
                    case .failed(let message):
                        PaywallUnavailableView(message: message, onRetry: retryOfferings)
                    }
                }
            }

            if let onClose {
                Button {
                    AnalyticsService.shared.capture(
                        AnalyticsEvent.paywallClosed,
                        properties: ["context": context]
                    )
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.34), in: Circle())
                }
                .accessibilityLabel("Close subscription plans")
                .padding(.top, 12)
                .padding(.trailing, 16)
            }

        }
        .onAppear {
            suspendBlockingForPaywall()
        }
        .onDisappear {
            resumeBlockingAfterPaywall()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await MetaAdsService.shared.requestPermissionBeforePaywall()
            if !didPrepareMeasurement {
                didPrepareMeasurement = true
                AnalyticsService.shared.capture(
                    "paywall_screen_entered",
                    properties: ["context": context]
                )
            }
            if subscriptionStore.offeringsState == .idle {
                startLoadingOfferings()
            } else {
                trackOfferingsResult(subscriptionStore.offeringsState)
            }
        }
        .onChange(of: subscriptionStore.offeringsState) { _, state in
            trackOfferingsResult(state)
        }
        .onChange(of: subscriptionStore.hasPremium) { _, hasPremium in
            if hasPremium {
                onUnlocked()
            }
        }
        .accessibilityIdentifier("subscription.paywall")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @MainActor
    private func suspendBlockingForPaywall() {
        PaywallBlockingState.setActive(true)
        reconcileBlockingPolicies(source: "paywall.blocking_suspended")
    }

    @MainActor
    private func resumeBlockingAfterPaywall() {
        guard experienceRouter.route != .checking else { return }
        PaywallBlockingState.setActive(false)
        reconcileBlockingPolicies(source: "paywall.blocking_resumed")
    }

    @MainActor
    private func reconcileBlockingPolicies(source: String) {
        timeWindowStore.evaluateSchedules(source: source, forceApply: true)
        instagramProtectionStore.refreshPauseMode()
        tiktokProtectionStore.refreshPauseMode()
        xProtectionStore.refreshPauseMode()
        appControlRulesStore.reconcile()
        appStore.syncVPNState(source: source)
    }

    private func startLoadingOfferings() {
        loadStartedAt = Date()
        didTrackLoadResult = false
        AnalyticsService.shared.capture(
            AnalyticsEvent.paywallLoadStarted,
            properties: ["context": context]
        )
        subscriptionStore.loadOfferings()
    }

    private func retryOfferings() {
        startLoadingOfferings()
    }

    private func trackOfferingsResult(_ state: OfferingsLoadState) {
        guard !didTrackLoadResult else { return }
        let duration = max(0, Int(Date().timeIntervalSince(loadStartedAt ?? Date()) * 1_000))
        switch state {
        case .loaded:
            didTrackLoadResult = true
            AnalyticsService.shared.capture(
                AnalyticsEvent.paywallLoaded,
                properties: [
                    "context": context,
                    "duration_ms": duration,
                    "load_source": loadStartedAt == nil ? "cache" : "network",
                    "offering_id": subscriptionStore.currentOffering?.identifier ?? "unknown",
                    "has_revenuecat_paywall": subscriptionStore.currentOffering?.hasPaywall == true,
                ]
            )
        case .failed(let message):
            didTrackLoadResult = true
            AnalyticsService.shared.capture(
                AnalyticsEvent.paywallLoadFailed,
                properties: [
                    "context": context,
                    "duration_ms": duration,
                    "load_source": loadStartedAt == nil ? "cache" : "network",
                    "reason": message.contains("too long") ? "timeout" : "offerings_unavailable",
                ]
            )
        case .idle, .loading:
            break
        }
    }
}

private struct RevenueCatPaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore

    let offering: RevenueCat.Offering
    let context: String
    @State private var purchaseAttempt: PurchaseAnalyticsAttempt?
    @State private var didTrackImpression = false

    var body: some View {
        PaywallView(offering: offering, displayCloseButton: false)
            .onAppear {
                guard !didTrackImpression else { return }
                didTrackImpression = true
                AnalyticsService.shared.capture(AnalyticsEvent.paywallViewed, properties: [
                    "context": context,
                    "offering_id": offering.identifier,
                    "product_ids": offering.availablePackages.map { $0.storeProduct.productIdentifier },
                    "package_ids": offering.availablePackages.map(\.identifier),
                    "paywall_implementation": "revenuecat_ui",
                ])
            }
            .onPurchaseStarted { package in
                let attempt = PurchaseAnalyticsAttempt(
                    offeringID: offering.identifier,
                    packageID: package.identifier,
                    productID: package.storeProduct.productIdentifier,
                    price: NSDecimalNumber(decimal: package.storeProduct.price).doubleValue,
                    currencyCode: package.storeProduct.currencyCode,
                    localizedPrice: package.localizedPriceString
                )
                purchaseAttempt = attempt
                AnalyticsService.shared.capture(
                    AnalyticsEvent.purchaseStarted,
                    properties: attempt.properties().merging(["context": context]) { current, _ in current }
                )
            }
            .onPurchaseCompleted { _, customerInfo in
                AcquisitionTrackingService.shared.purchaseCompleted(customerInfo)
                subscriptionStore.handlePaywallCustomerInfo(customerInfo)
                let entitlementActive = customerInfo.entitlements.active[SubscriptionStore.premiumEntitlementID] != nil
                let properties = purchaseProperties().merging([
                    "context": context,
                    "entitlement_active": entitlementActive,
                ]) { current, _ in current }
                AnalyticsService.shared.capture(AnalyticsEvent.purchaseSucceeded, properties: properties)
                AnalyticsService.shared.capture(
                    entitlementActive
                        ? AnalyticsEvent.entitlementActivated
                        : AnalyticsEvent.purchaseSucceededWithoutEntitlement,
                    properties: properties
                )
                purchaseAttempt = nil
            }
            .onPurchaseCancelled {
                AnalyticsService.shared.capture(
                    AnalyticsEvent.purchaseCancelled,
                    properties: purchaseProperties().merging(["context": context]) { current, _ in current }
                )
                purchaseAttempt = nil
            }
            .onPurchaseFailure { error in
                let code = RevenueCat.ErrorCode(rawValue: error.code)
                let event: String
                if code == .purchaseCancelledError {
                    event = AnalyticsEvent.purchaseCancelled
                } else if code == .paymentPendingError {
                    event = AnalyticsEvent.purchasePending
                } else {
                    event = AnalyticsEvent.purchaseFailed
                }
                let properties = purchaseProperties()
                    .merging(PurchaseAnalytics.errorProperties(error)) { current, _ in current }
                    .merging(["context": context]) { current, _ in current }
                AnalyticsService.shared.capture(event, properties: properties)
                purchaseAttempt = nil
                switch code {
                case .productAlreadyPurchasedError,
                     .receiptAlreadyInUseError,
                     .receiptInUseByOtherSubscriberError,
                     .purchaseBelongsToOtherUser:
                    // Apple knows the receipt is subscribed, but RevenueCat's
                    // current customer record needs to be reconciled.
                    subscriptionStore.recoverExistingAppStorePurchase()
                default:
                    break
                }
            }
            .onRestoreStarted {
                AnalyticsService.shared.capture(AnalyticsEvent.restoreStarted, properties: ["context": context])
            }
            .onRestoreCompleted { customerInfo in
                subscriptionStore.handlePaywallCustomerInfo(customerInfo)
                AnalyticsService.shared.capture(AnalyticsEvent.restoreSucceeded, properties: ["context": context])
            }
            .onRestoreFailure { _ in
                AnalyticsService.shared.capture(AnalyticsEvent.restoreFailed, properties: ["context": context])
            }
    }

    private func purchaseProperties() -> [String: Any] {
        purchaseAttempt?.properties() ?? [
            "purchase_attempt_id": UUID().uuidString.lowercased(),
            "offering_id": offering.identifier,
        ]
    }
}

private struct PaywallLoadingView: View {
    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.13, blue: 0.07)
                .ignoresSafeArea()

            ProgressView()
                .tint(Color(red: 0.71, green: 0.95, blue: 0.08))
        }
    }
}

private struct PaywallUnavailableView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.13, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Button("Try Again") {
                    onRetry()
                }
                .foregroundStyle(Color(red: 0.71, green: 0.95, blue: 0.08))
            }
            .padding(24)
        }
    }
}
