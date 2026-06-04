import SwiftUI
import NetworkExtension
import UIKit

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var authStore
    @Environment(\.sizeCategory) private var contentSizeCategory
    @EnvironmentObject private var vpnManager: VPNManager
    @State private var blockSessionEndsAt: Date?
    @State private var blockSessionStartedAt: Date?

    var onSelectApp: (BlockedApp) -> Void
    var onSignIn: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var onTrafficDashboard: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeDashboardLayout(
                screenSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                contentSizeCategory: contentSizeCategory
            )

            ZStack(alignment: .bottom) {
                HomeDashboardPalette.background
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    if layout.requiresScroll {
                        ScrollView(.vertical, showsIndicators: false) {
                            homeContent(layout: layout)
                                .frame(width: layout.contentWidth)
                                .frame(maxWidth: .infinity)
                                .padding(.top, layout.contentTopInset)
                                .padding(.bottom, layout.dockReservedHeight)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        homeContent(layout: layout)
                            .frame(width: layout.contentWidth)
                            .padding(.top, layout.contentTopInset)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    }

                    #if DEBUG
                    if HomeDashboardLayout.debugOverlayEnabled {
                        HomeDashboardDebugOverlay(layout: layout)
                            .allowsHitTesting(false)
                    }
                    #endif
                }

                HomeBottomDock(
                    scale: layout.scale,
                    onHome: {},
                    onLimits: openLimits,
                    onSettings: { onSettings?() }
                )
                .frame(width: layout.contentWidth, height: layout.dockHeight)
                .padding(.bottom, layout.dockBottomPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            syncSessionEndDate()
        }
        .onChange(of: blockedAppIDs) { _, _ in
            syncSessionEndDate()
        }
    }

    private func homeContent(layout: HomeDashboardLayout) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.topPadding)

            HomeLogo()
                .frame(width: layout.logoSize.width * 0.9, height: layout.logoSize.height * 0.9)

            Color.clear.frame(height: layout.logoToGreeting)

            HomeGreeting(name: displayName, scale: layout.scale)
                .frame(width: layout.contentWidth, height: layout.greetingHeight, alignment: .leading)

            Color.clear.frame(height: layout.greetingToBlocker)

            BlockingStatusCard(
                apps: dashboardApps,
                vpnState: blockingVPNState,
                sessionEndsAt: blockSessionEndsAt,
                onToggleApp: { appId in
                    toggleBlockState(for: appId)
                },
                onRequestVPNPermission: {
                    requestVPNPermission()
                }
            )
            .frame(width: layout.contentWidth, height: layout.blockerHeight)

            Color.clear.frame(height: layout.blockerToInsights)

            StreakCard(
                currentStreakDays: estimatedCurrentStreakDays,
                scale: layout.scale
            )
            .frame(width: layout.contentWidth, height: layout.insightsHeight)

            Color.clear.frame(height: layout.bottomPadding)
        }
    }

    private var dashboardApps: [BlockingDashboardApp] {
        ["instagram", "tiktok"].compactMap { appId in
            guard let app = store.app(for: appId) else { return nil }
            return BlockingDashboardApp(
                id: app.id,
                name: app.name,
                platform: app.platform ?? app.id,
                isBlocked: app.options.contains { $0.isEnabled }
            )
        }
    }

    private var blockedAppIDs: [String] {
        dashboardApps
            .filter { $0.isBlocked }
            .map(\.id)
            .sorted()
    }

    private var displayName: String {
        let localPart = authStore.userEmail
            .split(separator: "@")
            .first?
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .first

        guard let localPart, !localPart.isEmpty else {
            return "emily"
        }

        return String(localPart).lowercased()
    }

    private var estimatedCurrentStreakDays: Int {
        blockedAppIDs.isEmpty ? 0 : 8
    }

    private var blockingVPNState: BlockingVPNState {
        switch vpnManager.vpnStatus {
        case .invalid:
            return blockedAppIDs.isEmpty ? .disconnected : .permissionRequired
        case .disconnected:
            return .disconnected
        case .connecting, .reasserting:
            return .connecting
        case .connected:
            return .connected
        case .disconnecting:
            return .disconnecting
        @unknown default:
            return .disconnected
        }
    }

    private func toggleBlockState(for appId: String) {
        guard let app = store.app(for: appId),
              let optionId = app.options.first?.id else {
            return
        }

        let isCurrentlyBlocked = app.options.contains { $0.isEnabled }
        if !isCurrentlyBlocked && vpnManager.vpnStatus == .invalid {
            requestVPNPermission()
            return
        }

        store.toggleOption(appId: appId, optionId: optionId, source: "blocking_status_card")

        if !isCurrentlyBlocked {
            blockSessionStartedAt = Date()
            blockSessionEndsAt = nextDefaultSessionEndDate()
        }
    }

    private func requestVPNPermission() {
        vpnManager.startVPN(source: "blocking_status_card.permission_request")
    }

    private func syncSessionEndDate() {
        if blockedAppIDs.isEmpty {
            blockSessionEndsAt = nil
            blockSessionStartedAt = nil
        } else if blockSessionEndsAt == nil || (blockSessionEndsAt ?? .distantPast) <= Date() {
            blockSessionStartedAt = blockSessionStartedAt ?? Date()
            blockSessionEndsAt = nextDefaultSessionEndDate()
        } else if blockSessionStartedAt == nil {
            blockSessionStartedAt = Date()
        }
    }

    private func nextDefaultSessionEndDate() -> Date {
        Date().addingTimeInterval(12 * 60 * 60)
    }

    private func openLimits() {
        if let app = store.app(for: "instagram") {
            onSelectApp(app)
        }
    }
}

private enum HomeDashboardPalette {
    static let background = Color(red: 0.0, green: 0.118, blue: 0.067)
    static let card = Color(red: 0.004, green: 0.102, blue: 0.059)
    static let border = Color(red: 0.282, green: 0.376, blue: 0.333)
    static let accent = Color(red: 0.675, green: 0.867, blue: 0.137)
    static let muted = Color(red: 0.647, green: 0.682, blue: 0.624)
    static let dock = Color(red: 0.016, green: 0.141, blue: 0.082).opacity(0.78)
}

private struct HomeLogo: View {
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

private struct HomeGreeting: View {
    let name: String
    let scale: CGFloat

    private var titleSize: CGFloat {
        min(36, max(27, 32.4 * scale))
    }

    private var subcopySize: CGFloat {
        min(19.8, max(15.3, 18 * scale))
    }

    private var headlineFont: Font {
        .system(size: titleSize, weight: .bold, design: .rounded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(1, 2 * scale)) {
            VStack(alignment: .leading, spacing: 0) {
                Text("you’ve got this,")
                    .font(headlineFont)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text("\(name)!")
                    .font(headlineFont)
                    .foregroundStyle(HomeDashboardPalette.accent)
                    .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .overlay(alignment: .bottomLeading) {
                        LimeScribble()
                            .frame(width: 82.8 * scale, height: 8.1 * scale)
                            .padding(.leading, 2)
                            .offset(y: 6 * scale)
                    }
                    .padding(.bottom, 5 * scale)
            }

            Text("you’re keeping social,\nnot scrolling")
                .font(.system(size: subcopySize, weight: .regular, design: .rounded))
                .foregroundStyle(HomeDashboardPalette.muted.opacity(0.92))
                .lineSpacing(-2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LimeScribble: View {
    var body: some View {
        Canvas { context, size in
            var first = Path()
            first.move(to: CGPoint(x: 2, y: size.height * 0.56))
            first.addQuadCurve(
                to: CGPoint(x: size.width - 4, y: size.height * 0.46),
                control: CGPoint(x: size.width * 0.46, y: -size.height * 0.12)
            )

            var second = Path()
            second.move(to: CGPoint(x: 9, y: size.height * 0.8))
            second.addQuadCurve(
                to: CGPoint(x: size.width - 9, y: size.height * 0.72),
                control: CGPoint(x: size.width * 0.48, y: size.height * 0.24)
            )

            context.stroke(first, with: .color(HomeDashboardPalette.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(second, with: .color(HomeDashboardPalette.accent.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

private struct HomeMountainBackdrop: View {
    var body: some View {
        SVGView(svgName: "home_mountains")
            .opacity(0.96)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }
}

private struct StreakCard: View {
    let currentStreakDays: Int
    let scale: CGFloat

    private var visualScale: CGFloat {
        min(1.06, max(0.9, scale))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16 * visualScale) {
            StreakFlameBadge(scale: visualScale)
                .frame(width: 86 * visualScale, height: 92 * visualScale)

            VStack(alignment: .leading, spacing: 8 * visualScale) {
                VStack(alignment: .leading, spacing: 2 * visualScale) {
                    headlineView

                    Text(supportingCopy)
                        .font(BubbleFonts.coolvetica(size: 13.6 * visualScale))
                        .foregroundStyle(HomeDashboardPalette.muted.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                StreakWeekProgress(completedDays: completedWeekDays, scale: visualScale)
                    .frame(height: 26 * visualScale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.leading, 21 * visualScale)
        .padding(.trailing, 20 * visualScale)
        .padding(.vertical, 8 * visualScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(streakCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                .strokeBorder(HomeDashboardPalette.border.opacity(0.82), lineWidth: 1.2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var streakCardBackground: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                    .fill(HomeDashboardPalette.card.opacity(0.9))

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                HomeDashboardPalette.accent.opacity(0.16),
                                HomeDashboardPalette.accent.opacity(0)
                            ],
                            center: .center,
                            startRadius: 2 * visualScale,
                            endRadius: 74 * visualScale
                        )
                    )
                    .frame(width: 160 * visualScale, height: 160 * visualScale)
                    .offset(x: -42 * visualScale, y: 18 * visualScale)
                    .allowsHitTesting(false)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.055),
                                Color.white.opacity(0)
                            ],
                            center: .center,
                            startRadius: 1 * visualScale,
                            endRadius: 130 * visualScale
                        )
                    )
                    .frame(width: 260 * visualScale, height: 150 * visualScale)
                    .offset(x: 94 * visualScale, y: -42 * visualScale)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous))
        }
    }

    @ViewBuilder
    private var headlineView: some View {
        if currentStreakDays > 0 {
            Text("\(currentStreakDays) day streak")
                .font(.system(size: 23.76 * visualScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        } else {
            Text("Start a streak")
                .font(.system(size: 24 * visualScale, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private var supportingCopy: String {
        currentStreakDays > 0 ? "keep it up!" : "Block one app today"
    }

    private var completedWeekDays: Int {
        min(max(currentStreakDays, 0), 6)
    }

    private var accessibilitySummary: String {
        if currentStreakDays > 0 {
            return "\(currentStreakDays) day streak. Keep it up."
        }
        return "Start a streak. Block one app today."
    }
}

private struct StreakFlameBadge: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            Ellipse()
                .fill(HomeDashboardPalette.accent.opacity(0.18))
                .frame(width: 48 * scale, height: 11 * scale)
                .blur(radius: 8 * scale)
                .offset(y: 39 * scale)

            StreakBadgeSparkles(scale: scale)

            StreakHexagon()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.022, green: 0.17, blue: 0.095),
                            Color(red: 0.003, green: 0.09, blue: 0.052)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: HomeDashboardPalette.accent.opacity(0.34), radius: 16 * scale)

            StreakHexagon()
                .stroke(
                    LinearGradient(
                        colors: [
                            HomeDashboardPalette.accent,
                            HomeDashboardPalette.accent.opacity(0.74)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3.2 * scale, lineJoin: .round)
                )
                .shadow(color: HomeDashboardPalette.accent.opacity(0.28), radius: 8 * scale)

            if let image = UIImage.homeDashboardResource(named: "home_streak_flame", fileExtension: "png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 39.74 * scale, height: 46.96 * scale)
            }
        }
        .padding(4 * scale)
        .accessibilityHidden(true)
    }
}

private struct StreakWeekProgress: View {
    let completedDays: Int
    let scale: CGFloat

    private let days = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        GeometryReader { proxy in
            let dotSize = 10 * scale
            let centerY = dotSize / 2
            let lineWidth = 3 * scale
            let availableWidth = max(1, proxy.size.width - dotSize)
            let step = availableWidth / CGFloat(max(days.count - 1, 1))
            let activeEndX = dotSize / 2 + step * CGFloat(max(completedDays - 1, 0))

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(HomeDashboardPalette.muted.opacity(0.42))
                    .frame(width: availableWidth, height: lineWidth)
                    .offset(x: dotSize / 2, y: centerY - lineWidth / 2)

                Capsule()
                    .fill(HomeDashboardPalette.accent.opacity(completedDays > 0 ? 0.86 : 0))
                    .frame(width: max(0, activeEndX - dotSize / 2), height: lineWidth)
                    .offset(x: dotSize / 2, y: centerY - lineWidth / 2)

                ForEach(days.indices, id: \.self) { index in
                    let x = dotSize / 2 + step * CGFloat(index)

                    Circle()
                        .fill(dotFill(for: index))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(dotBorder(for: index), lineWidth: 1.2 * scale)
                        )
                        .shadow(
                            color: isComplete(index) ? HomeDashboardPalette.accent.opacity(0.42) : .clear,
                            radius: 7 * scale
                        )
                        .position(x: x, y: centerY)

                    Text(days[index])
                        .font(BubbleFonts.coolvetica(size: 12 * scale))
                        .foregroundStyle(HomeDashboardPalette.muted.opacity(0.82))
                        .lineLimit(1)
                        .position(x: x, y: 20 * scale)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func isComplete(_ index: Int) -> Bool {
        index < completedDays
    }

    private func dotFill(for index: Int) -> Color {
        isComplete(index) ? HomeDashboardPalette.accent : .clear
    }

    private func dotBorder(for index: Int) -> Color {
        isComplete(index) ? HomeDashboardPalette.accent.opacity(0.78) : HomeDashboardPalette.muted.opacity(0.58)
    }
}

private struct StreakHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.28))
        path.closeSubpath()
        return path
    }
}

private struct StreakBadgeSparkles: View {
    let scale: CGFloat

    var body: some View {
        ZStack {
            sparkle(size: 3.2, x: -38, y: -17)
            sparkle(size: 2.2, x: -27, y: 23)
            sparkle(size: 2.7, x: 38, y: -24)
            sparkle(size: 1.8, x: 30, y: 8)
            sparkle(size: 1.6, x: -46, y: 12)
        }
    }

    private func sparkle(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(HomeDashboardPalette.accent)
            .frame(width: size * scale, height: size * scale)
            .shadow(color: HomeDashboardPalette.accent.opacity(0.5), radius: 4 * scale)
            .offset(x: x * scale, y: y * scale)
    }
}

private struct HomeBottomDock: View {
    let scale: CGFloat
    let onHome: () -> Void
    let onLimits: () -> Void
    let onSettings: () -> Void

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack {
            dockItem(label: "home", icon: "house", isSelected: true, action: onHome)
            dockItem(label: "limits", icon: "clock", isSelected: false, action: onLimits)
            dockItem(label: "settings", icon: "gearshape", isSelected: false, action: onSettings)
        }
        .padding(.horizontal, 30 * visualScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LiquidGlassDockBackground(cornerRadius: 24 * visualScale)
        )
    }

    private func dockItem(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3 * visualScale) {
                Image(systemName: icon)
                    .font(.system(size: 22 * visualScale, weight: .medium))
                Text(label)
                    .font(BubbleFonts.coolvetica(size: 13.5 * visualScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? HomeDashboardPalette.accent : HomeDashboardPalette.muted)
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
                            HomeDashboardPalette.accent.opacity(0.18),
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
        .shadow(color: HomeDashboardPalette.accent.opacity(0.08), radius: 18, y: -2)
    }

    @available(iOS 26.0, *)
    private var ios26Glass: some View {
        shape
            .fill(.clear)
            .glassEffect(
                .regular
                    .tint(HomeDashboardPalette.dock.opacity(0.58))
                    .interactive(),
                in: shape
            )
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            HomeDashboardPalette.card.opacity(0.48),
                            HomeDashboardPalette.dock.opacity(0.36)
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
                            HomeDashboardPalette.dock.opacity(0.86),
                            HomeDashboardPalette.card.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
    }
}

#if DEBUG
private struct HomeDashboardDebugOverlay: View {
    let layout: HomeDashboardLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.cyan.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .frame(width: layout.contentWidth, height: layout.contentHeight)
                .position(
                    x: layout.screenSize.width / 2,
                    y: layout.contentTopInset + layout.contentHeight / 2
                )

            Rectangle()
                .fill(.cyan.opacity(0.2))
                .frame(width: layout.screenSize.width, height: 1)
                .offset(y: layout.contentTopInset)

            Rectangle()
                .stroke(.mint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: layout.contentWidth, height: layout.dockHeight)
                .position(
                    x: layout.screenSize.width / 2,
                    y: layout.screenSize.height - layout.dockBottomPadding - layout.dockHeight / 2
                )

            Rectangle()
                .fill(.orange.opacity(0.25))
                .frame(width: layout.screenSize.width, height: 1)
                .offset(y: layout.screenSize.height - layout.safeAreaInsets.bottom)
        }
    }
}
#endif

private extension UIImage {
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

#Preview {
    HomeScreen(onSelectApp: { _ in }, onSignIn: {})
        .environment(AppStore())
        .environment(GridPositionStore())
        .environment(AuthStore())
        .environmentObject(VPNManager())
}
