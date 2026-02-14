import SwiftUI

struct AppCluster: View {
    let apps: [BlockedApp]
    var onTapApp: (BlockedApp) -> Void
    var onTapAdd: () -> Void = {}

    var body: some View {
        let iconSize = BubbleSpacing.appIconMedium
        let spacing: CGFloat = 12

        // Diamond/cluster layout:
        // Row 1: first app (top center)
        // Row 2: second + third apps (left + right)
        // Row 3: add button (bottom center)
        VStack(spacing: spacing) {
            // Top icon
            if let first = apps.first {
                Button { onTapApp(first) } label: {
                    AppIconCircle(iconName: first.iconName, size: iconSize, platform: first.platform)
                }
            }

            // Middle row
            HStack(spacing: spacing * 2.5) {
                if apps.count > 1 {
                    Button { onTapApp(apps[1]) } label: {
                        AppIconCircle(iconName: apps[1].iconName, size: iconSize, platform: apps[1].platform)
                    }
                }
                if apps.count > 2 {
                    Button { onTapApp(apps[2]) } label: {
                        AppIconCircle(iconName: apps[2].iconName, size: iconSize, platform: apps[2].platform)
                    }
                }
            }

            // Add button
            Button(action: onTapAdd) {
                AppIconCircle(iconName: "plus", size: iconSize, isAddButton: true)
            }
        }
    }
}

#Preview {
    ZStack {
        BubbleColors.skyGradient.ignoresSafeArea()
        AppCluster(
            apps: AppStore().apps,
            onTapApp: { _ in }
        )
    }
}
