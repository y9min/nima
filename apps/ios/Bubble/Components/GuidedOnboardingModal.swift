import SwiftUI
import UIKit

struct GuidedOnboardingModal: View {
    var completionTitle: String = "Done"
    var onDone: () -> Void

    @State private var currentPage = 0

    private let slides = GuidedOnboardingSlide.slides

    var body: some View {
        GeometryReader { proxy in
            let layout = GuidedOnboardingModalLayout(screenSize: proxy.size)

            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()

                GuidedOnboardingCard(
                    slides: slides,
                    currentPage: $currentPage,
                    layout: layout,
                    completionTitle: completionTitle,
                    onDone: onDone
                )
                .frame(width: layout.cardWidth, height: layout.cardHeight)
                .accessibilityIdentifier("guided_onboarding.modal")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct GuidedOnboardingCard: View {
    let slides: [GuidedOnboardingSlide]
    @Binding var currentPage: Int
    let layout: GuidedOnboardingModalLayout
    let completionTitle: String
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("How it works")
                .font(.system(size: layout.titleFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .padding(.top, layout.topPadding)

            Text(slides[currentPage].subtitle)
                .font(.system(size: layout.supportingTextFontSize, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(height: layout.subtitleHeight, alignment: .center)

            ZStack {
                TabView(selection: $currentPage) {
                    ForEach(slides) { slide in
                        GuidedOnboardingSlideView(
                            slide: slide,
                            phoneHeight: layout.phoneHeight
                        )
                        .tag(slide.index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.18), value: currentPage)

                HStack {
                    GuidedOnboardingChevron(
                        systemName: "chevron.left",
                        accessibilityLabel: "Previous guide slide",
                        action: showPrevious
                    )
                    .opacity(currentPage == 0 ? 0 : 1)
                    .disabled(currentPage == 0)

                    Spacer()

                    GuidedOnboardingChevron(
                        systemName: "chevron.right",
                        accessibilityLabel: "Next guide slide",
                        action: showNext
                    )
                    .opacity(currentPage == slides.count - 1 ? 0 : 1)
                    .disabled(currentPage == slides.count - 1)
                }
                .padding(.horizontal, layout.chevronPadding)
            }
            .frame(height: layout.mediaHeight)
            .padding(.top, layout.mediaTopPadding)

            Text(slides[currentPage].body)
                .font(.system(size: layout.supportingTextFontSize, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 26)
                .frame(height: layout.bodyHeight)
                .padding(.top, layout.bodyTopPadding)
                .offset(y: currentPage == slides.count - 1 ? -8 : 0)

            Group {
                if currentPage == slides.count - 1 {
                    Button(action: onDone) {
                        Text(completionTitle)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(GuidedOnboardingPalette.card)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(width: max(116, CGFloat(completionTitle.count) * 10), height: 42)
                            .background(GuidedOnboardingPalette.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guided_onboarding.done")
                } else {
                    Color.clear
                        .frame(width: 116, height: 42)
                }
            }
            .frame(height: layout.doneAreaHeight)
            .offset(y: currentPage == slides.count - 1 ? -10 : 0)

            GuidedOnboardingDots(total: slides.count, current: currentPage)
                .padding(.top, layout.dotsTopPadding)
                .padding(.bottom, layout.bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(GuidedOnboardingPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.82), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.32), radius: 26, y: 12)
    }

    private func showPrevious() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    private func showNext() {
        guard currentPage < slides.count - 1 else { return }
        currentPage += 1
    }
}

private struct GuidedOnboardingSlideView: View {
    let slide: GuidedOnboardingSlide
    let phoneHeight: CGFloat

    var body: some View {
        mediaImage
            .frame(maxWidth: .infinity, maxHeight: phoneHeight, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mediaImage: some View {
        if let image = UIImage.homeDashboardResource(named: slide.imageName, fileExtension: "png") {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.11, blue: 0.08),
                    Color(red: 0.01, green: 0.04, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }
}

private struct GuidedOnboardingChevron: View {
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 56, height: 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GuidedOnboardingDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: GuidedOnboardingModalLayout.dotSpacing) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? .white.opacity(0.9) : .white.opacity(0.42))
                    .frame(
                        width: GuidedOnboardingModalLayout.dotDiameter,
                        height: GuidedOnboardingModalLayout.dotDiameter
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guide slide \(current + 1) of \(total)")
    }
}

private struct GuidedOnboardingModalLayout {
    let screenSize: CGSize

    static let dotDiameter: CGFloat = 13
    static let dotSpacing: CGFloat = 13

    var cardWidth: CGFloat {
        min(420, max(292, screenSize.width - 28))
    }

    var cardHeight: CGFloat {
        let maxHeight = max(420, screenSize.height - 54)
        return min(maxHeight, max(560, cardWidth * 2.0))
    }

    var cornerRadius: CGFloat {
        36
    }

    var topPadding: CGFloat {
        cardHeight < 470 ? 22 : 30
    }

    var bottomPadding: CGFloat {
        cardHeight < 620 ? 22 : 38
    }

    var mediaHeight: CGFloat {
        let reservedHeight = topPadding
            + titleLineHeight
            + subtitleHeight
            + mediaTopPadding
            + bodyTopPadding
            + bodyHeight
            + doneAreaHeight
            + dotsTopPadding
            + Self.dotDiameter
            + bottomPadding
        return max(240, cardHeight - reservedHeight)
    }

    var mediaTopPadding: CGFloat {
        cardHeight < 620 ? 4 : 14
    }

    var subtitleHeight: CGFloat {
        cardHeight < 620 ? 54 : 62
    }

    var bodyHeight: CGFloat {
        cardHeight < 620 ? 58 : 76
    }

    var bodyTopPadding: CGFloat {
        cardHeight < 620 ? 6 : 14
    }

    var doneAreaHeight: CGFloat {
        cardHeight < 620 ? 42 : 50
    }

    var dotsTopPadding: CGFloat {
        cardHeight < 620 ? 0 : 4
    }

    var phoneHeight: CGFloat {
        min(cardHeight < 620 ? 360 : 430, max(250, mediaHeight - 36))
    }

    var chevronPadding: CGFloat {
        max(10, cardWidth * 0.06)
    }

    var titleFontSize: CGFloat {
        35
    }

    var titleLineHeight: CGFloat {
        titleFontSize * 1.24
    }

    var supportingTextFontSize: CGFloat {
        22
    }
}

private struct GuidedOnboardingSlide: Identifiable {
    let index: Int
    let subtitle: String
    let imageName: String
    let body: String

    var id: Int { index }

    static let slides = [
        GuidedOnboardingSlide(
            index: 0,
            subtitle: "Drag an app to block short form feeds",
            imageName: "guided_onboarding_block_placeholder",
            body: "Pick the apps where you want short form feeds blocked"
        ),
        GuidedOnboardingSlide(
            index: 1,
            subtitle: "Open the app like normal",
            imageName: "guided_onboarding_feed_placeholder",
            body: "Short form videos are blocked. Posts or stories may also be interrupted"
        ),
        GuidedOnboardingSlide(
            index: 2,
            subtitle: "Keep messaging freely",
            imageName: "guided_onboarding_chat_placeholder",
            body: "DMs and chats stay usable, so you can stay connected without the scroll"
        )
    ]
}

private enum GuidedOnboardingPalette {
    static let card = Color(red: 0.125, green: 0.118, blue: 0.13)
    static let accent = AppChromePalette.accent
}

#Preview {
    ZStack {
        AppChromePalette.background.ignoresSafeArea()
        GuidedOnboardingModal {}
    }
    .preferredColorScheme(.dark)
}
