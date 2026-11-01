import FamilyControls
import SwiftUI
import UIKit

struct InstagramClientScreen: View {
    @Environment(InstagramProtectionStore.self) private var protectionStore
    @Environment(\.dismiss) private var dismiss
    let launchContext: InstagramLaunchContext
    var onGuidedPracticeCompleted: () -> Void
    var onGuidedPracticeCancelled: () -> Void

    @State private var session = InstagramWebSession()
    @State private var isShowingAppPicker = false
    @State private var authorizationError: String?
    @State private var isControlMenuPresented = false
    @State private var isOpenLinkPresented = false
    @State private var linkPasteError: String?
    @State private var controlPosition: CGPoint?
    @State private var controlGrabOffset: CGSize?
    @State private var isDraggingControl = false
    @State private var isControlIdle = false
    @State private var controlIdleTask: Task<Void, Never>?
    @State private var guidedExploreTask: Task<Void, Never>?
    @State private var isLoginIntroPresented: Bool
    @State private var initialInstagramURL: URL?
    @State private var shouldOpenLinkAfterLoginIntro: Bool
    @State private var isGuidedControlsExplanationPresented = false
    @State private var guidedCoachStep: InstagramGuidedCoachStep = .hidden
    @State private var hasCompletedGuidedPractice = false
    @State private var commentDraft = ""
    @State private var isSubmittingComment = false
    @State private var commentPostFailed = false
    @FocusState private var isCommentInputFocused: Bool

    init(
        launchContext: InstagramLaunchContext = .standard,
        onGuidedPracticeCompleted: @escaping () -> Void = {},
        onGuidedPracticeCancelled: @escaping () -> Void = {}
    ) {
        self.launchContext = launchContext
        self.onGuidedPracticeCompleted = onGuidedPracticeCompleted
        self.onGuidedPracticeCancelled = onGuidedPracticeCancelled
        let initiallyShowsOpenLink = launchContext == .openLink
        let shouldPresentLoginIntro = !InstagramLoginIntroduction.hasBeenSeen()
        _isOpenLinkPresented = State(
            initialValue: initiallyShowsOpenLink && !shouldPresentLoginIntro
        )
        _isLoginIntroPresented = State(initialValue: shouldPresentLoginIntro)
        _initialInstagramURL = State(
            initialValue: shouldPresentLoginIntro ? InstagramNavigationPolicy.loginURL : nil
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
                        statusBanner(
                            icon: "exclamationmark.triangle.fill",
                            text: "Instagram changed—Clean mode temporarily limited to DMs."
                        )
                    } else if (protectionStore.protectionEnabled || protectionStore.isScheduled),
                              protectionStore.shieldStatus != .protected {
                        shieldSetupBanner
                    }

                    if isLoginIntroPresented {
                        Color.black
                            .ignoresSafeArea(.container, edges: .bottom)
                    } else {
                        InstagramWebView(
                            session: session,
                            mode: protectionStore.effectiveMode,
                            initialURL: initialInstagramURL
                        )
                        .ignoresSafeArea(.container, edges: .bottom)
                    }
                }

                if isControlMenuPresented {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { closeControlMenu() }
                        .transition(.opacity)
                        .zIndex(1)

                    controlMenu
                        .position(
                            x: proxy.size.width / 2,
                            y: resolvedMenuY(in: proxy.size)
                        )
                        .transition(
                            .scale(scale: 0.68, anchor: .bottom)
                                .combined(with: .opacity)
                        )
                        .zIndex(2)
                }

                if session.isCommentComposerVisible && !isLoginIntroPresented {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        nativeCommentComposer
                    }
                    .zIndex(2)
                }

                if !isControlMenuPresented && !isLoginIntroPresented {
                    assistiveControl(in: proxy.size)
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                        .zIndex(3)
                }

                if isLoginIntroPresented {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .zIndex(4)

                    loginIntroModal
                        .padding(.horizontal, 24)
                        .zIndex(5)
                }

                if isGuidedControlsExplanationPresented {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .zIndex(6)

                    guidedControlsExplanationModal
                        .padding(.horizontal, 24)
                        .zIndex(7)
                }

                guidedPracticeCoachOverlay(in: proxy.size)
                    .zIndex(8)
            }
            .coordinateSpace(name: "controlDragArea")
        }
        .background(Color.black)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            session.configure(store: protectionStore)
            protectionStore.refreshAuthorizationStatus()
            AnalyticsService.shared.capture(
                "instagram_client_opened",
                properties: [
                    "mode": protectionStore.effectiveMode.rawValue,
                    "context": launchContext.analyticsName,
                ]
            )
            if isLoginIntroPresented {
                AnalyticsService.shared.capture("instagram_login_intro_viewed")
            }
            scheduleControlFade()
            presentGuidedControlsExplanationIfReady()
        }
        .onChange(of: session.sessionStatus) { _, _ in
            presentGuidedControlsExplanationIfReady()
        }
        .onChange(of: session.isCommentComposerVisible) { _, visible in
            if !visible {
                isCommentInputFocused = false
                commentDraft = ""
                commentPostFailed = false
            }
        }
        .onChange(of: session.commentFocusRequestID) { _, _ in
            commentDraft = session.commentPrefill
            isCommentInputFocused = true
        }
        .onChange(of: protectionStore.filteringHealth) { _, _ in
            presentGuidedControlsExplanationIfReady()
        }
        .onChange(of: protectionStore.effectiveMode) { _, _ in
            presentGuidedControlsExplanationIfReady()
        }
        .onDisappear {
            controlIdleTask?.cancel()
            guidedExploreTask?.cancel()
            guard launchContext == .guidedPractice,
                  !hasCompletedGuidedPractice else { return }
            hasCompletedGuidedPractice = true
            onGuidedPracticeCancelled()
        }
        .familyActivityPicker(
            isPresented: $isShowingAppPicker,
            selection: Binding(
                get: { protectionStore.familySelection },
                set: { protectionStore.familySelection = $0 }
            )
        )
        .sheet(isPresented: $isOpenLinkPresented, onDismiss: {
            linkPasteError = nil
        }) {
            openLinkSheet
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
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

    private var nativeCommentComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(["❤️", "🙌", "🔥", "👏", "🥲", "😍", "😮", "😂"], id: \.self) { emoji in
                    Button {
                        commentDraft += emoji
                        isCommentInputFocused = true
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(emoji) to comment")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 33))
                    .foregroundStyle(Color(red: 0.86, green: 0.88, blue: 0.91))

                HStack(spacing: 6) {
                    TextField("What do you think of this?", text: $commentDraft)
                        .focused($isCommentInputFocused)
                        .submitLabel(.send)
                        .onSubmit(submitNativeComment)
                        .font(.system(size: 16))
                        .tint(.blue)
                        .accessibilityIdentifier("instagram.comment.input")

                    if !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Post", action: submitNativeComment)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.25, green: 0.60, blue: 1.0))
                            .disabled(isSubmittingComment)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.white.opacity(0.17), lineWidth: 1)
                )
            }

            if commentPostFailed {
                Text("Could not post. Try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(red: 0.09, green: 0.11, blue: 0.12))
        .overlay(alignment: .top) {
            Color.white.opacity(0.12).frame(height: 1)
        }
    }

    private func submitNativeComment() {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmittingComment else { return }
        isSubmittingComment = true
        commentPostFailed = false
        Task {
            let accepted = await session.submitComment(text)
            isSubmittingComment = false
            if accepted {
                commentDraft = ""
            } else {
                commentPostFailed = true
            }
        }
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
                .multilineTextAlignment(.center)

            Text("Your Instagram login details stay private and aren’t collected by Nima.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Button(action: continueToInstagramLogin) {
                Text("Continue")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.29, green: 0.37, blue: 0.98))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityHint("Opens Instagram’s official login page")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 390)
        .background(
            Color(red: 0.08, green: 0.09, blue: 0.11),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var guidedControlsExplanationModal: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 66, height: 66)
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 20)

            Text("Your Instagram controls")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Tap the floating Nima button to switch modes, refresh Instagram, open a link, change accounts, or return Home.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Button(action: beginGuidedControlsWalkthrough) {
                Text("Show me")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.29, green: 0.37, blue: 0.98))
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityIdentifier("guided_practice.instagram_controls.continue")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 390)
        .background(
            Color(red: 0.08, green: 0.09, blue: 0.11),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func continueToInstagramLogin() {
        InstagramLoginIntroduction.markSeen()
        AnalyticsService.shared.capture("instagram_login_intro_continued")
        if launchContext == .guidedPractice {
            AnalyticsService.shared.capture("instagram_practice_privacy_continued")
        }
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

    private func presentGuidedControlsExplanationIfReady() {
        guard launchContext == .guidedPractice,
              !hasCompletedGuidedPractice,
              InstagramGuidedPracticePolicy.isReadyForControlsExplanation(
                  sessionStatus: session.sessionStatus,
                  mode: protectionStore.effectiveMode,
                  filteringHealth: protectionStore.filteringHealth
              ) else { return }
        guard !isGuidedControlsExplanationPresented,
              guidedCoachStep == .hidden else { return }

        AnalyticsService.shared.capture("instagram_practice_login_detected")
        AnalyticsService.shared.capture("instagram_practice_clean_mode_ready")
        withAnimation(.easeInOut(duration: 0.22)) {
            isGuidedControlsExplanationPresented = true
        }
    }

    private func beginGuidedControlsWalkthrough() {
        AnalyticsService.shared.capture("instagram_practice_controls_walkthrough_started")
        session.goHome()
        markControlActive()
        withAnimation(.easeInOut(duration: 0.22)) {
            isGuidedControlsExplanationPresented = false
            guidedCoachStep = .openControls
        }
    }

    private func showRemovedFeedsCoachMark() {
        AnalyticsService.shared.capture("instagram_practice_controls_overview_seen")
        session.goHome()
        withAnimation(.easeInOut(duration: 0.22)) {
            isControlMenuPresented = false
            guidedCoachStep = .feedsRemoved
        }
    }

    private func beginGuidedExploration() {
        AnalyticsService.shared.capture("instagram_practice_removed_feeds_explained")
        withAnimation(.easeInOut(duration: 0.22)) {
            guidedCoachStep = .freeExplore
            isControlMenuPresented = false
        }
        guidedExploreTask?.cancel()
        guidedExploreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  guidedCoachStep == .freeExplore else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                guidedCoachStep = .returnControls
            }
            AnalyticsService.shared.capture("instagram_practice_exploration_ready")

            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled,
                  guidedCoachStep == .returnControls else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                guidedCoachStep = .finishSetup
            }
            AnalyticsService.shared.capture("instagram_practice_finish_setup_prompted")
        }
    }

    private func openControlsToFinishSetup() {
        guidedExploreTask?.cancel()
        AnalyticsService.shared.capture("instagram_practice_finish_setup_tapped")
        withAnimation(.bouncy(duration: 0.34, extraBounce: 0.12)) {
            guidedCoachStep = .returnHome
            isControlMenuPresented = true
        }
    }

    private func finishGuidedInstagramPractice() {
        guard !hasCompletedGuidedPractice else { return }
        hasCompletedGuidedPractice = true
        AnalyticsService.shared.capture("instagram_practice_controls_explained")
        AnalyticsService.shared.capture("instagram_practice_home_tapped")
        onGuidedPracticeCompleted()
    }

    @ViewBuilder
    private func guidedPracticeCoachOverlay(in size: CGSize) -> some View {
        let cardWidth = min(size.width - 32, 350)

        switch guidedCoachStep {
        case .hidden:
            EmptyView()

        case .openControls:
            let controlPoint = resolvedControlPosition(in: size)
            ZStack {
                coachTargetRing(diameter: 76)
                    .position(controlPoint)

                InstagramGuidedCoachCard(
                    title: "Open your controls",
                    message: "Tap the floating Nima button."
                )
                .frame(width: min(cardWidth, 286))
                .position(
                    x: min(max(controlPoint.x, cardWidth / 2 + 8), size.width - cardWidth / 2 - 8),
                    y: max(86, controlPoint.y - 112)
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        case .controlsOverview:
            InstagramGuidedCoachCard(
                title: "Your Instagram controls",
                message: "Switch modes, refresh Instagram, open a link, or change accounts here.",
                buttonTitle: "Next",
                action: showRemovedFeedsCoachMark
            )
            .frame(width: cardWidth)
            .position(x: size.width / 2, y: 116)
            .accessibilityIdentifier("guided_practice.controls_overview")

        case .feedsRemoved:
            InstagramGuidedCoachCard(
                title: "Infinite feeds removed",
                message: "Reels and other endless feeds are hidden in Clean Mode. Messages, profiles, and posts you choose to open still work.",
                buttonTitle: "Try it",
                action: beginGuidedExploration
            )
            .frame(width: cardWidth)
            .position(x: size.width / 2, y: max(142, size.height - 190))
            .accessibilityIdentifier("guided_practice.feeds_removed")

        case .freeExplore:
            EmptyView()

        case .returnControls:
            let controlPoint = resolvedControlPosition(in: size)
            ZStack {
                coachTargetRing(diameter: 76)
                    .position(controlPoint)

                InstagramGuidedCoachCard(
                    title: "Ready to continue?",
                    message: "Open the Nima controls."
                )
                .frame(width: min(cardWidth, 300))
                .position(
                    x: min(max(controlPoint.x, cardWidth / 2 + 8), size.width - cardWidth / 2 - 8),
                    y: max(86, controlPoint.y - 112)
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        case .finishSetup:
            ZStack {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()

                InstagramGuidedCoachCard(
                    title: "Finish setup",
                    message: "Open your controls and tap Home to finish the walkthrough.",
                    buttonTitle: "Finish setup",
                    action: openControlsToFinishSetup
                )
                .frame(width: cardWidth)
                .position(x: size.width / 2, y: size.height / 2)
                .accessibilityIdentifier("guided_practice.finish_setup")
            }

        case .returnHome:
            let menuHomePoint = CGPoint(
                x: size.width / 2,
                y: resolvedMenuY(in: size) + 106
            )
            ZStack {
                coachTargetRing(diameter: 86)
                    .position(menuHomePoint)

                InstagramGuidedCoachCard(
                    title: "That’s it",
                    message: "Tap Home when you’re ready."
                )
                .frame(width: min(cardWidth, 286))
                .position(x: size.width / 2, y: 92)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func coachTargetRing(diameter: CGFloat) -> some View {
        Circle()
            .stroke(Color.white, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .background(Color.white.opacity(0.12), in: Circle())
            .shadow(color: Color.white.opacity(0.65), radius: 10)
            .allowsHitTesting(false)
    }

    private var openLinkSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Copy a post or Reel link from Instagram, then paste it here.")
                    .foregroundStyle(.secondary)

                Button(action: pasteAndOpenInstagramLink) {
                    Label("Paste Instagram link", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens the Instagram link currently copied to your clipboard")

                if let linkPasteError {
                    Label(linkPasteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Open Instagram link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: closeOpenLinkSheet)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pasteAndOpenInstagramLink() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation { linkPasteError = "Your clipboard doesn’t contain a link." }
            return
        }

        guard InstagramNavigationPolicy.instagramURL(from: clipboardText) != nil else {
            withAnimation { linkPasteError = "That isn’t an Instagram link. Copy a link from Instagram and try again." }
            return
        }

        session.openLink(clipboardText)
        closeOpenLinkSheet()
    }

    private func closeOpenLinkSheet() {
        isOpenLinkPresented = false
        linkPasteError = nil
    }

    private var controlMenu: some View {
        ZStack {
            controlMenuButton(
                title: destinationMode.title,
                icon: destinationMode == .dmOnly ? "message.fill" : "sparkles",
                isEnabled: canChangeMode && !isGuidedMenuWalkthroughActive
            ) {
                controlHaptic()
                protectionStore.setManualMode(destinationMode, source: "instagram_assistive_menu")
                session.activateMode(destinationMode)
                closeControlMenu()
            }
            .position(x: 82, y: 70)

            controlMenuButton(
                title: "Switch account",
                icon: "person.2.fill",
                isEnabled: !isGuidedMenuWalkthroughActive
            ) {
                controlHaptic()
                session.logOut()
                closeControlMenu()
            }
            .position(x: 230, y: 70)

            controlMenuButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                isEnabled: !isGuidedMenuWalkthroughActive
            ) {
                controlHaptic()
                session.reload()
                closeControlMenu()
            }
            .position(x: 58, y: 178)

            controlMenuButton(
                title: "Open link",
                icon: "link",
                isEnabled: !isGuidedMenuWalkthroughActive
            ) {
                controlHaptic()
                closeControlMenu()
                isOpenLinkPresented = true
            }
            .position(x: 254, y: 178)

            controlMenuButton(
                title: "Home",
                icon: "house.fill",
                isEnabled: !isGuidedMenuWalkthroughActive || guidedCoachStep == .returnHome
            ) {
                controlHaptic()
                if guidedCoachStep == .returnHome {
                    finishGuidedInstagramPractice()
                } else {
                    leaveInstagramClient()
                }
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
        .accessibilityLabel("Instagram controls")
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
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
                    .symbolEffect(.bounce, options: .nonRepeating, value: isControlMenuPresented)
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
        .accessibilityHint(modeChangeAccessibilityHint(for: title))
    }

    private func assistiveControl(in size: CGSize) -> some View {
        let position = resolvedControlPosition(in: size)
        return Button {
            markControlActive()
            controlHaptic()
            let isOpeningMenu = !isControlMenuPresented
            let coachStepBeforeOpening = guidedCoachStep
            withAnimation(.bouncy(duration: 0.38, extraBounce: 0.18)) {
                isControlMenuPresented.toggle()
                if isOpeningMenu, guidedCoachStep == .openControls {
                    guidedCoachStep = .controlsOverview
                } else if isOpeningMenu, guidedCoachStep == .returnControls {
                    guidedCoachStep = .returnHome
                } else if isOpeningMenu, guidedCoachStep == .finishSetup {
                    guidedCoachStep = .returnHome
                }
            }
            if isOpeningMenu, coachStepBeforeOpening == .openControls {
                AnalyticsService.shared.capture("instagram_practice_controls_opened")
            } else if isOpeningMenu, coachStepBeforeOpening == .returnControls {
                AnalyticsService.shared.capture("instagram_practice_return_controls_opened")
            } else if isOpeningMenu, coachStepBeforeOpening == .finishSetup {
                AnalyticsService.shared.capture("instagram_practice_finish_setup_controls_opened")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 0.12, green: 0.15, blue: 0.17))
                Circle()
                    .fill(Color(red: 0.37, green: 0.41, blue: 0.43))
                    .padding(8)
                Circle()
                    .fill(Color(red: 0.62, green: 0.65, blue: 0.67))
                    .padding(15)
                Circle()
                    .fill(Color.white)
                    .padding(22)
            }
            .frame(width: 60, height: 60)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.45), radius: isDraggingControl ? 14 : 9, y: isDraggingControl ? 8 : 4)
            .scaleEffect(isDraggingControl ? 1.09 : (isControlMenuPresented ? 0.94 : 1))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.68), value: isDraggingControl)
            .animation(.bouncy(duration: 0.3), value: isControlMenuPresented)
            .opacity(isControlIdle ? 0.38 : 0.94)
            .animation(.easeInOut(duration: 0.55), value: isControlIdle)
        }
        .buttonStyle(NativeAssistiveButtonStyle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("controlDragArea"))
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
        .allowsHitTesting(guidedCoachStep != .freeExplore)
        .position(position)
        .accessibilityLabel(isControlMenuPresented ? "Close Instagram controls" : "Open Instagram controls")
    }

    private var destinationMode: InstagramMode {
        protectionStore.effectiveMode == .clean ? .dmOnly : .clean
    }

    private var canChangeMode: Bool {
        protectionStore.filteringHealth != .limited
    }

    private var isGuidedMenuWalkthroughActive: Bool {
        guidedCoachStep == .controlsOverview || guidedCoachStep == .returnHome
    }

    private func closeControlMenu() {
        withAnimation(.bouncy(duration: 0.28, extraBounce: 0.08)) {
            isControlMenuPresented = false
        }
        scheduleControlFade()
    }

    private func leaveInstagramClient() {
        guard launchContext == .guidedPractice else {
            dismiss()
            return
        }
        guard !hasCompletedGuidedPractice else { return }
        hasCompletedGuidedPractice = true
        AnalyticsService.shared.capture("instagram_practice_cancelled")
        onGuidedPracticeCancelled()
    }

    private func controlHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
    }

    private func markControlActive() {
        controlIdleTask?.cancel()
        if isControlIdle {
            withAnimation(.easeOut(duration: 0.18)) {
                isControlIdle = false
            }
        }
    }

    private func scheduleControlFade() {
        controlIdleTask?.cancel()
        guard !isControlMenuPresented,
              guidedCoachStep == .hidden else { return }
        controlIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled, !isControlMenuPresented else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                isControlIdle = true
            }
        }
    }

    private func resolvedControlPosition(in size: CGSize) -> CGPoint {
        controlPosition ?? CGPoint(x: size.width - 34, y: size.height * 0.68)
    }

    private func resolvedMenuY(in size: CGSize) -> CGFloat {
        let halfMenuHeight: CGFloat = 166
        let desiredY = resolvedControlPosition(in: size).y
        return min(max(desiredY, halfMenuHeight + 12), size.height - halfMenuHeight - 12)
    }

    private func clampedControlPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 34), size.width - 34),
            y: min(max(point.y, 42), size.height - 42)
        )
    }

    private func modeChangeAccessibilityHint(for title: String) -> String {
        guard title == InstagramMode.clean.title || title == InstagramMode.dmOnly.title else { return "" }
        return canChangeMode ? "Switches Instagram to \(title)" : "Mode is temporarily limited by filter status"
    }

    private var shieldSetupBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
            Text("Official Instagram is not protected")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(protectionStore.shieldStatus == .selectionRequired ? "Select app" : "Enable") {
                configureShield()
            }
            .font(.system(size: 13, weight: .bold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .foregroundStyle(.white)
        .background(Color.orange.opacity(0.82))
    }

    private func statusBanner(icon: String, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .foregroundStyle(.white)
        .background(Color.orange.opacity(0.88))
    }

    private func configureShield() {
        Task {
            do {
                if protectionStore.authorizationStatus != .approved {
                    try await protectionStore.requestAuthorization()
                }
                isShowingAppPicker = true
            } catch {
                authorizationError = "Nima could not enable Screen Time access. You can continue using Clean mode without shielding the official app."
            }
        }
    }
}

private enum InstagramGuidedCoachStep: Equatable {
    case hidden
    case openControls
    case controlsOverview
    case feedsRemoved
    case freeExplore
    case returnControls
    case finishSetup
    case returnHome
}

private struct InstagramGuidedCoachCard: View {
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let buttonTitle {
                Button(buttonTitle, action: action)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(red: 0.29, green: 0.37, blue: 0.98))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.97),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }
}

enum InstagramLoginIntroduction {
    static func hasBeenSeen(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) -> Bool {
        defaults?.bool(forKey: NimaConstants.instagramLoginIntroSeenKey) ?? false
    }

    static func markSeen(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) {
        defaults?.set(true, forKey: NimaConstants.instagramLoginIntroSeenKey)
    }
}

struct NativeMenuControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                .interactiveSpring(response: 0.2, dampingFraction: 0.58),
                value: configuration.isPressed
            )
    }
}

struct NativeAssistiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(
                .interactiveSpring(response: 0.18, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

#Preview {
    NavigationStack {
        InstagramClientScreen()
            .environment(InstagramProtectionStore())
    }
}
