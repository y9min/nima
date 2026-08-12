import RevenueCat
import RevenueCatUI
import SwiftUI

struct PaywallScreen: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore

    let onUnlocked: () -> Void
    var onClose: (() -> Void)?

    init(
        onUnlocked: @escaping () -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.onUnlocked = onUnlocked
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch subscriptionStore.offeringsState {
                case .idle, .loading:
                    PaywallLoadingView()
                case .loaded:
                    if let offering = subscriptionStore.currentOffering, offering.hasPaywall {
                        RevenueCatPaywallView(offering: offering)
                    } else {
                        PaywallUnavailableView(message: "The subscription screen is unavailable right now.")
                    }
                case .failed(let message):
                    PaywallUnavailableView(message: message)
                }
            }

            if let onClose {
                Button(action: onClose) {
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
        .task {
            if subscriptionStore.offeringsState == .idle {
                subscriptionStore.loadOfferings()
            }
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
}

private struct RevenueCatPaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore

    let offering: RevenueCat.Offering

    var body: some View {
        PaywallView(offering: offering, displayCloseButton: false)
            .onPurchaseCompleted { _, customerInfo in
                subscriptionStore.handlePaywallCustomerInfo(customerInfo)
            }
            .onPurchaseFailure { error in
                switch RevenueCat.ErrorCode(rawValue: error.code) {
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
            .onRestoreCompleted { customerInfo in
                subscriptionStore.handlePaywallCustomerInfo(customerInfo)
            }
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
    @Environment(SubscriptionStore.self) private var subscriptionStore

    let message: String

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.13, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Button("Try Again") {
                    subscriptionStore.retryOfferings()
                }
                .foregroundStyle(Color(red: 0.71, green: 0.95, blue: 0.08))
            }
            .padding(24)
        }
    }
}
