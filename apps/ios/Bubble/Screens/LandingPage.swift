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
                VStack(alignment: .leading, spacing: BubbleSpacing.xs) {
                    Text("BUBBLE")
                        .font(BubbleFonts.titleLarge)
                        .foregroundStyle(.white)
                    
                    Text("into the clouds.")
                        .font(BubbleFonts.subtitleItalic)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.leading, BubbleSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // GO button - matching the design with blue background and white border
                BubbleButton(title: "GO", action: onGo)
                    .padding(.bottom, BubbleSpacing.xxl)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    LandingPage(onGo: {})
}
