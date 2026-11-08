import SwiftUI
import UIKit

struct LegacyBlockingDashboardApp: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    let isBlocked: Bool
    var isScheduled: Bool = false
}

enum LegacyBlockingVPNState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case permissionRequired
}

enum LegacyBlockingConnectionIndicatorState: Equatable {
    case disconnected
    case transitioning
    case connected
    case permissionRequired

    var statusColor: Color {
        switch self {
        case .disconnected:
            return LegacyBlockingCardStyle.offlineRed
        case .transitioning, .permissionRequired:
            return LegacyBlockingCardStyle.connectionYellow
        case .connected:
            return LegacyBlockingCardStyle.accent
        }
    }

    var accessibilityText: String {
        switch self {
        case .disconnected:
            return "VPN disconnected"
        case .transitioning:
            return "VPN connecting or disconnecting"
        case .connected:
            return "VPN connected"
        case .permissionRequired:
            return "VPN permission required"
        }
    }
}

extension LegacyBlockingVPNState {
    var connectionIndicatorState: LegacyBlockingConnectionIndicatorState {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting, .disconnecting:
            return .transitioning
        case .connected:
            return .connected
        case .permissionRequired:
            return .permissionRequired
        }
    }
}

enum LegacyBlockingRingState: Equatable {
    case empty
    case instagramOnly
    case tiktokOnly
    case both

    init(blockedAppIDs: Set<String>) {
        let hasInstagram = blockedAppIDs.contains("instagram")
        let hasTikTok = blockedAppIDs.contains("tiktok")

        switch (hasInstagram, hasTikTok) {
        case (false, false):
            self = .empty
        case (true, false):
            self = .instagramOnly
        case (false, true):
            self = .tiktokOnly
        case (true, true):
            self = .both
        }
    }

    init(apps: [LegacyBlockingDashboardApp]) {
        self.init(blockedAppIDs: Set(apps.filter(\.isBlocked).map(\.id)))
    }

    var isInstagramBlocked: Bool {
        self == .instagramOnly || self == .both
    }

    var isTikTokBlocked: Bool {
        self == .tiktokOnly || self == .both
    }

    var hasBlockedApp: Bool {
        self != .empty
    }

    var centerTitle: String {
        self == .both ? "UNBLOCK" : "BLOCK"
    }
}

struct LegacyBlockingStatusCard: View {
    let apps: [LegacyBlockingDashboardApp]
    let vpnState: LegacyBlockingVPNState
    let sessionEndsAt: Date?
    var onToggleApp: (String) -> Void
    var onRequestVPNPermission: () -> Void
    var onAddTimeWindow: () -> Void = {}
    var onEndScheduledWindow: (String) -> Void = { _ in }
    var onShowGuidedOnboarding: () -> Void = {}
    var guidedPracticeStep: GuidedPracticeCardStep? = nil
    var showsGuidedWindowsHomeCoachMark = false
    var onGuidedWindowsHomeCoachMarkTap: () -> Void = {}

    @State private var draggingAppID: String?
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var isDropTargeted = false

    private var hasBlockedApps: Bool {
        apps.contains { $0.isBlocked }
    }

    private var mode: LegacyBlockingCardMode {
        guard hasBlockedApps else { return .idle }
        switch vpnState {
        case .connected:
            return .active
        case .disconnected, .connecting, .disconnecting:
            return .starting
        case .permissionRequired:
            return .permissionRequired
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = LegacyBlockingCardLayout(actualSize: proxy.size)
            let ringState = LegacyBlockingRingState(apps: apps)
            let targetRadius = layout.dialSize * (isDropTargeted ? 0.35 : 0.29)
            let centerTitle = centerTitle(forDraggingAppID: draggingAppID, ringState: ringState)

            ZStack {
                LegacyBlockingMiniStatusControls(
                    mode: mode,
                    vpnState: vpnState,
                    onShowGuidedOnboarding: onShowGuidedOnboarding
                )
                    .scaleEffect(layout.visualScale)
                    .position(layout.miniControlsCenter)

                if mode == .permissionRequired {
                    vpnPermissionButton
                        .frame(width: layout.permissionButtonWidth)
                        .scaleEffect(layout.visualScale)
                        .position(layout.permissionButtonCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                LegacyRadialBlockDial(
                    mode: mode,
                    ringState: ringState,
                    isDragging: draggingAppID != nil,
                    isDropTargeted: isDropTargeted,
                    labelPrefix: draggingAppID == nil ? "drag to" : "release to",
                    centerTitle: centerTitle
                )
                .frame(width: layout.dialSize, height: layout.dialSize)
                .position(layout.dialCenter)

                Circle()
                    .strokeBorder(LegacyBlockingCardStyle.accent.opacity(isDropTargeted ? 0.22 : 0), lineWidth: 1.5)
                    .frame(width: targetRadius * 2, height: targetRadius * 2)
                    .position(layout.dialCenter)

                ForEach(apps) { app in
                    let origin = layout.tileCenter(for: app.id)
                    let dragOffset = dragOffsets[app.id] ?? .zero
                    let isDragging = draggingAppID == app.id
                    let isInstagram = app.id == "instagram"

                    LegacyPulsingTileChevrons(
                        direction: isInstagram ? .right : .left,
                        isLive: mode == .active || mode == .starting || draggingAppID != nil,
                        scale: layout.visualScale
                    )
                    .frame(width: layout.tileSize * 0.45, height: layout.tileSize * 0.42)
                    .position(layout.chevronCenter(for: app.id))
                    .opacity(isDragging ? 0 : 1)
                    .zIndex(0.5)

                    LegacyAppBlockTile(
                        app: app,
                        size: layout.tileSize,
                        isLive: mode == .active || mode == .starting,
                        isDragging: isDragging,
                        isDimmed: mode == .idle && draggingAppID == nil,
                        hasPermissionError: mode == .permissionRequired && app.isBlocked
                    )
                    .position(x: origin.x + dragOffset.width, y: origin.y + dragOffset.height)
                    .zIndex(isDragging ? 10 : 1)
                    .gesture(
                        dragGesture(
                            app: app,
                            startCenter: origin,
                            targetCenter: layout.dialCenter,
                            targetRadius: targetRadius
                        )
                    )
                    .onTapGesture {
                        if !app.isScheduled {
                            onToggleApp(app.id)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("nima.app.\(app.id)")
                    .accessibilityLabel("\(app.name.capitalized) \(app.isBlocked ? "blocked" : "not blocked")")
                    .accessibilityValue(app.isBlocked ? "enabled" : "disabled")
                    .accessibilityHint(app.isScheduled ? "Drag outward or to the center to end the current window" : (app.isBlocked ? "Double tap, drag outward, or drag to the center to unblock" : "Double tap or drag to the center to block"))

                    if app.isBlocked, let label = blockedLabel(for: app) {
                        LegacyBlockedAppStatusPill(text: label, scale: layout.visualScale)
                            .position(x: origin.x, y: origin.y + layout.tileSize * 0.58)
                            .opacity(isDragging ? 0 : 1)
                            .zIndex(3)
                            .accessibilityHidden(true)
                    }
                }

                LegacyDragInstructionRow(
                    text: mode == .permissionRequired
                        ? "allow VPN permission to activate blocking"
                        : "drag an app to block or unblock it",
                    isError: mode == .permissionRequired,
                    scale: layout.visualScale
                )
                .frame(width: layout.instructionWidth, height: layout.instructionHeight)
                .position(layout.instructionCenter)

                if let sessionEndsAt {
                    LegacyTimeRemainingPill(
                        endDate: sessionEndsAt,
                        scale: layout.visualScale
                    )
                        .position(layout.timePillCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    Button(action: onAddTimeWindow) {
                        LegacyAddTimeWindowPill(scale: layout.visualScale)
                    }
                    .buttonStyle(.plain)
                    .position(layout.timePillCenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

                    if showsGuidedWindowsHomeCoachMark {
                        Button(action: onGuidedWindowsHomeCoachMarkTap) {
                            LegacyBlockingGuidedCoachNima(text: "Want to schedule when your feeds are blocked? Press here")
                                .frame(width: min(layout.actualSize.width - 96, 352 * layout.visualScale))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("guided_windows.home.start")
                        .position(
                            x: layout.actualSize.width / 2,
                            y: max(54 * layout.visualScale, layout.timePillCenter.y - 70 * layout.visualScale)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(32)
                    }
                }

                if let guidedPracticeStep {
                    LegacyBlockingGuidedPracticeOverlay(step: guidedPracticeStep, layout: layout)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .allowsHitTesting(false)
                        .zIndex(30)
                }

                #if DEBUG
                if LegacyBlockingCardLayout.debugOverlayEnabled {
                    LegacyBlockingCardDebugOverlay(layout: layout)
                        .allowsHitTesting(false)
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBackground(mode: mode, isDragging: draggingAppID != nil))
            .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
            .overlay(cardBorder(mode: mode, cornerRadius: layout.cornerRadius))
            .overlay(cardInnerGlow(cornerRadius: layout.cornerRadius, scale: layout.visualScale))
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: draggingAppID)
            .animation(.easeInOut(duration: 0.22), value: mode)
        }
    }

    private func centerTitle(forDraggingAppID appID: String?, ringState: LegacyBlockingRingState) -> String {
        guard let appID,
              apps.first(where: { $0.id == appID })?.isBlocked == true else {
            return ringState.centerTitle
        }

        return "UNBLOCK"
    }

    private func blockedLabel(for app: LegacyBlockingDashboardApp) -> String? {
        switch app.id {
        case "instagram":
            return "REELS BLOCKED"
        case "tiktok":
            return "FYP BLOCKED"
        default:
            return "\(app.name) BLOCKED"
        }
    }

    private var vpnPermissionButton: some View {
        Button {
            onRequestVPNPermission()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text("VPN permission required")
                    .font(NimaFonts.inter(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Text("Allow")
                    .font(NimaFonts.inter(size: 14, weight: .bold))
                    .foregroundStyle(LegacyBlockingCardStyle.backgroundDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(LegacyBlockingCardStyle.accent)
                    .clipShape(Capsule())
            }
            .foregroundStyle(LegacyBlockingCardStyle.warning)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(LegacyBlockingCardStyle.warning.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LegacyBlockingCardStyle.warning.opacity(0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func dragGesture(
        app: LegacyBlockingDashboardApp,
        startCenter: CGPoint,
        targetCenter: CGPoint,
        targetRadius: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                draggingAppID = app.id
                dragOffsets[app.id] = value.translation
                let draggedCenter = CGPoint(
                    x: startCenter.x + value.translation.width,
                    y: startCenter.y + value.translation.height
                )
                isDropTargeted = distance(from: draggedCenter, to: targetCenter) <= targetRadius
            }
            .onEnded { value in
                let draggedCenter = CGPoint(
                    x: startCenter.x + value.translation.width,
                    y: startCenter.y + value.translation.height
                )
                let droppedInTarget = distance(from: draggedCenter, to: targetCenter) <= targetRadius

                let dragDistance = sqrt(
                    value.translation.width * value.translation.width +
                    value.translation.height * value.translation.height
                )
                let isUnblockDrag = droppedInTarget || (
                    app.isBlocked && isOutwardUnlockDrag(
                        translation: value.translation,
                        startCenter: startCenter,
                        targetCenter: targetCenter
                    ) && dragDistance > 24
                )

                if isUnblockDrag {
                    if app.isScheduled {
                        onEndScheduledWindow(app.id)
                    } else {
                        onToggleApp(app.id)
                    }
                }

                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    dragOffsets[app.id] = .zero
                    draggingAppID = nil
                    isDropTargeted = false
                }
            }
    }

    private func isOutwardUnlockDrag(
        translation: CGSize,
        startCenter: CGPoint,
        targetCenter: CGPoint
    ) -> Bool {
        let outwardX = startCenter.x - targetCenter.x
        let outwardY = startCenter.y - targetCenter.y
        let outwardLength = sqrt(outwardX * outwardX + outwardY * outwardY)
        guard outwardLength > 0 else { return false }

        let projectedDistance = (
            translation.width * outwardX +
            translation.height * outwardY
        ) / outwardLength

        return projectedDistance > 24
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return sqrt(dx * dx + dy * dy)
    }

    private func cardBackground(mode: LegacyBlockingCardMode, isDragging: Bool) -> some View {
        LegacyBlockingCardStyle.cardBackground
    }

    private func cardBorder(mode: LegacyBlockingCardMode, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.2),
                        LegacyBlockingCardStyle.accent.opacity(mode == .idle ? 0.16 : 0.42),
                        .white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func cardInnerGlow(cornerRadius: CGFloat, scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(LegacyBlockingCardStyle.accent.opacity(0.08), lineWidth: 10)
            .blur(radius: 12 * scale)
            .padding(5 * scale)
            .allowsHitTesting(false)
    }
}

private struct LegacyBlockingCardLayout {
    static let debugOverlayEnabled = false
    static let designSize = CGSize(width: 357, height: 367)

    private let space: ScaledDesignSpace

    init(actualSize: CGSize) {
        space = ScaledDesignSpace(
            designSize: LegacyBlockingCardLayout.designSize,
            actualSize: actualSize
        )
    }

    var visualScale: CGFloat {
        min(1.08, max(0.9, space.scale))
    }

    var actualSize: CGSize {
        space.actualSize
    }

    var cornerRadius: CGFloat {
        space.size(28)
    }

    var miniControlsCenter: CGPoint {
        space.point(x: 309, y: 31)
    }

    var permissionButtonCenter: CGPoint {
        space.point(x: 178.5, y: 66)
    }

    var permissionButtonWidth: CGFloat {
        space.size(286)
    }

    var dialCenter: CGPoint {
        space.point(x: 178.5, y: 158)
    }

    var tileCenterY: CGFloat {
        dialCenter.y
    }

    var dialSize: CGFloat {
        space.size(268)
    }

    var tileSize: CGFloat {
        space.size(74)
    }

    var instructionCenter: CGPoint {
        space.point(x: 178.5, y: 304)
    }

    var instructionWidth: CGFloat {
        space.size(318)
    }

    var instructionHeight: CGFloat {
        space.size(30)
    }

    var timePillCenter: CGPoint {
        space.point(x: 178.5, y: 340)
    }

    func tileCenter(for appID: String) -> CGPoint {
        switch appID {
        case "instagram":
            return space.point(x: 60, y: 158)
        case "tiktok":
            return space.point(x: 297, y: 158)
        default:
            return space.point(x: 178.5, y: 158)
        }
    }

    func chevronCenter(for appID: String) -> CGPoint {
        switch appID {
        case "instagram":
            return space.point(x: 95, y: 158)
        case "tiktok":
            return space.point(x: 262, y: 158)
        default:
            return space.point(x: 178.5, y: 158)
        }
    }
}

private struct LegacyBlockingGuidedPracticeOverlay: View {
    let step: GuidedPracticeCardStep
    let layout: LegacyBlockingCardLayout

    var body: some View {
        ZStack {
            if step == .dragTikTok {
                Circle()
                    .strokeBorder(.white.opacity(0.24), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )
                    .frame(width: layout.dialSize * 0.44, height: layout.dialSize * 0.44)
                    .position(layout.dialCenter)

                ForEach(["instagram", "tiktok"], id: \.self) { appID in
                    RoundedRectangle(cornerRadius: layout.tileSize * 0.24, style: .continuous)
                        .strokeBorder(LegacyBlockingCardStyle.accent.opacity(0.74), lineWidth: 3)
                        .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.45), radius: 10)
                        .frame(width: layout.tileSize * 1.15, height: layout.tileSize * 1.15)
                        .position(layout.tileCenter(for: appID))
                }
            }

            LegacyBlockingGuidedCoachNima(text: text)
                .frame(width: cardWidth)
                .position(x: layout.actualSize.width / 2, y: cardCenterY)
        }
        .frame(width: layout.actualSize.width, height: layout.actualSize.height)
    }

    private var text: String {
        switch step {
        case .ready:
            return "Ready to test? we'll guide you through a quick 30 second test"
        case .dragTikTok:
            return "Drag an app into the centre to block short form feeds"
        }
    }

    private var cardWidth: CGFloat {
        min(layout.actualSize.width - 64, 314 * layout.visualScale)
    }

    private var cardCenterY: CGFloat {
        max(42 * layout.visualScale, layout.dialCenter.y - layout.dialSize * 0.48)
    }
}

private struct LegacyBlockingGuidedCoachNima: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.01, green: 0.12, blue: 0.08))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white)
                )

            LegacyBlockingGuidedCoachTriangle()
                .fill(.white)
                .frame(width: 24, height: 15)
        }
        .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
    }
}

private struct LegacyBlockingGuidedCoachTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#if DEBUG
private struct LegacyBlockingCardDebugOverlay: View {
    let layout: LegacyBlockingCardLayout

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.cyan.opacity(0.24))
                .frame(width: layout.actualSize.width, height: 1)
                .position(x: layout.actualSize.width / 2, y: layout.tileCenterY)

            Circle()
                .stroke(.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: layout.dialSize, height: layout.dialSize)
                .position(layout.dialCenter)
        }
    }
}
#endif

struct LegacyLockStatusBadge: View {
    let mode: LegacyBlockingCardMode

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconFill)
                    .frame(width: 56, height: 56)

                Circle()
                    .strokeBorder(LegacyBlockingCardStyle.accent.opacity(mode == .idle ? 0.24 : 0.5), lineWidth: 7)
                    .frame(width: 56, height: 56)
                    .blur(radius: 0.2)

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(iconColor)
            }
            .shadow(color: iconColor.opacity(mode == .idle ? 0.08 : 0.35), radius: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(titlePrefix)
                    .font(NimaFonts.inter(size: 21, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(titleStatus)
                    .font(NimaFonts.inter(size: 31, weight: .black))
                    .foregroundStyle(statusColor)
                    .shadow(color: statusColor.opacity(mode == .idle ? 0 : 0.42), radius: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private var titlePrefix: String {
        switch mode {
        case .permissionRequired:
            return "blocking needs"
        default:
            return "blocking is"
        }
    }

    private var titleStatus: String {
        switch mode {
        case .idle:
            return "OFF"
        case .active:
            return "ACTIVE NOW"
        case .starting:
            return "STARTING"
        case .permissionRequired:
            return "VPN"
        }
    }

    private var iconName: String {
        switch mode {
        case .idle:
            return "lock.open.fill"
        case .active, .starting:
            return "lock.fill"
        case .permissionRequired:
            return "exclamationmark.shield.fill"
        }
    }

    private var iconFill: Color {
        switch mode {
        case .idle:
            return .white.opacity(0.08)
        case .permissionRequired:
            return LegacyBlockingCardStyle.warning.opacity(0.14)
        case .active, .starting:
            return LegacyBlockingCardStyle.accent.opacity(0.16)
        }
    }

    private var iconColor: Color {
        mode == .permissionRequired ? LegacyBlockingCardStyle.warning : LegacyBlockingCardStyle.accent
    }

    private var statusColor: Color {
        switch mode {
        case .idle:
            return .white.opacity(0.72)
        case .permissionRequired:
            return LegacyBlockingCardStyle.warning
        case .active, .starting:
            return LegacyBlockingCardStyle.accent
        }
    }
}

private struct LegacyBlockingMiniStatusControls: View {
    let mode: LegacyBlockingCardMode
    let vpnState: LegacyBlockingVPNState
    var onShowGuidedOnboarding: () -> Void

    private var indicatorState: LegacyBlockingConnectionIndicatorState {
        vpnState.connectionIndicatorState
    }

    var body: some View {
        Button(action: onShowGuidedOnboarding) {
            HStack(alignment: .center, spacing: 11) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.55), radius: 6)

                Image(systemName: mode == .permissionRequired ? "exclamationmark.circle" : "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(mode == .permissionRequired ? 0.78 : 0.58))
            }
            .frame(width: 56, height: 36, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Nima works")
        .accessibilityValue(accessibilityText)
        .accessibilityHint("Opens a short guide")
        .accessibilityIdentifier("blocking_card.how_it_works")
        .animation(.easeInOut(duration: 0.24), value: indicatorState)
    }

    private var statusColor: Color {
        indicatorState.statusColor
    }

    private var accessibilityText: String {
        indicatorState.accessibilityText
    }
}

struct LegacyTimeRemainingPill: View {
    let endDate: Date
    var scale: CGFloat = 1

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { timeline in
            HStack(spacing: 8 * visualScale) {
                Image(systemName: "clock")
                    .font(.system(size: 17 * visualScale, weight: .semibold))
                    .foregroundStyle(LegacyBlockingCardStyle.accent)

                Text("ends \(remainingText(at: timeline.date))")
                    .font(NimaFonts.inter(size: 17 * visualScale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 14 * visualScale)
            .padding(.vertical, 8 * visualScale)
            .background(
                Capsule()
                    .fill(LegacyBlockingCardStyle.accent.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LegacyBlockingCardStyle.accent.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.12), radius: 9, y: 4)
        }
    }

    private func remainingText(at date: Date) -> String {
        let remaining = max(0, endDate.timeIntervalSince(date))
        let totalMinutes = Int(ceil(remaining / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        }
        return "in \(minutes)m"
    }
}

private struct LegacyAddTimeWindowPill: View {
    var scale: CGFloat = 1

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: 7.65 * visualScale) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16.1 * visualScale, weight: .bold))
                .foregroundStyle(LegacyBlockingCardStyle.accent)

            Text("add a time window")
                .font(NimaFonts.inter(size: 13.8 * visualScale, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 11.5 * visualScale)
        .padding(.vertical, 6.1 * visualScale)
        .background(
            Capsule()
                .fill(LegacyBlockingCardStyle.accent.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(LegacyBlockingCardStyle.accent.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.12), radius: 9, y: 4)
        .accessibilityLabel("Add a time window")
    }
}

struct LegacyRadialBlockDial: View {
    let mode: LegacyBlockingCardMode
    let ringState: LegacyBlockingRingState
    let isDragging: Bool
    let isDropTargeted: Bool
    let labelPrefix: String
    let centerTitle: String

    private var isLit: Bool {
        ringState.hasBlockedApp || isDragging
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let baseRingWidth = max(13, size * 0.055)
            let activeRingWidth = max(18, size * 0.074)
            let centerCircle = size * 0.48

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                LegacyBlockingCardStyle.glow.opacity(isLit ? 0.28 : 0.1),
                                LegacyBlockingCardStyle.ringBase.opacity(0.22),
                                .clear
                            ],
                            center: .center,
                            startRadius: size * 0.12,
                            endRadius: size * 0.56
                        )
                    )
                    .blur(radius: isDropTargeted ? 16 : 8)

                ForEach(0..<4) { index in
                    Circle()
                        .strokeBorder(
                            LegacyBlockingCardStyle.ringBase.opacity(0.18 + Double(index) * 0.035),
                            lineWidth: index == 0 ? 1.4 : 0.8
                        )
                        .frame(
                            width: size * (0.98 - CGFloat(index) * 0.12),
                            height: size * (0.98 - CGFloat(index) * 0.12)
                        )
                }

                dialTicks(size: size, isLit: isLit)

                Circle()
                    .stroke(
                        LegacyBlockingCardStyle.ringBase.opacity(isLit ? 0.34 : 0.22),
                        style: StrokeStyle(lineWidth: baseRingWidth, lineCap: .round)
                    )
                    .frame(width: size * 0.78, height: size * 0.78)
                    .blur(radius: 0.5)

                if ringState == .both {
                    activeRing(size: size, lineWidth: activeRingWidth)
                        .transition(.opacity)
                } else if ringState.isTikTokBlocked {
                    activeHalfRing(from: 0, to: 0.5, size: size, lineWidth: activeRingWidth)
                        .transition(.opacity)
                } else if ringState.isInstagramBlocked {
                    activeHalfRing(from: 0.5, to: 1, size: size, lineWidth: activeRingWidth)
                        .transition(.opacity)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                LegacyBlockingCardStyle.backgroundMid,
                                LegacyBlockingCardStyle.backgroundDeep
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: centerCircle * 0.7
                        )
                    )
                    .frame(width: centerCircle, height: centerCircle)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                    )

                centerCopy(size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(isDropTargeted ? 1.055 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: isDropTargeted)
        }
    }

    private func centerCopy(size: CGFloat) -> some View {
        let labelSize = max(16, size * 0.065)
        return VStack(spacing: max(1, size * 0.005)) {
            Text(labelPrefix)
                .font(NimaFonts.inter(size: labelSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(centerTitle)
                .font(NimaFonts.inter(size: max(31, size * 0.125), weight: .black))
                .foregroundStyle(mode == .permissionRequired ? LegacyBlockingCardStyle.warning : LegacyBlockingCardStyle.accent)
                .shadow(color: LegacyBlockingCardStyle.accent.opacity(isLit ? 0.5 : 0.16), radius: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("short-form feeds")
                .font(NimaFonts.inter(size: labelSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, size * 0.12)
    }

    private func dialTicks(size: CGFloat, isLit: Bool) -> some View {
        ZStack {
            ForEach(0..<72, id: \.self) { index in
                Capsule()
                    .fill(LegacyBlockingCardStyle.accent.opacity(isLit ? tickOpacity(for: index) : tickOpacity(for: index) * 0.34))
                    .frame(width: 1, height: index.isMultiple(of: 6) ? size * 0.035 : size * 0.018)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(index) * 5))
            }
        }
    }

    private func tickOpacity(for index: Int) -> Double {
        index.isMultiple(of: 6) ? 0.2 : 0.07
    }

    private func activeHalfRing(from start: CGFloat, to end: CGFloat, size: CGFloat, lineWidth: CGFloat) -> some View {
        let ringDiameter = size * 0.78
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        return ZStack {
            Circle()
                .trim(from: start, to: end)
                .stroke(LegacyBlockingCardStyle.accent.opacity(0.64), style: strokeStyle)
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(-90))
                .blur(radius: 10)
                .opacity(isDropTargeted ? 0.72 : 0.52)

            Circle()
                .trim(from: start, to: end)
                .stroke(
                    AngularGradient(
                        colors: [
                            LegacyBlockingCardStyle.accentHot,
                            LegacyBlockingCardStyle.accent,
                            LegacyBlockingCardStyle.accentHot,
                            LegacyBlockingCardStyle.accent
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: strokeStyle
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(-90))
                .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.52), radius: 8)
        }
    }

    private func activeRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        let ringDiameter = size * 0.78
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        return ZStack {
            Circle()
                .stroke(LegacyBlockingCardStyle.accent.opacity(0.64), style: strokeStyle)
                .frame(width: ringDiameter, height: ringDiameter)
                .blur(radius: 10)
                .opacity(isDropTargeted ? 0.72 : 0.52)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            LegacyBlockingCardStyle.accentHot,
                            LegacyBlockingCardStyle.accent,
                            LegacyBlockingCardStyle.accentHot,
                            LegacyBlockingCardStyle.accent
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: strokeStyle
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.52), radius: 8)
        }
    }

}

private struct LegacyBlockedAppStatusPill: View {
    let text: String
    var scale: CGFloat = 1

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        Text(text)
            .font(NimaFonts.inter(size: 13 * visualScale, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8 * visualScale)
            .padding(.vertical, 3 * visualScale)
            .background(
                Capsule()
                    .fill(.black.opacity(0.78))
            )
            .overlay(
                Capsule()
                    .strokeBorder(LegacyBlockingCardStyle.accent.opacity(0.52), lineWidth: 0.8)
            )
            .shadow(color: LegacyBlockingCardStyle.accent.opacity(0.62), radius: 7)
    }
}

struct LegacyAppBlockTile: View {
    let app: LegacyBlockingDashboardApp
    let size: CGFloat
    let isLive: Bool
    let isDragging: Bool
    let isDimmed: Bool
    let hasPermissionError: Bool

    var body: some View {
        LegacyExactBlockingAppIcon(
            platform: app.platform,
            size: size * 1.296
        )
        .saturation(app.isBlocked ? 0 : 1)
        .brightness(app.isBlocked ? -0.12 : 0)
        .contrast(app.isBlocked ? 0.9 : 1)
        .opacity(app.isBlocked ? 0.78 : 1)
        .shadow(
            color: LegacyBlockingCardStyle.accent.opacity(app.isBlocked ? 0.46 : 0),
            radius: app.isBlocked ? 15 : 0,
            y: app.isBlocked ? 2 : 0
        )
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .scaleEffect(isDragging ? 1.12 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: app.isBlocked)
    }
}

private struct LegacyExactBlockingAppIcon: View {
    let platform: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage.legacyBlockingCardResource(named: resourceName) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                SocialMediaIcon(platform: platform, size: size * 0.58)
            }
        }
        .frame(width: size, height: size)
    }

    private var resourceName: String {
        switch platform.lowercased() {
        case "instagram":
            return "home_instagram_blocking_icon"
        case "tiktok":
            return "home_tiktok_blocking_icon"
        default:
            return platform
        }
    }
}

private enum LegacyTileChevronDirection {
    case left
    case right
}

private struct LegacyPulsingTileChevrons: View {
    let direction: LegacyTileChevronDirection
    let isLive: Bool
    var scale: CGFloat = 1

    @State private var pulse = false

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: -1) {
            ForEach(0..<2, id: \.self) { index in
                Image(systemName: direction == .right ? "chevron.right" : "chevron.left")
                    .font(.system(size: 15 * visualScale, weight: .black))
                    .foregroundStyle(LegacyBlockingCardStyle.accent)
                    .opacity((pulse ? 0.78 : 0.38) - Double(index) * 0.18)
                    .shadow(
                        color: LegacyBlockingCardStyle.accent.opacity(isLive ? 0.42 : 0.16),
                        radius: (isLive ? 7 : 4) * visualScale
                    )
            }
        }
        .offset(x: pulse ? pulseOffset : -pulseOffset * 0.35)
        .opacity(isLive ? 1 : 0.55)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var pulseOffset: CGFloat {
        (direction == .right ? 4 : -4) * visualScale
    }
}

struct LegacyDragInstructionRow: View {
    let text: String
    var isError: Bool = false
    var scale: CGFloat = 1

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: 10 * visualScale) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "hand.point.up.left.fill")
                .font(.system(size: 17.1 * visualScale, weight: .semibold))
                .foregroundStyle(isError ? LegacyBlockingCardStyle.warning : LegacyBlockingCardStyle.accent)
                .shadow(color: LegacyBlockingCardStyle.accent.opacity(isError ? 0 : 0.4), radius: 6 * visualScale)

            Text(text)
                .font(NimaFonts.inter(size: 17.1 * visualScale, weight: .medium))
                .foregroundStyle(.white.opacity(isError ? 0.68 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

enum LegacyBlockingCardMode: Equatable {
    case idle
    case starting
    case active
    case permissionRequired
}

private enum LegacyBlockingCardStyle {
    static let accent = Color(red: 0.78, green: 0.98, blue: 0.15)
    static let accentHot = Color(red: 0.93, green: 1.0, blue: 0.28)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let connectionYellow = Color(red: 1.0, green: 0.82, blue: 0.16)
    static let offlineRed = Color(red: 1.0, green: 0.05, blue: 0.04)
    static let glow = Color(red: 0.48, green: 0.95, blue: 0.24)
    static let cardBackground = Color(red: 1 / 255, green: 26 / 255, blue: 15 / 255)
    static let backgroundTop = cardBackground
    static let backgroundMid = cardBackground
    static let backgroundDeep = Color(red: 0.002, green: 0.035, blue: 0.028)
    static let ringBase = Color(red: 0.018, green: 0.27, blue: 0.16)
}

private extension UIImage {
    static func legacyBlockingCardResource(named name: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
}
