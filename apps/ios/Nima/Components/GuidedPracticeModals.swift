import AVFoundation
import SwiftUI
import UIKit

struct GuidedPracticeOpenAppPromptModal: View {
    let activeApps: Set<GuidedPracticeLaunchApp>
    let isStartingPIP: Bool
    let errorMessage: String?
    var onOpenApp: (GuidedPracticeLaunchApp) -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.88, proxy.size.height / 700))
                let videoWidth = 196 * scale
                let videoHeight = 384 * scale
                let iconSize = 48 * scale

                VStack(spacing: 0) {
                    Text("Perfect! now open the app like normal and attempt to scroll or send a dm")
                        .font(.system(size: 21 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * scale)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 30)
                        .padding(.top, 24 * scale)
                        .frame(height: 122 * scale, alignment: .center)

                    Color.clear.frame(height: 14 * scale)

                    GuidedPracticePromptVideo()
                        .frame(width: videoWidth, height: videoHeight)
                        .frame(maxWidth: .infinity)
                        .frame(height: 384 * scale)

                    Color.clear.frame(height: 10 * scale)

                    GuidedPracticeOpenAppCoachRow(activeApps: activeApps, scale: scale)
                        .frame(height: 30 * scale)

                    HStack(spacing: 64 * scale) {
                        ForEach(GuidedPracticeLaunchApp.allCases) { app in
                            GuidedPracticeOpenAppButton(
                                app: app,
                                scale: scale,
                                iconSize: iconSize,
                                isSuggested: activeApps.contains(app),
                                isDisabled: isStartingPIP,
                                action: {
                                    onOpenApp(app)
                                }
                            )
                        }
                    }
                    .frame(height: 78 * scale)

                    Color.clear.frame(height: 4 * scale)

                    Text("Short form videos are blocked. Posts or stories may also be interrupted")
                        .font(.system(size: 16.5 * scale, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1.5 * scale)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 44)
                        .frame(height: 68 * scale)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(GuidedPracticePalette.accent)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .frame(height: 34 * scale)
                    } else {
                        Color.clear.frame(height: 34 * scale)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .accessibilityIdentifier("guided_practice.open_app_prompt")
    }
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
                HStack(spacing: 64 * scale) {
                    ForEach(GuidedPracticeLaunchApp.allCases) { app in
                        Group {
                            if activeApps.contains(app) {
                                GuidedPracticeOpenAppCoachNima(text: "Open this app to test", scale: scale)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 118 * scale, height: 30 * scale)
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
            VStack(spacing: 0) {
                Spacer(minLength: 48)

                ZStack {
                    Circle()
                        .fill(GuidedPracticePalette.accent)
                        .frame(width: 176, height: 176)

                    Image(systemName: "checkmark")
                        .font(.system(size: 88, weight: .regular))
                        .foregroundStyle(.white)
                }

                Text("Doomscrolling\nblocked!")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 28)

                Text("Nima kept the feed out of reach while leaving the useful parts of your app open")
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 42)
                    .padding(.top, 22)

                Spacer(minLength: 42)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 238, height: 42)
                        .background(GuidedPracticePalette.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guided_practice.success_continue")

                Button(action: onTroubleshoot) {
                    Text("Something didn't work")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guided_practice.troubleshoot")

                Color.clear.frame(height: 42)
            }
        }
        .accessibilityIdentifier("guided_practice.success")
    }
}

struct GuidedPracticeReviewModal: View {
    var onContinue: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            VStack(spacing: 0) {
                Spacer(minLength: 48)

                ZStack {
                    Circle()
                        .fill(GuidedPracticePalette.accent)
                        .frame(width: 176, height: 176)

                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 76, weight: .regular))
                        .foregroundStyle(.white)
                }

                Text("Enjoying Nima?")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 22)
                    .padding(.top, 28)

                Text("If Nima helped block the scroll, a quick rating helps us keep improving it")
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 42)
                    .padding(.top, 22)

                Spacer(minLength: 42)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 238, height: 42)
                        .background(GuidedPracticePalette.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guided_practice.review_continue")

                Color.clear.frame(height: 42)
            }
        }
        .accessibilityIdentifier("guided_practice.review")
    }
}

struct GuidedPracticeTroubleshootingModal: View {
    var onBack: () -> Void
    var onOpenVPNSettings: () -> Void
    var onTryAgain: () -> Void

    var body: some View {
        GuidedPracticeOverlay {
            GeometryReader { proxy in
                let scale = min(1, max(0.84, proxy.size.height / 820))
                let horizontalPadding = max(38, 52 * scale)

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
                .frame(width: proxy.size.width, height: proxy.size.height)
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(detail)
                .font(.system(size: 22 * scale, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(1.5 * scale)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
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
        GeometryReader { proxy in
            let width = min(430, max(300, proxy.size.width - 28))
            let height = min(max(560, proxy.size.height - 72), proxy.size.height - 34)

            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()

                content
                    .frame(width: width, height: height)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(GuidedPracticePalette.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(.white.opacity(0.82), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.32), radius: 26, y: 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
