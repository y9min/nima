import SwiftUI
import UIKit

enum BlockingAppModeBadge: Equatable {
    case clean
    case directMessages

    var systemImage: String {
        switch self {
        case .clean:
            return "sparkles"
        case .directMessages:
            return "message.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .clean:
            return "Clean mode"
        case .directMessages:
            return "DM only mode"
        }
    }
}

struct BlockingDashboardApp: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    let isBlocked: Bool
    var isPaused: Bool = false
    var isScheduled: Bool = false
    var instagramMode: InstagramMode? = nil
    var tiktokMode: TikTokMode? = nil
    var xMode: XMode? = nil

    var activeModeBadge: BlockingAppModeBadge? {
        guard isBlocked else { return nil }

        switch id {
        case "instagram":
            return instagramMode == .dmOnly ? .directMessages : .clean
        case "tiktok":
            return tiktokMode == .dmOnly ? .directMessages : .clean
        case "x":
            return xMode == .dmOnly ? .directMessages : .clean
        default:
            return nil
        }
    }
}

enum BlockingVPNState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case permissionRequired
}

enum BlockingConnectionIndicatorState: Equatable {
    case disconnected
    case transitioning
    case connected
    case permissionRequired

    var statusColor: Color {
        switch self {
        case .disconnected:
            return BlockingCardStyle.offlineRed
        case .transitioning, .permissionRequired:
            return BlockingCardStyle.connectionYellow
        case .connected:
            return BlockingCardStyle.accent
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

extension BlockingVPNState {
    var connectionIndicatorState: BlockingConnectionIndicatorState {
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

enum BlockingRingState: Equatable {
    case empty
    case instagramOnly
    case tiktokOnly
    case xOnly
    case both
    case instagramAndX
    case tiktokAndX
    case all

    init(blockedAppIDs: Set<String>) {
        let hasInstagram = blockedAppIDs.contains("instagram")
        let hasTikTok = blockedAppIDs.contains("tiktok")
        let hasX = blockedAppIDs.contains("x")

        switch (hasInstagram, hasTikTok, hasX) {
        case (false, false, false):
            self = .empty
        case (true, false, false):
            self = .instagramOnly
        case (false, true, false):
            self = .tiktokOnly
        case (false, false, true):
            self = .xOnly
        case (true, true, false):
            self = .both
        case (true, false, true):
            self = .instagramAndX
        case (false, true, true):
            self = .tiktokAndX
        case (true, true, true):
            self = .all
        }
    }

    init(apps: [BlockingDashboardApp]) {
        self.init(blockedAppIDs: Set(apps.filter(\.isBlocked).map(\.id)))
    }

    var isInstagramBlocked: Bool {
        self == .instagramOnly || self == .both || self == .instagramAndX || self == .all
    }

    var isTikTokBlocked: Bool {
        self == .tiktokOnly || self == .both || self == .tiktokAndX || self == .all
    }

    var isXBlocked: Bool {
        self == .xOnly || self == .instagramAndX || self == .tiktokAndX || self == .all
    }

    var hasBlockedApp: Bool {
        self != .empty
    }

    var centerTitle: String {
        blockedCount > 1 ? "UNBLOCK" : "BLOCK"
    }

    var blockedCount: Int {
        [isInstagramBlocked, isTikTokBlocked, isXBlocked].filter { $0 }.count
    }
}

enum BlockingTileSlot: Equatable {
    case left
    case right
    case upperLeft
    case upperRight
    case bottom

    static func resolve(for appID: String, visibleAppIDs: Set<String>) -> BlockingTileSlot {
        let visibleAppCount = visibleAppIDs.intersection(["instagram", "tiktok", "x"]).count

        if visibleAppCount >= 3 {
            switch appID {
            case "instagram":
                return .left
            case "tiktok":
                return .right
            case "x":
                return .bottom
            default:
                return .bottom
            }
        }

        if visibleAppCount == 1 {
            return .left
        }

        if visibleAppIDs.contains("x") {
            if visibleAppIDs.contains("instagram") {
                return appID == "instagram" ? .left : .right
            }
            if visibleAppIDs.contains("tiktok") {
                return appID == "x" ? .left : .right
            }
        }

        return appID == "tiktok" ? .right : .left
    }

    fileprivate var chevronDirection: TileChevronDirection {
        switch self {
        case .left:
            return .right
        case .right:
            return .left
        case .upperLeft:
            return .right
        case .upperRight:
            return .left
        case .bottom:
            return .up
        }
    }
}

struct BlockingStatusCard: View {
    let apps: [BlockingDashboardApp]
    let vpnState: BlockingVPNState
    let sessionEndsAt: Date?
    var visibleAppIDs: Set<String> = ["instagram", "tiktok", "x"]
    var onEditBlockers: () -> Void = {}
    var pauseEndsAt: Date? = nil
    var onToggleApp: (String) -> Void
    var onOpenApp: (String) -> Void = { _ in }
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

    private var hasVisibleApps: Bool {
        apps.contains { visibleAppIDs.contains($0.id) }
    }

    private var hasVisibleBlockedApps: Bool {
        apps.contains { visibleAppIDs.contains($0.id) && $0.isBlocked }
    }

    private var visibleRingApps: [BlockingDashboardApp] {
        let clockwiseAppIDs = ["tiktok", "x", "instagram"]
        return clockwiseAppIDs.compactMap { appID in
            apps.first { $0.id == appID && visibleAppIDs.contains(appID) }
        }
    }

    private var mode: BlockingCardMode {
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
            let layout = BlockingCardLayout(actualSize: proxy.size)
            let ringApps = visibleRingApps
            let ringState = BlockingRingState(apps: ringApps)
            let targetRadius = layout.dialSize * (isDropTargeted ? 0.35 : 0.29)
            let centerTitle = hasVisibleApps
                ? centerTitle(forDraggingAppID: draggingAppID, ringState: ringState)
                : (ringState.hasBlockedApp ? "ON" : "OFF")

            ZStack {
                Button(action: onEditBlockers) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit blockers")
                    .accessibilityIdentifier("blocking_card.edit_blockers")
                    .scaleEffect(layout.visualScale)
                    .position(layout.miniControlsCenter)
                    .zIndex(40)

                if mode == .permissionRequired {
                    vpnPermissionButton
                        .frame(width: layout.permissionButtonWidth)
                        .scaleEffect(layout.visualScale)
                        .position(layout.permissionButtonCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                RadialBlockDial(
                    mode: mode,
                    ringState: ringState,
                    segmentAppIDs: ringApps.map(\.id),
                    instagramPaused: apps.first(where: { $0.id == "instagram" })?.isPaused == true,
                    tiktokPaused: apps.first(where: { $0.id == "tiktok" })?.isPaused == true,
                    xPaused: apps.first(where: { $0.id == "x" })?.isPaused == true,
                    isDragging: draggingAppID != nil,
                    isDropTargeted: isDropTargeted,
                    labelPrefix: draggingAppID == nil ? "drag to" : "release to",
                    centerTitle: centerTitle
                )
                .frame(width: layout.dialSize, height: layout.dialSize)
                .position(layout.dialCenter)

                Circle()
                    .strokeBorder(BlockingCardStyle.accent.opacity(isDropTargeted ? 0.22 : 0), lineWidth: 1.5)
                    .frame(width: targetRadius * 2, height: targetRadius * 2)
                    .position(layout.dialCenter)

                ForEach(apps.filter { visibleAppIDs.contains($0.id) }) { app in
                    let slot = BlockingTileSlot.resolve(for: app.id, visibleAppIDs: visibleAppIDs)
                    let origin = layout.tileCenter(for: slot)
                    let dragOffset = dragOffsets[app.id] ?? .zero
                    let isDragging = draggingAppID == app.id

                    if !app.isBlocked {
                        PulsingTileChevrons(
                            direction: slot.chevronDirection,
                            isLive: mode == .active || mode == .starting || draggingAppID != nil,
                            isPaused: app.isPaused,
                            scale: layout.visualScale
                        )
                        .frame(width: layout.tileSize * 0.45, height: layout.tileSize * 0.42)
                        .position(layout.chevronCenter(for: slot))
                        .opacity(isDragging ? 0 : 1)
                        .zIndex(0.5)
                    }

                    AppBlockTile(
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
                        onOpenApp(app.id)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("nima.app.\(app.id)")
                    .accessibilityLabel(accessibilityLabel(for: app))
                    .accessibilityValue(app.isPaused ? "paused" : app.isBlocked ? "enabled" : "disabled")
                    .accessibilityHint(accessibilityHint(for: app))
                    .accessibilityAction(named: "Open \(app.name.capitalized)") {
                        onOpenApp(app.id)
                    }
                    .accessibilityAction(named: app.isBlocked ? "Disable protection" : "Enable protection") {
                        if app.isScheduled {
                            onEndScheduledWindow(app.id)
                        } else {
                            onToggleApp(app.id)
                        }
                    }
                }

                DragInstructionRow(
                    text: !hasVisibleApps
                        ? "use the menu to show apps on this card"
                        : mode == .permissionRequired
                        ? "allow VPN permission to activate blocking"
                        : (hasVisibleBlockedApps
                            ? "drag an app to unblock, tap it to open"
                            : "drag an app to block, tap it to open"),
                    isError: mode == .permissionRequired,
                    scale: layout.visualScale
                )
                .frame(width: layout.instructionWidth, height: layout.instructionHeight)
                .position(layout.instructionCenter)

                if let pauseEndsAt {
                    TimeRemainingPill(
                        endDate: pauseEndsAt,
                        label: "resumes",
                        isPaused: true,
                        scale: layout.visualScale
                    )
                    .position(layout.timePillCenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if let sessionEndsAt {
                    TimeRemainingPill(
                        endDate: sessionEndsAt,
                        scale: layout.visualScale
                    )
                        .position(layout.timePillCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    Button(action: onAddTimeWindow) {
                        AddTimeWindowPill(scale: layout.visualScale)
                    }
                    .buttonStyle(.plain)
                    .position(layout.timePillCenter)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

                    if showsGuidedWindowsHomeCoachMark {
                        Button(action: onGuidedWindowsHomeCoachMarkTap) {
                            BlockingGuidedCoachNima(text: "Want to schedule when your feeds are blocked? Press here")
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
                    BlockingGuidedPracticeOverlay(
                        step: guidedPracticeStep,
                        layout: layout,
                        visibleAppIDs: visibleAppIDs
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .allowsHitTesting(false)
                        .zIndex(30)
                }

                #if DEBUG
                if BlockingCardLayout.debugOverlayEnabled {
                    BlockingCardDebugOverlay(layout: layout)
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

    private func centerTitle(forDraggingAppID appID: String?, ringState: BlockingRingState) -> String {
        guard let appID,
              apps.first(where: { $0.id == appID })?.isBlocked == true else {
            return ringState.centerTitle
        }

        return "UNBLOCK"
    }

    private func accessibilityHint(for app: BlockingDashboardApp) -> String {
        if ["instagram", "tiktok", "x"].contains(app.id) {
            return app.isScheduled
                ? "Double tap to open \(app.name.capitalized). Drag to the center to end the current window."
                : "Double tap to open \(app.name.capitalized). Use the custom action or drag to change protection."
        }
        return app.isScheduled
            ? "Drag outward or to the center to end the current window"
            : (app.isBlocked
                ? "Double tap, drag outward, or drag to the center to unblock"
                : "Double tap or drag to the center to block")
    }

    private func accessibilityLabel(for app: BlockingDashboardApp) -> String {
        if app.isPaused {
            return "\(app.name.capitalized) protection paused"
        }
        guard app.isBlocked else {
            return "\(app.name.capitalized) not blocked"
        }
        if let badge = app.activeModeBadge {
            return "\(app.name.capitalized) blocked in \(badge.accessibilityLabel)"
        }
        return "\(app.name.capitalized) blocked"
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
                    .foregroundStyle(BlockingCardStyle.backgroundDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BlockingCardStyle.accent)
                    .clipShape(Capsule())
            }
            .foregroundStyle(BlockingCardStyle.warning)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(BlockingCardStyle.warning.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(BlockingCardStyle.warning.opacity(0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func dragGesture(
        app: BlockingDashboardApp,
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

    private func cardBackground(mode: BlockingCardMode, isDragging: Bool) -> some View {
        BlockingCardStyle.cardBackground
    }

    private func cardBorder(mode: BlockingCardMode, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.2),
                        BlockingCardStyle.accent.opacity(mode == .idle ? 0.16 : 0.42),
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
            .stroke(BlockingCardStyle.accent.opacity(0.08), lineWidth: 10)
            .blur(radius: 12 * scale)
            .padding(5 * scale)
            .allowsHitTesting(false)
    }
}

private struct BlockingCardLayout {
    static let debugOverlayEnabled = false
    static let designSize = CGSize(width: 357, height: 367)

    private let space: ScaledDesignSpace
    private let clusterVerticalOffset: CGFloat = -18

    init(actualSize: CGSize) {
        space = ScaledDesignSpace(
            designSize: BlockingCardLayout.designSize,
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
        space.point(x: 178.5, y: 158 + clusterVerticalOffset)
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

    func tileCenter(for slot: BlockingTileSlot) -> CGPoint {
        switch slot {
        case .left:
            return space.point(x: 60, y: 158 + clusterVerticalOffset)
        case .right:
            return space.point(x: 297, y: 158 + clusterVerticalOffset)
        // Three equal arcs start at 12 o'clock, so their centres sit at 2, 6 and 10 o'clock.
        case .upperLeft:
            return space.point(x: 75.9, y: 80.7 + clusterVerticalOffset)
        case .upperRight:
            return space.point(x: 281.1, y: 80.7 + clusterVerticalOffset)
        case .bottom:
            return space.point(x: 178.5, y: 258 + clusterVerticalOffset)
        }
    }

    func chevronCenter(for slot: BlockingTileSlot) -> CGPoint {
        switch slot {
        case .left:
            return space.point(x: 95, y: 158 + clusterVerticalOffset)
        case .right:
            return space.point(x: 262, y: 158 + clusterVerticalOffset)
        case .upperLeft:
            return space.point(x: 106.2, y: 96.7 + clusterVerticalOffset)
        case .upperRight:
            return space.point(x: 250.8, y: 96.7 + clusterVerticalOffset)
        case .bottom:
            return space.point(x: 178.5, y: 222 + clusterVerticalOffset)
        }
    }
}

private struct BlockingGuidedPracticeOverlay: View {
    let step: GuidedPracticeCardStep
    let layout: BlockingCardLayout
    let visibleAppIDs: Set<String>

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
                    let slot = BlockingTileSlot.resolve(for: appID, visibleAppIDs: visibleAppIDs)
                    RoundedRectangle(cornerRadius: layout.tileSize * 0.24, style: .continuous)
                        .strokeBorder(BlockingCardStyle.accent.opacity(0.74), lineWidth: 3)
                        .shadow(color: BlockingCardStyle.accent.opacity(0.45), radius: 10)
                        .frame(width: layout.tileSize * 1.15, height: layout.tileSize * 1.15)
                        .position(layout.tileCenter(for: slot))
                }
            }

            BlockingGuidedCoachNima(text: text)
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
            return "Drag an app into the centre to block infinite feeds"
        }
    }

    private var cardWidth: CGFloat {
        min(layout.actualSize.width - 64, 314 * layout.visualScale)
    }

    private var cardCenterY: CGFloat {
        max(42 * layout.visualScale, layout.dialCenter.y - layout.dialSize * 0.48)
    }
}

private struct BlockingGuidedCoachNima: View {
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

            BlockingGuidedCoachTriangle()
                .fill(.white)
                .frame(width: 24, height: 15)
        }
        .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
    }
}

private struct BlockingGuidedCoachTriangle: Shape {
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
private struct BlockingCardDebugOverlay: View {
    let layout: BlockingCardLayout

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

struct LockStatusBadge: View {
    let mode: BlockingCardMode

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconFill)
                    .frame(width: 56, height: 56)

                Circle()
                    .strokeBorder(BlockingCardStyle.accent.opacity(mode == .idle ? 0.24 : 0.5), lineWidth: 7)
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
            return BlockingCardStyle.warning.opacity(0.14)
        case .active, .starting:
            return BlockingCardStyle.accent.opacity(0.16)
        }
    }

    private var iconColor: Color {
        mode == .permissionRequired ? BlockingCardStyle.warning : BlockingCardStyle.accent
    }

    private var statusColor: Color {
        switch mode {
        case .idle:
            return .white.opacity(0.72)
        case .permissionRequired:
            return BlockingCardStyle.warning
        case .active, .starting:
            return BlockingCardStyle.accent
        }
    }
}

private struct BlockingMiniStatusControls: View {
    let mode: BlockingCardMode
    let vpnState: BlockingVPNState
    var onShowGuidedOnboarding: () -> Void

    private var indicatorState: BlockingConnectionIndicatorState {
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

struct TimeRemainingPill: View {
    let endDate: Date
    var label = "ends"
    var isPaused = false
    var scale: CGFloat = 1

    private var accent: Color {
        isPaused ? BlockingCardStyle.pausedAccent : BlockingCardStyle.accent
    }

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { timeline in
            HStack(spacing: 8 * visualScale) {
                Image(systemName: "clock")
                    .font(.system(size: 17 * visualScale, weight: .semibold))
                    .foregroundStyle(accent)

                Text("\(label) \(remainingText(at: timeline.date))")
                    .font(NimaFonts.inter(size: 17 * visualScale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 14 * visualScale)
            .padding(.vertical, 8 * visualScale)
            .background(
                Capsule()
                    .fill(accent.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(accent.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: accent.opacity(isPaused ? 0.09 : 0.12), radius: 9, y: 4)
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

private struct AddTimeWindowPill: View {
    var scale: CGFloat = 1

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: 7.65 * visualScale) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16.1 * visualScale, weight: .bold))
                .foregroundStyle(BlockingCardStyle.accent)

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
                .fill(BlockingCardStyle.accent.opacity(0.12))
        )
        .overlay(
            Capsule()
                .strokeBorder(BlockingCardStyle.accent.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: BlockingCardStyle.accent.opacity(0.12), radius: 9, y: 4)
        .accessibilityLabel("Add a time window")
    }
}

struct RadialBlockDial: View {
    let mode: BlockingCardMode
    let ringState: BlockingRingState
    let segmentAppIDs: [String]
    let instagramPaused: Bool
    let tiktokPaused: Bool
    let xPaused: Bool
    let isDragging: Bool
    let isDropTargeted: Bool
    let labelPrefix: String
    let centerTitle: String

    private var isLit: Bool {
        ringState.hasBlockedApp || isDragging
    }

    private var fullyPaused: Bool {
        ringState.hasBlockedApp
            && (!ringState.isInstagramBlocked || instagramPaused)
            && (!ringState.isTikTokBlocked || tiktokPaused)
            && (!ringState.isXBlocked || xPaused)
    }

    private var dialAccent: Color {
        fullyPaused ? BlockingCardStyle.pausedAccent : BlockingCardStyle.accent
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
                                (fullyPaused ? BlockingCardStyle.pausedAccent : BlockingCardStyle.glow)
                                    .opacity(isLit ? 0.28 : 0.1),
                                BlockingCardStyle.ringBase.opacity(0.22),
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
                            BlockingCardStyle.ringBase.opacity(0.18 + Double(index) * 0.035),
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
                        BlockingCardStyle.ringBase.opacity(isLit ? 0.34 : 0.22),
                        style: StrokeStyle(lineWidth: baseRingWidth, lineCap: .round)
                    )
                    .frame(width: size * 0.78, height: size * 0.78)
                    .blur(radius: 0.5)

                if ringState.hasBlockedApp {
                    activeSegmentedRing(
                        ringState: ringState,
                        segmentAppIDs: segmentAppIDs,
                        size: size,
                        lineWidth: activeRingWidth,
                        instagramPaused: instagramPaused,
                        tiktokPaused: tiktokPaused,
                        xPaused: xPaused
                    )
                    .transition(.opacity)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BlockingCardStyle.backgroundMid,
                                BlockingCardStyle.backgroundDeep
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
                .foregroundStyle(mode == .permissionRequired ? BlockingCardStyle.warning : dialAccent)
                .shadow(color: dialAccent.opacity(isLit ? (fullyPaused ? 0.38 : 0.5) : 0.16), radius: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("infinite feeds")
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
                    .fill(dialAccent.opacity(isLit ? tickOpacity(for: index) : tickOpacity(for: index) * 0.34))
                    .frame(width: 1, height: index.isMultiple(of: 6) ? size * 0.035 : size * 0.018)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(index) * 5))
            }
        }
    }

    private func tickOpacity(for index: Int) -> Double {
        index.isMultiple(of: 6) ? 0.2 : 0.07
    }

    private func activeSegmentedRing(
        ringState: BlockingRingState,
        segmentAppIDs: [String],
        size: CGFloat,
        lineWidth: CGFloat,
        instagramPaused: Bool,
        tiktokPaused: Bool,
        xPaused: Bool
    ) -> some View {
        let segmentCount = max(1, segmentAppIDs.count)
        let segmentLength = 1 / CGFloat(segmentCount)

        return ZStack {
            ForEach(Array(segmentAppIDs.enumerated()), id: \.element) { index, appID in
                if isRingAppBlocked(appID, ringState: ringState) {
                    let start = CGFloat(index) * segmentLength
                    let end = start + segmentLength
                    activeSegment(
                        from: start,
                        to: end,
                        size: size,
                        lineWidth: lineWidth,
                        isPaused: isRingAppPaused(
                            appID,
                            instagramPaused: instagramPaused,
                            tiktokPaused: tiktokPaused,
                            xPaused: xPaused
                        )
                    )
                }
            }
        }
    }

    private func isRingAppBlocked(_ appID: String, ringState: BlockingRingState) -> Bool {
        switch appID {
        case "instagram":
            return ringState.isInstagramBlocked
        case "tiktok":
            return ringState.isTikTokBlocked
        case "x":
            return ringState.isXBlocked
        default:
            return false
        }
    }

    private func isRingAppPaused(
        _ appID: String,
        instagramPaused: Bool,
        tiktokPaused: Bool,
        xPaused: Bool
    ) -> Bool {
        switch appID {
        case "instagram":
            return instagramPaused
        case "tiktok":
            return tiktokPaused
        case "x":
            return xPaused
        default:
            return false
        }
    }

    private func activeSegment(
        from start: CGFloat,
        to end: CGFloat,
        size: CGFloat,
        lineWidth: CGFloat,
        isPaused: Bool
    ) -> some View {
        let ringDiameter = size * 0.78
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        let color = isPaused ? BlockingCardStyle.pausedAccent : BlockingCardStyle.accent
        let hotColor = isPaused ? BlockingCardStyle.pausedAccentHot : BlockingCardStyle.accentHot

        return ZStack {
            Circle()
                .trim(from: start, to: end)
                .stroke(color.opacity(isPaused ? 0.52 : 0.64), style: strokeStyle)
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(-90))
                .blur(radius: 10)
                .opacity(isDropTargeted ? 0.72 : 0.52)

            Circle()
                .trim(from: start, to: end)
                .stroke(
                    AngularGradient(
                        colors: [
                            hotColor,
                            color,
                            hotColor,
                            color
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: strokeStyle
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(isPaused ? 0.39 : 0.52), radius: 8)
        }
    }

}

struct AppBlockTile: View {
    let app: BlockingDashboardApp
    let size: CGFloat
    let isLive: Bool
    let isDragging: Bool
    let isDimmed: Bool
    let hasPermissionError: Bool

    var body: some View {
        ZStack {
            ExactBlockingAppIcon(
                platform: app.platform,
                size: size * 1.49
            )
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let badge = visibleBadge {
                BlockingAppTileBadge(
                    systemImage: badge.systemImage,
                    color: badge.color,
                    size: size * 0.31
                )
                .offset(x: size * 0.11, y: -size * 0.11)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .scaleEffect(isDragging ? 1.12 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: app.isBlocked)
        .animation(.easeInOut(duration: 0.2), value: app.isPaused)
    }

    private var visibleBadge: BlockingAppTileBadge.Content? {
        if app.isPaused {
            return .init(systemImage: "pause.fill", color: BlockingCardStyle.warning)
        }
        guard let mode = app.activeModeBadge else { return nil }
        return .init(systemImage: mode.systemImage, color: BlockingCardStyle.accent)
    }
}

private struct BlockingAppTileBadge: View {
    struct Content {
        let systemImage: String
        let color: Color
    }

    let systemImage: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(BlockingCardStyle.backgroundDeep.opacity(0.96))

            Circle()
                .strokeBorder(color.opacity(0.46), lineWidth: 1)

            Image(systemName: systemImage)
                .font(.system(size: size * 0.46, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.3), radius: size * 0.28, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

private struct ExactBlockingAppIcon: View {
    let platform: String
    let size: CGFloat

    var body: some View {
        SocialMediaIcon(platform: platform, size: size * 0.58)
        .frame(width: size, height: size)
    }
}

private enum TileChevronDirection {
    case left
    case right
    case up
}

private struct PulsingTileChevrons: View {
    let direction: TileChevronDirection
    let isLive: Bool
    let isPaused: Bool
    var scale: CGFloat = 1

    @State private var pulse = false

    private var visualScale: CGFloat {
        min(1.08, max(0.9, scale))
    }

    private var accent: Color {
        isPaused ? BlockingCardStyle.pausedAccent : BlockingCardStyle.accent
    }

    var body: some View {
        Group {
            if direction == .up {
                VStack(spacing: -1) {
                    chevrons
                }
            } else {
                HStack(spacing: -1) {
                    chevrons
                }
            }
        }
        .offset(y: direction == .up ? (pulse ? -pulseOffset : pulseOffset * 0.35) : 0)
        .offset(x: direction == .up ? 0 : (pulse ? pulseOffset : -pulseOffset * 0.35))
        .opacity(isLive ? 1 : 0.55)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var chevrons: some View {
        ForEach(0..<2, id: \.self) { index in
            Image(systemName: chevronSystemName)
                .font(.system(size: 15 * visualScale, weight: .black))
                .foregroundStyle(accent)
                .opacity((pulse ? 0.78 : 0.38) - Double(index) * 0.18)
                .shadow(
                    color: accent.opacity(isPaused ? 0.30 : isLive ? 0.42 : 0.16),
                    radius: (isLive ? 7 : 4) * visualScale
                )
        }
    }

    private var chevronSystemName: String {
        switch direction {
        case .left:
            return "chevron.left"
        case .right:
            return "chevron.right"
        case .up:
            return "chevron.up"
        }
    }

    private var pulseOffset: CGFloat {
        switch direction {
        case .left:
            return -4 * visualScale
        case .right:
            return 4 * visualScale
        case .up:
            return 4 * visualScale
        }
    }
}

struct DragInstructionRow: View {
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
                .foregroundStyle(isError ? BlockingCardStyle.warning : BlockingCardStyle.accent)
                .shadow(color: BlockingCardStyle.accent.opacity(isError ? 0 : 0.4), radius: 6 * visualScale)

            Text(text)
                .font(NimaFonts.inter(size: 17.1 * visualScale, weight: .medium))
                .foregroundStyle(.white.opacity(isError ? 0.68 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

enum BlockingCardMode: Equatable {
    case idle
    case starting
    case active
    case permissionRequired
}

private enum BlockingCardStyle {
    static let accent = Color(red: 0.78, green: 0.98, blue: 0.15)
    static let accentHot = Color(red: 0.93, green: 1.0, blue: 0.28)
    static let pausedAccent = Color(red: 0.70, green: 0.88, blue: 0.18)
    static let pausedAccentHot = Color(red: 0.82, green: 0.94, blue: 0.27)
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
    static func blockingCardResource(named name: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        guard let path = Bundle.main.path(forResource: name, ofType: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
}

#Preview("Blocking Status Card") {
    ZStack {
        Color.black.ignoresSafeArea()
        BlockingStatusCard(
            apps: [
                BlockingDashboardApp(id: "instagram", name: "Instagram", platform: "instagram", isBlocked: true),
                BlockingDashboardApp(id: "tiktok", name: "TikTok", platform: "tiktok", isBlocked: true)
            ],
            vpnState: .connected,
            sessionEndsAt: Date().addingTimeInterval(11 * 60 * 60 + 48 * 60),
            onToggleApp: { _ in },
            onRequestVPNPermission: {}
        )
        .padding(18)
    }
    .preferredColorScheme(.dark)
}
