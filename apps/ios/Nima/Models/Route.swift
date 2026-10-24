import Foundation

enum InstagramLaunchContext: Hashable {
    case standard
    case openLink
    case guidedPractice

    var analyticsName: String {
        switch self {
        case .standard: return "standard"
        case .openLink: return "open_link"
        case .guidedPractice: return "guided_practice"
        }
    }
}

enum Route: Hashable {
    case home
    case timeWindows
    case blockingOptions(appId: String)
    case instagramClient(context: InstagramLaunchContext = .standard)
    // Chungus VPN routes
    case settings
    case trafficDashboard
    case extensionLog
}
