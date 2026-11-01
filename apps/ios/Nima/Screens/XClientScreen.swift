import FamilyControls
import SwiftUI
import UIKit

struct XClientScreen: View {
    @Environment(XProtectionStore.self) private var protectionStore
    @Environment(\.dismiss) private var dismiss
    let launchContext: ControlledClientLaunchContext

    @State private var session = XWebSession()
    @State private var deviceStyle = UIScreen.main.traitCollection.userInterfaceStyle
    @State private var isShowingAppPicker = false
    @State private var authorizationError: String?
    @State private var isNavigationMenuPresented = false
    @State private var isControlMenuPresented = false
    @State private var isOpenLinkPresented: Bool
    @State private var linkPasteError: String?
    @State private var controlPosition: CGPoint?
    @State private var controlGrabOffset: CGSize?
    @State private var isDraggingControl = false
    @State private var isControlIdle = false
    @State private var controlIdleTask: Task<Void, Never>?
    @State private var isLoginIntroPresented: Bool
    @State private var initialURL: URL?
    @State private var shouldOpenLinkAfterLoginIntro: Bool

    init(launchContext: ControlledClientLaunchContext = .standard) {
        self.launchContext = launchContext
        let initiallyShowsOpenLink = launchContext == .openLink
        let shouldPresentLoginIntro = !XLoginIntroduction.hasBeenSeen()
        _isOpenLinkPresented = State(
            initialValue: initiallyShowsOpenLink && !shouldPresentLoginIntro
        )
        _isLoginIntroPresented = State(initialValue: shouldPresentLoginIntro)
        _initialURL = State(
            initialValue: shouldPresentLoginIntro ? XNavigationPolicy.loginURL : nil
        )
        _shouldOpenLinkAfterLoginIntro = State(
            initialValue: initiallyShowsOpenLink && shouldPresentLoginIntro
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    if protectionStore.filteringHealth == .limited {
                        Button {
                            session.retryCleanMode()
                        } label: {
                            statusBanner(
                                icon: "exclamationmark.triangle.fill",
                                text: "Clean mode couldn't verify Following.",
                                actionTitle: "Try again",
                                backgroundColor: Color(red: 0.58, green: 0.35, blue: 0.12)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if protectionStore.filteringHealth == .slow {
                        Button {
                            session.reload()
                        } label: {
                            statusBanner(
                                icon: "clock.fill",
                                text: "X is taking longer to load.",
                                actionTitle: "Try again",
                                backgroundColor: Color(red: 0.20, green: 0.34, blue: 0.46)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if protectionStore.isActive, protectionStore.shieldStatus != .protected {
                        shieldSetupBanner
                    }

                    if !isLoginIntroPresented {
                        navigationHeader
                        XWebView(
                            session: session,
                            initialURL: initialURL,
                            mode: protectionStore.effectiveMode,
                            userInterfaceStyle: deviceStyle
                        )
                        .ignoresSafeArea(
                            .container,
                            edges: session.isConversationOpen ? [] : .bottom
                        )
                        .overlay {
                            if session.isAwaitingMessagesPresentation {
                                VStack(spacing: 14) {
                                    if session.messagesLoadTimedOut {
                                        Text("Messages couldn't load")
                                            .font(.system(size: 16, weight: .semibold))
                                        Button("Try again") { session.openMessages() }
                                            .font(.system(size: 15, weight: .semibold))
                                    } else {
                                        ProgressView().tint(chromeForeground)
                                        Text("Loading messages")
                                            .font(.system(size: 14))
                                            .foregroundStyle(chromeForeground.opacity(0.65))
                                    }
                                }
                                .foregroundStyle(chromeForeground)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(chromeBackground)
                            }
                        }
                    } else {
                        Color.black.ignoresSafeArea(.container, edges: .bottom)
                    }
                }

                if isControlMenuPresented {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { closeControlMenu() }
                        .transition(.opacity)
                        .zIndex(1)

                    controlMenu
                        .position(x: proxy.size.width / 2, y: resolvedMenuY(in: proxy.size))
                        .transition(.scale(scale: 0.68, anchor: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }

                if !isControlMenuPresented && !isLoginIntroPresented {
                    assistiveControl(in: proxy.size)
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                        .zIndex(3)
                }

                if isLoginIntroPresented {
                    Color.black.opacity(0.58).ignoresSafeArea().zIndex(4)
                    loginIntroModal.padding(.horizontal, 24).zIndex(5)
                }
            }
            .coordinateSpace(name: "xControlDragArea")
        }
        .background(chromeBackground)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(deviceStyle == .dark ? .dark : .light)
        .onAppear {
            refreshDeviceStyle()
            session.configure(store: protectionStore)
            protectionStore.refreshAuthorizationStatus()
            AnalyticsService.shared.capture("x_client_opened")
            scheduleControlFade()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshDeviceStyle()
        }
        .onChange(of: protectionStore.effectiveMode) { _, mode in
            session.updateMode(mode)
        }
        .onDisappear { controlIdleTask?.cancel() }
        .familyActivityPicker(
            isPresented: $isShowingAppPicker,
            selection: Binding(
                get: { protectionStore.familySelection },
                set: { protectionStore.familySelection = $0 }
            )
        )
        .onChange(of: isShowingAppPicker) { wasShowing, isShowing in
            guard wasShowing, !isShowing,
                  !protectionStore.familySelection.applicationTokens.isEmpty else { return }
            protectionStore.setProtectionEnabled(true, source: "x_client.family_picker")
        }
        .sheet(isPresented: $isOpenLinkPresented, onDismiss: {
            linkPasteError = nil
        }) {
            openLinkSheet
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: $isNavigationMenuPresented) {
            navigationMenu
                .presentationDetents([.height(455)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(34)
                .presentationBackground(chromeBackground)
        }
        .alert("Screen Time setup", isPresented: Binding(
            get: { authorizationError != nil },
            set: { if !$0 { authorizationError = nil } }
        )) {
            Button("OK", role: .cancel) { authorizationError = nil }
        } message: {
            Text(authorizationError ?? "Please try again.")
        }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(currentSurfaceTitle)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(chromeForeground)

            HStack {
                backButton
                Spacer()
                menuButton
            }
            .foregroundStyle(chromeForeground)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(chromeBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(chromeForeground.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var backButton: some View {
        Button {
            session.goBack { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(session.canGoBack ? "Back" : "Nima home")
    }

    private var menuButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isNavigationMenuPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 24, weight: .medium))
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Open X menu")
    }

    private var currentSurfaceTitle: String {
        guard let url = session.currentURL else { return "X" }
        let path = url.path.lowercased()
        if path.hasPrefix("/messages") || path.hasPrefix("/i/chat") { return "Messages" }
        if path.hasPrefix("/notifications") { return "Notifications" }
        if path.hasPrefix("/search") { return "Search" }
        if path.hasPrefix("/settings") || path.hasPrefix("/i/account") { return "Account" }
        if path.contains("/status/") { return "Post" }
        if path == "/home" { return "Following" }
        return "X"
    }

    private var chromeBackground: Color {
        deviceStyle == .dark ? .black : .white
    }

    private var chromeForeground: Color {
        deviceStyle == .dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.11)
    }

    private func refreshDeviceStyle() {
        deviceStyle = UIScreen.main.traitCollection.userInterfaceStyle
    }

    private var loginIntroModal: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.white.opacity(0.1), in: Circle())
                .padding(.bottom, 20)

            Text("Sign in as usual")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your X login details stay private and aren’t collected by Nima.")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Button(action: continueToXLogin) {
                Text("Continue")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.16, green: 0.48, blue: 0.30))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 390)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func continueToXLogin() {
        XLoginIntroduction.markSeen()
        initialURL = XNavigationPolicy.loginURL
        withAnimation(.easeInOut(duration: 0.22)) {
            isLoginIntroPresented = false
        }

        guard shouldOpenLinkAfterLoginIntro else { return }
        shouldOpenLinkAfterLoginIntro = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            isOpenLinkPresented = true
        }
    }

    private var navigationMenu: some View {
        VStack(spacing: 0) {
            HStack {
                Text("X")
                    .font(.system(size: 21, weight: .bold))
                Spacer()
                Button {
                    isNavigationMenuPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Close X menu")
            }
            .foregroundStyle(chromeForeground)
            .padding(.leading, 28)
            .padding(.trailing, 20)
            .frame(height: 58)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if protectionStore.effectiveMode == .clean {
                        navigationRow("Following", icon: "person.2.fill") { session.openFollowing() }
                        navigationRow("Search", icon: "magnifyingglass") { session.openSearch() }
                        navigationRow("Notifications", icon: "bell.fill") { session.openNotifications() }
                    }
                    navigationRow("Messages", icon: "message.fill") { session.openMessages() }
                    if protectionStore.effectiveMode == .clean {
                        navigationRow("Profile", icon: "person.crop.circle") { session.openProfile() }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .background(chromeBackground)
        .preferredColorScheme(deviceStyle == .dark ? .dark : .light)
    }

    private func navigationRow(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
            isNavigationMenuPresented = false
            action()
        } label: {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(chromeForeground)
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var openLinkSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Copy an X post, profile, or search link, then open it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: pasteAndOpenXLink) {
                    Label("Paste X link", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let linkPasteError {
                    Label(linkPasteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Open X link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isOpenLinkPresented = false
                        linkPasteError = nil
                    }
                }
            }
        }
        .preferredColorScheme(deviceStyle == .dark ? .dark : .light)
    }

    private func pasteAndOpenXLink() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation { linkPasteError = "Your clipboard doesn’t contain a link." }
            return
        }
        guard XNavigationPolicy.xURL(from: clipboardText) != nil else {
            withAnimation { linkPasteError = "That isn’t an X link. Copy a link from X and try again." }
            return
        }
        session.openLink(clipboardText)
        isOpenLinkPresented = false
        linkPasteError = nil
    }

    private var controlMenu: some View {
        ZStack {
            controlMenuButton(
                title: protectionStore.effectiveMode == .clean ? "DM only" : "Clean",
                icon: protectionStore.effectiveMode == .clean ? "message.fill" : "sparkles",
                isEnabled: true
            ) {
                controlHaptic()
                let next: XMode = protectionStore.effectiveMode == .clean ? .dmOnly : .clean
                protectionStore.setManualMode(next, source: "x_assistive_menu")
                session.activateMode(next)
                closeControlMenu()
            }
            .position(x: 82, y: 70)

            controlMenuButton(title: "Switch account", icon: "person.2.fill") {
                controlHaptic()
                session.logOut()
                closeControlMenu()
            }
            .position(x: 230, y: 70)

            controlMenuButton(title: "Refresh", icon: "arrow.clockwise") {
                controlHaptic()
                session.reload()
                closeControlMenu()
            }
            .position(x: 58, y: 178)

            controlMenuButton(
                title: "Open link",
                icon: "link",
                isEnabled: protectionStore.effectiveMode == .clean
            ) {
                controlHaptic()
                closeControlMenu()
                isOpenLinkPresented = true
            }
            .position(x: 254, y: 178)

            controlMenuButton(title: "Home", icon: "house.fill") {
                controlHaptic()
                dismiss()
            }
            .position(x: 156, y: 272)
        }
        .frame(width: 312, height: 332)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.5), radius: 28, y: 14)
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("X controls")
    }

    private func controlMenuButton(
        title: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .foregroundStyle(.white)
            .frame(width: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(NativeMenuControlButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.34)
    }

    private func assistiveControl(in size: CGSize) -> some View {
        let position = resolvedControlPosition(in: size)
        return Button {
            markControlActive()
            controlHaptic()
            withAnimation(.bouncy(duration: 0.38, extraBounce: 0.18)) {
                isControlMenuPresented.toggle()
            }
        } label: {
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.15, blue: 0.17))
                Circle().fill(Color(red: 0.37, green: 0.41, blue: 0.43)).padding(8)
                Circle().fill(Color(red: 0.62, green: 0.65, blue: 0.67)).padding(15)
                Circle().fill(Color.white).padding(22)
            }
            .frame(width: 60, height: 60)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75) }
            .shadow(color: .black.opacity(0.45), radius: isDraggingControl ? 14 : 9, y: isDraggingControl ? 8 : 4)
            .scaleEffect(isDraggingControl ? 1.09 : (isControlMenuPresented ? 0.94 : 1))
            .opacity(isControlIdle ? 0.38 : 0.94)
            .animation(.easeInOut(duration: 0.55), value: isControlIdle)
        }
        .buttonStyle(NativeAssistiveButtonStyle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("xControlDragArea"))
                .onChanged { value in
                    markControlActive()
                    if controlGrabOffset == nil {
                        controlGrabOffset = CGSize(
                            width: position.x - value.startLocation.x,
                            height: position.y - value.startLocation.y
                        )
                        isDraggingControl = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                    guard let controlGrabOffset else { return }
                    controlPosition = clampedControlPosition(
                        CGPoint(
                            x: value.location.x + controlGrabOffset.width,
                            y: value.location.y + controlGrabOffset.height
                        ),
                        in: size
                    )
                }
                .onEnded { _ in
                    controlGrabOffset = nil
                    isDraggingControl = false
                    guard let controlPosition else { return }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
                    withAnimation(.bouncy(duration: 0.42, extraBounce: 0.22)) {
                        self.controlPosition = CGPoint(
                            x: controlPosition.x < size.width / 2 ? 34 : size.width - 34,
                            y: controlPosition.y
                        )
                    }
                    scheduleControlFade()
                }
        )
        .position(position)
        .accessibilityLabel(isControlMenuPresented ? "Close X controls" : "Open X controls")
    }

    private func controlHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
    }

    private func markControlActive() {
        controlIdleTask?.cancel()
        if isControlIdle {
            withAnimation(.easeOut(duration: 0.18)) { isControlIdle = false }
        }
    }

    private func scheduleControlFade() {
        controlIdleTask?.cancel()
        guard !isControlMenuPresented else { return }
        controlIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled, !isControlMenuPresented else { return }
            withAnimation(.easeInOut(duration: 0.55)) { isControlIdle = true }
        }
    }

    private func closeControlMenu() {
        withAnimation(.bouncy(duration: 0.28, extraBounce: 0.08)) {
            isControlMenuPresented = false
        }
        scheduleControlFade()
    }

    private func resolvedControlPosition(in size: CGSize) -> CGPoint {
        controlPosition ?? CGPoint(x: size.width - 34, y: size.height * 0.68)
    }

    private func resolvedMenuY(in size: CGSize) -> CGFloat {
        let halfMenuHeight: CGFloat = 166
        return min(
            max(resolvedControlPosition(in: size).y, halfMenuHeight + 12),
            size.height - halfMenuHeight - 12
        )
    }

    private func clampedControlPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 34), size.width - 34),
            y: min(max(point.y, 42), size.height - 42)
        )
    }

    private var shieldSetupBanner: some View {
        Button {
            Task {
                do {
                    if protectionStore.authorizationStatus != .approved {
                        try await protectionStore.requestAuthorization()
                    }
                    if protectionStore.familySelection.applicationTokens.isEmpty {
                        isShowingAppPicker = true
                    } else {
                        protectionStore.setProtectionEnabled(true, source: "x_client.banner")
                    }
                } catch {
                    authorizationError = "Nima needs Screen Time access to block the official X app."
                }
            }
        } label: {
            statusBanner(icon: "shield.lefthalf.filled", text: "Finish setup to protect the official X app.")
        }
        .buttonStyle(.plain)
    }

    private func statusBanner(
        icon: String,
        text: String,
        actionTitle: String? = nil,
        backgroundColor: Color = Color(red: 0.16, green: 0.48, blue: 0.30)
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
            Text(text).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            if let actionTitle {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .bold))
                    .underline()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(backgroundColor)
    }
}

enum XLoginIntroduction {
    static func hasBeenSeen(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: NimaConstants.xLoginIntroSeenKey)
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: NimaConstants.xLoginIntroSeenKey)
    }
}

#Preview {
    NavigationStack {
        XClientScreen()
            .environment(XProtectionStore())
    }
}
