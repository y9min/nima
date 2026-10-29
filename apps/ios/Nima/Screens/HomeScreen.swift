import FamilyControls
import SwiftUI
import NetworkExtension
import UIKit

struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(StreakStore.self) private var streakStore
    @Environment(TimeWindowStore.self) private var timeWindowStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @Environment(InstagramProtectionStore.self) private var instagramProtectionStore
    @Environment(TikTokProtectionStore.self) private var tiktokProtectionStore
    @Environment(\.sizeCategory) private var contentSizeCategory
    @EnvironmentObject private var vpnManager: VPNManager
    @State private var appIDPendingWindowEnd: String?
    @State private var isShowingInstagramPicker = false
    @State private var shouldEnableInstagramAfterSelection = false
    @State private var instagramSetupError: String?
    @State private var isShowingTikTokPicker = false
    @State private var shouldEnableTikTokAfterSelection = false
    @State private var tiktokSetupError: String?
    @State private var isShowingPauseMode = false
    @State private var pauseDurationMinutes = 10
    @State private var pauseNow = Date()
    @State private var pauseEndsAt: Date?
    @State private var pauseModeError: String?
    @State private var isShowingNothingToPauseAlert = false
    @State private var isShowingEditBlockers = false
    @AppStorage("blocking_card.instagram_visible", store: UserDefaults(suiteName: NimaConstants.appGroupID))
    private var showsInstagramOnCard = true
    @AppStorage("blocking_card.tiktok_visible", store: UserDefaults(suiteName: NimaConstants.appGroupID))
    private var showsTikTokOnCard = true
    private let pauseDefaults = UserDefaults(suiteName: NimaConstants.appGroupID)

    var onSelectApp: (BlockedApp) -> Void
    var onTimeWindows: (() -> Void)? = nil
    var onAddTimeWindow: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var onTrafficDashboard: (() -> Void)? = nil
    var onShowGuidedOnboarding: (() -> Void)? = nil
    var guidedPracticeCardStep: GuidedPracticeCardStep? = nil
    var showsGuidedWindowsHomeCoachMark = false
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
        .onAppear { refreshPauseMode() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPauseMode()
        }
        .task(id: pauseEndsAt) {
            guard let end = pauseEndsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled { refreshPauseMode() }
        }
        .sheet(isPresented: $isShowingPauseMode) {
            pauseModeSheet
                .presentationDetents([.height(445)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.13, green: 0.12, blue: 0.13))
        }
        .sheet(isPresented: $isShowingEditBlockers) {
            EditBlockersSheet(
                showsInstagram: showsInstagramOnCard,
                showsTikTok: showsTikTokOnCard,
                instagramMode: instagramProtectionStore.manualMode,
                tiktokMode: tiktokProtectionStore.manualMode
            ) { showsInstagram, showsTikTok, instagramMode, tiktokMode in
                showsInstagramOnCard = showsInstagram
                showsTikTokOnCard = showsTikTok
                if instagramMode != instagramProtectionStore.manualMode {
                    instagramProtectionStore.setManualMode(instagramMode, source: "edit_blockers")
                }
                if tiktokMode != tiktokProtectionStore.manualMode {
                    tiktokProtectionStore.setManualMode(tiktokMode, source: "edit_blockers")
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .alert("Nothing to pause yet", isPresented: $isShowingNothingToPauseAlert) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Turn on a blocker first. Then you can pause it for 5, 10, or 15 minutes.")
        }
        .alert("Pause Mode unavailable", isPresented: Binding(
            get: { pauseModeError != nil },
            set: { if !$0 { pauseModeError = nil } }
        )) {
            Button("OK", role: .cancel) { pauseModeError = nil }
        } message: {
            Text(pauseModeError ?? "Please try again.")
        }
        .toolbar(.hidden, for: .navigationBar)
        .familyActivityPicker(
            isPresented: $isShowingInstagramPicker,
            selection: Binding(
                get: { instagramProtectionStore.familySelection },
                set: { instagramProtectionStore.familySelection = $0 }
            )
        )
        .familyActivityPicker(
            isPresented: $isShowingTikTokPicker,
            selection: Binding(
                get: { tiktokProtectionStore.familySelection },
                set: { tiktokProtectionStore.familySelection = $0 }
            )
        )
        .onChange(of: isShowingInstagramPicker) { wasShowing, isShowing in
            guard wasShowing, !isShowing, shouldEnableInstagramAfterSelection else { return }
            shouldEnableInstagramAfterSelection = false
            guard !instagramProtectionStore.familySelection.applicationTokens.isEmpty else { return }
            instagramProtectionStore.setProtectionEnabled(
                true,
                source: "blocking_status_card.family_picker"
            )
        }
        .onChange(of: isShowingTikTokPicker) { wasShowing, isShowing in
            guard wasShowing, !isShowing, shouldEnableTikTokAfterSelection else { return }
            shouldEnableTikTokAfterSelection = false
            guard !tiktokProtectionStore.familySelection.applicationTokens.isEmpty else { return }
            tiktokProtectionStore.setProtectionEnabled(
                true,
                source: "blocking_status_card.family_picker"
            )
        }
        .alert("Instagram setup", isPresented: Binding(
            get: { instagramSetupError != nil },
            set: { if !$0 { instagramSetupError = nil } }
        )) {
            Button("OK", role: .cancel) { instagramSetupError = nil }
        } message: {
            Text(instagramSetupError ?? "Please try again.")
        }
        .alert("TikTok setup", isPresented: Binding(
            get: { tiktokSetupError != nil },
            set: { if !$0 { tiktokSetupError = nil } }
        )) {
            Button("OK", role: .cancel) { tiktokSetupError = nil }
        } message: {
            Text(tiktokSetupError ?? "Please try again.")
        }
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
                visibleAppIDs: visibleCardAppIDs,
                onEditBlockers: { isShowingEditBlockers = true },
                pauseEndsAt: dashboardApps.contains(where: \.isPaused) ? pauseEndsAt : nil,
                onToggleApp: { appId in
                    toggleBlockState(for: appId)
                },
                onOpenApp: { appId in
                    guard let app = store.app(for: appId) else { return }
                    onSelectApp(app)
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
                guidedPracticeStep: guidedPracticeCardStep,
                showsGuidedWindowsHomeCoachMark: showsGuidedWindowsHomeCoachMark,
                onGuidedWindowsHomeCoachMarkTap: {
                    openAddTimeWindow()
                }
            )
            .frame(width: layout.contentWidth, height: layout.blockerHeight)

            Color.clear.frame(height: layout.blockerToInsights)

            StreakActionRail(
                currentStreakDays: streakStore.currentStreak(),
                todayEarned: streakStore.hasEarnedToday(),
                scale: layout.scale,
                pauseEndsAt: pauseEndsAt,
                onPause: {
                    guard pauseEndsAt == nil else { return }
                    guard !activeUnpausedAppIDs.isEmpty else {
                        isShowingNothingToPauseAlert = true
                        return
                    }
                    isShowingPauseMode = true
                }
            )
            .frame(width: layout.contentWidth, height: layout.insightsHeight)

            Color.clear.frame(height: layout.bottomPadding)
        }
    }

    private var dashboardApps: [BlockingDashboardApp] {
        ["instagram", "tiktok"].compactMap { appId in
            guard let app = store.app(for: appId) else { return nil }
            let isScheduled = timeWindowStore.isAppScheduled(app.id)
            let isCurrentlyBlocked: Bool
            switch app.id {
            case "instagram": isCurrentlyBlocked = instagramProtectionStore.protectionEnabled || isScheduled
            case "tiktok": isCurrentlyBlocked = tiktokProtectionStore.protectionEnabled || isScheduled
            default: isCurrentlyBlocked = app.options.contains { $0.isEnabled } || isScheduled
            }
            return BlockingDashboardApp(
                id: app.id,
                name: app.name,
                platform: app.platform ?? app.id,
                isBlocked: isCurrentlyBlocked,
                isPaused: isCurrentlyBlocked && PauseModeState.isPaused(app.id, defaults: pauseDefaults, now: pauseNow),
                isScheduled: isScheduled,
                instagramMode: app.id == "instagram"
                    ? instagramProtectionStore.effectiveMode
                    : nil,
                tiktokMode: app.id == "tiktok"
                    ? tiktokProtectionStore.effectiveMode
                    : nil
            )
        }
    }

    private var visibleCardAppIDs: Set<String> {
        var result = Set<String>()
        if showsInstagramOnCard { result.insert("instagram") }
        if showsTikTokOnCard { result.insert("tiktok") }
        return result
    }

    private var blockedAppIDs: [String] {
        dashboardApps
            .filter { $0.isBlocked }
            .map(\.id)
            .sorted()
    }

    private var activeUnpausedAppIDs: Set<String> {
        Set(dashboardApps.filter { $0.isBlocked && !$0.isPaused }.map(\.id))
    }

    private func refreshPauseMode() {
        pauseNow = Date()
        let expiry = pauseDefaults?.object(forKey: NimaConstants.pauseModeExpiresAtKey) as? Date
        if let expiry, expiry > pauseNow {
            pauseEndsAt = expiry
        } else {
            pauseEndsAt = nil
            if expiry != nil { PauseModeState.clear(defaults: pauseDefaults) }
        }
        instagramProtectionStore.refreshPauseMode()
        tiktokProtectionStore.refreshPauseMode()
    }

    private func beginPauseMode() {
        let appIDs = activeUnpausedAppIDs
        guard let expiry = PauseModeState.start(
            appIDs: appIDs,
            windowIDs: timeWindowStore.activeWindowIDs,
            minutes: pauseDurationMinutes,
            defaults: pauseDefaults
        ) else { return }
        guard PauseModeMonitor.schedule(until: expiry) else {
            PauseModeState.clear(defaults: pauseDefaults)
            pauseModeError = "iOS couldn't schedule automatic blocking to return. Please try again."
            refreshPauseMode()
            return
        }
        PauseModeMonitor.clearClientScheduleShields()
        isShowingPauseMode = false
        refreshPauseMode()
    }

    private var pauseModeSheet: some View {
        VStack(spacing: 24) {
            Text("Pause Mode")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 20)

            HStack(spacing: 0) {
                ForEach([5, 10, 15], id: \.self) { minutes in
                    Button {
                        pauseDurationMinutes = minutes
                    } label: {
                        Text("\(minutes) mins")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background {
                                if pauseDurationMinutes == minutes {
                                    Capsule().fill(Color(red: 0.13, green: 0.12, blue: 0.13))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color(red: 0.22, green: 0.21, blue: 0.22)))

            Button(action: beginPauseMode) {
                Text("Continue")
                    .font(.system(size: 21))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Capsule().fill(Color(red: 0.04, green: 0.20, blue: 0.13)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 48)

            Text("Due to platform limitations, some features are unavailable in Clean Mode. Pause Mode briefly lifts restrictions so you can post, share stories, and more.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Stay social without getting stuck scrolling")
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            localOverride: appSettingsStore.normalizedDisplayName
        )
    }

    private var blockingVPNState: BlockingVPNState {
        let onlyClientProtection = dashboardApps.contains(where: { $0.isBlocked })
            && dashboardApps.filter(\.isBlocked).allSatisfy { ["instagram", "tiktok"].contains($0.id) }
        if onlyClientProtection {
            return .connected
        }
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
        if appId == "instagram" {
            guard !timeWindowStore.isAppScheduled(appId) else { return }
            if instagramProtectionStore.protectionEnabled {
                instagramProtectionStore.setProtectionEnabled(
                    false,
                    source: "blocking_status_card.drag"
                )
            } else {
                enableInstagramProtection()
            }
            return
        }
        if appId == "tiktok" {
            guard !timeWindowStore.isAppScheduled(appId) else { return }
            if tiktokProtectionStore.protectionEnabled {
                tiktokProtectionStore.setProtectionEnabled(
                    false,
                    source: "blocking_status_card.drag"
                )
            } else {
                enableTikTokProtection()
            }
            return
        }
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

    private func enableInstagramProtection() {
        Task {
            do {
                if instagramProtectionStore.authorizationStatus != .approved {
                    try await instagramProtectionStore.requestAuthorization()
                }

                guard instagramProtectionStore.familySelection.applicationTokens.isEmpty else {
                    instagramProtectionStore.setProtectionEnabled(
                        true,
                        source: "blocking_status_card.drag"
                    )
                    return
                }

                shouldEnableInstagramAfterSelection = true
                isShowingInstagramPicker = true
            } catch {
                instagramSetupError = "Nima needs Screen Time access before it can block the official Instagram app."
            }
        }
    }

    private func enableTikTokProtection() {
        Task {
            do {
                if tiktokProtectionStore.authorizationStatus != .approved {
                    try await tiktokProtectionStore.requestAuthorization()
                }

                guard tiktokProtectionStore.familySelection.applicationTokens.isEmpty else {
                    tiktokProtectionStore.setProtectionEnabled(
                        true,
                        source: "blocking_status_card.drag"
                    )
                    return
                }

                shouldEnableTikTokAfterSelection = true
                isShowingTikTokPicker = true
            } catch {
                tiktokSetupError = "Nima needs Screen Time access before it can block the official TikTok app."
            }
        }
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

            Text(scheduleSummary ?? "you’re keeping social, not scrolling")
                .font(.system(size: subcopySize, weight: .regular, design: .rounded))
                .foregroundStyle(HomeDashboardPalette.muted.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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

private struct StreakActionRail: View {
    let currentStreakDays: Int
    let todayEarned: Bool
    let scale: CGFloat
    let pauseEndsAt: Date?
    let onPause: () -> Void

    private var visualScale: CGFloat {
        min(1.06, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: 0) {
            railItem(
                title: currentStreakDays > 0 ? "\(currentStreakDays) day streak" : "Start a streak",
                subtitle: streakSubtitle,
                accessibilityHint: nil
            ) {
                StreakFlameBadge(scale: visualScale * 0.56)
                    .frame(width: 54 * visualScale, height: 54 * visualScale)
            }

            divider

            Button(action: onPause) {
                railItem(
                    title: "Pause Mode",
                    subtitle: pauseEndsAt == nil ? "Pause to post" : "Paused",
                    accessibilityHint: pauseEndsAt == nil ? "Choose a pause duration" : "Restrictions return automatically"
                ) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 25 * visualScale, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 54 * visualScale, height: 54 * visualScale)
                        .background(
                            RoundedRectangle(cornerRadius: 17 * visualScale, style: .continuous)
                                .fill(.white.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 17 * visualScale, style: .continuous)
                                .strokeBorder(HomeDashboardPalette.muted.opacity(0.42), lineWidth: 1.2)
                        )
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(pauseEndsAt == nil)

            divider

            railItem(
                title: "Hard Mode",
                subtitle: "Hold to activate",
                accessibilityHint: "Coming soon"
            ) {
                Image(systemName: "power")
                    .font(.system(size: 32 * visualScale, weight: .medium))
                    .foregroundStyle(hardModeColor)
                    .frame(width: 54 * visualScale, height: 54 * visualScale)
                    .background(Circle().fill(hardModeColor.opacity(0.07)))
                    .overlay(Circle().strokeBorder(hardModeColor.opacity(0.72), lineWidth: 1.5))
                    .shadow(color: hardModeColor.opacity(0.17), radius: 12 * visualScale)
            }
        }
        .padding(.horizontal, 8 * visualScale)
        .padding(.vertical, 13 * visualScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeDashboardPalette.card.opacity(0.9))
        .overlay(
            RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                .strokeBorder(HomeDashboardPalette.border.opacity(0.82), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous))
    }

    private func railItem<Icon: View>(
        title: String,
        subtitle: String,
        accessibilityHint: String?,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 0) {
            icon()
            Spacer(minLength: 4 * visualScale)
            Text(title)
                .font(.system(size: 14 * visualScale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(subtitle)
                .font(NimaFonts.coolvetica(size: 11.8 * visualScale))
                .foregroundStyle(HomeDashboardPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2 * visualScale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle).")
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var divider: some View {
        Rectangle()
            .fill(HomeDashboardPalette.border.opacity(0.55))
            .frame(width: 1, height: 75 * visualScale)
    }

    private var hardModeColor: Color {
        Color(red: 1, green: 0.38, blue: 0.43)
    }

    private var streakSubtitle: String {
        if todayEarned {
            return "Keep it up"
        }
        if currentStreakDays == 0 {
            return "Block today"
        }
        return "Keep it going"
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

private struct EditBlockersSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Bool, Bool, InstagramMode, TikTokMode) -> Void

    @State private var showsInstagram: Bool
    @State private var showsTikTok: Bool
    @State private var instagramMode: InstagramMode
    @State private var tiktokMode: TikTokMode

    private let background = Color(red: 0.0, green: 0.105, blue: 0.068)
    private let tile = Color(red: 0.035, green: 0.17, blue: 0.095)
    private let accent = AppChromePalette.accent
    private let muted = AppChromePalette.muted

    init(
        showsInstagram: Bool,
        showsTikTok: Bool,
        instagramMode: InstagramMode,
        tiktokMode: TikTokMode,
        onSave: @escaping (Bool, Bool, InstagramMode, TikTokMode) -> Void
    ) {
        self.onSave = onSave
        _showsInstagram = State(initialValue: showsInstagram)
        _showsTikTok = State(initialValue: showsTikTok)
        _instagramMode = State(initialValue: instagramMode)
        _tiktokMode = State(initialValue: tiktokMode)
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Text("choose which apps appear on Home\nand how they open")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.bottom, 28)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 30) {
                        appSection(title: "On Home", appIDs: shownAppIDs)
                        appSection(title: "Hidden", appIDs: hiddenAppIDs)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
                }
            }
            .padding(.top, 26)
        }
    }

    private var shownAppIDs: [String] {
        ["instagram", "tiktok"].filter { isShown($0) }
    }

    private var hiddenAppIDs: [String] {
        ["instagram", "tiktok"].filter { !isShown($0) }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(muted)
                    .frame(width: 46, height: 46)
                    .background(Circle().stroke(AppChromePalette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard changes")

            Spacer()

            Text("edit blockers")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button {
                onSave(showsInstagram, showsTikTok, instagramMode, tiktokMode)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(background)
                    .frame(width: 46, height: 46)
                    .background(accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save Home app changes")
        }
        .padding(.horizontal, 28)
    }

    private func appSection(title: String, appIDs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if appIDs.isEmpty {
                Text(title == "On Home" ? "No apps shown" : "No hidden apps")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(tile, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(appIDs, id: \.self) { appID in
                    appCard(appID)
                }
            }
        }
    }

    private func appCard(_ appID: String) -> some View {
        VStack(spacing: 0) {
            Button {
                toggleVisibility(appID)
            } label: {
                HStack(spacing: 14) {
                    SocialMediaIcon(platform: appID, size: 40)
                    Text(appID == "instagram" ? "Instagram" : "TikTok")
                        .font(.system(size: 21, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: isShown(appID) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(isShown(appID) ? accent : muted)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(appID == "instagram" ? "Instagram" : "TikTok") on Home")
            .accessibilityValue(isShown(appID) ? "Shown" : "Hidden")

            if isShown(appID) {
                modeRow(appID)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .background(tile, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func modeRow(_ appID: String) -> some View {
        if appID == "instagram" {
            Menu {
                ForEach(InstagramMode.allCases) { mode in
                    Button {
                        instagramMode = mode
                    } label: {
                        if instagramMode == mode {
                            Label(mode == .clean ? "Clean mode" : "DM Only mode", systemImage: "checkmark")
                        } else {
                            Text(mode == .clean ? "Clean mode" : "DM Only mode")
                        }
                    }
                }
            } label: {
                modeRowContent(value: instagramMode == .dmOnly ? "DM Only mode" : "Clean mode", showsChevron: true)
            }
            .accessibilityLabel("Instagram opens in \(instagramMode.title) mode")
        } else {
            Menu {
                ForEach(TikTokMode.allCases) { mode in
                    Button {
                        tiktokMode = mode
                    } label: {
                        if tiktokMode == mode {
                            Label(mode == .clean ? "Clean mode" : "DM Only mode", systemImage: "checkmark")
                        } else {
                            Text(mode == .clean ? "Clean mode" : "DM Only mode")
                        }
                    }
                }
            } label: {
                modeRowContent(value: tiktokMode == .dmOnly ? "DM Only mode" : "Clean mode", showsChevron: true)
            }
            .accessibilityLabel("TikTok opens in \(tiktokMode.title) mode")
        }
    }

    private func modeRowContent(value: String, showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Open in")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
        .frame(minHeight: 34)
        .contentShape(Rectangle())
    }

    private func isShown(_ appID: String) -> Bool {
        appID == "instagram" ? showsInstagram : showsTikTok
    }

    private func toggleVisibility(_ appID: String) {
        if appID == "instagram" {
            showsInstagram.toggle()
        } else {
            showsTikTok.toggle()
        }
    }
}

#Preview {
    HomeScreen(onSelectApp: { _ in })
        .environment(TikTokProtectionStore())
        .environment(AppStore())
        .environment(StreakStore(defaults: nil))
        .environment(TimeWindowStore())
        .environment(GridPositionStore())
        .environmentObject(VPNManager())
}
