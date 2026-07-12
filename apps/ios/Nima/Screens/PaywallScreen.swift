import RevenueCat
import RevenueCatUI
import SwiftUI

struct PaywallScreen: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onUnlocked: () -> Void

    var body: some View {
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
        .task {
            if subscriptionStore.offeringsState == .idle {
                subscriptionStore.loadOfferings()
            }
        }
        .onChange(of: subscriptionStore.hasPremium) { hasPremium in
            if hasPremium {
                onUnlocked()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct RevenueCatPaywallView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let offering: RevenueCat.Offering

    var body: some View {
        PaywallView(offering: offering, displayCloseButton: false)
            .onPurchaseCompleted { _, customerInfo in
                subscriptionStore.handlePaywallCustomerInfo(customerInfo)
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
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

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
