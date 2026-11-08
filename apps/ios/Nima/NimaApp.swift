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

    @StateObject private var vpnManager = VPNManager(reconciliationSuspended: true)
    @State private var path = NavigationPath()
    @State private var store = AppStore()
    @State private var streakStore = StreakStore()
    @State private var timeWindowStore = TimeWindowStore(evaluationSuspended: true)
    @State private var appControlRulesStore = AppControlRulesStore()
    @State private var hardModeCoordinator = HardModeCoordinator()
    @State private var gridPositionStore = GridPositionStore()
    @State private var appSettingsStore = AppSettingsStore()
    @State private var instagramProtectionStore = InstagramProtectionStore()
    @State private var tiktokProtectionStore = TikTokProtectionStore()
    @State private var xProtectionStore = XProtectionStore()
    @State private var onboardingStore = OnboardingStore()
    @State private var subscriptionStore: SubscriptionStore
    @State private var experienceRouter: ExperienceRouter
    @State private var didStartVPNManager = false
    @State private var appliedExperience: ExperienceRoute?
    @State private var didConfigureProtection = false
    @State private var didConfigureHardMode = false
    @State private var guidedOnboardingPresentationMode: GuidedOnboardingPresentationMode?
    @State private var guidedPracticePhase: GuidedPracticePhase = .hidden
    @State private var guidedPracticeActiveApps: Set<GuidedPracticeLaunchApp> = []
    @State private var guidedPracticeSelectedAppIDs: Set<String> = []
    @State private var guidedPracticeFamilySelection = FamilyActivitySelection()
    @State private var guidedPracticeApplicationTokens: [ApplicationToken] = []
    @State private var guidedPracticeAppAssignments: [ApplicationToken: String] = [:]
    @State private var isShowingGuidedPracticeFamilyPicker = false
    @State private var guidedPracticeFamilyPickerError: String?
    @State private var guidedPracticeInstagramOpenGate = GuidedPracticeInstagramOpenGate()
    @State private var didStartLaunchServices = false
    @State private var hasHandledGuidedPracticeReviewRequest = false
    @State private var didTrackGuidedPracticeResume = false
    @State private var didTrackAppUnlock = false
    @State private var appRuleAlertMessage: String?
    private let guidedPracticeReviewPromptStore = GuidedPracticeReviewPromptStore()

    init() {
        let onboardingStore = OnboardingStore()
        AnalyticsService.shared.configure()
        AnalyticsService.shared.enterForeground(existingInstallation: onboardingStore.isCompleted)
        let subscriptionStore = SubscriptionStore()
        subscriptionStore.configureAnonymousUser()
        let experienceRouter = ExperienceRouter()
        experienceRouter.resolveCachedIdentity(subscriptionStore.cohortIdentity)
        let restoredStep = onboardingStore.hasGuidedPracticeReturnPending
            ? GuidedPracticeStep.success
            : onboardingStore.guidedPracticeStep
        let restoredPhase = restoredStep?.phase ?? .hidden
        let restoredAppIDs = onboardingStore.guidedPracticeSelectedAppIDs
        let restoredFamilySelection = onboardingStore.guidedPracticeFamilySelection
            ?? FamilyActivitySelection()
        let savedConnections = ScreenTimeAppConnections.load()
        let restoredTokens: [ApplicationToken]
        if !restoredFamilySelection.applicationTokens.isEmpty {
            restoredTokens = Array(restoredFamilySelection.applicationTokens)
        } else {
            restoredTokens = GuidedPracticeLaunchApp.allCases.compactMap { app in
                guard restoredAppIDs.contains(app.rawValue) else { return nil }
                return savedConnections.selection(for: app.rawValue)?.applicationTokens.first
            }
        }
        var restoredAssignments: [ApplicationToken: String] = [:]
        for connection in onboardingStore.guidedPracticeAppConnections {
            restoredAssignments[connection.token] = connection.appID
        }
        for app in GuidedPracticeLaunchApp.allCases where restoredAppIDs.contains(app.rawValue) {
            guard restoredAssignments.values.contains(app.rawValue) == false else { continue }
            guard let token = savedConnections.selection(for: app.rawValue)?.applicationTokens.first else {
                continue
            }
            restoredAssignments[token] = app.rawValue
        }

        _onboardingStore = State(initialValue: onboardingStore)
        _subscriptionStore = State(initialValue: subscriptionStore)
        _experienceRouter = State(initialValue: experienceRouter)
        _guidedPracticePhase = State(initialValue: restoredPhase)
        _guidedOnboardingPresentationMode = State(
            initialValue: restoredStep == .introSlides ? .firstRunPractice : nil
        )
        _guidedPracticeSelectedAppIDs = State(initialValue: restoredAppIDs)
        _guidedPracticeFamilySelection = State(initialValue: restoredFamilySelection)
        _guidedPracticeActiveApps = State(
            initialValue: Set(
                GuidedPracticeLaunchApp.allCases.filter {
                    restoredAppIDs.contains($0.rawValue)
                }
            )
        )
        _guidedPracticeApplicationTokens = State(initialValue: restoredTokens)
        _guidedPracticeAppAssignments = State(initialValue: restoredAssignments)

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
                          if experienceRouter.route == .legacy {
                            LegacyTimeWindowsScreen(
                                onHome: { path = NavigationPath() },
                                onSettings: { path.append(Route.settings) },
                                authorizeFeatureAccess: featureAccessAuthorizer
                            )
                          } else {
                            TimeWindowsScreen(
                                onHome: {
                                    path = NavigationPath()
                                },
                                onSettings: {
                                    path.append(Route.settings)
                                },
                                authorizeFeatureAccess: featureAccessAuthorizer
                            )
                          }
                        case .blockingOptions(let appId):
                            BlockingOptionsScreen(
                                appId: appId,
                                authorizeFeatureAccess: featureAccessAuthorizer
                            )
                        case .instagramClient(let context):
                            InstagramClientScreen(
                                launchContext: context,
                                onGuidedPracticeCompleted: completeInstagramGuidedPractice,
                                onGuidedPracticeCancelled: cancelInstagramGuidedPractice
                            )
                        case .tiktokClient(let context):
                            TikTokClientScreen(launchContext: context)
                        case .xClient(let context):
                            XClientScreen(launchContext: context)
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
                .environment(appControlRulesStore)
                .environment(hardModeCoordinator)
                .environment(gridPositionStore)
                .environment(appSettingsStore)
                .environment(instagramProtectionStore)
                .environment(tiktokProtectionStore)
                .environment(xProtectionStore)
                .environment(onboardingStore)
                .environment(subscriptionStore)
                .environment(experienceRouter)
                .environmentObject(vpnManager)
                .statusBarHidden(!onboardingStore.isCompleted)
                .accessibilityHidden(
                    hardModeCoordinator.isShowingActivationWarning
                        || hardModeCoordinator.activeAttempt != nil
                )
                .preferredColorScheme(.dark)
                .task {
                    await startLaunchServicesIfNeeded()
                }
                .task(id: subscriptionStore.cohortCheckRevision) {
                    await recheckExperience()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    // Keep the first SwiftUI frame lightweight so iOS can leave the launch screen.
                    trackGuidedPracticeResumeIfNeeded()
                    trackAppUnlockIfNeeded(destination: rootDestination)
                    handlePendingInstagramShieldDestination()
                }
                .onChange(of: rootDestination) { _, destination in
                    trackAppUnlockIfNeeded(destination: destination)
                    if destination == .paywall || destination == .subscriptionLoading {
                        path = NavigationPath()
                    }
                }
                .onChange(of: onboardingStore.isCompleted) { _, isCompleted in
                    guard isCompleted else {
                        path = NavigationPath()
                        didConfigureProtection = false
                        guidedOnboardingPresentationMode = nil
                        guidedPracticePhase = .hidden
                        onboardingStore.resetGuidedPracticeProgress()
                        guidedPracticeActiveApps = []
                        guidedPracticeSelectedAppIDs = []
                        guidedPracticeFamilySelection = FamilyActivitySelection()
                        guidedPracticeApplicationTokens = []
                        guidedPracticeAppAssignments = [:]
                        guidedPracticeInstagramOpenGate.finishRoute()
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
                    setGuidedPracticePhase(.openAppPrompt, source: "active_app_detected")
                }
                .onChange(of: guidedPracticeSelectedAppIDs) { _, appIDs in
                    onboardingStore.setGuidedPracticeSelectedAppIDs(appIDs)
                }
                .onChange(of: guidedPracticeAppAssignments) { _, assignments in
                    onboardingStore.setGuidedPracticeAppConnections(
                        assignments
                            .map { GuidedPracticeAppConnection(appID: $0.value, token: $0.key) }
                            .sorted { $0.appID < $1.appID }
                    )
                }
                .onChange(of: vpnManager.vpnStatus) { _, _ in
                    if experienceRouter.route != .checking && onboardingStore.isCompleted {
                        store.syncVPNState(source: "vpn.status")
                        markStreakIfEligible(source: "vpn.status")
                    }
                }
                .onChange(of: [
                    instagramProtectionStore.protectionEnabled,
                    instagramProtectionStore.isScheduled,
                    tiktokProtectionStore.protectionEnabled,
                    tiktokProtectionStore.isScheduled,
                    xProtectionStore.protectionEnabled,
                    xProtectionStore.isScheduled
                ]) { _, _ in
                    markStreakIfEligible(source: "feed_protection.changed")
                }
                .onChange(of: timeWindowStore.pauseAll) { _, _ in
                    markStreakIfEligible(source: "time_windows.pause_changed")
                }
                .task(id: guidedPracticePhase) {
                    await handleGuidedPracticePhaseTask()
                }

                if experienceRouter.route == .new, let guidedOnboardingPresentationMode {
                    GuidedOnboardingModal(
                        completionTitle: guidedOnboardingPresentationMode.completionTitle,
                        initialPage: guidedOnboardingPresentationMode == .firstRunPractice
                            ? onboardingStore.guidedPracticeIntroSlideIndex
                            : 0,
                        onPageChanged: { page in
                            guard guidedOnboardingPresentationMode == .firstRunPractice else { return }
                            onboardingStore.setGuidedPracticeIntroSlideIndex(page)
                            AnalyticsService.shared.capture(
                                AnalyticsEvent.guidedPracticeStepViewed,
                                properties: [
                                    "step": GuidedPracticeStep.introSlides.rawValue,
                                    "slide_index": page,
                                    "source": "intro_slide_changed",
                                    "resumed": false,
                                ]
                            )
                        }
                    ) {
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

                if experienceRouter.route == .new {
                    hardModeOverlay
                    guidedPracticeOverlay
                }

                if hardModeCoordinator.isShowingActivationWarning {
                    HardModeActivationWarningCard(
                        onContinue: { hardModeCoordinator.confirmActivation() },
                        onNotYet: { hardModeCoordinator.dismissActivationWarning() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(40)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: guidedOnboardingPresentationMode)
            .animation(.easeInOut(duration: 0.18), value: guidedPracticePhase)
            .animation(.easeInOut(duration: 0.18), value: hardModeCoordinator.isShowingActivationWarning)
            .familyActivityPicker(
                isPresented: $isShowingGuidedPracticeFamilyPicker,
                selection: $guidedPracticeFamilySelection
            )
            .alert("App blocked", isPresented: Binding(
                get: { appRuleAlertMessage != nil },
                set: { if !$0 { appRuleAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { appRuleAlertMessage = nil }
            } message: {
                Text(appRuleAlertMessage ?? "")
            }
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

        configureHardModeIfNeeded()
    }

    @MainActor
    private func recheckExperience() async {
        let identity = subscriptionStore.cohortIdentity
        experienceRouter.resolveCachedIdentity(identity)
        if experienceRouter.route == .checking {
            timeWindowStore.setEvaluationSuspended(true)
            vpnManager.reconciliationSuspended = true
            return
        }
        applyExperience(experienceRouter.route)
        await experienceRouter.checkHistoricalPurchases(identity: identity)
        if experienceRouter.route == .legacy {
            applyExperience(.legacy)
        }
    }

    @MainActor
    private func applyExperience(_ route: ExperienceRoute) {
        guard route != .checking else { return }
        let legacy = route == .legacy
        guard subscriptionStore.cohortIdentity != nil else { return }
        if legacy && !subscriptionStore.hasAccessForRouting {
            guard subscriptionStore.verificationState == .verified else { return }
        }
        if appliedExperience != route {
            UserDefaults(suiteName: NimaConstants.appGroupID)?.set(legacy, forKey: ExperienceModeState.legacyKey)
            store.setLegacyProtectionEnabled(legacy)
            timeWindowStore.setLegacyProtectionEnabled(legacy)
            vpnManager.legacyProtectionEnabled = legacy
            InstagramScheduleMonitor.sync(windows: legacy ? [] : timeWindowStore.windows)
            appliedExperience = route
        }
        PaywallBlockingState.setActive(rootDestination == .paywall)
        instagramProtectionStore.refreshPauseMode()
        tiktokProtectionStore.refreshPauseMode()
        xProtectionStore.refreshPauseMode()
        appControlRulesStore.reconcile()
        timeWindowStore.setEvaluationSuspended(false)
        vpnManager.reconciliationSuspended = false
        if !didStartVPNManager {
            didStartVPNManager = true
            vpnManager.setup()
        }
        configureProtectionIfNeeded()
        timeWindowStore.evaluateSchedules(source: "experience.resolved", forceApply: true)
        store.syncVPNState(source: "experience.resolved")
        if !legacy { presentGuidedOnboardingIfNeeded() }
    }

    private func configureHardModeIfNeeded() {
        guard !didConfigureHardMode else { return }
        didConfigureHardMode = true
        hardModeCoordinator.configure { commit in
            commitHardModeChange(commit)
        }
    }

    private func configureProtectionIfNeeded() {
        guard experienceRouter.route != .checking,
              (onboardingStore.isCompleted || experienceRouter.route == .legacy),
              !didConfigureProtection else { return }
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
            applyInstagramProtection: { enabled, source in
                instagramProtectionStore.setScheduled(enabled, source: source)
                markStreakIfEligible(source: source)
            },
            applyTikTokProtection: { enabled, source in
                tiktokProtectionStore.setScheduled(enabled, source: source)
                markStreakIfEligible(source: source)
            },
            applyXProtection: { enabled, source in
                xProtectionStore.setScheduled(enabled, source: source)
                markStreakIfEligible(source: source)
            },
            startProtection: { source in
                vpnManager.requestProtectionReconciliation(source: source)
            },
            requestHomeFocus: {
                path = NavigationPath()
            }
        )
        markStreakIfEligible(source: "app.launch")
    }

    @ViewBuilder
    private var hardModeOverlay: some View {
        if hardModeCoordinator.activeAttempt != nil {
            HardModeChallengeOverlay(
                coordinator: hardModeCoordinator,
                availableClientAppIDs: Set(["instagram", "tiktok", "x"].filter {
                    ClientShieldPolicy.decision(
                        for: $0,
                        defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
                    ).shouldShield
                }),
                onCommit: { commit in
                    let result = commitHardModeChange(commit)
                    return result
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(31)
        }
    }

    @ViewBuilder
    private var rootScreen: some View {
        if experienceRouter.route == .checking {
            ExperienceCheckingScreen {
                subscriptionStore.configureAnonymousUser()
                subscriptionStore.retrySubscriptionCheck()
                Task { await recheckExperience() }
            } onRestore: {
                subscriptionStore.restore { }
            }
        } else {
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
    }

    private var mainTabsScreen: some View {
        MainTabsScreen(
            onSelectApp: { app in
                guard !isGuidedSetupActive else { return }
                if app.id == "instagram" {
                    featureAccessAuthorizer {
                        guard canOpenControlledClient("instagram") else { return }
                        path.append(Route.instagramClient())
                    }
                } else if app.id == "tiktok" {
                    featureAccessAuthorizer {
                        guard canOpenControlledClient("tiktok") else { return }
                        path.append(Route.tiktokClient())
                    }
                } else if app.id == "x" {
                    featureAccessAuthorizer {
                        guard canOpenControlledClient("x") else { return }
                        path.append(Route.xClient())
                    }
                } else {
                    guard !isGuidedSetupActive else { return }
                    path.append(Route.blockingOptions(appId: app.id))
                }
            },
            onTrafficDashboard: {
                guard !isGuidedSetupActive else { return }
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
            onGuidedWindowsEditorFinished: showGuidedWindowsReadyModal,
            authorizeFeatureAccess: featureAccessAuthorizer,
            showsDock: !isGuidedSetupActive,
            legacyExperience: experienceRouter.route == .legacy
        )
    }

    private var isGuidedSetupActive: Bool {
        rootDestination == .guidedExperience
    }

    private var featureAccessAuthorizer: FeatureAccessAuthorizer {
        if rootDestination == .guidedExperience {
            return { action in
                guard canUseFeatureActionsDuringGuidedSetup else { return }
                MainActor.assumeIsolated {
                    action()
                }
            }
        }
        return { action in
            subscriptionStore.authorizeFeatureAction(action)
        }
    }

    private var canUseFeatureActionsDuringGuidedSetup: Bool {
        switch guidedPracticePhase {
        case .windowsHomeCoachMark, .windowsEditor:
            return true
        case .hidden, .introSlides, .readyCoachMark, .appSelection, .familyPickerVideo, .appConnections,
             .dragTikTokCoachMark, .openAppPrompt, .waitingForReturn, .success,
             .windowsReady, .reviewPrompt, .troubleshooting, .completed:
            return false
        }
    }

    private var rootDestination: AppRootDestination {
        if experienceRouter.route == .legacy {
            guard subscriptionStore.cohortIdentity != nil else { return .subscriptionLoading }
            switch subscriptionStore.verificationState {
            case .verified:
                return subscriptionStore.hasAccessForRouting ? .mainApp : .paywall
            case .idle, .loading, .failed:
                return subscriptionStore.hasAccessForRouting ? .mainApp : .subscriptionLoading
            }
        }
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
        case .hidden, .completed:
            return false
        case .introSlides, .readyCoachMark, .appSelection, .familyPickerVideo, .appConnections,
             .dragTikTokCoachMark, .openAppPrompt, .waitingForReturn, .success,
             .windowsHomeCoachMark, .windowsEditor, .windowsReady, .reviewPrompt, .troubleshooting:
            return true
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
                    onboardingStore.setGuidedPracticeFamilySelection(FamilyActivitySelection())
                    onboardingStore.setGuidedPracticeAppConnections([])
                    setGuidedPracticePhase(.familyPickerVideo, source: "apps_selected")
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
        case .openAppPrompt, .waitingForReturn:
            if guidedPracticePhase.showsOpenAppPromptOverlay {
                GuidedPracticeOpenAppPromptModal(
                    onContinue: openGuidedPracticeInstagram
                )
                .transition(.opacity)
                .zIndex(11)
            }
        case .success:
            GuidedPracticeSuccessModal(
                onContinue: continueGuidedPracticeSuccess,
                onTroubleshoot: {
                    setGuidedPracticePhase(.troubleshooting, source: "practice_failed")
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
                    setGuidedPracticePhase(.success, source: "troubleshooting_back")
                },
                onOpenVPNSettings: openVPNSettings,
                onTryAgain: retryGuidedPracticeOpenApp
            )
            .transition(.opacity)
            .zIndex(11)
        case .hidden, .introSlides, .readyCoachMark, .dragTikTokCoachMark,
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

    private func setGuidedPracticePhase(_ nextPhase: GuidedPracticePhase, source: String) {
        let previousPhase = guidedPracticePhase
        guard previousPhase != nextPhase else { return }

        var properties: [String: Any] = [
            "source": source,
            "resumed": false,
        ]
        if let previousStep = GuidedPracticeStep(phase: previousPhase) {
            properties["step"] = previousStep.rawValue
            properties["next_step"] = GuidedPracticeStep(phase: nextPhase)?.rawValue ?? "hidden"
            AnalyticsService.shared.capture(
                AnalyticsEvent.guidedPracticeStepCompleted,
                properties: properties
            )
        }

        if let nextStep = GuidedPracticeStep(phase: nextPhase) {
            onboardingStore.setGuidedPracticeStep(nextStep)
            AnalyticsService.shared.capture(
                AnalyticsEvent.guidedPracticeStepViewed,
                properties: [
                    "step": nextStep.rawValue,
                    "source": source,
                    "resumed": false,
                ]
            )
        }
        if nextPhase != .waitingForReturn {
            guidedPracticeInstagramOpenGate.finishRoute()
        }
        guidedPracticePhase = nextPhase
    }

    private func trackGuidedPracticeResumeIfNeeded() {
        guard !didTrackGuidedPracticeResume else { return }
        didTrackGuidedPracticeResume = true
        guard let step = GuidedPracticeStep(phase: guidedPracticePhase) else { return }

        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedPracticeResumed,
            properties: ["step": step.rawValue]
        )
        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedPracticeStepViewed,
            properties: [
                "step": step.rawValue,
                "source": "app_launch",
                "resumed": true,
            ]
        )
    }

    private func presentGuidedOnboardingIfNeeded() {
        guard experienceRouter.route == .new else { return }
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
            setGuidedPracticePhase(.success, source: "guided_practice_return_pending")
            return
        }

        guard onboardingStore.isCompleted,
              !onboardingStore.hasCompletedGuidedPractice,
              guidedOnboardingPresentationMode == nil,
              guidedPracticePhase == .hidden || guidedPracticePhase == .completed else {
            return
        }

        setGuidedPracticePhase(.introSlides, source: "guided_practice_required")
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
        onboardingStore.setGuidedPracticeSelectedAppIDs([])
        onboardingStore.clearGuidedWindowsDraft()
        setGuidedPracticePhase(.readyCoachMark, source: "intro_completed")
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
        setGuidedPracticePhase(.appSelection, source: "ready_coach_mark_timer")
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
        onboardingStore.setGuidedPracticeFamilySelection(guidedPracticeFamilySelection)
        onboardingStore.setGuidedPracticeAppConnections(
            guidedPracticeAppAssignments
                .map { GuidedPracticeAppConnection(appID: $0.value, token: $0.key) }
                .sorted { $0.appID < $1.appID }
        )
        guidedPracticeFamilyPickerError = nil
        setGuidedPracticePhase(.appConnections, source: "family_picker_completed")
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
        setGuidedPracticePhase(.familyPickerVideo, source: "choose_apps_again")
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
        if let tiktokSelection = savedConnections.selection(for: GuidedPracticeLaunchApp.tiktok.rawValue),
           chosenAppIDs.contains(GuidedPracticeLaunchApp.tiktok.rawValue) {
            tiktokProtectionStore.familySelection = tiktokSelection
            tiktokProtectionStore.setProtectionEnabled(
                true,
                source: "guided_practice.app_connections"
            )
        }
        if let xSelection = savedConnections.selection(for: GuidedPracticeLaunchApp.x.rawValue),
           chosenAppIDs.contains(GuidedPracticeLaunchApp.x.rawValue) {
            xProtectionStore.familySelection = xSelection
            xProtectionStore.setProtectionEnabled(
                true,
                source: "guided_practice.app_connections"
            )
        }

        guidedPracticeActiveApps = Set(guidedPracticeChosenApps)
        setGuidedPracticePhase(.openAppPrompt, source: "app_connections_completed")
    }

    private func openGuidedPracticeInstagram() {
        guard guidedPracticeInstagramOpenGate.requestOpen(
            from: guidedPracticePhase,
            canOpenControlledClient: { canOpenControlledClient("instagram") }
        ) else { return }
        AnalyticsService.shared.capture("instagram_practice_open_tapped")
        setGuidedPracticePhase(.waitingForReturn, source: "instagram_opened")
        path.append(Route.instagramClient(context: .guidedPractice))
    }

    private func completeInstagramGuidedPractice() {
        AnalyticsService.shared.capture("instagram_practice_completed")
        onboardingStore.setGuidedPracticeReturnPending(true)
        path = NavigationPath()
        setGuidedPracticePhase(.success, source: "instagram_practice_completed")
    }

    private func cancelInstagramGuidedPractice() {
        guard guidedPracticePhase == .waitingForReturn else { return }
        path = NavigationPath()
        setGuidedPracticePhase(.openAppPrompt, source: "instagram_practice_cancelled")
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
        onboardingStore.clearGuidedWindowsDraft()
        setGuidedPracticePhase(.windowsHomeCoachMark, source: "windows_guide_started")
    }

    private func beginGuidedWindowsEditor() {
        guard guidedPracticePhase == .windowsHomeCoachMark else { return }
        AnalyticsService.shared.capture(
            AnalyticsEvent.guidedWindowsStepViewed,
            properties: ["step": "name"]
        )
        setGuidedPracticePhase(.windowsEditor(.name), source: "windows_home_tapped")
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
            setGuidedPracticePhase(.windowsEditor(nextStep), source: "windows_editor_advanced")
        }
    }

    private func showGuidedWindowsReadyModal() {
        guard case .windowsEditor = guidedPracticePhase else { return }
        onboardingStore.clearGuidedWindowsDraft()
        setGuidedPracticePhase(.windowsReady, source: "windows_saved")
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
        setGuidedPracticePhase(.reviewPrompt, source: "guided_practice_complete")
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
        setGuidedPracticePhase(.completed, source: "guided_practice_finished")
        guidedPracticeActiveApps = []
        hasHandledGuidedPracticeReviewRequest = false
        path = NavigationPath()
    }

    private func retryGuidedPracticeOpenApp() {
        onboardingStore.setGuidedPracticeReturnPending(false)
        hasHandledGuidedPracticeReviewRequest = false
        guidedPracticeActiveApps = activeGuidedPracticeBlockedApps
        setGuidedPracticePhase(.openAppPrompt, source: "guided_practice_retry")
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

    @MainActor
    private func commitHardModeChange(_ commit: HardModeCommit) -> HardModeCommitResult {
        hardModeCoordinator.reconcilePauses()
        let change = commit.change
        if commit.choice == .direct {
            return performHardModeMutation(change.mutation, source: change.source)
        }
        if case .batch(let selection) = commit.choice {
            return commitHardModeBatch(selection, source: change.source)
        }
        if change.mutation == .turnOffHardMode {
            return .success
        }

        timeWindowStore.evaluateSchedules(
            source: "hard_mode.revalidate",
            forceApply: true
        )
        if let staleMessage = hardModeStaleMessage(for: change) {
            return .stale(staleMessage)
        }

        switch commit.choice {
        case .direct:
            return performHardModeMutation(change.mutation, source: change.source)
        case .pause(let minutes):
            let ruleIDs = hardModeRuleIDs(for: change.mutation)
            let previousExpiry = HardModeProtectionState.nextPauseExpiry(
                defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
            )
            guard let _ = HardModeProtectionState.pause(
                appIDs: change.affectedAppIDs,
                ruleIDs: ruleIDs,
                minutes: minutes,
                defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
            ) else {
                return .failure("Choose where protection should resume and try again.")
            }
            guard let nextExpiry = HardModeProtectionState.nextPauseExpiry(
                defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
            ), HardModePauseMonitor.schedule(until: nextExpiry) else {
                HardModeProtectionState.removePauses(
                    appIDs: change.affectedAppIDs,
                    ruleIDs: ruleIDs,
                    defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
                )
                if let previousExpiry { _ = HardModePauseMonitor.schedule(until: previousExpiry) }
                return .failure("iOS couldn't schedule protection to return. Please try again.")
            }
            HardModePauseMonitor.clearScheduleShields(for: change.affectedAppIDs)
            refreshProtectionAfterHardModeChange(source: "\(change.source).paused")
            return .success
        case .off:
            let result = performHardModeMutation(change.mutation, source: change.source)
            guard result == .success else { return result }
            if change.mutation != .pauseAllWindows {
                for appID in change.affectedAppIDs {
                    if ["instagram", "tiktok", "x"].contains(appID) {
                        disableManualProtection(for: appID, source: "\(change.source).hard_mode_off")
                    }
                    HardModeProtectionState.markProtectionOff(
                        appID,
                        defaults: UserDefaults(suiteName: NimaConstants.appGroupID)
                    )
                }
            }
            HardModePauseMonitor.clearScheduleShields(for: change.affectedAppIDs)
            refreshProtectionAfterHardModeChange(source: "\(change.source).off")
            return .success
        case .batch:
            return .failure("Choose what changes and try again.")
        }
    }

    @MainActor
    private func commitHardModeBatch(
        _ selection: HardModeBatchSelection,
        source: String
    ) -> HardModeCommitResult {
        guard selection.hasChanges else { return .failure("Choose at least one change.") }
        let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)
        let previousExpiry = HardModeProtectionState.nextPauseExpiry(defaults: defaults)
        let changedApps = Set(selection.appChoices.compactMap { entry in
            entry.value == .keep ? nil : entry.key
        })
        guard changedApps.isSubset(of: ["instagram", "tiktok", "x"]) else {
            return .failure("This app is no longer available.")
        }

        timeWindowStore.evaluateSchedules(source: "hard_mode.batch_revalidate", forceApply: true)
        for appID in changedApps {
            guard ClientShieldPolicy.decision(for: appID, defaults: defaults).shouldShield else {
                return .stale("\(appID.capitalized) protection changed before you confirmed. Nothing was changed.")
            }
        }

        var pausedApps = Set<String>()
        for appID in changedApps.sorted() {
            guard case .pause(let minutes)? = selection.appChoices[appID] else { continue }
            guard [5, 10, 15].contains(minutes),
                  HardModeProtectionState.pause(
                    appIDs: [appID],
                    minutes: minutes,
                    defaults: defaults
                  ) != nil else {
                HardModeProtectionState.removePauses(appIDs: pausedApps, ruleIDs: [], defaults: defaults)
                return .failure("Could not schedule the selected pause. Nothing was changed.")
            }
            pausedApps.insert(appID)
        }
        if !pausedApps.isEmpty {
            guard let nextExpiry = HardModeProtectionState.nextPauseExpiry(defaults: defaults),
                  HardModePauseMonitor.schedule(until: nextExpiry, defaults: defaults) else {
                HardModeProtectionState.removePauses(appIDs: pausedApps, ruleIDs: [], defaults: defaults)
                if let previousExpiry { _ = HardModePauseMonitor.schedule(until: previousExpiry) }
                return .failure("iOS couldn't schedule protection to return. Nothing was changed.")
            }
        }

        for appID in changedApps.sorted() {
            guard selection.appChoices[appID] == .off else { continue }
            disableManualProtection(for: appID, source: "\(source).batch_off")
            HardModeProtectionState.markProtectionOff(appID, defaults: defaults)
        }
        HardModePauseMonitor.clearScheduleShields(for: changedApps)
        if !changedApps.isEmpty {
            refreshProtectionAfterHardModeChange(source: "\(source).batch")
        }
        return .success
    }

    @MainActor
    private func performHardModeMutation(
        _ mutation: HardModeRequestedMutation,
        source: String
    ) -> HardModeCommitResult {
        switch mutation {
        case .turnOffHardMode:
            return .success
        case .disableClientProtection(let appID):
            guard ["instagram", "tiktok", "x"].contains(appID) else {
                return .failure("This app is no longer available.")
            }
            disableManualProtection(for: appID, source: source)
        case .disableBlockingOption(let appID, let optionID):
            guard let app = store.app(for: appID),
                  let option = app.options.first(where: { $0.id == optionID }) else {
                return .failure("This blocker is no longer available.")
            }
            if option.isEnabled {
                store.toggleOption(appId: appID, optionId: optionID, source: source)
            }
        case .endActiveWindows(let appID):
            _ = timeWindowStore.endActiveWindow(for: appID)
        case .setWindowEnabled(let windowID, let enabled):
            timeWindowStore.setEnabled(enabled, for: windowID)
        case .updateWindow(let window, _):
            timeWindowStore.updateWindow(window)
        case .deleteWindow(let windowID):
            timeWindowStore.deleteWindow(id: windowID)
        case .updateAppRule(let ruleID, let kind, let dailyMinutes, _):
            guard let rule = appControlRulesStore.rules.first(where: { $0.id == ruleID }) else {
                return .failure("This app control changed before you finished.")
            }
            guard appControlRulesStore.save(
                token: rule.applicationToken,
                kind: kind,
                dailyMinutes: dailyMinutes,
                replacing: ruleID
            ) else {
                return .failure("Could not update this app control. Please try again.")
            }
        case .deleteAppRule(let ruleID, _):
            guard appControlRulesStore.delete(id: ruleID) else {
                return .failure("Could not remove this app control. Please try again.")
            }
        case .pauseAllWindows:
            timeWindowStore.setPauseAll(true)
        }
        refreshProtectionAfterHardModeChange(source: source)
        return .success
    }

    private func hardModeStaleMessage(for change: HardModeRequestedChange) -> String? {
        switch change.mutation {
        case .turnOffHardMode:
            return hardModeCoordinator.isEnabled
                ? nil
                : "Hard Mode is already off."
        case .disableClientProtection(let appID):
            guard currentManualProtection(for: appID) || timeWindowStore.isAppScheduled(appID) else {
                return "This protection changed before you finished. Nothing was turned off."
            }
        case .disableBlockingOption(let appID, let optionID):
            guard store.app(for: appID)?.options.first(where: { $0.id == optionID })?.isEnabled == true else {
                return "This blocker changed before you finished. Nothing was turned off."
            }
        case .endActiveWindows(let appID):
            guard timeWindowStore.activeWindows().contains(where: { $0.apps.contains(appID) }) else {
                return "This time window ended before you finished. Nothing was changed."
            }
        case .setWindowEnabled(let windowID, let enabled):
            guard let window = timeWindowStore.windows.first(where: { $0.id == windowID }),
                  window.enabled != enabled else {
                return "This time window changed before you finished. Nothing was changed."
            }
        case .updateWindow(let updated, let expectedUpdatedAt):
            guard let current = timeWindowStore.windows.first(where: { $0.id == updated.id }),
                  current.updatedAt == expectedUpdatedAt else {
                return "This time window changed before you finished. Nothing was changed."
            }
        case .deleteWindow(let windowID):
            guard timeWindowStore.windows.contains(where: { $0.id == windowID }) else {
                return "This time window was already deleted."
            }
        case .updateAppRule(let ruleID, _, _, _),
             .deleteAppRule(let ruleID, _):
            guard appControlRulesStore.rules.contains(where: { $0.id == ruleID }) else {
                return "This app control was already removed."
            }
        case .pauseAllWindows:
            guard !timeWindowStore.pauseAll,
                  !timeWindowStore.activeWindows().isEmpty else {
                return "There is no active time window left to pause."
            }
        }
        return nil
    }

    private func hardModeRuleIDs(for mutation: HardModeRequestedMutation) -> Set<String> {
        switch mutation {
        case .updateAppRule(let ruleID, _, _, _),
             .deleteAppRule(let ruleID, _):
            return [ruleID]
        default:
            return []
        }
    }

    private func currentManualProtection(for appID: String) -> Bool {
        switch appID {
        case "instagram": instagramProtectionStore.protectionEnabled
        case "tiktok": tiktokProtectionStore.protectionEnabled
        case "x": xProtectionStore.protectionEnabled
        default: store.app(for: appID)?.options.contains(where: \.isEnabled) ?? false
        }
    }

    private func disableManualProtection(for appID: String, source: String) {
        switch appID {
        case "instagram":
            instagramProtectionStore.setProtectionEnabled(false, source: source)
        case "tiktok":
            tiktokProtectionStore.setProtectionEnabled(false, source: source)
        case "x":
            xProtectionStore.setProtectionEnabled(false, source: source)
        default:
            if let option = store.app(for: appID)?.options.first(where: \.isEnabled) {
                store.toggleOption(appId: appID, optionId: option.id, source: source)
            }
        }
    }

    private func refreshProtectionAfterHardModeChange(source: String) {
        timeWindowStore.evaluateSchedules(source: source, forceApply: true)
        instagramProtectionStore.refreshPauseMode()
        tiktokProtectionStore.refreshPauseMode()
        xProtectionStore.refreshPauseMode()
        appControlRulesStore.reconcile()
        store.syncVPNState(source: source)
        markStreakIfEligible(source: source)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            AnalyticsService.shared.enterForeground(existingInstallation: onboardingStore.isCompleted)
            timeWindowStore.setEvaluationSuspended(true)
            vpnManager.reconciliationSuspended = true
            Task { await recheckExperience() }
            hardModeCoordinator.reconcilePauses()
            streakStore.refreshFromDisk()
            handlePendingInstagramShieldDestination()
            appControlRulesStore.reconcile()
            instagramProtectionStore.refreshAuthorizationStatus()
            tiktokProtectionStore.refreshAuthorizationStatus()
            xProtectionStore.refreshAuthorizationStatus()
            MetaAdsService.shared.refreshConsent()
            subscriptionStore.refreshAfterForeground()
            subscriptionStore.reconcilePendingPurchaseAfterForeground()
            if experienceRouter.route != .checking && onboardingStore.isCompleted {
                timeWindowStore.evaluateSchedules(source: "app.scene.active", forceApply: true)
                markStreakIfEligible(source: "app.scene.active")
                store.syncVPNState(source: "app.scene.active")
                vpnManager.repairScheduledProtectionIfNeeded(source: "app.scene.active")
            }
            guard onboardingStore.hasGuidedPracticeReturnPending else { return }
            path = NavigationPath()
            guidedOnboardingPresentationMode = nil
            setGuidedPracticePhase(.success, source: "app_foreground_return")
        case .inactive, .background:
            if newPhase == .background {
                hardModeCoordinator.cancelChallenge()
            }
            if newPhase == .background {
                AnalyticsService.shared.leaveForeground()
                AcquisitionTrackingService.shared.leaveForeground()
                MetaAdsService.shared.leaveForeground()
            }
        @unknown default:
            break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard !isGuidedSetupActive else { return }
        guard url.scheme?.lowercased() == "nima" else { return }
        if url.host?.lowercased() == "instagram" {
            let opensLinkSheet = url.path.lowercased() == "/open-link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("instagram") else { return }
                path = NavigationPath()
                path.append(
                    Route.instagramClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        } else if url.host?.lowercased() == "tiktok" {
            let opensLinkSheet = url.path.lowercased() == "/open-link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("tiktok") else { return }
                path = NavigationPath()
                path.append(
                    Route.tiktokClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        } else if url.host?.lowercased() == "x" {
            let opensLinkSheet = url.path.lowercased() == "/open-link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("x") else { return }
                path = NavigationPath()
                path.append(
                    Route.xClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        }
    }

    private func canOpenControlledClient(_ appID: String) -> Bool {
        let tokens: Set<ApplicationToken>
        switch appID {
        case "instagram": tokens = instagramProtectionStore.familySelection.applicationTokens
        case "tiktok": tokens = tiktokProtectionStore.familySelection.applicationTokens
        case "x": tokens = xProtectionStore.familySelection.applicationTokens
        default: return true
        }
        guard let kind = appControlRulesStore.activeKind(for: tokens) else { return true }
        appRuleAlertMessage = kind == .blocked
            ? "You blocked this app in Controls. Remove the block there to open it."
            : "Your daily time limit for this app has been reached. It resets tomorrow."
        return false
    }

    private func handlePendingInstagramShieldDestination() {
        guard !isGuidedSetupActive else { return }
        guard let defaults = UserDefaults(suiteName: NimaConstants.appGroupID) else { return }
        let destination = defaults.string(forKey: NimaConstants.shieldPendingDestinationKey)
            ?? defaults.string(forKey: NimaConstants.instagramShieldPendingDestinationKey)
        guard let destination else { return }

        defaults.removeObject(forKey: NimaConstants.shieldPendingDestinationKey)
        defaults.removeObject(forKey: NimaConstants.instagramShieldPendingDestinationKey)
        defaults.synchronize()

        if destination == "tiktok" || destination == "tiktok_open_link" {
            let opensLinkSheet = destination == "tiktok_open_link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("tiktok") else { return }
                path = NavigationPath()
                path.append(
                    Route.tiktokClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        } else if destination == "x" || destination == "x_open_link" {
            let opensLinkSheet = destination == "x_open_link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("x") else { return }
                path = NavigationPath()
                path.append(
                    Route.xClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        } else {
            let opensLinkSheet = destination == "open_link"
            featureAccessAuthorizer {
                guard canOpenControlledClient("instagram") else { return }
                path = NavigationPath()
                path.append(
                    Route.instagramClient(context: opensLinkSheet ? .openLink : .standard)
                )
            }
        }
    }

    private func markStreakIfEligible(source _: String) {
        let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)
        guard onboardingStore.isCompleted,
              let activeSource = StreakEligibility.activeSource(
                instagramManual: instagramProtectionStore.protectionEnabled,
                instagramScheduled: instagramProtectionStore.isScheduled,
                instagramPaused: PauseModeState.isPaused("instagram", defaults: defaults),
                tiktokManual: tiktokProtectionStore.protectionEnabled,
                tiktokScheduled: tiktokProtectionStore.isScheduled,
                tiktokPaused: PauseModeState.isPaused("tiktok", defaults: defaults),
                xManual: xProtectionStore.protectionEnabled,
                xScheduled: xProtectionStore.isScheduled,
                xPaused: PauseModeState.isPaused("x", defaults: defaults)
              ) else {
            syncStreakReminder()
            return
        }

        streakStore.markTodayEarned(source: activeSource)
        syncStreakReminder()
    }

    private func syncStreakReminder() {
        appSettingsStore.syncStreakReminder(
            hasEarnedToday: streakStore.hasEarnedToday()
        )
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

private struct ExperienceCheckingScreen: View {
    let onRetry: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.12, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("nima").font(.system(size: 48, weight: .black, design: .rounded))
                ProgressView().tint(.white)
                Text("Checking your purchases…").multilineTextAlignment(.center)
                Button("Try again", action: onRetry)
                Button("Restore purchases", action: onRestore)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
    }
}
