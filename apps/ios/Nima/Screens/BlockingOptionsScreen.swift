import SwiftUI

struct BlockingOptionsScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(HardModeCoordinator.self) private var hardModeCoordinator
    @Environment(\.dismiss) private var dismiss
    let appId: String
    var authorizeFeatureAccess = FeatureAccessGate.unrestricted

    private var app: BlockedApp? {
        store.app(for: appId)
    }

    var body: some View {
        ZStack {
            SkyBackgroundView()

            VStack(spacing: 0) {
                HeaderBar()

                Spacer()

                if let app {
                    DialSelector(
                        app: app,
                        onToggleOption: { optionId in
                            let isEnabled = app.options.first(where: { $0.id == optionId })?.isEnabled == true
                            if isEnabled,
                               hardModeCoordinator.requestOff(
                                    .disableBlockingOption(appID: appId, optionID: optionId),
                                    source: "blocking_options_screen.tap"
                               ) {
                                return
                            }
                            if isEnabled {
                                store.toggleOption(
                                    appId: appId,
                                    optionId: optionId,
                                    source: "blocking_options_screen.tap"
                                )
                            } else {
                                authorizeFeatureAccess {
                                    store.toggleOption(
                                        appId: appId,
                                        optionId: optionId,
                                        source: "blocking_options_screen.tap"
                                    )
                                }
                            }
                        }
                    )

                    Text(app.name)
                        .font(NimaFonts.headerTitle)
                        .foregroundStyle(.white)
                        .padding(.top, NimaSpacing.xl)
                }

                Spacer()
            }

            // Back button - matching the design (blue arrow on left)
            VStack {
                Spacer()
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(NimaColors.skyBlue)
                            .clipShape(Circle())
                    }
                    .padding(.leading, NimaSpacing.lg + 5)
                    .padding(.bottom, NimaSpacing.xxl - 10)

                    Spacer()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        BlockingOptionsScreen(appId: "instagram")
            .environment(AppStore())
    }
}
