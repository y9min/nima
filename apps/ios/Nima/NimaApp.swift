import GoogleSignIn
import SwiftUI
import NetworkExtension
import StoreKit
import UIKit

@main
struct NimaApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var vpnManager = VPNManager()
    @State private var path = NavigationPath()
    @State private var store = AppStore()
    @State private var streakStore = StreakStore()
    @State private var timeWindowStore = TimeWindowStore()
    @State private var gridPositionStore = GridPositionStore()
    @State private var authStore = AuthStore()
    @State private var appSettingsStore = AppSettingsStore()
    @State private var onboardingStore = OnboardingStore()
    @State private var subscriptionStore = SubscriptionStore()
    @State private var didConfigureProtection = false
    @State private var guidedOnboardingPresentationMode: GuidedOnboardingPresentationMode?
    @State private var guidedPracticePhase: GuidedPracticePhase = .hidden
    @State private var guidedPracticeActiveApps: Set<GuidedPracticeLaunchApp> = []
    @State private var guidedPracticePIPError: String?
    @State private var isStartingGuidedPracticePIP = false
    @State private var pipInstructionController = PiPInstructionVideoController()
    @State private var didStartLaunchServices = false
    @State private var hasHandledGuidedPracticeReviewRequest = false
    private let guidedPracticeReviewPromptStore = GuidedPracticeReviewPromptStore()

    init() {
        TimeWindowNotificationCoordinator.shared.install()
        let sharedDefaults = UserDefaults(suiteName: NimaConstants.appGroupID)
        Self.migrateUDPSelectiveSafeModeDefault(sharedDefaults)
        sharedDefaults?.register(defaults: [
            NimaConstants.strictUDPBlockEnabledKey: false,
            NimaConstants.udpDisabledFastRejectEnabledKey: false,
            NimaConstants.udpSelectiveSafeModeEnabledKey: true,
            NimaConstants.tun2socksStartupModeKey: NimaConstants.tun2socksStartupModeStagedAfterConnect,
            NimaConstants.transportProtectionV2StabilityFirstKey: true,
            NimaConstants.windowsNotificationsEnabledKey: true,
            NimaConstants.streakRemindersEnabledKey: AppSettingsStore.defaultStreakRemindersEnabled,
            NimaConstants.streakReminderHourKey: AppSettingsStore.defaultStreakReminderHour,
            NimaConstants.streakReminderMinuteKey: AppSettingsStore.defaultStreakReminderMinute,
            NimaConstants.pauseIntervalMinutesKey: AppSettingsStore.defaultPauseIntervalMinutes,
        ])
        if sharedDefaults?.bool(forKey: NimaConstants.transportProtectionV2StabilityFirstDefaultMigratedKey) != true {
            if sharedDefaults?.object(forKey: NimaConstants.transportProtectionV2StabilityFirstKey) == nil {
                sharedDefaults?.set(true, forKey: NimaConstants.transportProtectionV2StabilityFirstKey)
            }
            sharedDefaults?.set(true, forKey: NimaConstants.transportProtectionV2StabilityFirstDefaultMigratedKey)
        }
    }

    private static func migrateUDPSelectiveSafeModeDefault(_ defaults: UserDefaults?) {
        guard let defaults else { return }
        guard defaults.bool(forKey: NimaConstants.udpSelectiveSafeModeMigratedKey) != true else { return }

        if persistentBool(defaults, key: NimaConstants.udpSelectiveSafeModeEnabledKey) != nil {
            if persistentBool(defaults, key: NimaConstants.udpForwardingDisabledKey) == true {
                defaults.set(false, forKey: NimaConstants.udpForwardingDisabledKey)
            }
            defaults.set(true, forKey: NimaConstants.udpSelectiveSafeModeMigratedKey)
            return
        }

        if let legacyDisabled = persistentBool(defaults, key: NimaConstants.udpForwardingDisabledKey) {
            defaults.set(legacyDisabled, forKey: NimaConstants.udpSelectiveSafeModeEnabledKey)
            if legacyDisabled {
                defaults.set(false, forKey: NimaConstants.udpForwardingDisabledKey)
            }
        } else {
            defaults.set(true, forKey: NimaConstants.udpSelectiveSafeModeEnabledKey)
        }

        defaults.set(true, forKey: NimaConstants.udpSelectiveSafeModeMigratedKey)
    }

    private static func persistentBool(_ defaults: UserDefaults, key: String) -> Bool? {
        defaults.persistentDomain(forName: NimaConstants.appGroupID)?[key] as? Bool
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                NavigationStack(path: $path) {
                    rootScreen
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .home:
                            mainTabsScreen
                        case .timeWindows:
                            TimeWindowsScreen(
                                onHome: {
                                    path = NavigationPath()
                                },
                                onSettings: {
                                    path.append(Route.settings)
                                }
                            )
                        case .blockingOptions(let appId):
                            BlockingOptionsScreen(appId: appId)
                        case .settings:
                            SettingsScreen(
                                onHome: {
                                    path = NavigationPath()
                                },
                                onWindows: {
                                    path = NavigationPath()
                                    path.append(Route.timeWindows)
                                },
                                onAccountDeleted: routeToSplashAfterAccountDeletion
                            )
                        case .trafficDashboard:
                            TrafficDashboardView()
                        case .extensionLog:
                            ExtensionLogView()
                        }
                    }
                }
                .environment(store)
                .environment(streakStore)
                .environment(timeWindowStore)
                .environment(gridPositionStore)
                .environment(authStore)
                .environment(appSettingsStore)
                .environment(onboardingStore)
                .environment(subscriptionStore)
                .environmentObject(vpnManager)
                .statusBarHidden(!onboardingStore.isCompleted)
                .preferredColorScheme(.dark)
                .task {
                    await startLaunchServicesIfNeeded()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    // Keep the first SwiftUI frame lightweight so iOS can leave the launch screen.
                }
                .onChange(of: onboardingStore.isCompleted) { _, isCompleted in
                    guard isCompleted else {
                        path = NavigationPath()
                        didConfigureProtection = false
                        guidedOnboardingPresentationMode = nil
                        guidedPracticePhase = .hidden
                        guidedPracticeActiveApps = []
                        guidedPracticePIPError = nil
                        isStartingGuidedPracticePIP = false
                        hasHandledGuidedPracticeReviewRequest = false
                        return
                    }
                    configureProtectionIfNeeded()
                    store.syncVPNState(source: "onboarding.completed")
                    markStreakIfEligible(source: "onboarding.completed")
                    presentGuidedOnboardingIfNeeded()
                }
                .onChange(of: authStore.isLoggedIn) { _, isLoggedIn in
                    if isLoggedIn {
                        path = NavigationPath()
                        guidedOnboardingPresentationMode = nil
                        if guidedPracticePhase != .waitingForReturn {
                            guidedPracticePhase = .hidden
                        }
                        applySubscriptionIdentity()
                    } else {
                        subscriptionStore.logOut()
                    }
                    presentGuidedOnboardingIfNeeded()
                }
                .onChange(of: subscriptionStore.hasPremium) { _, hasPremium in
                    if hasPremium {
                        presentGuidedOnboardingIfNeeded()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
                .onChange(of: activeGuidedPracticeBlockedApps) { _, activeApps in
                    guard !activeApps.isEmpty, guidedPracticePhase == .dragTikTokCoachMark else { return }
                    guidedPracticeActiveApps = activeApps
                    guidedPracticePhase = .openAppPrompt
                }
                .onChange(of: vpnManager.vpnStatus) { _, _ in
                    if onboardingStore.isCompleted {
                        store.syncVPNState(source: "vpn.status")
                        markStreakIfEligible(source: "vpn.status")
                    }
                }
                .task(id: guidedPracticePhase) {
                    await handleGuidedPracticePhaseTask()
                }

                if shouldMountPiPInstructionHost {
                    PiPInstructionVideoHost(controller: pipInstructionController)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let guidedOnboardingPresentationMode {
                    GuidedOnboardingModal(completionTitle: guidedOnboardingPresentationMode.completionTitle) {
                        if guidedOnboardingPresentationMode == .firstRunPractice {
                            onboardingStore.markGuidedOnboardingSeen()
                        }
                        self.guidedOnboardingPresentationMode = nil
                        if guidedOnboardingPresentationMode == .firstRunPractice {
                            beginGuidedPractice()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }

                guidedPracticeOverlay
            }
            .animation(.easeInOut(duration: 0.18), value: guidedOnboardingPresentationMode)
            .animation(.easeInOut(duration: 0.18), value: guidedPracticePhase)
        }
    }

    @MainActor
    private func startLaunchServicesIfNeeded() async {
        guard !didStartLaunchServices else { return }
        didStartLaunchServices = true

        await Task.yield()
        try? await Task.sleep(nanoseconds: 250_000_000)

        _ = AppOptionsService.shared
        SVGCache.shared.preload(svgNames: ["instagram", "kalshi", "fanduel"])
        SVGCache.shared.preload(svgNames: ["home_mountains"], size: CGSize(width: 500, height: 280))

        vpnManager.setup()
        configureProtectionIfNeeded()
        presentGuidedOnboardingIfNeeded()

        await authStore.loadCurrentSession()
        subscriptionStore.configure()
        if authStore.isLoggedIn, !authStore.userEmail.isEmpty {
            applySubscriptionIdentity()
        } else {
            subscriptionStore.refreshAfterLaunch()
        }

        await authStore.listenForAuthChanges()
    }

    private func configureProtectionIfNeeded() {
        guard onboardingStore.isCompleted, !didConfigureProtection else { return }
        didConfigureProtection = true

        store.configureVPNAutostart(
            startVPN: { vpnManager.startVPN(source: "app_store.autostart") },
            stopVPN: { vpnManager.stopVPN(source: "app_store.autostop") },
            vpnStatus: { vpnManager.vpnStatus },
            markStreakIfEligible: { source in
                markStreakIfEligible(source: source)
            }
        )
        timeWindowStore.configure(
            applyScheduledApps: { appIDs, source in
                store.setScheduledBlockedAppIDs(appIDs, source: source)
            },
            startProtection: { source in
                vpnManager.startVPN(source: source)
            },
            requestHomeFocus: {
                path = NavigationPath()
            }
        )
        markStreakIfEligible(source: "app.launch")
    }

    @ViewBuilder
    private var rootScreen: some View {
        if onboardingStore.isCompleted {
            if shouldWaitForSubscriptionStatus {
                SubscriptionStatusLoadingScreen()
            } else if shouldShowPaywall {
                PaywallScreen(onUnlocked: completePaywall)
            } else {
                mainTabsScreen
            }
        } else {
            OnboardingFlowScreen()
        }
    }

    private var mainTabsScreen: some View {
        MainTabsScreen(
            onSelectApp: { app in
                path.append(Route.blockingOptions(appId: app.id))
            },
            onAccountDeleted: routeToSplashAfterAccountDeletion,
            onTrafficDashboard: {
                path.append(Route.trafficDashboard)
            },
            onShowGuidedOnboarding: {
                guidedOnboardingPresentationMode = .manualReplay
            },
            guidedPracticeCardStep: guidedPracticeCardStep,
            showsGuidedWindowsHomeCoachMark: guidedPracticePhase == .windowsHomeCoachMark,
            onGuidedWindowsHomeAction: beginGuidedWindowsEditor,
            guidedWindowsEditorStep: guidedWindowsEditorStep,
            onGuidedWindowsEditorAdvance: advanceGuidedWindowsEditorStep,
            onGuidedWindowsEditorFinished: showGuidedWindowsReadyModal
        )
    }

    private var shouldShowPaywall: Bool {
        needsSubscriptionGate
            && !shouldHoldPaywallForGuidedPracticeReturn
            && subscriptionStore.isReadyForPaywallDecision
            && !subscriptionStore.hasPremium
    }

    private var shouldWaitForSubscriptionStatus: Bool {
        needsSubscriptionGate
            && !shouldHoldPaywallForGuidedPracticeReturn
            && !subscriptionStore.isReadyForPaywallDecision
    }

    private var needsSubscriptionGate: Bool {
        onboardingStore.isCompleted
            && onboardingStore.hasCompletedGuidedPractice
            && onboardingStore.hasCompletedGuidedWindowsOnboarding
    }

    private var shouldHoldPaywallForGuidedPracticeReturn: Bool {
        if onboardingStore.hasGuidedPracticeReturnPending {
            return true
        }

        switch guidedPracticePhase {
        case .success, .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting:
            return true
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark, .openAppPrompt, .waitingForReturn, .completed:
            return false
        }
    }

    private func applySubscriptionIdentity() {
        guard !authStore.userEmail.isEmpty else { return }
        if authStore.isDemo, AuthStore.isAnnualDemoAccount(email: authStore.userEmail) {
            subscriptionStore.activateDemoAnnualPlan()
        } else {
            subscriptionStore.identify(appUserID: authStore.userEmail)
            subscriptionStore.loadOfferings()
        }
    }

    private func routeToSplashAfterAccountDeletion() {
        path = NavigationPath()
    }

    @ViewBuilder
    private var guidedPracticeOverlay: some View {
        switch guidedPracticePhase {
        case .openAppPrompt:
            GuidedPracticeOpenAppPromptModal(
                activeApps: guidedPracticeActiveApps,
                isStartingPIP: isStartingGuidedPracticePIP,
                errorMessage: guidedPracticePIPError,
                onOpenApp: openGuidedPracticeApp
            )
            .transition(.opacity)
            .zIndex(11)
        case .success:
            GuidedPracticeSuccessModal(
                onContinue: continueGuidedPracticeSuccess,
                onTroubleshoot: {
                    guidedPracticePhase = .troubleshooting
                }
            )
            .transition(.opacity)
            .zIndex(11)
        case .windowsReady:
            GuidedWindowsReadyModal(
                onContinue: continueGuidedWindowsReady
            )
            .transition(.opacity)
            .zIndex(11)
        case .reviewPrompt:
            GuidedPracticeReviewModal(
                onContinue: continueGuidedPracticeReviewPrompt
            )
            .transition(.opacity)
            .zIndex(11)
        case .troubleshooting:
            GuidedPracticeTroubleshootingModal(
                onBack: {
                    guidedPracticePhase = .success
                },
                onOpenVPNSettings: openVPNSettings,
                onTryAgain: retryGuidedPracticeOpenApp
            )
            .transition(.opacity)
            .zIndex(11)
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark, .waitingForReturn, .windowsHomeCoachMark, .windowsEditor, .completed:
            EmptyView()
        }
    }

    private var guidedPracticeCardStep: GuidedPracticeCardStep? {
        switch guidedPracticePhase {
        case .readyCoachMark:
            return .ready
        case .dragTikTokCoachMark:
            return .dragTikTok
        case .hidden, .introSlides, .openAppPrompt, .waitingForReturn, .success, .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting, .completed:
            return nil
        }
    }

    private var guidedWindowsEditorStep: GuidedWindowsEditorStep? {
        guard case .windowsEditor(let step) = guidedPracticePhase else { return nil }
        return step
    }

    private var shouldMountPiPInstructionHost: Bool {
        switch guidedPracticePhase {
        case .openAppPrompt, .waitingForReturn:
            return true
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark, .success, .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting, .completed:
            return false
        }
    }

    private func presentGuidedOnboardingIfNeeded() {
        guard onboardingStore.isCompleted else {
            return
        }
        guard !shouldShowPaywall, !shouldWaitForSubscriptionStatus else {
            return
        }

        if onboardingStore.hasGuidedPracticeReturnPending {
            path = NavigationPath()
            guidedOnboardingPresentationMode = nil
            hasHandledGuidedPracticeReviewRequest = false
            guidedPracticePhase = .success
            return
        }

        if onboardingStore.hasCompletedGuidedPractice,
           !onboardingStore.hasCompletedGuidedWindowsOnboarding,
           guidedOnboardingPresentationMode == nil,
           guidedPracticePhase == .hidden || guidedPracticePhase == .completed {
            beginGuidedWindowsOnboarding()
            return
        }

        guard onboardingStore.isCompleted,
              !onboardingStore.hasCompletedGuidedPractice,
              guidedOnboardingPresentationMode == nil,
              guidedPracticePhase == .hidden || guidedPracticePhase == .completed else {
            return
        }

        guidedPracticePhase = .introSlides
        guidedOnboardingPresentationMode = .firstRunPractice
    }

    private func completePaywall() {
        path = NavigationPath()
        presentGuidedOnboardingIfNeeded()
    }

    private func beginGuidedPractice() {
        path = NavigationPath()
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticeActiveApps = activeGuidedPracticeBlockedApps
        guidedPracticePhase = guidedPracticeActiveApps.isEmpty ? .readyCoachMark : .openAppPrompt
    }

    private var activeGuidedPracticeBlockedApps: Set<GuidedPracticeLaunchApp> {
        Set(GuidedPracticeLaunchApp.allCases.filter { isBlockedForGuidedPractice($0) })
    }

    private func isBlockedForGuidedPractice(_ app: GuidedPracticeLaunchApp) -> Bool {
        let appID = app.rawValue
        let isManuallyBlocked = store.app(for: appID)?.options.contains { $0.isEnabled } == true
        return isManuallyBlocked || store.isAppScheduled(appID) || timeWindowStore.isAppScheduled(appID)
    }

    @MainActor
    private func handleGuidedPracticePhaseTask() async {
        guard guidedPracticePhase == .readyCoachMark else { return }
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        guard guidedPracticePhase == .readyCoachMark else { return }
        guidedPracticeActiveApps = activeGuidedPracticeBlockedApps
        guidedPracticePhase = guidedPracticeActiveApps.isEmpty ? .dragTikTokCoachMark : .openAppPrompt
    }

    private func openGuidedPracticeApp(_ app: GuidedPracticeLaunchApp) {
        startGuidedPracticePIP {
            openFirstAvailableURL(app.launchURLs)
        }
    }

    private func startGuidedPracticePIP(onStarted: (() -> Void)? = nil) {
        guard !isStartingGuidedPracticePIP else { return }
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = true

        pipInstructionController.start(
            onStarted: {
                onboardingStore.markGuidedPracticeCompleted()
                onboardingStore.setGuidedPracticeReturnPending(true)
                guidedPracticePhase = .waitingForReturn
                isStartingGuidedPracticePIP = false
                onStarted?()
            },
            onFailed: { message in
                guidedPracticePIPError = message
                isStartingGuidedPracticePIP = false
                guidedPracticePhase = .openAppPrompt
            }
        )
    }

    private func openFirstAvailableURL(_ urls: [URL]) {
        guard let url = urls.first else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            guard !success else { return }
            openFirstAvailableURL(Array(urls.dropFirst()))
        }
    }

    private func continueGuidedPracticeSuccess() {
        if onboardingStore.hasCompletedGuidedWindowsOnboarding {
            onboardingStore.markGuidedPracticeCompleted()
            onboardingStore.setGuidedPracticeReturnPending(false)
            showGuidedPracticeReviewPrompt()
        } else {
            onboardingStore.markGuidedWindowsOnboardingPending()
            onboardingStore.markGuidedPracticeCompleted()
            onboardingStore.setGuidedPracticeReturnPending(false)
            beginGuidedWindowsOnboarding()
        }
    }

    private func beginGuidedWindowsOnboarding() {
        path = NavigationPath()
        guidedOnboardingPresentationMode = nil
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticePhase = .windowsHomeCoachMark
    }

    private func beginGuidedWindowsEditor() {
        guard guidedPracticePhase == .windowsHomeCoachMark else { return }
        guidedPracticePhase = .windowsEditor(.name)
    }

    private func advanceGuidedWindowsEditorStep() {
        guard case .windowsEditor(let step) = guidedPracticePhase else { return }
        switch step {
        case .name:
            guidedPracticePhase = .windowsEditor(.time)
        case .time:
            guidedPracticePhase = .windowsEditor(.apps)
        case .apps:
            guidedPracticePhase = .windowsEditor(.repeatDays)
        case .repeatDays:
            guidedPracticePhase = .windowsEditor(.icon)
        case .icon:
            guidedPracticePhase = .windowsEditor(.saveOrCancel)
        case .saveOrCancel:
            break
        }
    }

    private func showGuidedWindowsReadyModal() {
        guard case .windowsEditor = guidedPracticePhase else { return }
        guidedPracticePhase = .windowsReady
    }

    private func continueGuidedWindowsReady() {
        onboardingStore.markGuidedWindowsOnboardingCompleted()
        showGuidedPracticeReviewPrompt()
    }

    private func showGuidedPracticeReviewPrompt() {
        onboardingStore.markGuidedPracticeCompleted()
        onboardingStore.setGuidedPracticeReturnPending(false)
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticePhase = .reviewPrompt
    }

    private func continueGuidedPracticeReviewPrompt() {
        guard hasHandledGuidedPracticeReviewRequest else {
            requestGuidedPracticeReviewIfNeeded()
            hasHandledGuidedPracticeReviewRequest = true
            return
        }

        finishGuidedPracticeReturn()
    }

    @MainActor
    private func requestGuidedPracticeReviewIfNeeded() {
        guard let userIdentifier = guidedPracticeReviewUserIdentifier else { return }
        guard !guidedPracticeReviewPromptStore.hasAttemptedPrompt(for: userIdentifier) else { return }
        guard let windowScene = activeForegroundWindowScene else { return }

        SKStoreReviewController.requestReview(in: windowScene)
        guidedPracticeReviewPromptStore.markPromptAttempted(for: userIdentifier)
    }

    private var guidedPracticeReviewUserIdentifier: String? {
        let email = AuthStore.normalizedEmail(authStore.userEmail)
        if !email.isEmpty {
            return "email:\(email)"
        }

        return authStore.userID.map { "user_id:\($0.uuidString.lowercased())" }
    }

    private var activeForegroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func finishGuidedPracticeReturn() {
        guidedPracticePhase = .completed
        guidedPracticeActiveApps = []
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
        hasHandledGuidedPracticeReviewRequest = false
        path = NavigationPath()
    }

    private func retryGuidedPracticeOpenApp() {
        onboardingStore.setGuidedPracticeReturnPending(false)
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticeActiveApps = activeGuidedPracticeBlockedApps
        guidedPracticePhase = .openAppPrompt
        path = NavigationPath()
    }

    private func openVPNSettings() {
        let appSettingsURL = URL(string: UIApplication.openSettingsURLString)
        let vpnSettingsURL = URL(string: "App-prefs:root=General&path=VPN")

        guard let vpnSettingsURL else {
            if let appSettingsURL {
                UIApplication.shared.open(appSettingsURL)
            }
            return
        }

        UIApplication.shared.open(vpnSettingsURL, options: [:]) { success in
            guard !success, let appSettingsURL else { return }
            UIApplication.shared.open(appSettingsURL)
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            if onboardingStore.isCompleted {
                timeWindowStore.evaluateSchedules(source: "app.scene.active", forceApply: true)
                store.syncVPNState(source: "app.scene.active")
                vpnManager.repairScheduledProtectionIfNeeded(source: "app.scene.active")
            }
            guard onboardingStore.hasGuidedPracticeReturnPending else { return }
            pipInstructionController.stop()
            path = NavigationPath()
            guidedOnboardingPresentationMode = nil
            guidedPracticePhase = .success
        case .inactive, .background:
            guard guidedPracticePhase == .openAppPrompt else { return }
            startGuidedPracticePIP()
        @unknown default:
            break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        Task {
            do {
                let handled = try await authStore.handleEmailMagicLink(url)
                guard handled else { return }
                await MainActor.run {
                    onboardingStore.markCompleted()
                }
            } catch {}
        }
    }

    private func markStreakIfEligible(source: String) {
        guard Self.isProtectionActive(vpnManager.vpnStatus),
              store.hasAnyEnabledBlockingOption else {
            syncStreakReminder()
            return
        }

        streakStore.markTodayEarned(
            source: store.firstEnabledBlockerSource ?? source
        )
        syncStreakReminder()
    }

    private func syncStreakReminder() {
        appSettingsStore.syncStreakReminder(
            hasEarnedToday: streakStore.hasEarnedToday()
        )
    }

    private static func isProtectionActive(_ status: NEVPNStatus) -> Bool {
        status == .connected || status == .connecting || status == .reasserting
    }
}

private struct SubscriptionStatusLoadingScreen: View {
    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.12, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if let image = UIImage(named: "nima_logo") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 54)
                } else {
                    Text("nima")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                ProgressView()
                    .tint(Color(red: 0.73, green: 0.93, blue: 0.09))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
