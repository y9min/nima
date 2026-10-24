import AppTrackingTransparency
import FBSDKCoreKit
import RevenueCat
import UIKit

struct MetaAdsConfiguration {
    let appID: String
    let clientToken: String
    let enabled: Bool

    init(info: [String: Any]) {
        appID = (info["FacebookAppID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        clientToken = (info["FacebookClientToken"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        enabled = ["YES", "TRUE", "1"].contains(String(describing: info["META_ADS_ENABLED"] ?? "").uppercased())
    }

    var isValid: Bool {
        enabled && !appID.isEmpty && appID.allSatisfy(\.isNumber)
            && !clientToken.isEmpty && !clientToken.contains("$(") && !clientToken.hasPrefix("your-")
    }
}

/// One activation per foreground session. Never send custom product or VPN events.
struct MetaAdsConsentState {
    private(set) var didActivate = false
    mutating func leaveForeground() { didActivate = false }
    mutating func shouldActivate(configured: Bool, authorized: Bool, active: Bool) -> Bool {
        guard configured, authorized, active, !didActivate else { return false }
        didActivate = true
        return true
    }
}

@MainActor
final class MetaAdsService {
    static let shared = MetaAdsService()
    private let configuration = MetaAdsConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private var initialized = false
    private var consentState = MetaAdsConsentState()
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    private let attributionCoordinator = MetaAdsAttributionCoordinator()
    private var permissionTask: Task<Void, Never>?

    func didFinishLaunching(options: [UIApplication.LaunchOptionsKey: Any]?) {
        launchOptions = options
        refreshConsent()
    }

    func leaveForeground() { consentState.leaveForeground() }

    func refreshConsent() {
        let authorized = configuration.isValid && ATTrackingManager.trackingAuthorizationStatus == .authorized
        guard authorized || initialized else {
            updateRevenueCatAttribution()
            return
        }
        // These defaults also live in Info.plist, before the SDK is touched.
        Settings.shared.isAutoLogAppEventsEnabled = false
        Settings.shared.isAdvertiserIDCollectionEnabled = authorized
        Settings.shared.isSKAdNetworkReportEnabled = false
        Settings.shared.isCodelessDebugLogEnabled = false
        AppEvents.shared.flushBehavior = .explicitOnly
        if authorized && !initialized {
            initialized = true
            ApplicationDelegate.shared.application(UIApplication.shared, didFinishLaunchingWithOptions: launchOptions)
        }
        updateRevenueCatAttribution()
        if consentState.shouldActivate(configured: initialized, authorized: authorized,
                                       active: UIApplication.shared.applicationState == .active) {
            AppEvents.shared.activateApp()
            // Explicit flushing prevents queued activation events being automatically
            // delivered by a timer after permission is revoked.
            AppEvents.shared.flush()
        }
    }

    /// Called after RevenueCat configuration and immediately before purchase/restore.
    func updateRevenueCatAttribution() {
        guard Purchases.isConfigured else { return }
        let status = ATTrackingManager.trackingAuthorizationStatus
        let authorized = configuration.isValid && status == .authorized
        attributionCoordinator.update(
            identity: Purchases.shared.appUserID,
            consent: status.rawValue,
            authorized: authorized,
            collect: { Purchases.shared.attribution.collectDeviceIdentifiers() },
            attach: { Purchases.shared.attribution.setFBAnonymousID(AppEvents.shared.anonymousID) },
            clear: {
                Purchases.shared.attribution.setAttributes(["$idfa": "", "$idfv": "", "$ip": "", "$fbAnonId": ""])
            },
            sync: { completion in
                // RC itself refreshes $attConsentStatus on attribute sync/receipt posts.
                Purchases.shared.syncAttributesAndOfferingsIfNeeded { _, error in completion(error == nil) }
            }
        )
    }

    /// Paywall stays in its loading state while the native prompt is open.
    /// Refusal and restricted status always allow purchases to continue.
    func requestPermissionBeforePaywall() async {
        if let permissionTask {
            await permissionTask.value
            refreshConsent()
            return
        }
        guard configuration.isValid,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined,
              UIApplication.shared.applicationState == .active else {
            refreshConsent()
            return
        }
        AnalyticsService.shared.capture(
            AnalyticsEvent.permissionRequested,
            properties: ["permission": "app_tracking_transparency"]
        )
        let request = Task { _ = await ATTrackingManager.requestTrackingAuthorization() }
        permissionTask = request
        await request.value
        permissionTask = nil
        refreshConsent()
        AnalyticsService.shared.capture(
            AnalyticsEvent.permissionResolved,
            properties: [
                "permission": "app_tracking_transparency",
                "status": Self.analyticsName(for: ATTrackingManager.trackingAuthorizationStatus),
            ]
        )
    }

    private static func analyticsName(for status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }
}

final class NimaApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MetaAdsService.shared.didFinishLaunching(options: launchOptions)
        return true
    }
}

/// Applies consent to the current RC identity before syncing. Failed syncs are
/// retried on the next foreground/purchase; unchanged states avoid rate limiting.
@MainActor
final class MetaAdsAttributionCoordinator {
    private var appliedState: String?
    private var generation = 0

    func update(identity: String?, consent: UInt, authorized: Bool,
                collect: () -> Void, attach: () -> Void, clear: () -> Void,
                sync: (@escaping (Bool) -> Void) -> Void) {
        guard let identity, !identity.isEmpty else { return }
        let state = "\(identity):\(consent):\(authorized)"
        guard appliedState != state else { return }
        generation += 1
        let requestGeneration = generation
        appliedState = state
        if authorized {
            collect()
            attach()
        } else {
            clear()
        }
        sync { [weak self] succeeded in
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                if !succeeded { self.appliedState = nil }
            }
        }
    }
}
