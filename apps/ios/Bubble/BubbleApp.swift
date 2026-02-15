import SwiftUI

@main
struct BubbleApp: App {
    @State private var path = NavigationPath()
    @State private var store = AppStore()
    @State private var gridPositionStore = GridPositionStore()
    @State private var authStore: AuthStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                LandingPage(onGo: {
                    // Navigate to login if not authenticated, otherwise go to home
                    if authStore.isLoggedIn {
                        path.append(Route.home)
                    } else {
                        path.append(Route.magicSignIn)
                    }
                })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .home:
                        HomeScreen(
                            onSelectApp: { app in
                                path.append(Route.blockingOptions(appId: app.id))
                            },
                            onSignIn: {
                                path.append(Route.magicSignIn)
                            }
                        )
                    case .blockingOptions(let appId):
                        BlockingOptionsScreen(appId: appId)
                    case .magicSignIn:
                        MagicSignInScreen(onCodeSent: { email in
                            path.append(Route.codeVerification(email: email))
                        })
                    case .codeVerification(let email):
                        CodeVerificationScreen(email: email, onVerified: {
                            // Clear navigation stack and go to home
                            path = NavigationPath()
                            path.append(Route.home)
                        })
                    }
                }
            }
            .environment(store)
            .environment(gridPositionStore)
            .environment(authStore)
            .preferredColorScheme(.dark)
            .task {
                SVGCache.shared.preload(svgNames: ["instagram", "kalshi", "fanduel"])
            }
        }
    }
}
