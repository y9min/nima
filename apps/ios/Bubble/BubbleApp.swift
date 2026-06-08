import SwiftUI
import NetworkExtension

@main
struct BubbleApp: App {
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
            }
            .onChange(of: onboardingStore.isCompleted) { _, isCompleted in
                guard isCompleted else { return }
                configureProtectionIfNeeded()
                store.syncVPNState(source: "onboarding.completed")
                markStreakIfEligible(source: "onboarding.completed")
            }
            .onChange(of: vpnManager.vpnStatus) { _, _ in
                if onboardingStore.isCompleted {
                    store.syncVPNState(source: "vpn.status")
                    markStreakIfEligible(source: "vpn.status")
                }
            }
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
            }
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
