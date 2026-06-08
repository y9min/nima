import SwiftUI
import UIKit
import Combine

struct OnboardingFlowScreen: View {
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @EnvironmentObject private var vpnManager: VPNManager

    @State private var step: OnboardingStep = .splash
    @State private var displayName = ""
    @State private var phoneHours: Double = 0
    @State private var age = 18
    @State private var selectedHabits: Set<String> = []
    @State private var selectedApps: Set<String> = []
    @State private var showsPrivacySheet = false

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
        case .age:
            agePage
        case .habits:
            habitsPage
        case .apps:
            appsPage
        case .vpn:
            vpnEducationPage
        case .account:
            accountPage
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
            OnboardingPrimaryButton(title: "Continue") {
                if AppSettingsStore.normalizedDisplayName(displayName) != nil {
                    appSettingsStore.setDisplayName(displayName)
                }
                step = .phoneTime
            }
            .accessibilityIdentifier("onboarding.name.continue")
        }
    }

    private var phoneTimePage: some View {
        OnboardingWhitePage(onBack: goBack) {
            VStack(spacing: 12) {
                OnboardingTitle("How much time do you\nspend on your phone?")
                    .padding(.top, 22)

                Text("on your phone daily")
                    .font(.system(size: OnboardingMetrics.subtitleFont, weight: .regular))
                    .foregroundStyle(OnboardingPalette.secondaryText)

                Spacer()
                    .frame(height: 52)

                PhoneUsageGauge(hours: Int(phoneHours.rounded()))
                    .frame(width: 230, height: 230)

                OnboardingPhoneSlider(value: $phoneHours, range: 0...16, step: 1)
                    .padding(.horizontal, 34)
                    .accessibilityIdentifier("onboarding.phone.slider")
            }
        } bottom: {
            VStack(spacing: 16) {
                Button("I don’t know") {
                    onboardingStore.setPhoneHours(nil)
                    step = .age
                }
                .font(.system(size: OnboardingMetrics.secondaryActionFont, weight: .regular))
                .foregroundStyle(OnboardingPalette.secondaryText)
                .accessibilityIdentifier("onboarding.phone.unknown")

                OnboardingPrimaryButton(title: "Continue") {
                    onboardingStore.setPhoneHours(Int(phoneHours.rounded()))
                    step = .age
                }
                .accessibilityIdentifier("onboarding.phone.continue")
            }
        }
    }

    private var agePage: some View {
        OnboardingWhitePage(showsSkip: true, onSkip: {
            onboardingStore.setAge(nil)
            step = .habits
        }, onBack: goBack) {
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
                    .accessibilityIdentifier("onboarding.age.picker")
                }
            }
        } bottom: {
            OnboardingPrimaryButton(title: "Continue") {
                onboardingStore.setAge(age)
                step = .habits
            }
            .accessibilityIdentifier("onboarding.age.continue")
        }
    }

    private var habitsPage: some View {
        OnboardingWhitePage(showsSkip: true, onSkip: {
            selectedHabits = []
            onboardingStore.setSelectedHabits([])
            step = .apps
        }, onBack: goBack) {
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
            OnboardingPrimaryButton(title: "Continue") {
                onboardingStore.setSelectedHabits(selectedHabits)
                step = .apps
            }
            .accessibilityIdentifier("onboarding.habits.continue")
        }
    }

    private var appsPage: some View {
        OnboardingWhitePage(showsSkip: true, onSkip: {
            selectedApps = []
            onboardingStore.setSelectedApps([])
            step = .vpn
        }, onBack: goBack) {
            VStack(spacing: 12) {
                OnboardingTitle("Which apps do you use\nthe most?")
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
            OnboardingPrimaryButton(title: "Continue") {
                onboardingStore.setSelectedApps(selectedApps)
                step = .vpn
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

    private var accountPage: some View {
        OnboardingWhitePage(topLogoWidth: OnboardingMetrics.topLogoWidth, onBack: goBack) {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 54)

                OnboardingTitle("Let’s create your account")

                VStack(spacing: 18) {
                    OnboardingAuthButton(title: "Continue with Apple", systemImage: "apple.logo") {
                        completeOnboarding()
                    }
                    OnboardingAuthButton(title: "Continue with Google", letter: "G") {
                        completeOnboarding()
                    }
                    OnboardingAuthButton(title: "Sign up with email", systemImage: "envelope", isOutlined: true) {
                        completeOnboarding()
                    }

                    Text("Already have an account?")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(OnboardingPalette.placeholder)
                        .padding(.top, 6)
                }
            }
        } bottom: {
            EmptyView()
        }
    }

    private func loadDraftState() {
        displayName = appSettingsStore.displayName
        phoneHours = Double(onboardingStore.phoneHours ?? 0)
        age = onboardingStore.age ?? 18
        selectedHabits = onboardingStore.selectedHabits
        selectedApps = onboardingStore.selectedApps
    }

    private func triggerVPNPermissionAndContinue() {
        onboardingStore.markVPNPermissionRequested()
        vpnManager.startVPN(source: "onboarding.vpn_permission")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showsPrivacySheet = false
            step = .account
        }
    }

    private func completeOnboarding() {
        onboardingStore.markCompleted()
    }

    private func goBack() {
        guard let previousStep = step.previous else { return }
        if showsPrivacySheet {
            showsPrivacySheet = false
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
}

private enum OnboardingStep {
    case splash
    case name
    case phoneTime
    case age
    case habits
    case apps
    case vpn
    case account

    var previous: OnboardingStep? {
        switch self {
        case .splash:
            return nil
        case .name:
            return .splash
        case .phoneTime:
            return .name
        case .age:
            return .phoneTime
        case .habits:
            return .age
        case .apps:
            return .habits
        case .vpn:
            return .apps
        case .account:
            return .vpn
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
        "Ignoring people around you",
        "Scrolling in bed",
        "Constantly checking my phone",
        "Scrolling as soon as you wake up",
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

                    OnboardingPrimaryButton(title: "Get started") {
                        onStart()
                    }
                    .frame(width: min(254, max(220, proxy.size.width * 0.63)))
                    .padding(.bottom, max(54, proxy.safeAreaInsets.bottom + 22))
                    .scaleEffect(splashSettled ? 1 : 0.98)
                    .offset(y: splashSettled ? 0 : 8)
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
        }
        .buttonStyle(.plain)
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
        .accessibilityLabel("\(accessibilityHours) on your phone daily")
    }
}

private struct OnboardingPhoneSlider: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double

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
                value = min(range.upperBound, value + step)
            case .decrement:
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
