import SwiftUI

@main
struct BubbleApp: App {
    @State private var path = NavigationPath()
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                LandingPage(onGo: {
                    path.append(Route.home)
                })
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .home:
                        HomeScreen(onSelectApp: { app in
                            path.append(Route.blockingOptions(appId: app.id))
                        })
                    case .blockingOptions(let appId):
                        BlockingOptionsScreen(appId: appId)
                    }
                }
            }
            .environment(store)
            .preferredColorScheme(.dark)
        }
    }
}
