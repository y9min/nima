import SwiftUI
import NetworkExtension
import UIKit

@main
struct BubbleApp: App {
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
    @State private var didConfigureProtection = false
    @State private var guidedOnboardingPresentationMode: GuidedOnboardingPresentationMode?
    @State private var guidedPracticePhase: GuidedPracticePhase = .hidden
    @State private var guidedPracticeActiveApps: Set<GuidedPracticeLaunchApp> = []
    @State private var guidedPracticePIPError: String?
    @State private var isStartingGuidedPracticePIP = false
    @State private var pipInstructionController = PiPInstructionVideoController()

    init() {
        TimeWindowNotificationCoordinator.shared.install()
        let sharedDefaults = UserDefaults(suiteName: BubbleConstants.appGroupID)
        Self.migrateUDPSelectiveSafeModeDefault(sharedDefaults)
        sharedDefaults?.register(defaults: [
            BubbleConstants.strictUDPBlockEnabledKey: false,
            BubbleConstants.udpDisabledFastRejectEnabledKey: false,
            BubbleConstants.udpSelectiveSafeModeEnabledKey: true,
            BubbleConstants.tun2socksStartupModeKey: BubbleConstants.tun2socksStartupModeStagedAfterConnect,
            BubbleConstants.transportProtectionV2StabilityFirstKey: true,
            BubbleConstants.windowsNotificationsEnabledKey: true,
            BubbleConstants.streakRemindersEnabledKey: AppSettingsStore.defaultStreakRemindersEnabled,
            BubbleConstants.streakReminderHourKey: AppSettingsStore.defaultStreakReminderHour,
            BubbleConstants.streakReminderMinuteKey: AppSettingsStore.defaultStreakReminderMinute,
            BubbleConstants.pauseIntervalMinutesKey: AppSettingsStore.defaultPauseIntervalMinutes,
        ])
        if sharedDefaults?.bool(forKey: BubbleConstants.transportProtectionV2StabilityFirstDefaultMigratedKey) != true {
            if sharedDefaults?.object(forKey: BubbleConstants.transportProtectionV2StabilityFirstKey) == nil {
                sharedDefaults?.set(true, forKey: BubbleConstants.transportProtectionV2StabilityFirstKey)
            }
            sharedDefaults?.set(true, forKey: BubbleConstants.transportProtectionV2StabilityFirstDefaultMigratedKey)
        }
        _ = AppOptionsService.shared
    }

    private static func migrateUDPSelectiveSafeModeDefault(_ defaults: UserDefaults?) {
        guard let defaults else { return }
        guard defaults.bool(forKey: BubbleConstants.udpSelectiveSafeModeMigratedKey) != true else { return }

        if persistentBool(defaults, key: BubbleConstants.udpSelectiveSafeModeEnabledKey) != nil {
            if persistentBool(defaults, key: BubbleConstants.udpForwardingDisabledKey) == true {
                defaults.set(false, forKey: BubbleConstants.udpForwardingDisabledKey)
            }
            defaults.set(true, forKey: BubbleConstants.udpSelectiveSafeModeMigratedKey)
            return
        }

        if let legacyDisabled = persistentBool(defaults, key: BubbleConstants.udpForwardingDisabledKey) {
            defaults.set(legacyDisabled, forKey: BubbleConstants.udpSelectiveSafeModeEnabledKey)
            if legacyDisabled {
                defaults.set(false, forKey: BubbleConstants.udpForwardingDisabledKey)
            }
        } else {
            defaults.set(true, forKey: BubbleConstants.udpSelectiveSafeModeEnabledKey)
        }

        defaults.set(true, forKey: BubbleConstants.udpSelectiveSafeModeMigratedKey)
    }

    private static func persistentBool(_ defaults: UserDefaults, key: String) -> Bool? {
        defaults.persistentDomain(forName: BubbleConstants.appGroupID)?[key] as? Bool
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
                        case .magicSignIn:
                            MagicSignInScreen(
                                onCodeSent: { email in
                                    path.append(Route.codeVerification(email: email))
                                },
                                onDemoLogin: {
                                    path = NavigationPath()
                                }
                            )
                        case .codeVerification(let email):
                            CodeVerificationScreen(email: email, onVerified: {
                                path = NavigationPath()
                            })
                        case .settings:
                            SettingsScreen(
                                onHome: {
                                    path = NavigationPath()
                                },
                                onWindows: {
                                    path = NavigationPath()
                                    path.append(Route.timeWindows)
                                }
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
                .environmentObject(vpnManager)
                .statusBarHidden(!onboardingStore.isCompleted)
                .preferredColorScheme(.dark)
                .task {
                    SVGCache.shared.preload(svgNames: ["instagram", "kalshi", "fanduel"])
                    SVGCache.shared.preload(svgNames: ["home_mountains"], size: CGSize(width: 500, height: 280))
                }
                .task {
                    await authStore.listenForAuthChanges()
                }
                .onAppear {
                    vpnManager.setup()
                    configureProtectionIfNeeded()
                    presentGuidedOnboardingIfNeeded()
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
                        return
                    }
                    configureProtectionIfNeeded()
                    store.syncVPNState(source: "onboarding.completed")
                    markStreakIfEligible(source: "onboarding.completed")
                    presentGuidedOnboardingIfNeeded()
                }
                .onChange(of: authStore.isLoggedIn) { _, _ in
                    presentGuidedOnboardingIfNeeded()
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

                PiPInstructionVideoHost(controller: pipInstructionController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

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
            mainTabsScreen
        } else {
            OnboardingFlowScreen()
        }
    }

    private var mainTabsScreen: some View {
        MainTabsScreen(
            onSelectApp: { app in
                path.append(Route.blockingOptions(appId: app.id))
            },
            onSignIn: {
                path.append(Route.magicSignIn)
            },
            onTrafficDashboard: {
                path.append(Route.trafficDashboard)
            },
            onShowGuidedOnboarding: {
                guidedOnboardingPresentationMode = .manualReplay
            },
            guidedPracticeCardStep: guidedPracticeCardStep
        )
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
                onContinue: completeGuidedPracticeReturn,
                onTroubleshoot: {
                    guidedPracticePhase = .troubleshooting
                }
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
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark, .waitingForReturn, .completed:
            EmptyView()
        }
    }

    private var guidedPracticeCardStep: GuidedPracticeCardStep? {
        switch guidedPracticePhase {
        case .readyCoachMark:
            return .ready
        case .dragTikTokCoachMark:
            return .dragTikTok
        case .hidden, .introSlides, .openAppPrompt, .waitingForReturn, .success, .troubleshooting, .completed:
            return nil
        }
    }

    private func presentGuidedOnboardingIfNeeded() {
        guard onboardingStore.isCompleted else {
            return
        }

        if onboardingStore.hasGuidedPracticeReturnPending {
            path = NavigationPath()
            guidedOnboardingPresentationMode = nil
            guidedPracticePhase = .success
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

    private func beginGuidedPractice() {
        path = NavigationPath()
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
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

    private func completeGuidedPracticeReturn() {
        onboardingStore.markGuidedPracticeCompleted()
        onboardingStore.setGuidedPracticeReturnPending(false)
        guidedPracticePhase = .completed
        guidedPracticeActiveApps = []
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
        path = NavigationPath()
    }

    private func retryGuidedPracticeOpenApp() {
        onboardingStore.setGuidedPracticeReturnPending(false)
        guidedPracticePIPError = nil
        isStartingGuidedPracticePIP = false
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
