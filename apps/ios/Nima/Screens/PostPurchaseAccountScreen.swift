import SwiftUI

struct PostPurchaseAccountScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(SubscriptionStore.self) private var subscriptionStore

    let allowsTemporaryAccess: Bool
    let onAuthenticationSucceeded: () -> Void
    let onContinueTemporarily: () -> Void
    let onBackToPlans: () -> Void

    @State private var page: Page = .account
    @State private var emailAddress = ""
    @State private var pendingEmailAddress = ""
    @State private var isAuthenticating = false
    @State private var authErrorMessage: String?

    var body: some View {
        Group {
            switch page {
            case .account:
                accountPage
            case .email:
                emailPage
            case .emailSent:
                emailSentPage
            }
        }
        .preferredColorScheme(.light)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            AnalyticsService.shared.capture(
                AnalyticsEvent.accountScreenViewed,
                properties: ["context": allowsTemporaryAccess ? "post_purchase" : "existing_subscriber"]
            )
        }
        .onChange(of: authStore.isLoggedIn) { _, isLoggedIn in
            guard isLoggedIn else { return }
            AnalyticsService.shared.capture(AnalyticsEvent.authSucceeded)
            onAuthenticationSucceeded()
        }
    }

    private var accountPage: some View {
        OnboardingWhitePage(topLogoWidth: OnboardingMetrics.topLogoWidth) {
            VStack(spacing: 26) {
                Spacer().frame(height: 42)

                OnboardingTitle(allowsTemporaryAccess ? "Protect your purchase" : "Sign in to restore access")

                Text(allowsTemporaryAccess
                     ? "Create an account or sign in so your subscription stays available on your other devices."
                     : "Already have a Nima account? Sign in and we’ll check its subscription.")
                    .font(.system(size: 17))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)

                VStack(spacing: 16) {
                    OnboardingAuthButton(title: "Continue with Apple", systemImage: "apple.logo") {
                        authenticate(method: "apple") {
                            try await authStore.signInWithApple()
                        }
                    }
                    .disabled(isAuthenticating)

                    OnboardingAuthButton(title: "Continue with Google", letter: "G") {
                        authenticate(method: "google") {
                            try await authStore.signInWithGoogle()
                        }
                    }
                    .disabled(isAuthenticating)

                    OnboardingAuthButton(title: "Continue with email", systemImage: "envelope", isOutlined: true) {
                        authErrorMessage = nil
                        page = .email
                    }
                    .disabled(isAuthenticating)

                    if isAuthenticating {
                        ProgressView().tint(OnboardingPalette.darkGreen)
                    }

                    if let authErrorMessage {
                        VStack(spacing: 10) {
                            Text(authErrorMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                            Text("Choose a sign-in method above to try again.")
                                .font(.system(size: 14))
                                .foregroundStyle(OnboardingPalette.secondaryText)
                        }
                    }

                    Button(subscriptionStore.isRestoring ? "Restoring…" : "Restore purchases") {
                        restorePurchases()
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(OnboardingPalette.darkGreen)
                    .disabled(subscriptionStore.isRestoring)

                    if let restoreError = subscriptionStore.restoreErrorMessage {
                        Text(restoreError)
                            .font(.system(size: 14))
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        } bottom: {
            Button(allowsTemporaryAccess ? "Continue for now" : "Back to plans") {
                if allowsTemporaryAccess {
                    AnalyticsService.shared.capture(AnalyticsEvent.accountLinkDeferred)
                    onContinueTemporarily()
                } else {
                    onBackToPlans()
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(OnboardingPalette.secondaryText)
            .buttonStyle(.plain)
            .accessibilityIdentifier("account.continue_temporarily")
        }
    }

    private var emailPage: some View {
        OnboardingWhitePage(keyboardAvoidance: true, onBack: { page = .account }) {
            VStack(spacing: 28) {
                Spacer().frame(height: 44)
                OnboardingTitle("Continue with email")

                TextField("you@example.com", text: $emailAddress)
                    .font(.system(size: 22))
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(Color.black.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(OnboardingPalette.darkGreen.opacity(0.22)) }
                    .accessibilityIdentifier("account.email.input")

                if isAuthenticating { ProgressView().tint(OnboardingPalette.darkGreen) }
                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                }

                Text("We’ll email you a secure sign-in link.")
                    .font(.system(size: 16))
                    .foregroundStyle(OnboardingPalette.secondaryText)
            }
        } bottom: {
            OnboardingPrimaryButton(
                title: isAuthenticating ? "Sending…" : "Send link",
                isDisabled: isAuthenticating || !isValidEmail
            ) {
                sendEmailLink()
            }
        }
    }

    private var emailSentPage: some View {
        OnboardingWhitePage(onBack: { page = .email }) {
            VStack(spacing: 24) {
                Spacer().frame(height: 44)
                OnboardingTitle("Check your email")
                Text("We sent a Nima sign-in link to \(pendingEmailAddress). Tap it to return here and finish linking your purchase.")
                    .font(.system(size: 16))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Resend link", isDisabled: isAuthenticating) {
                sendEmailLink(to: pendingEmailAddress, advances: false)
            }
        }
    }

    private var normalizedEmail: String { AuthStore.normalizedEmail(emailAddress) }
    private var isValidEmail: Bool {
        normalizedEmail.range(
            of: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$"#,
            options: .regularExpression
        ) != nil
    }

    private func authenticate(method: String, action: @escaping () async throws -> Void) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authErrorMessage = nil
        AnalyticsService.shared.capture(AnalyticsEvent.authStarted, properties: ["method": method])
        Task {
            do {
                try await action()
                await MainActor.run { isAuthenticating = false }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authErrorMessage = "We couldn’t sign you in. Check your connection and try again."
                    AnalyticsService.shared.capture(
                        AnalyticsEvent.authFailed,
                        properties: ["method": method, "reason": "request_failed"]
                    )
                }
            }
        }
    }

    private func sendEmailLink() {
        sendEmailLink(to: normalizedEmail, advances: true)
    }

    private func sendEmailLink(to email: String, advances: Bool) {
        authenticate(method: "email") {
            try await authStore.sendEmailMagicLink(to: email)
            await MainActor.run {
                pendingEmailAddress = email
                if advances { page = .emailSent }
            }
        }
    }

    private func restorePurchases() {
        AnalyticsService.shared.capture(AnalyticsEvent.restoreStarted, properties: ["context": "account"])
        subscriptionStore.restore {
            AnalyticsService.shared.capture(AnalyticsEvent.restoreSucceeded, properties: ["context": "account"])
        }
    }
}

private enum Page {
    case account
    case email
    case emailSent
}
