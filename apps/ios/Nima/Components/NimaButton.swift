import SwiftUI

struct NimaButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(NimaFonts.buttonText)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: NimaSpacing.buttonHeight)
                .background(NimaColors.skyBlue)
                .clipShape(RoundedRectangle(cornerRadius: NimaSpacing.buttonCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: NimaSpacing.buttonCornerRadius)
                        .strokeBorder(Color.white, lineWidth: 2)
                )
        }
        .padding(.horizontal, NimaSpacing.buttonHorizontalPadding)
    }
}

#Preview {
    ZStack {
        NimaColors.skyGradient.ignoresSafeArea()
        NimaButton(title: "GO") {}
    }
}
