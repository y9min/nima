import SwiftUI

struct MainTabsScreen: View {
    @Environment(TimeWindowStore.self) private var timeWindowStore
    @Environment(\.sizeCategory) private var contentSizeCategory
    @State private var selectedTab: AppDockDestination = .home
    @State private var pendingAddWindowRequestID: UUID?

    let onSelectApp: (BlockedApp) -> Void
    let onSignIn: () -> Void
    let onSettings: () -> Void
    let onTrafficDashboard: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeDashboardLayout(
                screenSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                contentSizeCategory: contentSizeCategory
            )

            ZStack(alignment: .bottom) {
                ZStack {
                    switch selectedTab {
                    case .home:
                        HomeScreen(
                            onSelectApp: onSelectApp,
                            onTimeWindows: { selectedTab = .windows },
                            onAddTimeWindow: openAddTimeWindow,
                            onSignIn: onSignIn,
                            onSettings: onSettings,
                            onTrafficDashboard: onTrafficDashboard,
                            showsDock: false
                        )
                        .transition(.opacity)
                    case .windows:
                        TimeWindowsScreen(
                            onHome: { selectedTab = .home },
                            onSettings: onSettings,
                            addWindowRequestID: pendingAddWindowRequestID,
                            onAddWindowRequestHandled: {
                                pendingAddWindowRequestID = nil
                            },
                            showsDock: false
                        )
                        .transition(.opacity)
                    case .settings:
                        EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: selectedTab)

                AppBottomDock(
                    selected: selectedTab,
                    scale: layout.scale,
                    onHome: { selectedTab = .home },
                    onWindows: { selectedTab = .windows },
                    onSettings: onSettings
                )
                .frame(width: layout.contentWidth, height: layout.dockHeight)
                .padding(.bottom, layout.dockBottomPadding)
            }
        }
        .onAppear {
            if timeWindowStore.homeFocusRequestID != nil {
                selectedTab = .home
            }
        }
        .onChange(of: timeWindowStore.homeFocusRequestID) { _, newValue in
            if newValue != nil {
                selectedTab = .home
            }
        }
    }

    private func openAddTimeWindow() {
        pendingAddWindowRequestID = UUID()
        selectedTab = .windows
    }
}
