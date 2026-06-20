import SwiftUI
import UIKit
import Combine
import UserNotifications

struct OnboardingFlowScreen: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @EnvironmentObject private var vpnManager: VPNManager

    @State private var step: OnboardingStep = .splash
    @State private var displayName = ""
    @State private var phoneHours: Double = 0
    @State private var age = 18
    @State private var didProvidePhoneHours = false
    @State private var didProvideAge = false
    @State private var selectedHabits: Set<String> = []
    @State private var selectedApps: Set<String> = []
    @State private var showsPrivacySheet = false
    @State private var isAuthenticating = false
    @State private var authErrorMessage: String?
    @State private var emailAuthAddress = ""
    @State private var pendingEmailAuthAddress = ""

    private var hasValidDisplayName: Bool {
        AppSettingsStore.normalizedDisplayName(displayName) != nil
    }

    private var canContinuePhoneTime: Bool {
        didProvidePhoneHours
    }

    private var canContinueAge: Bool {
        didProvideAge
    }

    private var canContinueHabits: Bool {
        !selectedHabits.isEmpty
    }

    private var canContinueApps: Bool {
        !selectedApps.isEmpty
    }

    private var normalizedEmailAuthAddress: String {
        emailAuthAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendEmailAuthLink: Bool {
        isValidEmail(normalizedEmailAuthAddress)
    }

    var body: some View {
        ZStack {
            currentScreen
                .transition(.opacity)

            if showsPrivacySheet {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .transition(.opacity)

                OnboardingPrivacySheet(
                    onContinue: triggerVPNPermissionAndContinue
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .animation(.easeInOut(duration: 0.2), value: showsPrivacySheet)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .preferredColorScheme(.light)
        .onAppear(perform: loadDraftState)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch step {
        case .splash:
            OnboardingSplashPage {
                step = .name
            }
        case .name:
            namePage
        case .phoneTime:
            phoneTimePage
        case .calculating:
            calculatingPage
        case .newsTransition:
            newsTransitionPage
        case .badNews:
            badNewsPage
        case .goodNews:
            goodNewsPage
        case .stayConnected:
            stayConnectedPage
        case .age:
            agePage
        case .habits:
            habitsPage
        case .apps:
            appsPage
        case .vpn:
            vpnEducationPage
        case .notifications:
            notificationsPage
        case .account:
            accountPage
        case .emailEntry:
            emailEntryPage
        case .emailLinkSent:
            emailLinkSentPage
        }
    }

    private var namePage: some View {
        OnboardingWhitePage(keyboardAvoidance: true, onBack: goBack) {
            VStack(spacing: 24) {
                OnboardingTitle("What’s your name?")

                VStack(spacing: 0) {
                    TextField("", text: $displayName, prompt: Text("Let us know what to call you...")
                        .foregroundStyle(OnboardingPalette.placeholder))
                        .font(.system(size: OnboardingMetrics.inputFont, weight: .regular))
                        .foregroundStyle(.black)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboarding.name.input")

                    Rectangle()
                        .fill(OnboardingPalette.rule)
                        .frame(height: 2)
                }
            }
            .padding(.top, 22)
        } bottom: {
            OnboardingPrimaryButton(title: "Continue", isDisabled: !hasValidDisplayName) {
                guard hasValidDisplayName else { return }
                appSettingsStore.setDisplayName(displayName)
                step = .habits
            }
            .accessibilityIdentifier("onboarding.name.continue")
        }
    }

    private var phoneTimePage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 12) {
                OnboardingTitle("How much time do you\nspend on your phone?")
                    .padding(.top, 22)

                Text("your best guess is fine")
                    .font(.system(size: OnboardingMetrics.subtitleFont, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)

                Spacer()
                    .frame(height: 52)

                PhoneUsageGauge(hours: Int(phoneHours.rounded()))
                    .frame(width: 230, height: 230)

                OnboardingPhoneSlider(value: $phoneHours, range: 0...16, step: 1) {
                    didProvidePhoneHours = true
                }
                    .padding(.horizontal, 34)
                    .accessibilityIdentifier("onboarding.phone.slider")
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue", isDisabled: !canContinuePhoneTime) {
                guard canContinuePhoneTime else { return }
                onboardingStore.setPhoneHours(Int(phoneHours.rounded()))
                step = .calculating
            }
            .accessibilityIdentifier("onboarding.phone.continue")
        }
    }

    private var calculatingPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 28) {
                Spacer(minLength: 0)

                OnboardingTitle("Calculating…")

                PulsatingDotsLoader()
                    .frame(height: 42)
                    .accessibilityLabel("Calculating")

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } bottom: {
            EmptyView()
        }
        .onAppear {
            advanceAfterDelay(from: .calculating, to: .newsTransition, delay: 2.0)
        }
    }

    private var newsTransitionPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            OnboardingTransitionMessage {
                advanceAfterDelay(from: .newsTransition, to: .badNews, delay: 2.0)
            }
        } bottom: {
            EmptyView()
        }
    }

    private var badNewsPage: some View {
        let projection = currentProjection

        return OnboardingWhitePage(onBack: goBack) {
            OnboardingProjectionPage(
                topLines: [
                    ProjectionTextLine(text: "The bad news is you’ll spend", highlightedText: nil),
                    ProjectionTextLine(text: "\(projection.daysThisYear) days on your phone this year", highlightedText: "\(projection.daysThisYear) days")
                ],
                leadInLines: [
                    "meaning that you’re on track",
                    "to spend"
                ],
                carouselValue: projection.lifeYears,
                middleSuffix: "",
                bottomLines: [
                    "of your life looking down at your",
                    "phone. Yep, you read that right"
                ],
                disclaimer: "Projection of your current habits, based\non an average 16 waking hours each day",
                accessibilityPrefix: "Bad news"
            )
        } bottom: {
            OnboardingDelayedButton(title: "Fix this", delay: ProjectionRevealTiming.buttonDelay) {
                step = .goodNews
            }
            .accessibilityIdentifier("onboarding.bad-news.continue")
        }
    }

    private var goodNewsPage: some View {
        let projection = currentProjection

        return OnboardingWhitePage(onBack: goBack) {
            OnboardingProjectionPage(
                topLines: [
                    ProjectionTextLine(text: "The good news is that Nima can", highlightedText: nil),
                    ProjectionTextLine(text: "help you get back", highlightedText: nil)
                ],
                leadInLines: [],
                carouselValue: projection.yearsBack,
                middleSuffix: " years+",
                bottomLines: [
                    "of your life from scrolling, so you",
                    "can spend it on what actually",
                    "matters"
                ],
                disclaimer: "Projection based on your answers and an\nestimated reduction while Nima is active",
                accessibilityPrefix: "Good news"
            )
        } bottom: {
            OnboardingDelayedButton(title: "Get years back", delay: ProjectionRevealTiming.buttonDelay) {
                step = .stayConnected
            }
            .accessibilityIdentifier("onboarding.good-news.continue")
        }
    }

    private var stayConnectedPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            StayConnectedContent()
        } bottom: {
            VStack(spacing: 16) {
                Label("Keep what matters. Lose what doesn’t.", systemImage: "heart")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingPalette.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                OnboardingPrimaryButton(title: "Set Up Nima") {
                    step = .vpn
                }
                .accessibilityIdentifier("onboarding.stay-connected.continue")
            }
        }
    }

    private var agePage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 8) {
                OnboardingTitle("How old are you?")
                    .padding(.top, 22)

                Text("so we can suggest the best\nsetup for you")
                    .font(.system(size: OnboardingMetrics.subtitleFont, weight: .regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingPalette.secondaryText)

                Spacer()
                    .frame(height: 82)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 34)
                        .padding(.horizontal, 14)

                    Picker("Age", selection: $age) {
                        ForEach(13...80, id: \.self) { value in
                            Text("\(value)")
                                .font(.system(size: 21, weight: .regular))
                                .foregroundStyle(OnboardingPalette.secondaryText)
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 166)
                    .clipped()
                    .onChange(of: age) { _, _ in
                        didProvideAge = true
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                didProvideAge = true
                            }
                    )
                    .accessibilityIdentifier("onboarding.age.picker")
                }
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue", isDisabled: !canContinueAge) {
                guard canContinueAge else { return }
                onboardingStore.setAge(age)
                step = .apps
            }
            .accessibilityIdentifier("onboarding.age.continue")
        }
    }

    private var habitsPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 12) {
                OnboardingTitle(
                    "What habit would you like\nto change?",
                    fontSize: 26,
                    minimumScale: 0.78,
                    lineLimit: 2
                )
                    .padding(.top, 20)
                    .layoutPriority(10)

                Text("select one or more")
                    .font(.system(size: OnboardingMetrics.subtitleFont, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)

                VStack(spacing: 14) {
                    ForEach(OnboardingCopy.habits, id: \.self) { habit in
                        OnboardingSelectableRow(
                            title: habit,
                            isSelected: selectedHabits.contains(habit)
                        ) {
                            toggle(habit, in: &selectedHabits)
                        }
                    }
                }
                .padding(.top, 22)
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue", isDisabled: !canContinueHabits) {
                guard canContinueHabits else { return }
                onboardingStore.setSelectedHabits(selectedHabits)
                step = .age
            }
            .accessibilityIdentifier("onboarding.habits.continue")
        }
    }

    private var appsPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 12) {
                OnboardingTitle("Where do you spend the\nmost time scrolling?")
                    .padding(.top, 20)

                Text("select one or more")
                    .font(.system(size: OnboardingMetrics.subtitleFont, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)

                VStack(spacing: 22) {
                    ForEach(OnboardingCopy.apps, id: \.self) { app in
                        OnboardingSelectableRow(
                            title: app,
                            isSelected: selectedApps.contains(app)
                        ) {
                            toggle(app, in: &selectedApps)
                        }
                    }
                }
                .padding(.top, 26)
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue", isDisabled: !canContinueApps) {
                guard canContinueApps else { return }
                onboardingStore.setSelectedApps(selectedApps)
                step = .phoneTime
            }
            .accessibilityIdentifier("onboarding.apps.continue")
        }
    }

    private var vpnEducationPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 14) {
                OnboardingTitle("Let Nima block the scroll")
                    .padding(.top, 22)

                Text("Nima uses a local VPN configuration to\nblock short-form feeds while keeping the\nuseful parts of social apps working")
                    .font(.system(size: 20, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(OnboardingPalette.secondaryText)

                Spacer()
                    .frame(height: 30)

                VPNPermissionIllustration()
                    .frame(width: 270, height: 255)
                    .offset(y: -8)
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue") {
                showsPrivacySheet = true
            }
            .accessibilityIdentifier("onboarding.vpn.continue")
        }
    }

    private var notificationsPage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 14) {
                OnboardingTitle("Stay on track with\nreminders")
                    .padding(.top, 22)

                Text("Nima can remind you when a blocking\nwindow starts, ends, or needs\nyour attention")
                    .font(.system(size: 20, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(OnboardingPalette.secondaryText)

                Spacer()
                    .frame(height: 30)

                NotificationPermissionIllustration()
                    .frame(width: 270, height: 255)
                    .offset(y: -8)
            }
        } bottom: {
            VStack(spacing: 16) {
                Text("You can change this at any time")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                OnboardingPrimaryButton(title: "Continue") {
                    requestNotificationPermissionAndContinue()
                }
                .accessibilityIdentifier("onboarding.notifications.continue")
            }
        }
    }

    private var accountPage: some View {
        OnboardingWhitePage(topLogoWidth: OnboardingMetrics.topLogoWidth, onBack: goBack) {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 54)

                OnboardingTitle("Let’s create your account")

                VStack(spacing: 18) {
                    OnboardingAuthButton(title: "Continue with Apple", systemImage: "apple.logo") {
                        signInWithAppleAndComplete()
                    }
                    .disabled(isAuthenticating)
                    OnboardingAuthButton(title: "Continue with Google", letter: "G") {
                        signInWithGoogleAndComplete()
                    }
                    .disabled(isAuthenticating)
                    OnboardingAuthButton(title: "Continue with email", systemImage: "envelope", isOutlined: true) {
                        startEmailAuthFlow()
                    }
                    .disabled(isAuthenticating)

                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(OnboardingPalette.darkGreen)
                    }

                    if let authErrorMessage {
                        Text(authErrorMessage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Already have an account? Log in") {
                        startEmailAuthFlow()
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OnboardingPalette.placeholder)
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .disabled(isAuthenticating)
                }
            }
        } bottom: {
            EmptyView()
        }
    }

    private var emailEntryPage: some View {
        OnboardingWhitePage(keyboardAvoidance: true, onBack: goBack) {
            VStack(spacing: 28) {
                Spacer()
                    .frame(height: 44)

                OnboardingTitle("Continue with email")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Email")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.darkGreen)

                    TextField("", text: $emailAuthAddress, prompt: Text("you@example.com")
                        .foregroundStyle(OnboardingPalette.placeholder))
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.black)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .onSubmit(sendEmailAuthLink)
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(Color.black.opacity(0.04))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(OnboardingPalette.darkGreen.opacity(0.22), lineWidth: 1)
                        }
                        .accessibilityIdentifier("onboarding.email.input")
                }

                if isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(OnboardingPalette.darkGreen)
                }

                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("We’ll send a sign-in link to this email. Tap the link to open Nima and finish login.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        } bottom: {
            OnboardingPrimaryButton(
                title: isAuthenticating ? "Sending..." : "Send link",
                isDisabled: isAuthenticating || !canSendEmailAuthLink,
                action: sendEmailAuthLink
            )
            .accessibilityIdentifier("onboarding.email.send_link")
        }
    }

    private var emailLinkSentPage: some View {
        OnboardingWhitePage(keyboardAvoidance: true, onBack: goBack) {
            VStack(spacing: 26) {
                Spacer()
                    .frame(height: 44)

                OnboardingTitle("Check your email")

                Text("We sent a Nima sign-in link to \(pendingEmailAuthAddress). Tap that link to open the app and finish login.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)

                if isAuthenticating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(OnboardingPalette.darkGreen)
                }

                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Resend link") {
                    resendEmailAuthLink()
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(OnboardingPalette.darkGreen)
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
                .accessibilityIdentifier("onboarding.email.resend_link")
            }
        } bottom: {
            EmptyView()
        }
    }

    private func loadDraftState() {
        displayName = appSettingsStore.displayName
        phoneHours = Double(onboardingStore.phoneHours ?? 0)
        age = onboardingStore.age ?? 18
        didProvidePhoneHours = onboardingStore.phoneHours != nil
        didProvideAge = onboardingStore.age != nil
        selectedHabits = onboardingStore.selectedHabits
        selectedApps = onboardingStore.selectedApps
    }

    private var currentProjection: OnboardingProjection {
        OnboardingProjection.calculate(
            dailyPhoneHours: Int(phoneHours.rounded()),
            userAge: age
        )
    }

    private func advanceAfterDelay(from expectedStep: OnboardingStep, to nextStep: OnboardingStep, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard step == expectedStep else { return }
            step = nextStep
        }
    }

    private func triggerVPNPermissionAndContinue() {
        onboardingStore.markVPNPermissionRequested()
        vpnManager.startVPN(source: "onboarding.vpn_permission")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showsPrivacySheet = false
            step = .notifications
        }
    }

    private func requestNotificationPermissionAndContinue() {
        appSettingsStore.setWindowsNotificationsEnabled(true)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                step = .account
            }
        }
    }

    private func completeOnboarding() {
        onboardingStore.markCompleted()
    }

    private func startEmailAuthFlow() {
        authErrorMessage = nil
        step = .emailEntry
    }

    private func sendEmailAuthLink() {
        guard !isAuthenticating, canSendEmailAuthLink else { return }
        let email = normalizedEmailAuthAddress
        sendEmailAuthLink(to: email, shouldAdvance: true)
    }

    private func resendEmailAuthLink() {
        guard !isAuthenticating, !pendingEmailAuthAddress.isEmpty else { return }
        sendEmailAuthLink(to: pendingEmailAuthAddress, shouldAdvance: false)
    }

    private func sendEmailAuthLink(to email: String, shouldAdvance: Bool) {
        isAuthenticating = true
        authErrorMessage = nil

        Task {
            do {
                try await authStore.sendEmailMagicLink(to: email)
                await MainActor.run {
                    pendingEmailAuthAddress = email
                    emailAuthAddress = email
                    isAuthenticating = false
                    if shouldAdvance {
                        step = .emailLinkSent
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func signInWithAppleAndComplete() {
        signInAndComplete {
            try await authStore.signInWithApple()
        }
    }

    private func signInWithGoogleAndComplete() {
        signInAndComplete {
            try await authStore.signInWithGoogle()
        }
    }

    private func signInAndComplete(_ action: @escaping () async throws -> Void) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authErrorMessage = nil

        Task {
            do {
                try await action()
                await MainActor.run {
                    isAuthenticating = false
                    completeOnboarding()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func goBack() {
        guard let previousStep = step.previous else { return }
        if showsPrivacySheet {
            showsPrivacySheet = false
        }
        if step == .emailEntry || step == .emailLinkSent {
            authErrorMessage = nil
        }
        step = previousStep
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailPattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$"#
        return email.range(of: emailPattern, options: .regularExpression) != nil
    }
}

private enum OnboardingStep {
    case splash
    case name
    case phoneTime
    case calculating
    case newsTransition
    case badNews
    case goodNews
    case stayConnected
    case age
    case habits
    case apps
    case vpn
    case notifications
    case account
    case emailEntry
    case emailLinkSent

    var previous: OnboardingStep? {
        switch self {
        case .splash:
            return nil
        case .name:
            return .splash
        case .phoneTime:
            return .apps
        case .calculating:
            return .phoneTime
        case .newsTransition:
            return .calculating
        case .badNews:
            return .newsTransition
        case .goodNews:
            return .badNews
        case .stayConnected:
            return .goodNews
        case .age:
            return .habits
        case .habits:
            return .name
        case .apps:
            return .age
        case .vpn:
            return .stayConnected
        case .notifications:
            return .vpn
        case .account:
            return .notifications
        case .emailEntry:
            return .account
        case .emailLinkSent:
            return .emailEntry
        }
    }
}

struct OnboardingProjection: Equatable {
    let daysThisYear: Int
    let lifeYears: Int
    let yearsBack: Int

    static func calculate(
        dailyPhoneHours: Int,
        userAge: Int,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> OnboardingProjection {
        let clampedHours = max(0, dailyPhoneHours)
        let remainingYears = max(0, 85 - userAge)
        let daysThisYear = Int(((Double(clampedHours) * Double(daysRemainingInYearIncludingToday(from: date, calendar: calendar))) / 24).rounded())
        let lifeYears = max(1, Int(((Double(clampedHours) / 16) * Double(remainingYears)).rounded()))
        let yearsBack = max(1, Int((Double(lifeYears) * 0.30).rounded()))

        return OnboardingProjection(
            daysThisYear: daysThisYear,
            lifeYears: lifeYears,
            yearsBack: yearsBack
        )
    }

    static func carouselValues(for value: Int) -> [Int] {
        [max(1, value - 1), max(1, value), max(1, value + 1)]
    }

    static func daysRemainingInYearIncludingToday(from date: Date, calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: startOfToday)
        guard let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return 0
        }
        return max(0, calendar.dateComponents([.day], from: startOfToday, to: startOfNextYear).day ?? 0)
    }
}

private struct ProjectionTextLine: Identifiable {
    let id = UUID()
    let text: String
    let highlightedText: String?
}

private struct PulsatingDotsLoader: View {
    var body: some View {
        HStack(spacing: 8) {
            PulsatingDot(delay: 0)
            PulsatingDot(delay: 0.3)
            PulsatingDot(delay: 0.6)
        }
    }
}

private struct PulsatingDot: View {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let progress = reduceMotion ? 0.5 : animationProgress(at: timeline.date)

            Circle()
                .fill(OnboardingPalette.green)
                .frame(width: 12, height: 12)
                .scaleEffect(1 + (0.5 * progress))
                .opacity(0.5 + (0.5 * progress))
        }
    }

    private func animationProgress(at date: Date) -> Double {
        let cycleDuration = 1.0
        let rawPhase = (date.timeIntervalSinceReferenceDate - delay).truncatingRemainder(dividingBy: cycleDuration)
        let phase = rawPhase < 0 ? rawPhase + cycleDuration : rawPhase
        let triangleProgress = phase < 0.5 ? phase / 0.5 : (cycleDuration - phase) / 0.5
        return 0.5 - (0.5 * cos(.pi * triangleProgress))
    }
}
private struct OnboardingTransitionMessage: View {
    let onReady: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            AnimatedRevealText(
                "Some not so good news,",
                delay: 0.18,
                font: .system(size: 27, weight: .black),
                color: .black,
                lineLimit: 1
            )

            AnimatedRevealText(
                "& some great news…",
                delay: 0.72,
                font: .system(size: 27, weight: .black),
                color: .black,
                lineLimit: 1
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: onReady)
    }
}

private struct StayConnectedContent: View {
    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 590
            let titleSize: CGFloat = isCompact ? 30 : 37
            let titleTopPadding: CGFloat = isCompact ? 10 : 20
            let titleBottomPadding: CGFloat = isCompact ? 16 : 26
            let rowSpacing: CGFloat = isCompact ? 10 : 14
            let rowIconSize: CGFloat = isCompact ? 50 : 58
            let cardHeight: CGFloat = isCompact ? 94 : 112

            VStack(spacing: 0) {
                StayConnectedTitle(fontSize: titleSize)
                    .padding(.top, titleTopPadding)
                    .padding(.bottom, titleBottomPadding)

                VStack(spacing: rowSpacing) {
                    StayConnectedRow(
                        systemImage: "hourglass",
                        title: "App limits still rely on discipline.",
                        bodyText: "They’re easy to ignore when\nyou want to scroll.",
                        iconSize: rowIconSize
                    )

                    StayConnectedDivider()

                    StayConnectedRow(
                        systemImage: "bubble.left.and.bubble.right.fill",
                        title: "Deleting apps cuts you off\nfrom messages and real plans.",
                        bodyText: "It’s an all-or-nothing approach\nthat doesn’t work.",
                        iconSize: rowIconSize
                    )

                    StayConnectedDivider()

                    StayConnectedRow(
                        systemImage: "lock.fill",
                        title: "Full blockers treat the whole\napp like the problem.",
                        bodyText: "Too blunt. Too extreme.\nNot built for real life.",
                        iconSize: rowIconSize
                    )
                }

                Spacer(minLength: isCompact ? 14 : 24)

                StayConnectedNimaCard()
                    .frame(height: cardHeight)
            }
            .padding(.horizontal, isCompact ? 2 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StayConnectedTitle: View {
    let fontSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text("Stay connected")
                .foregroundStyle(.black)
            Text("without")
                .foregroundStyle(OnboardingPalette.green)
            Text("getting trapped")
                .foregroundStyle(.black)
        }
        .font(.system(size: fontSize, weight: .black))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stay connected without getting trapped")
    }
}

private struct StayConnectedRow: View {
    let systemImage: String
    let title: String
    let bodyText: String
    let iconSize: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(OnboardingPalette.green.opacity(0.10))

                Image(systemName: systemImage)
                    .font(.system(size: iconSize * 0.42, weight: .bold))
                    .foregroundStyle(OnboardingPalette.green)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: iconSize, height: iconSize)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .lineSpacing(1)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bodyText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)
                    .lineSpacing(2)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StayConnectedDivider: View {
    var body: some View {
        Rectangle()
            .fill(OnboardingPalette.rule)
            .frame(height: 1)
            .padding(.leading, 80)
    }
}

private struct StayConnectedNimaCard: View {
    var body: some View {
        cardText
            .font(.system(size: 25, weight: .black))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(OnboardingPalette.darkGreen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: OnboardingPalette.green.opacity(0.10), radius: 8, x: 0, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Nima blocks the scroll, not the social.")
    }

    private var cardText: Text {
        Text("Nima ")
            .foregroundColor(.white)
            + Text("blocks the scroll,\n")
            .foregroundColor(Color(red: 0.16, green: 0.92, blue: 0.52))
            + Text("not the social.")
            .foregroundColor(.white)
    }
}

private struct OnboardingProjectionPage: View {
    let topLines: [ProjectionTextLine]
    let leadInLines: [String]
    let carouselValue: Int
    let middleSuffix: String
    let bottomLines: [String]
    let disclaimer: String
    let accessibilityPrefix: String

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 600
            let topPadding: CGFloat = isCompact ? 8 : 22
            let firstGap: CGFloat = isCompact ? 14 : 28
            let leadInGap: CGFloat = isCompact ? 14 : 28
            let carouselGap: CGFloat = isCompact ? 16 : 30
            let carouselHeight: CGFloat = isCompact ? 132 : 166
            let disclaimerGap: CGFloat = isCompact ? 14 : 40

            VStack(spacing: 0) {
                Spacer(minLength: topPadding)

                VStack(spacing: 2) {
                    ForEach(Array(topLines.enumerated()), id: \.element.id) { index, line in
                        AnimatedProjectionLine(
                            line: line,
                            delay: ProjectionRevealTiming.topStart + (Double(index) * ProjectionRevealTiming.lineGap),
                            fontSize: isCompact ? 20 : 22,
                            fontWeight: .bold
                        )
                    }
                }

                Color.clear
                    .frame(height: firstGap)

                if !leadInLines.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(leadInLines.enumerated()), id: \.offset) { index, line in
                            AnimatedRevealText(
                                line,
                                delay: ProjectionRevealTiming.leadInStart + (Double(index) * ProjectionRevealTiming.lineGap),
                                font: .system(size: isCompact ? 20 : 22, weight: .bold),
                                color: .black,
                                lineLimit: 1
                            )
                        }
                    }

                    Color.clear
                        .frame(height: leadInGap)
                }

                NumberCarouselView(
                    value: carouselValue,
                    finalMiddleSuffix: middleSuffix,
                    startDelay: ProjectionRevealTiming.carouselStart
                )
                    .frame(height: carouselHeight)

                Color.clear
                    .frame(height: carouselGap)

                VStack(spacing: 2) {
                    ForEach(Array(bottomLines.enumerated()), id: \.offset) { index, line in
                        AnimatedRevealText(
                            line,
                            delay: ProjectionRevealTiming.bottomStart + (Double(index) * ProjectionRevealTiming.bottomLineGap),
                            font: .system(size: isCompact ? 18 : 20, weight: .bold),
                            color: .black,
                            lineLimit: 1
                        )
                    }
                }

                Spacer(minLength: disclaimerGap)

                AnimatedRevealText(
                    disclaimer,
                    delay: ProjectionRevealTiming.disclaimerStart,
                    font: .system(size: isCompact ? 14 : 16, weight: .regular),
                    color: OnboardingPalette.secondaryText,
                    lineLimit: 2
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityPrefix)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ProjectionRevealTiming {
    static let topStart = 0.2
    static let lineGap = 0.38
    static let leadInStart = 1.18
    static let carouselStart = 1.88
    static let bottomStart = 4.05
    static let bottomLineGap = 0.3
    static let disclaimerStart = 4.82
    static let buttonDelay = 5.2
}

private struct AnimatedProjectionLine: View {
    let line: ProjectionTextLine
    let delay: Double
    let fontSize: CGFloat
    let fontWeight: Font.Weight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        styledText
            .font(.system(size: fontSize, weight: fontWeight))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .onAppear(perform: reveal)
    }

    private var styledText: Text {
        guard let highlightedText = line.highlightedText,
              let range = line.text.range(of: highlightedText) else {
            return Text(line.text).foregroundColor(.black)
        }

        let prefix = String(line.text[..<range.lowerBound])
        let suffix = String(line.text[range.upperBound...])
        return Text(prefix).foregroundColor(.black)
            + Text(highlightedText).foregroundColor(OnboardingPalette.green)
            + Text(suffix).foregroundColor(.black)
    }

    private func reveal() {
        guard !isVisible else { return }
        guard !reduceMotion else {
            isVisible = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.42)) {
                isVisible = true
            }
        }
    }
}

private struct AnimatedRevealText: View {
    let text: String
    let delay: Double
    let font: Font
    let color: Color
    let lineLimit: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    init(
        _ text: String,
        delay: Double,
        font: Font,
        color: Color,
        lineLimit: Int
    ) {
        self.text = text
        self.delay = delay
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .onAppear(perform: reveal)
    }

    private func reveal() {
        guard !isVisible else { return }
        guard !reduceMotion else {
            isVisible = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.42)) {
                isVisible = true
            }
        }
    }
}

private struct NumberCarouselView: View {
    let value: Int
    let finalMiddleSuffix: String
    let startDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var hasSettled = false
    @State private var spinTask: Task<Void, Never>?

    private let rowHeight: CGFloat = 62

    private var finalValues: [Int] {
        OnboardingProjection.carouselValues(for: value)
    }

    private var spinValues: [Int] {
        let highValue = max(36, value + 18)
        let finalRun = Array(max(1, value - 4)...(value + 2))
        return Array(1...highValue) + finalRun
    }

    private var finalSpinIndex: Int {
        max(0, spinValues.count - 3)
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportHeight = proxy.size.height

            ZStack {
                spinningList(viewportHeight: viewportHeight)
                    .opacity(hasSettled || reduceMotion ? 0 : 1)

                finalRows
                    .opacity(hasSettled || reduceMotion ? 1 : 0)
                    .scaleEffect(hasSettled || reduceMotion ? 1 : 0.96)
                    .blur(radius: hasSettled || reduceMotion ? 0 : 2)
            }
            .frame(width: proxy.size.width, height: viewportHeight)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.26), value: hasSettled)
        .onAppear(perform: startAnimation)
        .onDisappear {
            spinTask?.cancel()
            spinTask = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(middleText)
    }

    private func spinningList(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(spinValues.enumerated()), id: \.offset) { _, year in
                Text("\(year) years")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(OnboardingPalette.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
            }
        }
        .offset(y: centeredOffset(for: scrollOffset, viewportHeight: viewportHeight))
        .blur(radius: 5.5)
        .opacity(0.72)
    }

    private var finalRows: some View {
        VStack(spacing: 4) {
            carouselText("\(finalValues[0]) years", fontSize: 30, opacity: 0.46, color: OnboardingPalette.green, weight: .black)
            carouselText(middleText, fontSize: 60, opacity: 1, color: OnboardingPalette.green, weight: .black)
            carouselText("\(finalValues[2]) years", fontSize: 30, opacity: 0.28, color: OnboardingPalette.green, weight: .black)
        }
        .frame(maxWidth: .infinity)
    }

    private var middleText: String {
        guard hasSettled, !finalMiddleSuffix.isEmpty else {
            return "\(finalValues[1]) years"
        }
        return "\(finalValues[1])\(finalMiddleSuffix)"
    }

    private func carouselText(_ text: String, fontSize: CGFloat, opacity: Double, color: Color, weight: Font.Weight = .bold) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(color.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
    }

    private func startAnimation() {
        guard !hasSettled else { return }
        scrollOffset = 0
        guard !reduceMotion else {
            hasSettled = true
            return
        }

        spinTask?.cancel()
        spinTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 1.85)) {
                scrollOffset = CGFloat(finalSpinIndex)
            }

            try? await Task.sleep(nanoseconds: 1_850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                hasSettled = true
            }
        }
    }

    private func centeredOffset(for index: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        (viewportHeight / 2) - (rowHeight / 2) - (index * rowHeight)
    }
}

private struct OnboardingDelayedButton: View {
    let title: String
    let delay: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        OnboardingPrimaryButton(title: title, action: action)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .allowsHitTesting(isVisible)
            .onAppear(perform: reveal)
    }

    private func reveal() {
        guard !isVisible else { return }
        guard !reduceMotion else {
            isVisible = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.36)) {
                isVisible = true
            }
        }
    }
}

private enum OnboardingPalette {
    static let green = Color(red: 0.0, green: 0.55, blue: 0.35)
    static let darkGreen = Color(red: 0.015, green: 0.22, blue: 0.12)
    static let progressLight = Color(red: 0.70, green: 0.95, blue: 0.72)
    static let progressMid = Color(red: 0.24, green: 0.80, blue: 0.42)
    static let privacySheet = Color(red: 0.105, green: 0.095, blue: 0.11)
    static let privacyCard = Color(red: 0.22, green: 0.21, blue: 0.23)
    static let lime = Color(red: 0.78, green: 0.93, blue: 0.18)
    static let secondaryText = Color(red: 0.43, green: 0.44, blue: 0.41)
    static let skipText = secondaryText.opacity(0.72)
    static let placeholder = Color(red: 0.70, green: 0.70, blue: 0.68)
    static let rule = Color(red: 0.82, green: 0.82, blue: 0.80)
    static let rowBackground = Color(red: 0.92, green: 0.92, blue: 0.92)
}

private enum OnboardingMetrics {
    static let horizontalPadding: CGFloat = 34
    static let topLogoWidth: CGFloat = 116
    static let titleFont: CGFloat = 28
    static let subtitleFont: CGFloat = 21
    static let inputFont: CGFloat = 20
    static let secondaryActionFont: CGFloat = 18
    static let buttonFont: CGFloat = 22
    static let buttonHeight: CGFloat = 56
    static let skipFont: CGFloat = 21
    static let rowFont: CGFloat = 20
    static let rowHeight: CGFloat = 58
    static let rowIconSize: CGFloat = 28
}

private enum OnboardingCopy {
    static let habits = [
        "Ignoring people around me",
        "Scrolling in bed",
        "Constantly checking my phone",
        "Scrolling as soon as I wake up",
        "Interrupting my work/studying",
        "Feeling bad after using my phone"
    ]

    static let apps = [
        "Tiktok",
        "Instagram",
        "Snapchat",
        "Facebook",
        "X/Twitter"
    ]
}

private struct OnboardingSplashPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAnimateIn = false

    let onStart: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingPalette.green
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                        .frame(height: proxy.size.height * 0.39)

                    OnboardingLogo(assetName: "nima_logo", fallbackColor: .white)
                        .frame(width: min(214, proxy.size.width * 0.53), height: 76, alignment: .leading)
                        .opacity(splashSettled ? 1 : 0.92)
                        .scaleEffect(splashSettled ? 1 : 0.97, anchor: .leading)
                        .offset(y: splashSettled ? 0 : 10)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("keeping social media")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Text("social.")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(OnboardingPalette.lime)
                    }
                    .opacity(splashSettled ? 1 : 0.92)
                    .offset(y: splashSettled ? 0 : 8)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 52)
                .allowsHitTesting(false)

                VStack {
                    Spacer()

                    OnboardingPrimaryButton(title: "Get Started") {
                        onStart()
                    }
                    .frame(width: min(254, max(220, proxy.size.width * 0.63)))
                    .padding(.bottom, max(54, proxy.safeAreaInsets.bottom + 22))
                    .contentShape(Capsule())
                    .accessibilityIdentifier("onboarding.splash.start")
                }
                .frame(maxWidth: .infinity)
                .zIndex(2)
            }
            .onAppear {
                startSplashAnimationIfNeeded()
            }
        }
    }

    private var splashSettled: Bool {
        reduceMotion || didAnimateIn
    }

    private func startSplashAnimationIfNeeded() {
        guard !reduceMotion else {
            didAnimateIn = true
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            didAnimateIn = false
        }

        withAnimation(.easeOut(duration: 0.38).delay(0.04)) {
            didAnimateIn = true
        }
    }
}

private struct OnboardingWhitePage<Content: View, Bottom: View>: View {
    var showsSkip = false
    var skipTitle = "skip"
    var topLogoWidth: CGFloat = OnboardingMetrics.topLogoWidth
    var keyboardAvoidance = false
    var onSkip: (() -> Void)?
    var onBack: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let bottom: Bottom
    @State private var keyboardHeight: CGFloat = 0

    init(
        showsSkip: Bool = false,
        skipTitle: String = "skip",
        topLogoWidth: CGFloat = OnboardingMetrics.topLogoWidth,
        keyboardAvoidance: Bool = false,
        onSkip: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.showsSkip = showsSkip
        self.skipTitle = skipTitle
        self.topLogoWidth = topLogoWidth
        self.keyboardAvoidance = keyboardAvoidance
        self.onSkip = onSkip
        self.onBack = onBack
        self.content = content()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = bottomPadding(for: proxy)

            ZStack(alignment: .topTrailing) {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: max(10, proxy.safeAreaInsets.top - 6))

                    OnboardingLogo(assetName: "nima_logo_green", fallbackColor: OnboardingPalette.green)
                        .frame(width: topLogoWidth, height: topLogoWidth * 0.38)

                    content

                    Spacer(minLength: 10)

                    bottom
                        .padding(.horizontal, 40)
                        .padding(.bottom, bottomInset)
                }
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height)
                .padding(.horizontal, OnboardingMetrics.horizontalPadding)

                if showsSkip {
                    Group {
                        if let onSkip {
                            OnboardingSkipButton(title: skipTitle, action: onSkip)
                        } else {
                            Text(skipTitle)
                                .font(.system(size: OnboardingMetrics.skipFont, weight: .regular))
                                .foregroundStyle(OnboardingPalette.skipText)
                        }
                    }
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 2))
                    .padding(.trailing, 36)
                }

                #if DEBUG
                if let onBack {
                    HStack {
                        OnboardingBackButton(action: onBack)
                        Spacer()
                    }
                    .padding(.top, max(8, proxy.safeAreaInsets.top - 4))
                    .padding(.leading, 18)
                }
                #endif
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                guard keyboardAvoidance else { return }
                updateKeyboardHeight(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                guard keyboardAvoidance else { return }
                let duration = keyboardAnimationDuration(from: notification)
                withAnimation(.easeOut(duration: duration)) {
                    keyboardHeight = 0
                }
            }
        }
    }

    private func bottomPadding(for proxy: GeometryProxy) -> CGFloat {
        let defaultPadding = max(24, proxy.safeAreaInsets.bottom + 20)
        guard keyboardAvoidance, keyboardHeight > 0 else { return defaultPadding }
        return max(12, keyboardHeight - proxy.safeAreaInsets.bottom + 12)
    }

    private func updateKeyboardHeight(from notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let nextHeight = max(0, UIScreen.main.bounds.height - endFrame.minY)
        let duration = keyboardAnimationDuration(from: notification)
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = nextHeight
        }
    }

    private func keyboardAnimationDuration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    }
}

private struct OnboardingLogo: View {
    let assetName: String
    let fallbackColor: Color

    var body: some View {
        Group {
            if let image = UIImage.homeDashboardResource(named: assetName, fileExtension: "png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("nima")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(fallbackColor)
            }
        }
        .accessibilityLabel("nima")
    }
}

private struct OnboardingTitle: View {
    let text: String
    let fontSize: CGFloat
    let minimumScale: CGFloat
    let lineLimit: Int

    init(
        _ text: String,
        fontSize: CGFloat = OnboardingMetrics.titleFont,
        minimumScale: CGFloat = 0.72,
        lineLimit: Int = 3
    ) {
        self.text = text
        self.fontSize = fontSize
        self.minimumScale = minimumScale
        self.lineLimit = lineLimit
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .black))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .minimumScaleFactor(minimumScale)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: OnboardingMetrics.buttonFont, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: OnboardingMetrics.buttonHeight)
                .background(OnboardingPalette.darkGreen)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct OnboardingSkipButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: OnboardingMetrics.skipFont, weight: .regular))
            .foregroundStyle(OnboardingPalette.skipText)
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.skip")
    }
}

#if DEBUG
private struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OnboardingPalette.skipText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("onboarding.debug.back")
    }
}
#endif

private struct OnboardingSelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? .white : .clear)
                        .frame(width: OnboardingMetrics.rowIconSize, height: OnboardingMetrics.rowIconSize)
                        .overlay {
                            Circle()
                                .stroke(isSelected ? .white : Color.black.opacity(0.7), lineWidth: 3)
                        }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(OnboardingPalette.darkGreen)
                    }
                }

                Text(title)
                    .font(.system(size: OnboardingMetrics.rowFont, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: OnboardingMetrics.rowHeight)
            .background(isSelected ? OnboardingPalette.darkGreen : OnboardingPalette.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct PhoneUsageGauge: View {
    let hours: Int

    private var progress: CGFloat {
        min(max(CGFloat(hours) / 16, 0), 1)
    }

    private var displayHours: String {
        hours >= 16 ? "16+" : "\(hours)"
    }

    private var accessibilityHours: String {
        hours >= 16 ? "16 or more hours" : "\(hours) hours"
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let strokeWidth = side * 0.09
            let arcStart = 133.0
            let arcEnd = 407.0
            let progressEnd = arcStart + ((arcEnd - arcStart) * Double(progress))

            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    GaugeTick(angle: .degrees(Double(index) * 45))
                        .stroke(Color.gray.opacity(0.55), style: StrokeStyle(lineWidth: max(2, side * 0.01), lineCap: .round))
                        .frame(width: side * 0.83, height: side * 0.83)
                }

                GaugeArc(startAngle: arcStart, endAngle: arcEnd)
                    .stroke(Color.gray.opacity(0.22), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .padding(strokeWidth / 2)

                if progress > 0 {
                    GaugeArc(startAngle: arcStart, endAngle: progressEnd)
                        .stroke(
                            AngularGradient(
                                stops: [
                                    .init(color: OnboardingPalette.green, location: 0),
                                    .init(color: OnboardingPalette.progressMid, location: 0.45),
                                    .init(color: OnboardingPalette.progressLight, location: 1)
                                ],
                                center: .center,
                                startAngle: .degrees(arcStart),
                                endAngle: .degrees(arcEnd)
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .padding(strokeWidth / 2)
                }

                VStack(spacing: 0) {
                    Text(displayHours)
                        .font(.system(size: side * 0.29, weight: .black))
                        .foregroundStyle(.black)
                        .monospacedDigit()
                    Text("hours")
                        .font(.system(size: side * 0.09, weight: .regular))
                        .foregroundStyle(OnboardingPalette.secondaryText)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: hours)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityHours). Your best guess is fine.")
    }
}

private struct OnboardingPhoneSlider: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double
    var onInteraction: () -> Void = {}

    private let thumbSize: CGFloat = 30
    private let trackHeight: CGFloat = 8

    private var progress: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max(CGFloat((value - range.lowerBound) / span), 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let usableWidth = max(1, proxy.size.width - thumbSize)
            let fillWidth = usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.82, green: 0.85, blue: 0.87))
                    .frame(width: usableWidth, height: trackHeight)
                    .offset(x: thumbSize / 2)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [OnboardingPalette.green, OnboardingPalette.progressMid],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth, height: trackHeight)
                    .offset(x: thumbSize / 2)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .offset(x: fillWidth)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onInteraction()
                        updateValue(from: gesture.location.x, width: usableWidth)
                    }
            )
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel("Phone usage")
        .accessibilityValue("\(Int(value.rounded())) hours")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onInteraction()
                value = min(range.upperBound, value + step)
            case .decrement:
                onInteraction()
                value = max(range.lowerBound, value - step)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(from x: CGFloat, width: CGFloat) {
        let adjustedX = min(max(x - thumbSize / 2, 0), width)
        let rawValue = range.lowerBound + Double(adjustedX / width) * (range.upperBound - range.lowerBound)
        let steppedValue = ((rawValue - range.lowerBound) / step).rounded() * step + range.lowerBound
        value = min(max(steppedValue, range.lowerBound), range.upperBound)
    }
}

private struct GaugeTick: Shape {
    let angle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = CGFloat(angle.radians)
        let outer = min(rect.width, rect.height) * 0.46
        let inner = min(rect.width, rect.height) * 0.39
        let start = CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner)
        let end = CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

private struct GaugeArc: Shape {
    let startAngle: Double
    let endAngle: Double

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = side / 2

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

private struct VPNPermissionIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "globe")
                            .font(.system(size: 31, weight: .medium))
                            .foregroundStyle(.white)
                    }

                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 6, y: 6)
            }

            Text("“Nima” Would Like to Add VPN\nConfigurations")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("All network activity on this iPhone\nmay be filtered or monitored when\nusing VPN.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(2)

            Spacer()

            HStack(spacing: 10) {
                Text("Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())

                Text("Don’t Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(OnboardingPalette.green.opacity(0.42), lineWidth: 1)
                }
        }
        .overlay(alignment: .bottomLeading) {
            CurvedArrow()
                .stroke(OnboardingPalette.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 70, height: 84)
                .offset(x: 60, y: 34)
        }
        .accessibilityLabel("Example VPN permission dialog")
    }
}

private struct NotificationPermissionIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("“Nima” Would Like to Send You\nNotifications")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Notifications may include alerts,\nsounds and icon badges. These can\nbe configured in Settings.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(2)

            Spacer()

            HStack(spacing: 10) {
                Text("Don’t Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())

                Text("Allow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(OnboardingPalette.green.opacity(0.42), lineWidth: 1)
                }
        }
        .overlay(alignment: .bottomTrailing) {
            CurvedArrow()
                .stroke(OnboardingPalette.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 70, height: 84)
                .scaleEffect(x: -1, y: 1)
                .offset(x: -48, y: 34)
        }
        .accessibilityLabel("Example notification permission dialog")
    }
}

private struct CurvedArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX * 0.72, y: rect.maxY * 0.92))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.22, y: rect.maxY * 0.16),
            control1: CGPoint(x: rect.maxX * 0.14, y: rect.maxY * 0.78),
            control2: CGPoint(x: rect.maxX * 0.12, y: rect.maxY * 0.34)
        )
        path.move(to: CGPoint(x: rect.maxX * 0.08, y: rect.maxY * 0.27))
        path.addLine(to: CGPoint(x: rect.maxX * 0.22, y: rect.maxY * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX * 0.36, y: rect.maxY * 0.30))
        return path
    }
}

private struct OnboardingPrivacySheet: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()

                VStack(spacing: 18) {
                    Text("Your data stays private")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nima does NOT see:")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        ForEach(["Messages", "Passwords", "Photos", "Any personal content"], id: \.self) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(width: 21, height: 21)
                                    .overlay {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                Text(item)
                                    .font(.system(size: 21, weight: .regular))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text("Blocking happens on your phone using\nonly the network signals needed")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OnboardingPalette.privacyCard)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier("onboarding.privacy.continue")
                }
                .padding(.horizontal, 30)
                .padding(.top, 34)
                .padding(.bottom, max(42, proxy.safeAreaInsets.bottom + 30))
                .frame(maxWidth: .infinity)
                .background(OnboardingPalette.privacySheet)
                .clipShape(TopRoundedRectangle(radius: 40))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct TopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private struct OnboardingAuthButton: View {
    let title: String
    var systemImage: String?
    var letter: String?
    var isOutlined = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 28)
                } else if let letter {
                    Text(letter)
                        .font(.system(size: 26, weight: .black))
                        .frame(width: 28)
                }

                Text(title)
                    .font(.system(size: 22, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(isOutlined ? OnboardingPalette.darkGreen : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isOutlined ? Color.white : OnboardingPalette.darkGreen)
            .clipShape(Capsule())
            .overlay {
                if isOutlined {
                    Capsule()
                        .stroke(OnboardingPalette.darkGreen, lineWidth: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.account.\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

#Preview {
    OnboardingFlowScreen()
        .environment(OnboardingStore(defaults: nil))
        .environment(AppSettingsStore(defaults: nil))
        .environmentObject(VPNManager())
}
