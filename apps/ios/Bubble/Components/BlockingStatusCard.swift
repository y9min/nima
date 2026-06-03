import SwiftUI

struct BlockingDashboardApp: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String
    let isBlocked: Bool
}

enum BlockingVPNState: Equatable {
    case ready
    case starting
    case permissionRequired
}

struct BlockingStatusCard: View {
    let apps: [BlockingDashboardApp]
    let vpnState: BlockingVPNState
    let sessionEndsAt: Date?
    var onToggleApp: (String) -> Void
    var onRequestVPNPermission: () -> Void

    @State private var draggingAppID: String?
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var isDropTargeted = false

    private var hasBlockedApps: Bool {
        apps.contains { $0.isBlocked }
    }

    private var mode: BlockingCardMode {
        guard hasBlockedApps else { return .idle }
        switch vpnState {
        case .ready:
            return .active
        case .starting:
            return .starting
        case .permissionRequired:
            return .permissionRequired
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = BlockingCardLayout(actualSize: proxy.size)
            let targetRadius = layout.dialSize * (isDropTargeted ? 0.35 : 0.29)

            ZStack {
                BlockingMiniStatusControls(mode: mode)
                    .scaleEffect(layout.visualScale)
                    .position(layout.miniControlsCenter)

                if mode == .permissionRequired {
                    vpnPermissionButton
                        .frame(width: layout.permissionButtonWidth)
                        .scaleEffect(layout.visualScale)
                        .position(layout.permissionButtonCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                RadialBlockDial(
                    mode: mode,
                    isDragging: draggingAppID != nil,
                    isDropTargeted: isDropTargeted,
                    labelPrefix: draggingAppID == nil ? "drag to" : "release to",
                    progress: mode == .active ? 0.76 : 0
                )
                .frame(width: layout.dialSize, height: layout.dialSize)
                .position(layout.dialCenter)

                Circle()
                    .strokeBorder(BlockingCardStyle.accent.opacity(isDropTargeted ? 0.22 : 0), lineWidth: 1.5)
                    .frame(width: targetRadius * 2, height: targetRadius * 2)
                    .position(layout.dialCenter)

                ForEach(apps) { app in
                    let origin = layout.tileCenter(for: app.id)
                    let dragOffset = dragOffsets[app.id] ?? .zero
                    let isDragging = draggingAppID == app.id
                    let isInstagram = app.id == "instagram"

                    PulsingTileChevrons(
                        direction: isInstagram ? .right : .left,
                        isLive: mode == .active || mode == .starting || draggingAppID != nil,
                        scale: layout.visualScale
                    )
                    .frame(width: layout.tileSize * 0.45, height: layout.tileSize * 0.42)
                    .position(layout.chevronCenter(for: app.id))
                    .opacity(isDragging ? 0 : 1)
                    .zIndex(0.5)

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
                        if app.isBlocked {
                            onToggleApp(app.id)
                        }
                    }
                    .accessibilityLabel("\(app.name.capitalized) \(app.isBlocked ? "blocked" : "not blocked")")
                    .accessibilityHint(app.isBlocked ? "Double tap to stop blocking" : "Drag to the center to block")
                }

                DragInstructionRow(
                    text: mode == .permissionRequired
                        ? "allow VPN permission to activate blocking"
                        : "drag an app to block or unblock it",
                    isError: mode == .permissionRequired,
                    scale: layout.visualScale
                )
                .frame(width: layout.instructionWidth, height: layout.instructionHeight)
                .position(layout.instructionCenter)

                if showsTimePill {
                    TimeRemainingPill(
                        endDate: sessionEndsAt ?? defaultSessionEndDate,
                        scale: layout.visualScale
                    )
                        .position(layout.timePillCenter)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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

    private func header(width: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: max(14, width * 0.04)) {
                LockStatusBadge(mode: mode)

                Spacer(minLength: 8)

                if showsTimePill {
                    TimeRemainingPill(endDate: sessionEndsAt ?? defaultSessionEndDate)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                LockStatusBadge(mode: mode)
                if showsTimePill {
                    TimeRemainingPill(endDate: sessionEndsAt ?? defaultSessionEndDate)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var showsTimePill: Bool {
        mode == .active || mode == .starting
    }

    private var defaultSessionEndDate: Date {
        Date().addingTimeInterval(12 * 60 * 60)
    }

    private var vpnPermissionButton: some View {
        Button {
            onRequestVPNPermission()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text("VPN permission required")
                    .font(BubbleFonts.coolvetica(size: 15))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Text("Allow")
                    .font(BubbleFonts.coolvetica(size: 14))
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

    private func dialZone(width: CGFloat, height: CGFloat, dialSize: CGFloat, tileSize: CGFloat) -> some View {
        GeometryReader { proxy in
            let zoneSize = proxy.size
            let center = CGPoint(x: zoneSize.width / 2, y: zoneSize.height * 0.52)
            let targetRadius = dialSize * (isDropTargeted ? 0.35 : 0.29)

            ZStack {
                RadialBlockDial(
                    mode: mode,
                    isDragging: draggingAppID != nil,
                    isDropTargeted: isDropTargeted,
                    labelPrefix: draggingAppID == nil ? "drag to" : "release to",
                    progress: mode == .active ? 0.76 : 0
                )
                .frame(width: dialSize, height: dialSize)
                .position(center)
                .overlay(
                    Circle()
                        .strokeBorder(BlockingCardStyle.accent.opacity(isDropTargeted ? 0.22 : 0), lineWidth: 1.5)
                        .frame(width: targetRadius * 2, height: targetRadius * 2)
                        .position(center)
                )

                ForEach(apps) { app in
                    let origin = tileCenter(for: app, zone: zoneSize, tileSize: tileSize, ringCenterY: center.y)
                    let dragOffset = dragOffsets[app.id] ?? .zero
                    let isDragging = draggingAppID == app.id
                    let isInstagram = app.id == "instagram"

                    PulsingTileChevrons(
                        direction: isInstagram ? .right : .left,
                        isLive: mode == .active || mode == .starting || draggingAppID != nil
                    )
                    .frame(width: tileSize * 0.45, height: tileSize * 0.42)
                    .position(
                        x: origin.x + (isInstagram ? tileSize * 0.44 : -tileSize * 0.44),
                        y: origin.y
                    )
                    .opacity(isDragging ? 0 : 1)
                    .zIndex(0.5)

                    AppBlockTile(
                        app: app,
                        size: tileSize,
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
                            targetCenter: center,
                            targetRadius: targetRadius
                        )
                    )
                    .onTapGesture {
                        if app.isBlocked {
                            onToggleApp(app.id)
                        }
                    }
                    .accessibilityLabel("\(app.name.capitalized) \(app.isBlocked ? "blocked" : "not blocked")")
                    .accessibilityHint(app.isBlocked ? "Double tap to stop blocking" : "Drag to the center to block")
                }
            }
        }
    }

    private func tileCenter(for app: BlockingDashboardApp, zone: CGSize, tileSize: CGFloat, ringCenterY: CGFloat) -> CGPoint {
        let y = ringCenterY
        switch app.id {
        case "instagram":
            return CGPoint(x: max(tileSize * 0.52, zone.width * 0.105), y: y)
        case "tiktok":
            return CGPoint(x: min(zone.width - tileSize * 0.52, zone.width * 0.895), y: y)
        default:
            return CGPoint(x: zone.width / 2, y: zone.height * 0.82)
        }
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

                if droppedInTarget && !app.isBlocked {
                    onToggleApp(app.id)
                } else if app.isBlocked && !droppedInTarget && dragDistance > 24 {
                    onToggleApp(app.id)
                }

                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    dragOffsets[app.id] = .zero
                    draggingAppID = nil
                    isDropTargeted = false
                }
            }
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return sqrt(dx * dx + dy * dy)
    }

    private func cardBackground(mode: BlockingCardMode, isDragging: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    BlockingCardStyle.backgroundTop,
                    BlockingCardStyle.backgroundMid,
                    BlockingCardStyle.backgroundDeep
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    BlockingCardStyle.glow.opacity(mode == .idle ? 0.12 : 0.24),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: isDragging ? 330 : 250
            )

            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    BlockingCardStyle.accent.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
        }
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
        space.point(x: 178.5, y: 168)
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
        space.point(x: 178.5, y: 292)
    }

    var instructionWidth: CGFloat {
        space.size(318)
    }

    var instructionHeight: CGFloat {
        space.size(30)
    }

    var timePillCenter: CGPoint {
        space.point(x: 178.5, y: 337)
    }

    func tileCenter(for appID: String) -> CGPoint {
        switch appID {
        case "instagram":
            return space.point(x: 60, y: 168)
        case "tiktok":
            return space.point(x: 297, y: 168)
        default:
            return space.point(x: 178.5, y: 168)
        }
    }

    func chevronCenter(for appID: String) -> CGPoint {
        switch appID {
        case "instagram":
            return space.point(x: 95, y: 168)
        case "tiktok":
            return space.point(x: 262, y: 168)
        default:
            return space.point(x: 178.5, y: 168)
        }
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
                    .font(BubbleFonts.coolvetica(size: 21))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(titleStatus)
                    .font(.system(size: 31, weight: .black, design: .rounded))
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

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.55), radius: 6)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(mode == .permissionRequired ? 0.54 : 0.92))
                        .frame(width: 6, height: CGFloat(9 + index * 5))
                }
            }
            .accessibilityHidden(true)

            Image(systemName: mode == .permissionRequired ? "exclamationmark.circle" : "info.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(mode == .permissionRequired ? 0.78 : 0.58))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusColor: Color {
        switch mode {
        case .idle:
            return .white.opacity(0.46)
        case .permissionRequired:
            return BlockingCardStyle.warning
        case .active, .starting:
            return BlockingCardStyle.accent
        }
    }

    private var accessibilityText: String {
        switch mode {
        case .idle:
            return "Blocking is off"
        case .active:
            return "Blocking is active"
        case .starting:
            return "Blocking is starting"
        case .permissionRequired:
            return "VPN permission required"
        }
    }
}

struct TimeRemainingPill: View {
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
                    .foregroundStyle(BlockingCardStyle.accent)

                Text("ends \(remainingText(at: timeline.date))")
                    .font(BubbleFonts.coolvetica(size: 17 * visualScale))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 14 * visualScale)
            .padding(.vertical, 8 * visualScale)
            .background(
                Capsule()
                    .fill(BlockingCardStyle.accent.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(BlockingCardStyle.accent.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: BlockingCardStyle.accent.opacity(0.12), radius: 9, y: 4)
        }
    }

    private func remainingText(at date: Date) -> String {
        let remaining = max(0, endDate.timeIntervalSince(date))
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        }
        return "in \(minutes)m"
    }
}

struct RadialBlockDial: View {
    let mode: BlockingCardMode
    let isDragging: Bool
    let isDropTargeted: Bool
    let labelPrefix: String
    let progress: CGFloat

    private var isLit: Bool {
        mode == .active || mode == .starting || isDragging
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringWidth = max(8, size * 0.035)
            let centerCircle = size * 0.48

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BlockingCardStyle.glow.opacity(isLit ? 0.28 : 0.1),
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
                            BlockingCardStyle.accent.opacity(0.07 + Double(index) * 0.035),
                            lineWidth: index == 0 ? 1.4 : 0.8
                        )
                        .frame(
                            width: size * (0.98 - CGFloat(index) * 0.12),
                            height: size * (0.98 - CGFloat(index) * 0.12)
                        )
                }

                dialTicks(size: size)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                BlockingCardStyle.accent.opacity(0.06),
                                BlockingCardStyle.accent.opacity(isLit ? 0.2 : 0.1),
                                .white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: ringWidth
                    )
                    .frame(width: size * 0.78, height: size * 0.78)
                    .blur(radius: 0.5)

                if progress > 0 || isDragging {
                    topArc(size: size, lineWidth: ringWidth)
                        .transition(.opacity)
                }

                orbitLine(size: size)

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
                .font(BubbleFonts.coolvetica(size: labelSize))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("BLOCK")
                .font(BubbleFonts.coolvetica(size: max(31, size * 0.125)))
                .fontWeight(.bold)
                .foregroundStyle(mode == .permissionRequired ? BlockingCardStyle.warning : BlockingCardStyle.accent)
                .shadow(color: BlockingCardStyle.accent.opacity(isLit ? 0.5 : 0.16), radius: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text("short-form feeds")
                .font(BubbleFonts.coolvetica(size: labelSize))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, size * 0.12)
    }

    private func dialTicks(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<72, id: \.self) { index in
                Capsule()
                    .fill(BlockingCardStyle.accent.opacity(index.isMultiple(of: 6) ? 0.22 : 0.09))
                    .frame(width: 1, height: index.isMultiple(of: 6) ? size * 0.035 : size * 0.018)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(index) * 5))
            }
        }
    }

    private func topArc(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            BlockDialArcShape(startAngle: .degrees(205), endAngle: .degrees(325))
                .stroke(
                    BlockingCardStyle.accent,
                    style: StrokeStyle(lineWidth: lineWidth * 1.4, lineCap: .round)
                )
                .frame(width: size * 0.74, height: size * 0.74)
                .blur(radius: 10)
                .opacity(isDragging ? 0.55 : 0.42)

            BlockDialArcShape(startAngle: .degrees(205), endAngle: .degrees(325))
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.86),
                            BlockingCardStyle.accent,
                            BlockingCardStyle.accentHot
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 1.28, lineCap: .round)
                )
                .frame(width: size * 0.74, height: size * 0.74)
                .opacity(mode == .active || isDragging ? 1 : 0.52)
        }
    }

    private func orbitLine(size: CGFloat) -> some View {
        ZStack {
            BlockDialArcShape(startAngle: .degrees(45), endAngle: .degrees(138))
                .stroke(BlockingCardStyle.accent.opacity(0.62), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: size * 0.78, height: size * 0.78)

            BlockDialArcShape(startAngle: .degrees(42), endAngle: .degrees(140))
                .stroke(BlockingCardStyle.accent.opacity(0.24), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: size * 0.78, height: size * 0.78)
                .blur(radius: 5)
        }
        .rotationEffect(.degrees(180))
        .opacity(isLit ? 0.76 : 0.32)
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
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(tileFill)
                .overlay(tileHighlight)
                .overlay(tileBorder)

            SocialMediaIcon(platform: app.platform, size: size * 0.64)
                .saturation(isDimmed ? 0.58 : 1)
                .opacity(isDimmed ? 0.68 : 1)
        }
        .frame(width: size, height: size)
        .scaleEffect(isDragging ? 1.12 : 1)
        .shadow(color: glowColor.opacity(glowOpacity), radius: isDragging ? 22 : 14, y: isDragging ? 14 : 8)
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: app.isBlocked)
    }

    private var tileFill: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(app.isBlocked && isLive ? 0.16 : 0.1),
                BlockingCardStyle.tileDeep.opacity(0.96),
                .black.opacity(0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var tileHighlight: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .strokeBorder(
                hasPermissionError
                    ? BlockingCardStyle.warning.opacity(0.45)
                    : BlockingCardStyle.accent.opacity(app.isBlocked ? 0.58 : 0.16),
                lineWidth: app.isBlocked ? 1.2 : 0.8
            )
    }

    private var glowColor: Color {
        hasPermissionError ? BlockingCardStyle.warning : BlockingCardStyle.accent
    }

    private var glowOpacity: Double {
        if isDragging { return 0.62 }
        if app.isBlocked && isLive { return 0.54 }
        if app.isBlocked || hasPermissionError { return 0.28 }
        return 0.08
    }
}

private enum TileChevronDirection {
    case left
    case right
}

private struct PulsingTileChevrons: View {
    let direction: TileChevronDirection
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
                    .foregroundStyle(BlockingCardStyle.accent)
                    .opacity((pulse ? 0.78 : 0.38) - Double(index) * 0.18)
                    .shadow(
                        color: BlockingCardStyle.accent.opacity(isLive ? 0.42 : 0.16),
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
                .font(.system(size: 19 * visualScale, weight: .semibold))
                .foregroundStyle(isError ? BlockingCardStyle.warning : BlockingCardStyle.accent)
                .shadow(color: BlockingCardStyle.accent.opacity(isError ? 0 : 0.4), radius: 6 * visualScale)

            Text(text)
                .font(BubbleFonts.coolvetica(size: 19 * visualScale))
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

private struct BlockDialArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

private enum BlockingCardStyle {
    static let accent = Color(red: 0.78, green: 0.98, blue: 0.15)
    static let accentHot = Color(red: 0.93, green: 1.0, blue: 0.28)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let glow = Color(red: 0.48, green: 0.95, blue: 0.24)
    static let backgroundTop = Color(red: 0.006, green: 0.09, blue: 0.058)
    static let backgroundMid = Color(red: 0.015, green: 0.145, blue: 0.09)
    static let backgroundDeep = Color(red: 0.002, green: 0.035, blue: 0.028)
    static let ringBase = Color(red: 0.018, green: 0.27, blue: 0.16)
    static let tileDeep = Color(red: 0.035, green: 0.07, blue: 0.055)
}

#Preview("Blocking Status Card") {
    ZStack {
        Color.black.ignoresSafeArea()
        BlockingStatusCard(
            apps: [
                BlockingDashboardApp(id: "instagram", name: "Instagram", platform: "instagram", isBlocked: true),
                BlockingDashboardApp(id: "tiktok", name: "TikTok", platform: "tiktok", isBlocked: true)
            ],
            vpnState: .ready,
            sessionEndsAt: Date().addingTimeInterval(11 * 60 * 60 + 48 * 60),
            onToggleApp: { _ in },
            onRequestVPNPermission: {}
        )
        .padding(18)
    }
    .preferredColorScheme(.dark)
}
