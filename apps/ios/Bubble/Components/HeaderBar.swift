import SwiftUI

struct HeaderBar: View {
    var title: String = "BLOCKING"

    var body: some View {
        HStack {
            Text(title)
                .font(BubbleFonts.headerTitle)
                .foregroundStyle(.white)

            Spacer()

            // Profile picture circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.8, green: 0.85, blue: 0.9),
                            Color(red: 0.7, green: 0.75, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: BubbleSpacing.avatarSize, height: BubbleSpacing.avatarSize)
                .overlay(
                    // Simple face representation
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(width: 6, height: 6)
                            .offset(x: -4, y: 2)
                        Circle()
                            .fill(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(width: 6, height: 6)
                            .offset(x: 4, y: 2)
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.3, blue: 0.3))
                            .frame(width: 12, height: 3)
                            .offset(y: 6)
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.horizontal, BubbleSpacing.lg)
        .padding(.top, BubbleSpacing.md)
    }
}

#Preview {
    ZStack {
        BubbleColors.skyGradient.ignoresSafeArea()
        VStack {
            HeaderBar()
            Spacer()
        }
    }
}
