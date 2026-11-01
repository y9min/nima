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
    private static let tiktokFamilySelectionKey = "tiktok.client.family_selection"
    private static let xFamilySelectionKey = "x.client.family_selection"
    private static let screenTimeAppConnectionsKey = "screen_time.app_connections"
    private static let openParentalControlsAppRawValue = 3

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        if AppControlRuleState.activeKind(for: application) != nil {
            completionHandler(.close)
            return
        }
        switch action {
        case .primaryButtonPressed:
            openNima(destination: destination(for: application), completionHandler: completionHandler)
        case .secondaryButtonPressed:
            let appDestination = destination(for: application)
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

    private func destination(for application: ApplicationToken) -> Destination {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return .instagram }
        if let data = defaults.data(forKey: Self.xFamilySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           selection.applicationTokens.contains(application) {
            return .x
        }
        if let data = defaults.data(forKey: Self.tiktokFamilySelectionKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           selection.applicationTokens.contains(application) {
            return .tiktok
        }
        if let data = defaults.data(forKey: Self.screenTimeAppConnectionsKey),
           let connections = try? JSONDecoder().decode(ShieldAppConnections.self, from: data),
           connections.selectionsByAppID["tiktok"]?.applicationTokens.contains(application) == true {
            return .tiktok
        }
        if let data = defaults.data(forKey: Self.screenTimeAppConnectionsKey),
           let connections = try? JSONDecoder().decode(ShieldAppConnections.self, from: data),
           connections.selectionsByAppID["x"]?.applicationTokens.contains(application) == true {
            return .x
        }
        return .instagram
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

private struct ShieldAppConnections: Decodable {
    let selectionsByAppID: [String: FamilyActivitySelection]
}
