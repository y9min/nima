import SwiftUI
import UIKit

struct SocialMediaIcon: View {
    let platform: String
    var size: CGFloat = NimaSpacing.appIconMedium
    
    var body: some View {
        Group {
            switch platform.lowercased() {
            case "instagram":
                InstagramIcon(size: size)
            case "tiktok":
                TikTokIcon(size: size)
            case "facebook", "shield":
                FacebookIcon(size: size)
            case "kalshi":
                KalshiIcon(size: size)
            case "fanduel":
                FanduelIcon(size: size)
            case "x":
                XIcon(size: size)
            default:
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(NimaColors.skyBlue)
            }
        }
    }
}

struct InstagramIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.2, blue: 0.98),
                            Color(red: 0.86, green: 0.08, blue: 0.74),
                            Color(red: 1.0, green: 0.25, blue: 0.26),
                            Color(red: 1.0, green: 0.76, blue: 0.18)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .strokeBorder(.white, lineWidth: size * 0.075)
                .padding(size * 0.18)

            Circle()
                .strokeBorder(.white, lineWidth: size * 0.07)
                .frame(width: size * 0.34, height: size * 0.34)

            Circle()
                .fill(.white)
                .frame(width: size * 0.085, height: size * 0.085)
                .offset(x: size * 0.19, y: -size * 0.19)
        }
        .frame(width: size, height: size)
    }
}

struct TikTokIcon: View {
    let size: CGFloat

    var body: some View {
        if let asset = UIImage.nimaResource(named: "home_tiktok_icon", fileExtension: "png") {
            Image(uiImage: asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            ZStack {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.68, weight: .black))
                    .foregroundStyle(Color(red: 0.0, green: 0.95, blue: 1.0))
                    .offset(x: -size * 0.065, y: size * 0.045)

                Image(systemName: "music.note")
                    .font(.system(size: size * 0.68, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.12, blue: 0.32))
                    .offset(x: size * 0.065, y: size * 0.04)

                Image(systemName: "music.note")
                    .font(.system(size: size * 0.68, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

struct FacebookIcon: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Facebook shield icon
            Path { path in
                let center = size / 2
                let radius = size * 0.3
                
                // Shield shape
                path.move(to: CGPoint(x: center, y: size * 0.2))
                path.addLine(to: CGPoint(x: center - radius * 0.8, y: size * 0.3))
                path.addQuadCurve(
                    to: CGPoint(x: center - radius * 0.8, y: size * 0.6),
                    control: CGPoint(x: center - radius * 1.2, y: size * 0.45)
                )
                path.addLine(to: CGPoint(x: center, y: size * 0.75))
                path.addLine(to: CGPoint(x: center + radius * 0.8, y: size * 0.6))
                path.addQuadCurve(
                    to: CGPoint(x: center + radius * 0.8, y: size * 0.3),
                    control: CGPoint(x: center + radius * 1.2, y: size * 0.45)
                )
                path.closeSubpath()
            }
            .fill(NimaColors.skyBlue)
            
            // Letter F
            Text("F")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct KalshiIcon: View {
    let size: CGFloat

    var body: some View {
        SVGView(svgName: "kalshi")
            .frame(width: size * 0.7, height: size * 0.7)
    }
}

struct FanduelIcon: View {
    let size: CGFloat
    
    var body: some View {
        SVGView(svgName: "fanduel")
            .frame(width: size, height: size)
    }
}

struct XIcon: View {
    let size: CGFloat

    var body: some View {
        Text("X")
            .font(.system(size: size * 0.52, weight: .black, design: .rounded))
            .foregroundStyle(NimaColors.skyBlue)
            .frame(width: size, height: size)
    }
}

private extension UIImage {
    static func nimaResource(named name: String, fileExtension: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        guard let path = Bundle.main.path(forResource: name, ofType: fileExtension) else {
            return nil
        }
        return UIImage(contentsOfFile: path)
    }
}

#Preview {
    ZStack {
        NimaColors.skyGradient.ignoresSafeArea()
        HStack(spacing: 20) {
            SocialMediaIcon(platform: "instagram")
            SocialMediaIcon(platform: "tiktok")
        }
    }
}
