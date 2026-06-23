import SwiftUI

struct PageIndicator: View {
    let totalPages: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: NimaSpacing.dotSpacing) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? NimaColors.skyBlue : NimaColors.skyBlue.opacity(0.4))
                    .frame(width: NimaSpacing.dotSize, height: NimaSpacing.dotSize)
            }
        }
    }
}

#Preview {
    ZStack {
        NimaColors.skyGradient.ignoresSafeArea()
        PageIndicator(totalPages: 3, currentPage: 0)
    }
}
