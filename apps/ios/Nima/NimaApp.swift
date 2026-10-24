import FamilyControls
import ManagedSettings
import SwiftUI
import NetworkExtension
import StoreKit
import UIKit

@main
struct NimaApp: App {
    @UIApplicationDelegateAdaptor(NimaApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var vpnManager = VPNManager()
    @State private var path = NavigationPath()
    @State private var store = AppStore()
    @State private var streakStore = StreakStore()
    @State private var timeWindowStore = TimeWindowStore()
    @State private var gridPositionStore = GridPositionStore()
    @State private var appSettingsStore = AppSettingsStore()
    @State private var instagramProtectionStore = InstagramProtectionStore()
    @State private var onboardingStore = OnboardingStore()
    @State private var subscriptionStore = SubscriptionStore()
    @State private var didConfigureProtection = false
    @State private var guidedOnboardingPresentationMode: GuidedOnboardingPresentationMode?
    @State private var guidedPracticePhase: GuidedPracticePhase = .hidden
    @State private var guidedPracticeActiveApps: Set<GuidedPracticeLaunchApp> = []
    @State private var guidedPracticeSelectedAppIDs: Set<String> = []
    @State private var guidedPracticeFamilySelection = FamilyActivitySelection()
    @State private var guidedPracticeApplicationTokens: [ApplicationToken] = []
    @State private var guidedPracticeAppAssignments: [ApplicationToken: String] = [:]
    @State private var isShowingGuidedPracticeFamilyPicker = false
    @State private var guidedPracticeFamilyPickerError: String?
    @State private var didStartLaunchServices = false
    @State private var hasHandledGuidedPracticeReviewRequest = false
    @State private var didTrackAppUnlock = false
    private let guidedPracticeReviewPromptStore = GuidedPracticeReviewPromptStore()

    init() {
        AnalyticsService.shared.configure()
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
                        case .instagramClient(let context):
                            InstagramClientScreen(
                                launchContext: context,
                                onGuidedPracticeCompleted: completeInstagramGuidedPractice,
                                onGuidedPracticeCancelled: cancelInstagramGuidedPractice
                            )
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
                .environment(appSettingsStore)
                .environment(instagramProtectionStore)
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
                    trackAppUnlockIfNeeded(destination: rootDestination)
                    handlePendingInstagramShieldDestination()
                }
                .onChange(of: rootDestination) { _, destination in
                    trackAppUnlockIfNeeded(destination: destination)
                }
                .onChange(of: onboardingStore.isCompleted) { _, isCompleted in
                    guard isCompleted else {
                        path = NavigationPath()
                        didConfigureProtection = false
                        guidedOnboardingPresentationMode = nil
                        guidedPracticePhase = .hidden
                        guidedPracticeActiveApps = []
                        guidedPracticeSelectedAppIDs = []
                        guidedPracticeFamilySelection = FamilyActivitySelection()
                        guidedPracticeApplicationTokens = []
                        guidedPracticeAppAssignments = [:]
                        isShowingGuidedPracticeFamilyPicker = false
                        guidedPracticeFamilyPickerError = nil
                        hasHandledGuidedPracticeReviewRequest = false
                        return
                    }
                    configureProtectionIfNeeded()
                    store.syncVPNState(source: "onboarding.completed")
                    markStreakIfEligible(source: "onboarding.completed")
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

                if shouldShowTimeWindowActivationPrompt,
                   let prompt = timeWindowStore.activationPrompt {
                    TimeWindowActivationModal(
                        prompt: prompt,
                        onActivate: {
                            timeWindowStore.activatePromptedWindows()
                        },
                        onDecline: {
                            timeWindowStore.declinePromptedWindows()
                        }
                    )
                    .id(prompt.id)
                    .transition(.opacity)
                    .zIndex(9)
                }

                guidedPracticeOverlay
            }
            .animation(.easeInOut(duration: 0.18), value: guidedOnboardingPresentationMode)
            .animation(.easeInOut(duration: 0.18), value: guidedPracticePhase)
            .animation(.easeInOut(duration: 0.18), value: timeWindowStore.activationPrompt?.id)
            .familyActivityPicker(
                isPresented: $isShowingGuidedPracticeFamilyPicker,
                selection: $guidedPracticeFamilySelection
            )
            .onChange(of: isShowingGuidedPracticeFamilyPicker) { wasShowing, isShowing in
                guard wasShowing, !isShowing else { return }
                finishGuidedPracticeFamilyPicker()
            }
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

        subscriptionStore.configureAnonymousUser()
    }

    private func configureProtectionIfNeeded() {
        guard onboardingStore.isCompleted, !didConfigureProtection else { return }
        didConfigureProtection = true

        store.configureVPNAutostart(
            reconcileProtection: { intent in
                await vpnManager.reconcileProtection(intent)
            },
            vpnStatus: { vpnManager.vpnStatus },
            markStreakIfEligible: { source in
                markStreakIfEligible(source: source)
            }
        )
        timeWindowStore.configure(
            applyScheduledApps: { appIDs, source in
                store.setScheduledBlockedAppIDs(appIDs, source: source)
            },
            applyInstagramMode: { mode, source in
                instagramProtectionStore.setScheduledMode(mode, source: source)
            },
            startProtection: { source in
                vpnManager.requestProtectionReconciliation(source: source)
            },
            manuallyBlockedAppIDs: {
                store.manuallyBlockedAppIDs
            },
            requestHomeFocus: {
                path = NavigationPath()
            }
        )
        markStreakIfEligible(source: "app.launch")
    }

    @ViewBuilder
    private var rootScreen: some View {
        switch rootDestination {
        case .onboarding:
            OnboardingFlowScreen()
        case .guidedExperience, .mainApp:
            mainTabsScreen
        case .subscriptionLoading:
            SubscriptionStatusLoadingScreen()
        case .paywall:
            PaywallScreen(
                onUnlocked: completePaywall
            )
        }
    }

    private var mainTabsScreen: some View {
        MainTabsScreen(
            onSelectApp: { app in
                if app.id == "instagram" {
                    path.append(Route.instagramClient())
                } else {
                    path.append(Route.blockingOptions(appId: app.id))
                }
            },
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

    private var rootDestination: AppRootDestination {
        return AppAccessPolicy.destination(
            onboardingCompleted: onboardingStore.isCompleted,
            guidedExperienceCompleted: hasCompletedRequiredGuidedExperience,
            hasPremium: subscriptionStore.hasAccessForRouting,
            verificationState: subscriptionStore.verificationState
        )
    }

    private var hasCompletedRequiredGuidedExperience: Bool {
        onboardingStore.hasCompletedGuidedPractice
            && !shouldHoldPaywallForGuidedPracticeReturn
    }

    private var shouldShowPaywall: Bool {
        rootDestination == .paywall
    }

    private var shouldWaitForSubscriptionStatus: Bool {
        rootDestination == .subscriptionLoading
    }

    private var shouldHoldPaywallForGuidedPracticeReturn: Bool {
        if onboardingStore.hasGuidedPracticeReturnPending {
            return true
        }

        switch guidedPracticePhase {
        case .success, .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting:
            return true
        case .hidden, .introSlides, .readyCoachMark, .appSelection, .familyPickerVideo, .appConnections,
             .dragTikTokCoachMark, .openAppPrompt, .waitingForReturn, .completed:
            return false
        }
    }

    @ViewBuilder
    private var guidedPracticeOverlay: some View {
        switch guidedPracticePhase {
        case .appSelection:
            GuidedPracticeAppSelectionModal(
                selectedAppIDs: $guidedPracticeSelectedAppIDs,
                onContinue: {
                    guidedPracticeFamilyPickerError = nil
                    guidedPracticeFamilySelection = FamilyActivitySelection()
                    guidedPracticeApplicationTokens = []
                    guidedPracticeAppAssignments = [:]
                    guidedPracticePhase = .familyPickerVideo
                }
            )
            .transition(.opacity)
            .zIndex(11)
        case .familyPickerVideo:
            GuidedPracticeFamilyPickerVideoModal(
                errorMessage: guidedPracticeFamilyPickerError,
                onContinue: presentGuidedPracticeFamilyPicker
            )
            .transition(.opacity)
            .zIndex(11)
        case .appConnections:
            GuidedPracticeAppConnectionsModal(
                applicationTokens: guidedPracticeApplicationTokens,
                selectedApps: guidedPracticeChosenApps,
                assignments: $guidedPracticeAppAssignments,
                onChooseAppsAgain: chooseGuidedPracticeAppsAgain,
                onContinue: continueGuidedPracticeConnections
            )
            .transition(.opacity)
            .zIndex(11)
        case .openAppPrompt:
            GuidedPracticeOpenAppPromptModal(
                onContinue: openGuidedPracticeInstagram
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
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark, .waitingForReturn,
             .windowsHomeCoachMark, .windowsEditor, .completed:
            EmptyView()
        }
    }

    private var guidedPracticeCardStep: GuidedPracticeCardStep? {
        switch guidedPracticePhase {
        case .readyCoachMark:
            return .ready
        case .dragTikTokCoachMark:
            return .dragTikTok
        case .hidden, .introSlides, .appSelection, .familyPickerVideo, .appConnections, .openAppPrompt,
             .waitingForReturn, .success, .windowsHomeCoachMark, .windowsEditor,
             .windowsReady, .reviewPrompt, .troubleshooting, .completed:
            return nil
        }
    }

    private var guidedWindowsEditorStep: GuidedWindowsEditorStep? {
        guard case .windowsEditor(let step) = guidedPracticePhase else { return nil }
        return step
    }

    private var shouldShowTimeWindowActivationPrompt: Bool {
        guard rootDestination == .mainApp,
              guidedOnboardingPresentationMode == nil else {
            return false
        }
        switch guidedPracticePhase {
        case .hidden, .completed:
            return true
        case .introSlides, .readyCoachMark, .appSelection, .familyPickerVideo, .appConnections,
             .dragTikTokCoachMark, .openAppPrompt, .waitingForReturn, .success,
             .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting:
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
        AnalyticsService.shared.capture(AnalyticsEvent.paywallUnlocked)
        presentGuidedOnboardingIfNeeded()
    }

    private func trackAppUnlockIfNeeded(destination: AppRootDestination) {
        guard destination == .mainApp, !didTrackAppUnlock else { return }
        didTrackAppUnlock = true
        AnalyticsService.shared.capture(
            AnalyticsEvent.appUnlocked,
            properties: ["mode": "anonymous"]
        )
    }

    private func beginGuidedPractice() {
        AnalyticsService.shared.capture(AnalyticsEvent.guidedPracticeStarted)
        path = NavigationPath()
        guidedPracticeFamilyPickerError = nil
        hasHandledGuidedPracticeReviewRequest = false

        if NimaLaunchConfiguration.skipsExternalGuidedPractice() {
            skipExternalGuidedPractice()
            return
        }

        guidedPracticeSelectedAppIDs = []
        guidedPracticeFamilySelection = FamilyActivitySelection()
        guidedPracticeApplicationTokens = []
        guidedPracticeAppAssignments = [:]
        guidedPracticeActiveApps = []
        guidedPracticePhase = .readyCoachMark
    }

    private func skipExternalGuidedPractice() {
        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedPracticeCompleted,
            properties: ["completion": "skipped"]
        )
        onboardingStore.markGuidedPracticeCompleted()
        onboardingStore.setGuidedPracticeReturnPending(false)
        guidedPracticeActiveApps = []

        showGuidedPracticeReviewPrompt()
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
        guidedPracticePhase = .appSelection
    }

    private func presentGuidedPracticeFamilyPicker() {
        guard guidedPracticePhase == .familyPickerVideo else { return }
        guidedPracticeFamilyPickerError = nil

        Task { @MainActor in
            do {
                if instagramProtectionStore.authorizationStatus != .approved {
                    try await instagramProtectionStore.requestAuthorization()
                }
                isShowingGuidedPracticeFamilyPicker = true
            } catch {
                guidedPracticeFamilyPickerError = "Nima needs Screen Time access before you can select apps."
            }
        }
    }

    private func finishGuidedPracticeFamilyPicker() {
        guard guidedPracticePhase == .familyPickerVideo else { return }
        guard !guidedPracticeFamilySelection.applicationTokens.isEmpty else {
            guidedPracticeFamilyPickerError = "Select at least one app to continue."
            return
        }

        guard guidedPracticeFamilySelection.categoryTokens.isEmpty,
              guidedPracticeFamilySelection.webDomainTokens.isEmpty else {
            guidedPracticeFamilyPickerError = "Select individual apps only, not categories or websites."
            return
        }

        guidedPracticeApplicationTokens = Array(guidedPracticeFamilySelection.applicationTokens)
        guidedPracticeAppAssignments = existingAssignments(
            for: guidedPracticeApplicationTokens,
            apps: guidedPracticeChosenApps
        )
        guidedPracticeFamilyPickerError = nil
        guidedPracticePhase = .appConnections
    }

    private var guidedPracticeChosenApps: [GuidedPracticeLaunchApp] {
        GuidedPracticeLaunchApp.allCases.filter {
            guidedPracticeSelectedAppIDs.contains($0.rawValue)
        }
    }

    private func existingAssignments(
        for tokens: [ApplicationToken],
        apps: [GuidedPracticeLaunchApp]
    ) -> [ApplicationToken: String] {
        let savedConnections = ScreenTimeAppConnections.load()
        var assignments: [ApplicationToken: String] = [:]

        for app in apps {
            guard let savedToken = savedConnections.selection(for: app.rawValue)?.applicationTokens.first,
                  tokens.contains(savedToken) else { continue }
            assignments[savedToken] = app.rawValue
        }

        return assignments
    }

    private func chooseGuidedPracticeAppsAgain() {
        guidedPracticeAppAssignments = [:]
        guidedPracticePhase = .familyPickerVideo
        isShowingGuidedPracticeFamilyPicker = true
    }

    private func continueGuidedPracticeConnections() {
        let chosenAppIDs = Set(guidedPracticeChosenApps.map(\.rawValue))
        guard guidedPracticeApplicationTokens.count == guidedPracticeChosenApps.count,
              guidedPracticeApplicationTokens.allSatisfy({ guidedPracticeAppAssignments[$0] != nil }),
              Set(guidedPracticeAppAssignments.values) == chosenAppIDs else {
            return
        }

        var savedConnections = ScreenTimeAppConnections.load()
        for (token, appID) in guidedPracticeAppAssignments {
            savedConnections.connect(appID, to: token)
        }
        savedConnections.save()

        if let instagramSelection = savedConnections.selection(for: GuidedPracticeLaunchApp.instagram.rawValue),
           chosenAppIDs.contains(GuidedPracticeLaunchApp.instagram.rawValue) {
            instagramProtectionStore.familySelection = instagramSelection
            instagramProtectionStore.setProtectionEnabled(
                true,
                source: "guided_practice.app_connections"
            )
        }

        guidedPracticeActiveApps = Set(guidedPracticeChosenApps)
        guidedPracticePhase = .openAppPrompt
    }

    private func openGuidedPracticeInstagram() {
        AnalyticsService.shared.capture("instagram_practice_open_tapped")
        guidedPracticePhase = .waitingForReturn
        path.append(Route.instagramClient(context: .guidedPractice))
    }

    private func completeInstagramGuidedPractice() {
        AnalyticsService.shared.capture("instagram_practice_completed")
        onboardingStore.setGuidedPracticeReturnPending(true)
        path = NavigationPath()
        guidedPracticePhase = .success
    }

    private func cancelInstagramGuidedPractice() {
        guard guidedPracticePhase == .waitingForReturn else { return }
        path = NavigationPath()
        guidedPracticePhase = .openAppPrompt
    }

    private func continueGuidedPracticeSuccess() {
        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedPracticeCompleted,
            properties: ["completion": "instagram_clean_mode_verified"]
        )
        onboardingStore.markGuidedPracticeCompleted()
        onboardingStore.setGuidedPracticeReturnPending(false)
        showGuidedPracticeReviewPrompt()
    }

    private func beginGuidedWindowsOnboarding() {
        AnalyticsService.shared.capture(AnalyticsEvent.guidedWindowsStarted)
        path = NavigationPath()
        guidedOnboardingPresentationMode = nil
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticePhase = .windowsHomeCoachMark
    }

    private func beginGuidedWindowsEditor() {
        guard guidedPracticePhase == .windowsHomeCoachMark else { return }
        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedWindowsStepViewed,
            properties: ["step": "name"]
        )
        guidedPracticePhase = .windowsEditor(.name)
    }

    private func advanceGuidedWindowsEditorStep() {
        guard case .windowsEditor(let step) = guidedPracticePhase else { return }
        let nextStep: GuidedWindowsEditorStep?
        switch step {
        case .name:
            nextStep = .time
        case .time:
            nextStep = .apps
        case .apps:
            nextStep = .repeatDays
        case .repeatDays:
            nextStep = .icon
        case .icon:
            nextStep = .saveOrCancel
        case .saveOrCancel:
            nextStep = nil
        }
        if let nextStep {
            AnalyticsService.shared.capture(
                AnalyticsEvent.guidedWindowsStepViewed,
                properties: ["step": nextStep.analyticsName]
            )
            guidedPracticePhase = .windowsEditor(nextStep)
        }
    }

    private func showGuidedWindowsReadyModal() {
        guard case .windowsEditor = guidedPracticePhase else { return }
        guidedPracticePhase = .windowsReady
    }

    private func continueGuidedWindowsReady() {
        AnalyticsService.shared.capture(AnalyticsEvent.guidedWindowsCompleted)
        onboardingStore.markGuidedWindowsOnboardingCompleted()
        showGuidedPracticeReviewPrompt()
    }

    private func showGuidedPracticeReviewPrompt() {
        deactivateBlockersBeforeGuidedPracticeReview()
        onboardingStore.markGuidedPracticeCompleted()
        onboardingStore.setGuidedPracticeReturnPending(false)
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticePhase = .reviewPrompt
    }

    private func deactivateBlockersBeforeGuidedPracticeReview() {
        for app in GuidedPracticeLaunchApp.allCases {
            timeWindowStore.endActiveWindow(for: app.rawValue)
        }
        store.disableAllManualBlockingOptions(source: "guided_practice.before_review")
    }

    private func continueGuidedPracticeReviewPrompt() {
        if !hasHandledGuidedPracticeReviewRequest {
            requestGuidedPracticeReviewIfNeeded()
            hasHandledGuidedPracticeReviewRequest = true
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
        guard let defaults = UserDefaults(suiteName: NimaConstants.appGroupID) else {
            return nil
        }
        if let existingID = defaults.string(forKey: NimaConstants.onDemandInstallationIDKey),
           !existingID.isEmpty {
            return "installation_id:\(existingID.lowercased())"
        }
        let installationID = UUID().uuidString.lowercased()
        defaults.set(installationID, forKey: NimaConstants.onDemandInstallationIDKey)
        return "installation_id:\(installationID)"
    }

    private var activeForegroundWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func finishGuidedPracticeReturn() {
        guidedPracticePhase = .completed
        guidedPracticeActiveApps = []
        hasHandledGuidedPracticeReviewRequest = false
        path = NavigationPath()
    }

    private func retryGuidedPracticeOpenApp() {
        onboardingStore.setGuidedPracticeReturnPending(false)
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
            handlePendingInstagramShieldDestination()
            instagramProtectionStore.refreshAuthorizationStatus()
            MetaAdsService.shared.refreshConsent()
            subscriptionStore.refreshAfterForeground()
            subscriptionStore.reconcilePendingPurchaseAfterForeground()
            if onboardingStore.isCompleted {
                timeWindowStore.evaluateSchedules(source: "app.scene.active", forceApply: true)
                timeWindowStore.refreshActivationPrompt(source: "app.scene.active")
                store.syncVPNState(source: "app.scene.active")
                vpnManager.repairScheduledProtectionIfNeeded(source: "app.scene.active")
            }
            guard onboardingStore.hasGuidedPracticeReturnPending else { return }
            path = NavigationPath()
            guidedOnboardingPresentationMode = nil
            guidedPracticePhase = .success
        case .inactive, .background:
            if newPhase == .background { MetaAdsService.shared.leaveForeground() }
        @unknown default:
            break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "nima",
           url.host?.lowercased() == "instagram" {
            let opensLinkSheet = url.path.lowercased() == "/open-link"
            path = NavigationPath()
            path.append(
                Route.instagramClient(context: opensLinkSheet ? .openLink : .standard)
            )
        }
    }

    private func handlePendingInstagramShieldDestination() {
        guard let defaults = UserDefaults(suiteName: NimaConstants.appGroupID),
              let destination = defaults.string(
                forKey: NimaConstants.instagramShieldPendingDestinationKey
              ) else { return }

        defaults.removeObject(forKey: NimaConstants.instagramShieldPendingDestinationKey)
        defaults.synchronize()

        let opensLinkSheet = destination == "open_link"
        path = NavigationPath()
        path.append(
            Route.instagramClient(context: opensLinkSheet ? .openLink : .standard)
        )
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
    @Environment(SubscriptionStore.self) private var subscriptionStore

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

                switch subscriptionStore.verificationState {
                case .idle, .loading:
                    ProgressView()
                        .tint(Color(red: 0.73, green: 0.93, blue: 0.09))

                case .failed:
                    VStack(spacing: 16) {
                        Text("We couldn’t check your subscription")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Check your connection and try again.")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)

                        Button("Try Again") {
                            subscriptionStore.retrySubscriptionCheck()
                        }
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .frame(height: 48)
                        .background(Color(red: 0.73, green: 0.93, blue: 0.09))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 32)

                case .verified:
                    EmptyView()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
