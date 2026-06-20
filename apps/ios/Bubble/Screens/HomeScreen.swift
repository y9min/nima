import SwiftUI
import NetworkExtension
import UIKit

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(StreakStore.self) private var streakStore
    @Environment(TimeWindowStore.self) private var timeWindowStore
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @Environment(\.sizeCategory) private var contentSizeCategory
    @EnvironmentObject private var vpnManager: VPNManager
    @State private var appIDPendingWindowEnd: String?

    var onSelectApp: (BlockedApp) -> Void
    var onTimeWindows: (() -> Void)? = nil
    var onAddTimeWindow: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var onTrafficDashboard: (() -> Void)? = nil
    var onShowGuidedOnboarding: (() -> Void)? = nil
    var guidedPracticeCardStep: GuidedPracticeCardStep? = nil
    var showsDock = true

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

                if showsDock {
                    AppBottomDock(
                        selected: .home,
                        scale: layout.scale,
                        onHome: {},
                        onWindows: openLimits,
                        onSettings: { onSettings?() }
                    )
                    .frame(width: layout.contentWidth, height: layout.dockHeight)
                    .padding(.bottom, layout.dockBottomPadding)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("End current window?", isPresented: isShowingEndWindowConfirmation) {
            Button("End Window", role: .destructive) {
                if let appIDPendingWindowEnd {
                    timeWindowStore.endActiveWindow(for: appIDPendingWindowEnd)
                }
                appIDPendingWindowEnd = nil
            }
            Button("Cancel", role: .cancel) {
                appIDPendingWindowEnd = nil
            }
        } message: {
            Text("This will end the current window. You can pause it instead in the windows tab.")
        }
    }

    private func homeContent(layout: HomeDashboardLayout) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.topPadding)

            HomeLogo()
                .frame(width: layout.logoSize.width * 0.9, height: layout.logoSize.height * 0.9)

            Color.clear.frame(height: layout.logoToGreeting)

            HomeGreeting(name: displayName, scale: layout.scale, scheduleSummary: timeWindowStore.activeSummary)
                .frame(width: layout.contentWidth, height: layout.greetingHeight, alignment: .leading)

            Color.clear.frame(height: layout.greetingToBlocker)

            BlockingStatusCard(
                apps: dashboardApps,
                vpnState: blockingVPNState,
                sessionEndsAt: blockerSessionEndsAt,
                onToggleApp: { appId in
                    toggleBlockState(for: appId)
                },
                onRequestVPNPermission: {
                    requestVPNPermission()
                },
                onAddTimeWindow: {
                    openAddTimeWindow()
                },
                onEndScheduledWindow: { appID in
                    appIDPendingWindowEnd = appID
                },
                onShowGuidedOnboarding: {
                    onShowGuidedOnboarding?()
                },
                guidedPracticeStep: guidedPracticeCardStep
            )
            .frame(width: layout.contentWidth, height: layout.blockerHeight)

            Color.clear.frame(height: layout.blockerToInsights)

            StreakCard(
                currentStreakDays: streakStore.currentStreak(),
                todayEarned: streakStore.hasEarnedToday(),
                weekDays: streakStore.weekStates(),
                scale: layout.scale
            )
            .frame(width: layout.contentWidth, height: layout.insightsHeight)

            Color.clear.frame(height: layout.bottomPadding)
        }
    }

    private var dashboardApps: [BlockingDashboardApp] {
        ["instagram", "tiktok"].compactMap { appId in
            guard let app = store.app(for: appId) else { return nil }
            let isScheduled = timeWindowStore.isAppScheduled(app.id)
            return BlockingDashboardApp(
                id: app.id,
                name: app.name,
                platform: app.platform ?? app.id,
                isBlocked: app.options.contains { $0.isEnabled } || isScheduled,
                isScheduled: isScheduled
            )
        }
    }

    private var blockedAppIDs: [String] {
        dashboardApps
            .filter { $0.isBlocked }
            .map(\.id)
            .sorted()
    }

    private var isShowingEndWindowConfirmation: Binding<Bool> {
        Binding(
            get: { appIDPendingWindowEnd != nil },
            set: { isPresented in
                if !isPresented {
                    appIDPendingWindowEnd = nil
                }
            }
        )
    }

    private var blockerSessionEndsAt: Date? {
        timeWindowStore.soonestActiveWindowEndDate()
    }

    private var displayName: String {
        AppSettingsStore.resolvedDisplayName(
            localOverride: appSettingsStore.normalizedDisplayName,
            userEmail: authStore.userEmail
        )
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
        guard !timeWindowStore.isAppScheduled(appId), !store.isAppScheduled(appId) else {
            return
        }

        let isCurrentlyBlocked = app.options.contains { $0.isEnabled }
        if !isCurrentlyBlocked && vpnManager.vpnStatus == .invalid {
            requestVPNPermission()
            return
        }

        store.toggleOption(appId: appId, optionId: optionId, source: "blocking_status_card")
    }

    private func requestVPNPermission() {
        vpnManager.startVPN(source: "blocking_status_card.permission_request")
    }

    private func openLimits() {
        onTimeWindows?()
    }

    private func openAddTimeWindow() {
        onAddTimeWindow?()
    }
}

private enum HomeDashboardPalette {
    static let background = AppChromePalette.background
    static let card = AppChromePalette.card
    static let border = AppChromePalette.border
    static let accent = AppChromePalette.accent
    static let muted = AppChromePalette.muted
    static let dock = AppChromePalette.dock
}

private struct HomeGreeting: View {
    let name: String
    let scale: CGFloat
    let scheduleSummary: String?

    private var titleSize: CGFloat {
        min(36, max(27, 32.4 * scale))
    }

    private var subcopySize: CGFloat {
        min(19.8, max(15.3, 18 * scale))
    }

    private var headlineFont: Font {
        .system(size: titleSize, weight: .bold, design: .rounded)
    }

    private var nameUnderlineWidth: CGFloat {
        let visibleCharacterCount = max(3, min(name.count, 16))
        return min(178 * scale, max(52 * scale, CGFloat(visibleCharacterCount) * titleSize * 0.58))
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
                            .frame(width: nameUnderlineWidth, height: 8.1 * scale)
                            .padding(.leading, 2)
                            .offset(y: 6 * scale)
                    }
                    .padding(.bottom, 5 * scale)
            }

            Text(scheduleSummary ?? "you’re keeping social,\nnot scrolling")
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
    let todayEarned: Bool
    let weekDays: [StreakWeekDayState]
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

                VStack(alignment: .leading, spacing: 3 * visualScale) {
                    Text("This week")
                        .font(BubbleFonts.coolvetica(size: 10.8 * visualScale))
                        .foregroundStyle(HomeDashboardPalette.muted.opacity(0.86))

                    StreakWeekProgress(days: weekDays, scale: visualScale)
                        .frame(height: 28 * visualScale)
                }
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
                .font(.system(size: 24 * visualScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private var supportingCopy: String {
        if todayEarned {
            return "Keep it up!"
        }
        if currentStreakDays == 0 {
            return "Start your streak by turning on any blocker"
        }
        return "Turn on a blocker to keep your streak"
    }

    private var accessibilitySummary: String {
        if currentStreakDays > 0 {
            return "\(currentStreakDays) day streak. \(supportingCopy)."
        }
        return "Start a streak. \(supportingCopy)."
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
    let days: [StreakWeekDayState]
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let dotSize = 10 * scale
            let centerY = 7 * scale
            let lineWidth = 2.6 * scale
            let count = max(days.count, 1)
            let availableWidth = max(1, proxy.size.width - dotSize)
            let step = availableWidth / CGFloat(max(count - 1, 1))

            ZStack(alignment: .topLeading) {
                ForEach(0..<max(days.count - 1, 0), id: \.self) { index in
                    let startX = dotSize / 2 + step * CGFloat(index)
                    let segmentWidth = max(0, step - dotSize - 4 * scale)

                    Capsule()
                        .fill(segmentFill(after: index))
                        .frame(width: segmentWidth, height: lineWidth)
                        .position(x: startX + step / 2, y: centerY)
                }

                ForEach(days.indices, id: \.self) { index in
                    let x = dotSize / 2 + step * CGFloat(index)
                    let day = days[index]

                    Circle()
                        .fill(dotFill(for: day.status))
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle()
                                .strokeBorder(dotBorder(for: day.status), lineWidth: 1.2 * scale)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(todayRing(for: day), lineWidth: 1.3 * scale)
                                .frame(width: dotSize + 6 * scale, height: dotSize + 6 * scale)
                        )
                        .shadow(
                            color: day.status == .earned ? HomeDashboardPalette.accent.opacity(0.42) : .clear,
                            radius: 7 * scale
                        )
                        .position(x: x, y: centerY)

                    Text(day.label)
                        .font(BubbleFonts.coolvetica(size: 12 * scale))
                        .foregroundStyle(labelColor(for: day.status))
                        .lineLimit(1)
                        .position(x: x, y: 22 * scale)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func segmentFill(after index: Int) -> Color {
        let current = days[index].status
        let next = days[index + 1].status
        if current == .earned && next == .earned {
            return HomeDashboardPalette.accent.opacity(0.82)
        }
        if current.isMuted || next.isMuted {
            return HomeDashboardPalette.muted.opacity(0.14)
        }
        return HomeDashboardPalette.muted.opacity(0.32)
    }

    private func dotFill(for status: StreakWeekDayStatus) -> Color {
        switch status {
        case .earned:
            return HomeDashboardPalette.accent
        case .missed, .todayPending:
            return HomeDashboardPalette.muted.opacity(0.12)
        case .future, .beforeTrackingStarted:
            return HomeDashboardPalette.muted.opacity(0.055)
        }
    }

    private func dotBorder(for status: StreakWeekDayStatus) -> Color {
        switch status {
        case .earned:
            return HomeDashboardPalette.accent.opacity(0.78)
        case .todayPending:
            return HomeDashboardPalette.accent.opacity(0.72)
        case .missed:
            return HomeDashboardPalette.muted.opacity(0.5)
        case .future, .beforeTrackingStarted:
            return HomeDashboardPalette.muted.opacity(0.22)
        }
    }

    private func todayRing(for day: StreakWeekDayState) -> Color {
        day.isToday ? HomeDashboardPalette.accent.opacity(0.62) : .clear
    }

    private func labelColor(for status: StreakWeekDayStatus) -> Color {
        switch status {
        case .earned:
            return .white.opacity(0.92)
        case .todayPending:
            return HomeDashboardPalette.accent.opacity(0.86)
        case .missed:
            return HomeDashboardPalette.muted.opacity(0.76)
        case .future, .beforeTrackingStarted:
            return HomeDashboardPalette.muted.opacity(0.38)
        }
    }
}

private extension StreakWeekDayStatus {
    var isMuted: Bool {
        self == .future || self == .beforeTrackingStarted
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

#Preview {
    HomeScreen(onSelectApp: { _ in })
        .environment(AppStore())
        .environment(StreakStore(defaults: nil))
        .environment(TimeWindowStore())
        .environment(GridPositionStore())
        .environment(AuthStore())
        .environmentObject(VPNManager())
}
