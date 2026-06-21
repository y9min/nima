import SwiftUI

struct LandingPage: View {
    var onGo: () -> Void

    var body: some View {
        ZStack {
            SkyBackgroundView()

            VStack(spacing: 0) {
                // Spacer to position text closer to top
                Spacer()
                    .frame(height: UIScreen.main.bounds.height / 6)

                // Title block - positioned closer to top, slightly to the right
                VStack(alignment: .leading, spacing: NimaSpacing.xs) {
                    Text("NIMA")
                        .font(NimaFonts.titleLarge)
                        .foregroundStyle(.white)
                    
                    Text("into the clouds.")
                        .font(NimaFonts.subtitleItalic)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.leading, NimaSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            
            // Forward arrow button in bottom right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        onGo()
                    } label: {
                        BackArrowView(size: 34, color: .white)
                            .rotationEffect(.degrees(180))
                            .frame(width: 44, height: 44)
                            .background(NimaColors.skyBlue)
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("nima.landing.go")
                    .accessibilityLabel("Continue")
                    .padding(.trailing, NimaSpacing.xl + 10)
                    .padding(.bottom, 14)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Preload SVG icons for faster loading
            SVGCache.shared.preload(svgNames: ["kalshi", "instagram", "fanduel"])
        }
    }
}

#Preview {
    LandingPage(onGo: {})
}
