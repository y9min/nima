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
                MainTabsScreen(
                    onSelectApp: { app in
                        path.append(Route.blockingOptions(appId: app.id))
                    },
                    onSignIn: {
                        path.append(Route.magicSignIn)
                    },
                    onSettings: {
                        path.append(Route.settings)
                    },
                    onTrafficDashboard: {
                        path.append(Route.trafficDashboard)
                    }
                )
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .home:
                        MainTabsScreen(
                            onSelectApp: { app in
                                path.append(Route.blockingOptions(appId: app.id))
                            },
                            onSignIn: {
                                path.append(Route.magicSignIn)
                            },
                            onSettings: {
                                path.append(Route.settings)
                            },
                            onTrafficDashboard: {
                                path.append(Route.trafficDashboard)
                            }
                        )
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
                        SettingsScreen()
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
            .environmentObject(vpnManager)
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
            .onChange(of: vpnManager.vpnStatus) { _, _ in
                markStreakIfEligible(source: "vpn.status")
            }
        }
    }

    private func markStreakIfEligible(source: String) {
        guard Self.isProtectionActive(vpnManager.vpnStatus),
              store.hasAnyEnabledBlockingOption else {
            return
        }

        streakStore.markTodayEarned(
            source: store.firstEnabledBlockerSource ?? source
        )
    }

    private static func isProtectionActive(_ status: NEVPNStatus) -> Bool {
        status == .connected || status == .connecting || status == .reasserting
    }
}
