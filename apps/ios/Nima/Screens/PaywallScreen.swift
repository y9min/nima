import RevenueCat
import SwiftUI
import UIKit

struct PaywallScreen: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @State private var selectedPlan: PaywallPlan = .yearly

    let onUnlocked: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 430)
            let availableHeight = proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            let scale = min(1, width / 390, availableHeight / 820)
            let horizontalPadding = 24 * scale

            ZStack {
                PaywallPalette.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    logo
                        .frame(width: 150 * scale, height: 54 * scale)
                        .padding(.top, max(proxy.safeAreaInsets.top + 8, 14))

                    VStack(alignment: .leading, spacing: 5 * scale) {
                        Text("Take back your\nattention")
                            .font(.system(size: 30 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineSpacing(-5 * scale)

                        Text("Nima helps you block addictive feeds while keeping the useful parts of social media")
                            .font(.system(size: 18 * scale, weight: .regular, design: .rounded))
                            .foregroundStyle(PaywallPalette.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.86)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8 * scale)

                    VStack(alignment: .leading, spacing: 15 * scale) {
                        PaywallFeatureRow(
                            icon: "nosign",
                            title: "Short Form Blocking",
                            bodyText: "Block endless scroll content",
                            scale: scale
                        )
                        PaywallFeatureRow(
                            icon: "ellipsis.message.fill",
                            title: "Keep the useful parts:",
                            bodyText: "Stay connected with DMs & chats",
                            scale: scale
                        )
                        PaywallFeatureRow(
                            icon: "clock",
                            title: "Build better habits",
                            bodyText: "Use blocking windows & reminders",
                            scale: scale
                        )
                    }
                    .padding(.top, 26 * scale)

                    Text("Select a plan")
                        .font(.system(size: 24 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 28 * scale)

                    HStack(spacing: 18 * scale) {
                        PaywallPlanCard(
                            plan: .yearly,
                            isSelected: selectedPlan == .yearly,
                            price: yearlyPrice,
                            comparisonPrice: yearlyComparisonPrice,
                            subtitle: "Billed yearly",
                            badge: "50% SAVINGS",
                            scale: scale
                        ) {
                            selectedPlan = .yearly
                        }

                        PaywallPlanCard(
                            plan: .monthly,
                            isSelected: selectedPlan == .monthly,
                            price: monthlyPrice,
                            comparisonPrice: nil,
                            subtitle: "Billed monthly",
                            badge: nil,
                            scale: scale
                        ) {
                            selectedPlan = .monthly
                        }
                    }
                    .padding(.top, 12 * scale)

                    Text("Change plans or cancel anytime")
                        .font(.system(size: 15 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(PaywallPalette.secondaryText)
                        .padding(.top, 18 * scale)

                    Button(action: continueTapped) {
                        ZStack {
                            Text(subscriptionStore.hasPendingPurchase ? "Purchase Pending" : "Continue")
                                .font(.system(size: 24 * scale, weight: .regular, design: .rounded))
                                .foregroundStyle(.black)

                            if subscriptionStore.isPurchasing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                                    .offset(x: -82 * scale)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56 * scale)
                        .background(PaywallPalette.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(
                        selectedPackage == nil
                            || subscriptionStore.hasPendingPurchase
                            || subscriptionStore.isRestoring
                    )
                    .opacity(selectedPackage == nil ? 0.6 : 1)
                    .padding(.top, 14 * scale)

                    Button(action: restoreTapped) {
                        Text(subscriptionStore.isRestoring ? "Restoring..." : "Restore Purchases")
                            .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .disabled(subscriptionStore.isRestoring || subscriptionStore.hasPendingPurchase)
                    .padding(.top, 9 * scale)

                    statusLine(scale: scale)
                        .frame(minHeight: 28 * scale)
                        .padding(.top, 4 * scale)
                }
                .frame(width: width - (horizontalPadding * 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
    }

    private var logo: some View {
        Group {
            if let image = UIImage(named: "nima_logo") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("nima")
                    .font(NimaFonts.pupok(size: 56))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("nima")
    }

    private var selectedPackage: RevenueCat.Package? {
        switch selectedPlan {
        case .yearly:
            subscriptionStore.yearlyPackage
        case .monthly:
            subscriptionStore.monthlyPackage
        }
    }

    private var yearlyPrice: String {
        subscriptionStore.yearlyPackage.map { "\($0.storeProduct.localizedPriceString)/YR" }
            ?? unavailableOrLoadingPrice
    }

    private var monthlyPrice: String {
        subscriptionStore.monthlyPackage.map { "\($0.storeProduct.localizedPriceString)/MO" }
            ?? unavailableOrLoadingPrice
    }

    private var unavailableOrLoadingPrice: String {
        subscriptionStore.offeringsErrorMessage == nil ? "Loading price" : "Unavailable"
    }

    private var yearlyComparisonPrice: String? {
        guard let monthlyProduct = subscriptionStore.monthlyPackage?.storeProduct else { return nil }

        let yearlyPrice = NSDecimalNumber(decimal: monthlyProduct.price)
            .multiplying(by: NSDecimalNumber(value: 12))
        let formattedPrice = monthlyProduct.priceFormatter?.string(from: yearlyPrice)
            ?? Self.currencyFormatter(currencyCode: monthlyProduct.currencyCode).string(from: yearlyPrice)

        return formattedPrice.map { "\($0)/YR" }
    }

    private static func currencyFormatter(currencyCode: String?) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        if let currencyCode {
            formatter.currencyCode = currencyCode
        }
        return formatter
    }

    private func continueTapped() {
        guard let selectedPackage else { return }
        subscriptionStore.purchase(selectedPackage, onUnlocked: onUnlocked)
    }

    private func restoreTapped() {
        subscriptionStore.restore(onUnlocked: onUnlocked)
    }

    private func statusLine(scale: CGFloat) -> some View {
        VStack(spacing: 4 * scale) {
            if let errorMessage = subscriptionStore.offeringsErrorMessage {
                HStack(spacing: 8 * scale) {
                    Text(errorMessage)
                        .font(.system(size: 12 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Button("Try Again") {
                        subscriptionStore.retryOfferings()
                    }
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(PaywallPalette.accent)
                    .fixedSize()
                }
            } else if subscriptionStore.isLoadingOfferings {
                ProgressView()
                    .tint(PaywallPalette.accent)
            }

            if let errorMessage = subscriptionStore.purchaseErrorMessage {
                HStack(spacing: 8 * scale) {
                    Text(errorMessage)
                        .font(.system(size: 12 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if subscriptionStore.hasPendingPurchase {
                        Button("Check Again") {
                            subscriptionStore.retryPurchaseConfirmation()
                        }
                        .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(PaywallPalette.accent)
                        .fixedSize()
                    }
                }
            }

            if let errorMessage = subscriptionStore.restoreErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 12 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
    }
}

private enum PaywallPlan {
    case yearly
    case monthly

    var title: String {
        switch self {
        case .yearly:
            return "Yearly"
        case .monthly:
            return "Monthly"
        }
    }
}

private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let bodyText: String
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 20 * scale) {
            Image(systemName: icon)
                .font(.system(size: 42 * scale, weight: .regular))
                .foregroundStyle(PaywallPalette.accent)
                .frame(width: 54 * scale, height: 54 * scale)

            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(title)
                    .font(.system(size: 20 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text(bodyText)
                    .font(.system(size: 20 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let price: String
    let comparisonPrice: String?
    let subtitle: String
    let badge: String?
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22 * scale)
                    .fill(PaywallPalette.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22 * scale)
                            .strokeBorder(.white.opacity(isSelected ? 0.35 : 0.2), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4 * scale) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5 * scale) {
                            Text(plan.title)
                                .font(.system(size: 22 * scale, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)

                            Text(price)
                                .font(.system(size: 18 * scale, weight: .regular, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            if plan == .yearly, let comparisonPrice {
                                Text(comparisonPrice)
                                    .font(.system(size: 15 * scale, weight: .regular, design: .rounded))
                                    .foregroundStyle(PaywallPalette.secondaryText)
                                    .strikethrough()
                            }
                        }

                        Spacer(minLength: 8 * scale)

                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .background(
                                    Circle()
                                        .fill(isSelected ? PaywallPalette.accent : .clear)
                                )
                                .frame(width: 31 * scale, height: 31 * scale)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15 * scale, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    Spacer()

                    Text(subtitle)
                        .font(.system(size: 15 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(PaywallPalette.secondaryText)
                }
                .padding(14 * scale)

                if let badge {
                    Text(badge)
                        .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(PaywallPalette.accent)
                        .clipShape(Capsule())
                        .offset(x: 50 * scale, y: -8 * scale)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 126 * scale)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private enum PaywallPalette {
    static let background = Color(red: 0.0, green: 0.13, blue: 0.07)
    static let accent = Color(red: 0.71, green: 0.95, blue: 0.08)
    static let secondaryText = Color.white.opacity(0.72)
}

#Preview {
    PaywallScreen(onUnlocked: {})
        .environment(SubscriptionStore())
}
