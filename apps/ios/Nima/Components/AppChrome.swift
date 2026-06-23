import SwiftUI
import UIKit

enum AppDockDestination: Equatable {
    case home
    case windows
    case settings
}

enum AppChromePalette {
    static let background = Color(red: 0.0, green: 0.118, blue: 0.067)
    static let card = Color(red: 0.004, green: 0.102, blue: 0.059)
    static let border = Color(red: 0.282, green: 0.376, blue: 0.333)
    static let accent = Color(red: 0.675, green: 0.867, blue: 0.137)
    static let muted = Color(red: 0.647, green: 0.682, blue: 0.624)
    static let dock = Color(red: 0.016, green: 0.141, blue: 0.082).opacity(0.78)
}

struct HomeLogo: View {
    var body: some View {
        Group {
            if let image = UIImage.homeDashboardResource(named: "nima_logo", fileExtension: "png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("nima")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("nima")
    }
}

struct AppBottomDock: View {
    let selected: AppDockDestination
    let scale: CGFloat
    let onHome: () -> Void
    let onWindows: () -> Void
    let onSettings: () -> Void

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack {
            dockItem(label: "home", icon: "house", destination: .home, action: onHome)
            dockItem(label: "windows", icon: "clock", destination: .windows, action: onWindows)
            dockItem(label: "settings", icon: "gearshape", destination: .settings, action: onSettings)
        }
        .padding(.horizontal, 30 * visualScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LiquidGlassDockBackground(cornerRadius: 24 * visualScale)
        )
    }

    private func dockItem(label: String, icon: String, destination: AppDockDestination, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3 * visualScale) {
                Image(systemName: icon)
                    .font(.system(size: 22 * visualScale, weight: .medium))
                Text(label)
                    .font(NimaFonts.coolvetica(size: 13.5 * visualScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected == destination ? AppChromePalette.accent : AppChromePalette.muted)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct LiquidGlassDockBackground: View {
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                ios26Glass
            } else {
                fallbackGlass
            }
        }
        .overlay(
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.22),
                            AppChromePalette.accent.opacity(0.18),
                            .black.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1.2)
                .padding(.horizontal, 28)
                .padding(.top, 2)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, y: 12)
        .shadow(color: AppChromePalette.accent.opacity(0.08), radius: 18, y: -2)
    }

    @available(iOS 26.0, *)
    private var ios26Glass: some View {
        shape
            .fill(.clear)
            .glassEffect(
                .regular
                    .tint(AppChromePalette.dock.opacity(0.58))
                    .interactive(),
                in: shape
            )
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            AppChromePalette.card.opacity(0.48),
                            AppChromePalette.dock.opacity(0.36)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
    }

    private var fallbackGlass: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            AppChromePalette.dock.opacity(0.86),
                            AppChromePalette.card.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
    }
}

extension UIImage {
    static func homeDashboardResource(named name: String, fileExtension: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        guard let path = Bundle.main.path(forResource: name, ofType: fileExtension) else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
}
