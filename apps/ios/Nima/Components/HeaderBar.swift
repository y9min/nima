import SwiftUI
import UIKit

struct HeaderBar: View {
    var title: String = "NIMA"

    var body: some View {
        HStack {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 54, alignment: .leading)
                    .accessibilityLabel(title)
            } else {
                Text(title)
                    .font(NimaFonts.headerTitle)
                    .foregroundStyle(.white)
            }

            Spacer()
        }
    }

    private var logoImage: UIImage? {
        if let path = Bundle.main.path(forResource: "nima_logo", ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return UIImage(named: "nima_logo")
    }
}

#Preview {
    ZStack {
        NimaColors.skyGradient.ignoresSafeArea()
        VStack {
            HeaderBar()
            Spacer()
        }
    }
}
