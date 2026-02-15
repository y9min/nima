import SwiftUI

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var authStore
    var onSelectApp: (BlockedApp) -> Void
    var onSignIn: (() -> Void)? = nil

    var body: some View {
        ZStack {
            SkyBackgroundView()

            AppCluster(
                apps: store.apps,
                onTapApp: { app in
                    onSelectApp(app)
                },
                onTapAdd: {
                    // TODO: Handle add app action
                    print("Add app tapped")
                },
                showAddButton: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // HeaderBar in top left corner
            VStack {
                HStack {
                    HeaderBar()
                        .padding(.top, BubbleSpacing.md + 10)
                        .padding(.leading, BubbleSpacing.lg + 5)
                    Spacer()
                    
                    // Sign in button in top right corner (only show if not logged in)
                    if !authStore.isLoggedIn, let onSignIn = onSignIn {
                        Button {
                            onSignIn()
                        } label: {
                            Text("Sign In")
                                .font(BubbleFonts.coolvetica(size: 16))
                                .foregroundStyle(.white)
                                .padding(.horizontal, BubbleSpacing.md)
                                .padding(.vertical, BubbleSpacing.sm)
                                .background(BubbleColors.skyBlue)
                                .clipShape(RoundedRectangle(cornerRadius: BubbleSpacing.buttonCornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: BubbleSpacing.buttonCornerRadius)
                                        .strokeBorder(Color.white, lineWidth: 1)
                                )
                        }
                        .padding(.top, BubbleSpacing.md + 10)
                        .padding(.trailing, BubbleSpacing.lg + 5)
                    }
                }
                Spacer()
            }

            // Add button in bottom right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        // TODO: Handle add app action
                        print("Add app tapped")
                    } label: {
                        AppIconCircle(iconName: "plus", size: BubbleSpacing.appIconMedium, isAddButton: true)
                    }
                    .padding(.trailing, BubbleSpacing.xl + 10)
                    .padding(.bottom, 14)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    HomeScreen(onSelectApp: { _ in }, onSignIn: {})
        .environment(AppStore())
        .environment(GridPositionStore())
        .environment(AuthStore())
}
