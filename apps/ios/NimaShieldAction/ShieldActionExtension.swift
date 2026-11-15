import ManagedSettings
import Foundation
import FamilyControls

final class ShieldActionExtension: ShieldActionDelegate {
    private enum Destination: String {
        case instagram
        case tiktok
        case x
        case openLink = "open_link"
        case tiktokOpenLink = "tiktok_open_link"
        case xOpenLink = "x_open_link"
    }

    private static let appGroupID = "group.so.nima.app"
    private static let pendingDestinationKey = "shield.pending_destination"
    private static let openParentalControlsAppRawValue = 3

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard let app = SupportedClientApp.matching(application) else {
            completionHandler(.close)
            return
        }
        switch action {
        case .primaryButtonPressed:
            openNima(destination: destination(for: app), completionHandler: completionHandler)
        case .secondaryButtonPressed:
            let appDestination = destination(for: app)
            openNima(
                destination: appDestination == .instagram
                    ? .openLink
                    : appDestination == .x ? .xOpenLink : .tiktokOpenLink,
                completionHandler: completionHandler
            )
        default:
            completionHandler(.none)
        }
    }

    private func destination(for app: SupportedClientApp) -> Destination {
        switch app {
        case .instagram: return .instagram
        case .tiktok: return .tiktok
        case .x: return .x
        }
    }

    private func openNima(
        destination: Destination,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard ShieldActionAvailability.canOpenParentApp,
        // Xcode 26.4 does not name the iOS 26.5 case yet. Raw value 3 is
        // ShieldActionResponse.openParentalControlsApp on the newer runtime.
        let openParentAppResponse = ShieldActionResponse(
            rawValue: Self.openParentalControlsAppRawValue
        ),
        let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            completionHandler(.close)
            return
        }

        defaults.set(destination.rawValue, forKey: Self.pendingDestinationKey)
        defaults.synchronize()
        completionHandler(openParentAppResponse)
    }
}
