import AVFoundation
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

struct GuidedPracticeAppSelectionModal: View {
    @Binding var selectedAppIDs: Set<String>
    var onContinue: () -> Void

    private let apps = [
        GuidedPracticeAppChoice(id: "instagram", title: "Instagram"),
        GuidedPracticeAppChoice(id: "tiktok", title: "TikTok"),
        GuidedPracticeAppChoice(id: "x", title: "X/Twitter"),
    ]

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.76, min(proxy.size.width / 390, proxy.size.height / 700)))

                VStack(spacing: 0) {
                    Text("Which apps would you like infinite feeds removed from?")
                        .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 42 * scale)

                    VStack(spacing: 13 * scale) {
                        ForEach(apps) { app in
                            GuidedPracticeAppChoiceRow(
                                app: app,
                                isSelected: selectedAppIDs.contains(app.id),
                                scale: scale,
                                action: { toggle(app.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 44 * scale)

                    Spacer(minLength: 28 * scale)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(GuidedPracticePalette.card)
                            .frame(width: 186 * scale, height: 44 * scale)
                            .background(GuidedPracticePalette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAppIDs.isEmpty)
                    .opacity(selectedAppIDs.isEmpty ? 0.38 : 1)
                    .accessibilityIdentifier("guided_practice.app_selection.continue")
                    .padding(.bottom, 46 * scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityIdentifier("guided_practice.app_selection")
    }

    private func toggle(_ appID: String) {
        if selectedAppIDs.contains(appID) {
            selectedAppIDs.remove(appID)
        } else {
            selectedAppIDs.insert(appID)
        }
    }
}

struct GuidedPracticeFamilyPickerVideoModal: View {
    let errorMessage: String?
    var onContinue: () -> Void

    @State private var hasFinishedPlayback = false

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.72, min(proxy.size.width / 390, proxy.size.height / 760)))

                VStack(spacing: 0) {
                    Text("Search and select each app")
                        .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 32 * scale)

                    Spacer(minLength: 18 * scale)

                    GuidedFamilyPickerInstructionVideo(
                        onFinished: { hasFinishedPlayback = true }
                    )
                        .aspectRatio(888.0 / 958.0, contentMode: .fit)
                        .frame(maxWidth: 292 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 18 * scale)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(GuidedPracticePalette.accent)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 30)
                            .padding(.bottom, 12 * scale)
                    }

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                hasFinishedPlayback
                                    ? GuidedPracticePalette.card
                                    : .white.opacity(0.42)
                            )
                            .frame(width: 186 * scale, height: 44 * scale)
                            .background(
                                hasFinishedPlayback
                                    ? GuidedPracticePalette.accent
                                    : Color.white.opacity(0.12)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasFinishedPlayback)
                    .accessibilityIdentifier("guided_practice.family_picker_video.continue")
                    .padding(.bottom, 46 * scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityIdentifier("guided_practice.family_picker_video")
    }
}

struct GuidedPracticeAppConnectionsModal: View {
    let applicationTokens: [ApplicationToken]
    let selectedApps: [GuidedPracticeLaunchApp]
    @Binding var assignments: [ApplicationToken: String]
    var onChooseAppsAgain: () -> Void
    var onContinue: () -> Void

    private var selectedAppIDs: Set<String> {
        Set(selectedApps.map(\.rawValue))
    }

    private var connectedCount: Int {
        Set(assignments.values).intersection(selectedAppIDs).count
    }

    private var isComplete: Bool {
        applicationTokens.count == selectedApps.count
            && applicationTokens.allSatisfy { assignments[$0] != nil }
            && Set(assignments.values) == selectedAppIDs
    }

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.7, min(proxy.size.width / 390, proxy.size.height / 760)))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("Connect your apps")
                            .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .padding(.top, 34 * scale)

                        Text("Match each app on your phone with its Nima experience")
                            .font(.system(size: 16 * scale, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2 * scale)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 36)
                            .padding(.top, 10 * scale)

                        if applicationTokens.count != selectedApps.count {
                            connectionCountMessage(scale: scale)
                                .padding(.horizontal, 28)
                                .padding(.top, 18 * scale)
                        }

                        VStack(spacing: 12 * scale) {
                            ForEach(applicationTokens, id: \.self) { token in
                                connectionRow(for: token, scale: scale)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 24 * scale)

                        Button("Choose apps again", action: onChooseAppsAgain)
                            .font(.system(size: 14 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                            .buttonStyle(.plain)
                            .padding(.top, 18 * scale)
                            .accessibilityIdentifier("guided_practice.app_connections.choose_again")

                        Spacer(minLength: 28 * scale)

                        Text("\(connectedCount) of \(selectedApps.count) connected")
                            .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(isComplete ? GuidedPracticePalette.accent : .white.opacity(0.58))
                            .padding(.bottom, 12 * scale)

                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 18 * scale, weight: .semibold, design: .rounded))
                                .foregroundStyle(isComplete ? GuidedPracticePalette.card : .white.opacity(0.42))
                                .frame(width: 210 * scale, height: 44 * scale)
                                .background(isComplete ? GuidedPracticePalette.accent : Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isComplete)
                        .accessibilityIdentifier("guided_practice.app_connections.continue")
                        .padding(.bottom, 38 * scale)
                    }
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityIdentifier("guided_practice.app_connections")
    }

    @ViewBuilder
    private func connectionCountMessage(scale: CGFloat) -> some View {
        Text("You chose \(selectedApps.count) in Nima but selected \(applicationTokens.count) in Apple’s picker. Choose the same apps in both places.")
            .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
            .foregroundStyle(GuidedPracticePalette.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func connectionRow(for token: ApplicationToken, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Menu {
                ForEach(selectedApps) { app in
                    Button {
                        assign(app.rawValue, to: token)
                    } label: {
                        if assignments[token] == app.rawValue {
                            Label(app.displayName, systemImage: "checkmark")
                        } else {
                            Text(app.displayName)
                        }
                    }
                }

                if assignments[token] != nil {
                    Divider()
                    Button("Disconnect", role: .destructive) {
                        assignments.removeValue(forKey: token)
                    }
                }
            } label: {
                HStack(spacing: 7 * scale) {
                    if let app = assignedApp(for: token) {
                        SocialMediaIcon(platform: app.platform, size: 24 * scale)
                            .frame(width: 26 * scale, height: 26 * scale)
                        Text(app.displayName)
                            .lineLimit(1)
                    } else {
                        Text("Choose app")
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10 * scale, weight: .bold))
                }
                .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(assignments[token] == nil ? .white.opacity(0.72) : GuidedPracticePalette.accent)
                .padding(.horizontal, 11 * scale)
                .frame(minWidth: 118 * scale, minHeight: 44 * scale)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
            }
            .accessibilityLabel("Connect selected app")
            .accessibilityValue(assignedApp(for: token)?.displayName ?? "Not connected")
        }
        .padding(.horizontal, 14 * scale)
        .frame(minHeight: 76 * scale)
        .background(Color.white.opacity(0.075))
        .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
    }

    private func assignedApp(for token: ApplicationToken) -> GuidedPracticeLaunchApp? {
        guard let appID = assignments[token] else { return nil }
        return GuidedPracticeLaunchApp(rawValue: appID)
    }

    private func assign(_ appID: String, to token: ApplicationToken) {
        let previousAppID = assignments[token]

        if let otherToken = assignments.first(where: { $0.key != token && $0.value == appID })?.key {
            if let previousAppID {
                assignments[otherToken] = previousAppID
            } else {
                assignments.removeValue(forKey: otherToken)
            }
        }

        assignments[token] = appID
    }
}

private struct GuidedPracticeAppChoice: Identifiable {
    let id: String
    let title: String
}

private struct GuidedPracticeAppChoiceRow: View {
    let app: GuidedPracticeAppChoice
    let isSelected: Bool
    let scale: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14 * scale) {
                SocialMediaIcon(platform: app.id, size: 34 * scale)
                    .frame(width: 36 * scale, height: 36 * scale)

                Text(app.title)
                    .font(.system(size: 19 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                ZStack {
                    Circle()
                        .fill(isSelected ? GuidedPracticePalette.accent : .clear)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? GuidedPracticePalette.accent : .white.opacity(0.2),
                                    lineWidth: 2 * scale
                                )
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15 * scale, weight: .bold))
                            .foregroundStyle(GuidedPracticePalette.card)
                    }
                }
                .frame(width: 29 * scale, height: 29 * scale)
            }
            .padding(.horizontal, 18 * scale)
            .frame(height: 68 * scale)
            .background(Color.white.opacity(0.075))
            .clipShape(RoundedRectangle(cornerRadius: 15 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("guided_practice.app_selection.\(app.id)")
    }
}

private struct GuidedFamilyPickerInstructionVideo: UIViewRepresentable {
    var onFinished: () -> Void

    func makeUIView(context: Context) -> GuidedFamilyPickerInstructionVideoView {
        let view = GuidedFamilyPickerInstructionVideoView()
        view.configure(onFinished: onFinished)
        return view
    }

    func updateUIView(_ uiView: GuidedFamilyPickerInstructionVideoView, context: Context) {
        uiView.configure(onFinished: onFinished)
    }
}

private final class GuidedFamilyPickerInstructionVideoView: UIView {
    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var onFinished: (() -> Void)?
    private var isConfigured = false

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func configure(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect

        guard !isConfigured else { return }
        isConfigured = true

        guard let videoURL = Bundle.main.url(
            forResource: "guided_family_picker",
            withExtension: "mov"
        ) else { return }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onFinished?()
            self.player.seek(to: .zero)
            self.player.play()
        }
        player.play()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            player.pause()
        } else if player.currentItem?.status == .readyToPlay,
                  player.currentTime() < (player.currentItem?.duration ?? .zero) {
            player.play()
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}

struct GuidedPracticeOpenAppPromptModal: View {
    var onContinue: () -> Void

    @State private var selectedPage = 0

    private let pages = [
        GuidedPracticeOpenAppPage(
            title: "Perfect! Open Instagram through Nima to see Clean Mode",
            imageName: "guided_practice_open_through_nima",
            imageWidth: 294,
            imageHeight: 500
        ),
        GuidedPracticeOpenAppPage(
            title: "Infinite feeds are removed. Posts and stories are still viewable",
            imageName: "guided_practice_feed_removed",
            imageWidth: 292,
            imageHeight: 410
        ),
    ]

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.68, min(proxy.size.width / 390, proxy.size.height / 760)))
                let page = pages[selectedPage]

                VStack(spacing: 0) {
                    Text(page.title)
                        .font(.system(size: 21 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * scale)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 28)
                        .frame(height: 126 * scale, alignment: .center)

                    ZStack {
                        GuidedPracticeBundledImage(name: page.imageName)
                            .frame(
                                width: page.imageWidth * scale,
                                height: page.imageHeight * scale
                            )

                        HStack {
                            if selectedPage > 0 {
                                pageArrow(systemName: "chevron.left", scale: scale) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPage -= 1
                                    }
                                }
                                .accessibilityLabel("Previous page")
                            } else {
                                Color.clear.frame(width: 46 * scale)
                            }

                            Spacer()

                            if selectedPage < pages.count - 1 {
                                pageArrow(systemName: "chevron.right", scale: scale) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPage += 1
                                    }
                                }
                                .accessibilityLabel("Next page")
                            } else {
                                Color.clear.frame(width: 46 * scale)
                            }
                        }
                        .padding(.horizontal, 24 * scale)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 500 * scale)

                    HStack(spacing: 12 * scale) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == selectedPage ? .white.opacity(0.9) : .white.opacity(0.38))
                                .frame(width: 15 * scale, height: 15 * scale)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedPage = index
                                    }
                                }
                        }
                    }
                    .frame(height: 34 * scale)

                    Group {
                        if selectedPage == pages.count - 1 {
                            Button(action: onContinue) {
                                HStack(spacing: 8 * scale) {
                                    GuidedPracticePromptAppIcon(platform: "instagram")
                                        .frame(width: 23 * scale, height: 23 * scale)
                                    Text("Open Instagram")
                                        .font(.system(size: 17 * scale, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(GuidedPracticePalette.card)
                                .frame(width: 196 * scale, height: 44 * scale)
                                .background(GuidedPracticePalette.accent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("guided_practice.open_app_prompt.continue")
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: 44 * scale)
                    .padding(.top, 6 * scale)

                    Spacer(minLength: 14 * scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityIdentifier("guided_practice.open_app_prompt")
    }

    private func pageArrow(
        systemName: String,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 28 * scale, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 46 * scale, height: 58 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

private struct GuidedPracticeBundledImage: View {
    let name: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(name)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
    }
}

private struct GuidedPracticeOpenAppPage {
    let title: String
    let imageName: String
    let imageWidth: CGFloat
    let imageHeight: CGFloat
}

private struct GuidedPracticeOpenAppCoachRow: View {
    let activeApps: Set<GuidedPracticeLaunchApp>
    let scale: CGFloat

    var body: some View {
        Group {
            if activeApps.count > 1 {
                GuidedPracticeOpenAppCoachNima(text: "Open either app to test", scale: scale)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 30 * scale) {
                    ForEach(GuidedPracticeLaunchApp.allCases) { app in
                        Group {
                            if activeApps.contains(app) {
                                GuidedPracticeOpenAppCoachNima(text: "Open this app to test", scale: scale)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 82 * scale, height: 30 * scale)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct GuidedPracticeOpenAppCoachNima: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.01, green: 0.12, blue: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 5 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                        .fill(.white.opacity(0.96))
                )

            Triangle()
                .fill(.white.opacity(0.96))
                .frame(width: 12 * scale, height: 7 * scale)
        }
        .shadow(color: .black.opacity(0.26), radius: 8 * scale, y: 4 * scale)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct GuidedPracticePromptVideo: UIViewRepresentable {
    func makeUIView(context: Context) -> GuidedPracticePromptVideoView {
        let view = GuidedPracticePromptVideoView()
        view.configure()
        return view
    }

    func updateUIView(_ uiView: GuidedPracticePromptVideoView, context: Context) {
        uiView.configure()
    }
}

private final class GuidedPracticePromptVideoView: UIView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func configure() {
        guard looper == nil,
              let videoURL = Bundle.main.url(forResource: "Frame-2", withExtension: "mov") else {
            return
        }

        let item = AVPlayerItem(url: videoURL)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        player.play()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            player.pause()
        } else {
            player.play()
        }
    }
}

struct GuidedPracticeSuccessModal: View {
    var onContinue: () -> Void
    var onTroubleshoot: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GuidedPracticeFeedbackModal(
                symbol: "checkmark",
                symbolSize: 88,
                title: "Doomscrolling\nblocked!",
                message: "Nima kept the feed out of reach while leaving the useful parts of your app open",
                primaryAccessibilityIdentifier: "guided_practice.success_continue",
                onContinue: onContinue,
                secondaryTitle: "Something didn't work",
                secondaryAccessibilityIdentifier: "guided_practice.troubleshoot",
                onSecondary: onTroubleshoot
            )
        }
        .accessibilityIdentifier("guided_practice.success")
    }
}

struct GuidedPracticeReviewModal: View {
    var onContinue: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GuidedPracticeFeedbackModal(
                symbol: "hand.thumbsup",
                symbolSize: 76,
                title: "Enjoying Nima?",
                message: "If Nima helped block the scroll, a quick rating helps us keep improving it",
                primaryAccessibilityIdentifier: "guided_practice.review_continue",
                onContinue: onContinue
            )
        }
        .accessibilityIdentifier("guided_practice.review")
    }
}

private struct GuidedPracticeFeedbackModal: View {
    let symbol: String
    let symbolSize: CGFloat
    let title: String
    let message: String
    let primaryAccessibilityIdentifier: String
    var onContinue: () -> Void
    var secondaryTitle: String?
    var secondaryAccessibilityIdentifier: String?
    var onSecondary: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, max(0.72, min(proxy.size.width / 390, proxy.size.height / 700)))
            let horizontalPadding = max(24, 42 * scale)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 48 * scale)

                    ZStack {
                        Circle()
                            .fill(GuidedPracticePalette.accent)
                            .frame(width: 176 * scale, height: 176 * scale)

                        Image(systemName: symbol)
                            .font(.system(size: symbolSize * scale, weight: .regular))
                            .foregroundStyle(.white)
                    }

                    Text(title)
                        .font(.system(size: 40 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 22)
                        .padding(.top, 28 * scale)

                    Text(message)
                        .font(.system(size: 24 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 22 * scale)

                    Spacer(minLength: 34 * scale)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 20 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 238 * scale, height: max(42, 42 * scale))
                            .background(GuidedPracticePalette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(primaryAccessibilityIdentifier)

                    if let secondaryTitle, let onSecondary {
                        Button(action: onSecondary) {
                            Text(secondaryTitle)
                                .font(.system(size: 14 * scale, weight: .regular, design: .rounded))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 12 * scale)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(secondaryAccessibilityIdentifier ?? "")
                    }

                    Color.clear.frame(height: 36 * scale)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct GuidedWindowsReadyModal: View {
    var onContinue: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.7, min(proxy.size.width / 390, proxy.size.height / 760)))
                let graphicHeight = 224 * scale

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 44 * scale)

                    GuidedWindowsReadyGraphic()
                        .frame(width: min(proxy.size.width - 44, 390 * scale), height: graphicHeight)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 6 * scale)

                    Text("Your window is ready!")
                        .font(.system(size: 40 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 22)

                        Text("At the scheduled time, Nima will turn your window on automatically")
                        .font(.system(size: 24 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * scale)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 42)
                        .padding(.top, 16 * scale)

                    Spacer(minLength: 34 * scale)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 238, height: 42)
                            .background(GuidedPracticePalette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guided_windows.ready_continue")

                        Color.clear.frame(height: 42 * scale)
                    }
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityIdentifier("guided_windows.ready")
    }
}

private struct GuidedWindowsReadyGraphic: View {
    var body: some View {
        Group {
            if let image = UIImage.homeDashboardResource(named: "guided_windows_ready", fileExtension: "png") {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 70, weight: .regular))
                            .foregroundStyle(GuidedPracticePalette.accent)
                    }
            }
        }
    }
}

struct GuidedPracticeTroubleshootingModal: View {
    var onBack: () -> Void
    var onOpenVPNSettings: () -> Void
    var onTryAgain: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.68, min(proxy.size.width / 390, proxy.size.height / 820)))
                let horizontalPadding = max(38, 52 * scale)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ZStack {
                        Text("Lets get Nima working")
                            .font(.system(size: 34 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.horizontal, 68)

                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 28 * scale, weight: .light))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back")

                            Spacer()
                        }
                        .padding(.leading, 28)
                        }
                        .frame(height: 78 * scale)
                        .padding(.top, 12 * scale)

                    VStack(alignment: .leading, spacing: 18 * scale) {
                        GuidedPracticeTroubleshootingStep(
                            number: 1,
                            title: "Check Nima is active",
                            detail: "Make sure the blocker is switched on before opening the app you want to test",
                            scale: scale
                        )

                        VStack(alignment: .leading, spacing: 13 * scale) {
                            GuidedPracticeTroubleshootingStep(
                                number: 2,
                                title: "Check VPN permission",
                                detail: "Nima needs VPN permission to block selected feeds on your device",
                                scale: scale
                            )

                            Button(action: onOpenVPNSettings) {
                                Text("Open VPN Settings")
                                    .font(.system(size: 18 * scale, weight: .medium, design: .rounded))
                                    .foregroundStyle(.black)
                                    .frame(width: 236 * scale, height: 40 * scale)
                                    .background(GuidedPracticePalette.accent)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }

                        GuidedPracticeTroubleshootingStep(
                            number: 3,
                            title: "Force close your apps",
                            detail: "Close your apps fully, then open them again while Nima is active",
                            scale: scale
                        )

                        GuidedPracticeTroubleshootingStep(
                            number: 4,
                            title: "Check you picked the right feed",
                            detail: "Make sure the feed you tested matches the one you selected in Nima",
                            scale: scale
                        )

                        GuidedPracticeTroubleshootingStep(
                            number: 5,
                            title: "Wait a few seconds",
                            detail: "Some apps cache content. Give Nima a moment, then try opening the feed again",
                            scale: scale
                        )
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 28 * scale)

                        Spacer(minLength: 10 * scale)

                        Button(action: onTryAgain) {
                            Text("Try again")
                                .font(.system(size: 18 * scale, weight: .medium, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(width: 238 * scale, height: 40 * scale)
                                .background(GuidedPracticePalette.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 28 * scale)
                        .accessibilityIdentifier("guided_practice.try_again")
                    }
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityIdentifier("guided_practice.troubleshooting")
    }
}

private struct GuidedPracticeTroubleshootingStep: View {
    let number: Int
    let title: String
    let detail: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text("\(number). \(title)")
                .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.system(size: 22 * scale, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(1.5 * scale)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuidedPracticeOverlay<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        DarkInstructionModalSurface {
            content
        }
    }
}

private struct GuidedPracticeOpenAppButton: View {
    let app: GuidedPracticeLaunchApp
    let scale: CGFloat
    let iconSize: CGFloat
    let isSuggested: Bool
    let isDisabled: Bool
    var action: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5 * scale) {
                ZStack {
                    if isSuggested {
                        RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                            .strokeBorder(
                                GuidedPracticePalette.accent.opacity(isPulsing ? 0.46 : 0.92),
                                lineWidth: 2 * scale
                            )
                            .frame(width: iconSize + 9 * scale, height: iconSize + 9 * scale)
                            .scaleEffect(isPulsing ? 1.1 : 1)
                            .shadow(
                                color: GuidedPracticePalette.accent.opacity(isPulsing ? 0.58 : 0.32),
                                radius: (isPulsing ? 14 : 8) * scale
                            )
                    }

                    GuidedPracticePromptAppIcon(platform: app.platform)
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.34), radius: 8, y: 5)
                }
                .frame(width: iconSize + 12 * scale, height: iconSize + 12 * scale)

                Text("Open")
                    .font(.system(size: 11.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(GuidedPracticePalette.accent)
                    .clipShape(Capsule())
            }
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Open \(app.displayName)")
        .onAppear {
            guard isSuggested else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onChange(of: isSuggested) { _, suggested in
            if suggested {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
}

private struct GuidedPracticePromptAppIcon: View {
    let platform: String

    var body: some View {
        Group {
            if let image = UIImage.homeDashboardResource(named: resourceName, fileExtension: "png") {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                SocialMediaIcon(platform: platform, size: 52)
            }
        }
    }

    private var resourceName: String {
        switch platform.lowercased() {
        case "instagram":
            return "guided_practice_instagram_icon"
        case "tiktok":
            return "guided_practice_tiktok_icon"
        default:
            return platform
        }
    }
}

private enum GuidedPracticePalette {
    static let card = Color(red: 0.125, green: 0.118, blue: 0.13)
    static let accent = AppChromePalette.accent
}
