import Foundation

enum Route: Hashable {
    case home
    case timeWindows
    case blockingOptions(appId: String)
    // Chungus VPN routes
    case settings
    case trafficDashboard
    case extensionLog
}
