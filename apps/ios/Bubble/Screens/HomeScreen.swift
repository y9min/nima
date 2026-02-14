import SwiftUI

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    var onSelectApp: (BlockedApp) -> Void

    var body: some View {
        ZStack {
            SkyBackgroundView()

            VStack(spacing: 0) {
                HeaderBar()

                Spacer()

                AppCluster(
                    apps: store.apps,
                    onTapApp: { app in
                        onSelectApp(app)
                    }
                )

                Spacer()

                PageIndicator(totalPages: 3, currentPage: 0)
                    .padding(.bottom, BubbleSpacing.xxl)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    HomeScreen(onSelectApp: { _ in })
        .environment(AppStore())
}
