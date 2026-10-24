import ManagedSettings
import Foundation

final class ShieldActionExtension: ShieldActionDelegate {
    private enum Destination: String {
        case instagram
        case openLink = "open_link"
    }

    private static let appGroupID = "group.so.nima.app"
    private static let pendingDestinationKey = "instagram.shield.pending_destination"
    private static let openParentalControlsAppRawValue = 3

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            openNima(destination: .openLink, completionHandler: completionHandler)
        case .secondaryButtonPressed:
            openNima(destination: .instagram, completionHandler: completionHandler)
        default:
            completionHandler(.none)
        }
    }

    private func openNima(
        destination: Destination,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
        ),
        // Xcode 26.4 does not name the iOS 26.5 case yet. Raw value 3 is
        // ShieldActionResponse.openParentalControlsApp on the newer runtime.
        let openParentAppResponse = ShieldActionResponse(
            rawValue: Self.openParentalControlsAppRawValue
        ),
        let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            completionHandler(.none)
            return
        }

        defaults.set(destination.rawValue, forKey: Self.pendingDestinationKey)
        defaults.synchronize()
        completionHandler(openParentAppResponse)
    }
}
