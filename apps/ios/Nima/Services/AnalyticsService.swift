import AppTrackingTransparency
import Foundation
import PostHog

enum AnalyticsEvent {
    static let appFirstObserved = "app_first_observed"
    static let sessionStarted = "app_session_started"
    static let appForegrounded = "app_foregrounded"
    static let appBackgrounded = "app_backgrounded"
    static let activationCompleted = "activation_completed"
    static let onboardingStarted = "onboarding_started"
    static let onboardingStepViewed = "onboarding_step_viewed"
    static let onboardingStepCompleted = "onboarding_step_completed"
    static let onboardingCompleted = "onboarding_completed"
    static let permissionRequested = "permission_requested"
    static let permissionResolved = "permission_resolved"
    static let guidedPracticeStarted = "guided_practice_started"
    static let guidedPracticeStepViewed = "guided_practice_step_viewed"
    static let guidedPracticeStepCompleted = "guided_practice_step_completed"
    static let guidedPracticeResumed = "guided_practice_resumed"
    static let guidedPracticeCompleted = "guided_practice_completed"
    static let guidedWindowsStarted = "guided_windows_started"
    static let guidedWindowsStepViewed = "guided_windows_step_viewed"
    static let guidedWindowsCompleted = "guided_windows_completed"
    static let paywallViewed = "paywall_screen_viewed"
    static let paywallLoadStarted = "paywall_load_started"
    static let paywallLoaded = "paywall_loaded"
    static let paywallLoadFailed = "paywall_load_failed"
    static let paywallClosed = "paywall_closed"
    static let paywallUnlocked = "paywall_unlocked"
    static let purchaseStarted = "purchase_started"
    static let purchaseCancelled = "purchase_cancelled"
    static let purchasePending = "purchase_pending"
    static let purchaseSucceeded = "purchase_succeeded"
    static let purchaseFailed = "purchase_failed"
    static let entitlementActivated = "entitlement_activated"
    static let purchaseSucceededWithoutEntitlement = "purchase_succeeded_without_entitlement"
    static let restoreStarted = "restore_started"
    static let restoreSucceeded = "restore_succeeded"
    static let restoreFailed = "restore_failed"
    static let appUnlocked = "app_unlocked"
}

struct PurchaseAnalyticsAttempt {
    let id: UUID
    let startedAt: Date
    let offeringID: String
    let packageID: String
    let productID: String
    let price: Double
    let currencyCode: String?
    let localizedPrice: String

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        offeringID: String,
        packageID: String,
        productID: String,
        price: Double,
        currencyCode: String?,
        localizedPrice: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.offeringID = offeringID
        self.packageID = packageID
        self.productID = productID
        self.price = price
        self.currencyCode = currencyCode
        self.localizedPrice = localizedPrice
    }

    func properties(now: Date = Date()) -> [String: Any] {
        var properties: [String: Any] = [
            "purchase_attempt_id": id.uuidString.lowercased(),
            "offering_id": offeringID,
            "package_id": packageID,
            "product_id": productID,
            "price": price,
            "localized_price": localizedPrice,
            "duration_ms": max(0, Int(now.timeIntervalSince(startedAt) * 1_000)),
        ]
        if let currencyCode, !currencyCode.isEmpty {
            properties["currency"] = currencyCode
        }
        return properties
    }
}

enum PurchaseAnalytics {
    static func errorProperties(_ error: NSError) -> [String: Any] {
        var properties: [String: Any] = [
            "error_source": errorSource(error),
            "revenuecat_error_code": error.code,
            "revenuecat_error_domain": error.domain,
        ]

        if let readableCode = stringValue(error.userInfo["readable_error_code"])
            ?? stringValue(error.userInfo["rc_code_name"]) {
            properties["revenuecat_error_name"] = readableCode
        }
        if let backendCode = scalarValue(error.userInfo["rc_backend_error_code"]) {
            properties["revenuecat_backend_error_code"] = backendCode
        }
        if let statusCode = scalarValue(error.userInfo["rc_response_status_code"]) {
            properties["http_status_code"] = statusCode
        }
        if let underlying = underlyingError(error) {
            properties["store_error_domain"] = underlying.domain
            properties["store_error_code"] = underlying.code
        }
        return properties
    }

    static func errorSource(_ error: NSError) -> String {
        if error.userInfo["rc_backend_error_code"] != nil || [11, 12, 16, 17, 23, 29, 33, 37].contains(error.code) {
            return "revenuecat_backend"
        }
        if [10, 35].contains(error.code) {
            return "network"
        }
        if underlyingError(error) != nil || [2, 3, 4, 5, 6, 8, 9, 18, 19, 20, 32].contains(error.code) {
            return "apple_storekit"
        }
        return "revenuecat_sdk"
    }

    private static func underlyingError(_ error: NSError) -> NSError? {
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying
        }
        return error.userInfo["rc_root_error"] as? NSError
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func scalarValue(_ value: Any?) -> Any? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value
        case let value as Int: return value
        default: return nil
        }
    }
}

final class AnalyticsService {
    static let shared = AnalyticsService()
    static let flowVersion = "acquisition_v3"

    private(set) var isConfigured = false
    private var lifecycle = AnalyticsLifecycleState(defaults: .standard)
    private var sessionProperties: [String: Any] = [:]
    private var acquisitionProperties: [String: String] = [:]

    private init() {}

    func configure() {
        guard !isConfigured,
              NSClassFromString("XCTestCase") == nil,
              let token = Self.bundleValue(for: "POSTHOG_PROJECT_TOKEN"),
              let host = Self.bundleValue(for: "POSTHOG_HOST") else { return }

        let config = PostHogConfig(projectToken: token, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.sessionReplay = false
        config.personProfiles = .identifiedOnly
        config.disableGeoIp = true
        #if DEBUG
        config.debug = true
        #endif
        PostHogSDK.shared.setup(config)
        isConfigured = true
    }

    func enterForeground(existingInstallation: Bool) {
        guard isConfigured else { return }
        let update = lifecycle.enterForeground(now: Date(), existingInstallation: existingInstallation)
        guard let update else { return }
        sessionProperties = update.properties
        if update.isFirstObservation { capture(AnalyticsEvent.appFirstObserved) }
        if update.isNewSession { capture(AnalyticsEvent.sessionStarted) }
        capture(AnalyticsEvent.appForegrounded)
    }

    func leaveForeground() {
        guard isConfigured, let duration = lifecycle.leaveForeground(now: Date()) else { return }
        capture(AnalyticsEvent.appBackgrounded, properties: ["foreground_duration_ms": duration])
        PostHogSDK.shared.flush()
    }

    func capture(_ event: String, properties: [String: Any] = [:]) {
        // Acquisition must not depend on the product-analytics SDK being configured.
        Task { @MainActor in
            AcquisitionTrackingService.shared.captureProductEvent(event)
        }
        guard isConfigured else { return }
        var safeProperties = sessionProperties.merging(properties) { _, event in event }
        safeProperties["flow_version"] = Self.flowVersion
        safeProperties["event_id"] = UUID().uuidString.lowercased()
        safeProperties["app_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        safeProperties["app_build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        safeProperties["platform"] = "ios"
        safeProperties["event_schema_version"] = 1
        safeProperties["att_status"] = ATTrackingManager.trackingAuthorizationStatus.rawValue
        if ATTrackingManager.trackingAuthorizationStatus == .authorized {
            for (key, value) in acquisitionProperties { safeProperties[key] = value }
        }
        #if DEBUG
        safeProperties["environment"] = "development"
        #else
        safeProperties["environment"] = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            ? "sandbox" : "production"
        #endif
        PostHogSDK.shared.capture(event, properties: safeProperties)
        // A single completed practice is a product activation, not a purchase.
        if event == AnalyticsEvent.guidedPracticeCompleted,
           lifecycle.markActivation() {
            capture(AnalyticsEvent.activationCompleted)
        }
    }

    var distinctID: String? {
        guard isConfigured else { return nil }
        return PostHogSDK.shared.getDistinctId()
    }

    func setAcquisitionContext(_ properties: [String: String]) {
        acquisitionProperties = properties
    }

    private static func bundleValue(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}

/// Explicit foreground sessions avoid recording taps, screen content or browsing activity.
struct AnalyticsLifecycleState {
    let defaults: UserDefaults
    private(set) var activeSince: Date?
    private var sessionID: String?
    private var lastBackground: Date?
    private let prefix = "analytics.lifecycle.v1."

    struct ForegroundUpdate {
        let isFirstObservation: Bool
        let isNewSession: Bool
        let properties: [String: Any]
    }

    init(defaults: UserDefaults) { self.defaults = defaults }

    mutating func enterForeground(now: Date, existingInstallation: Bool) -> ForegroundUpdate? {
        guard activeSince == nil else { return nil }
        let first = defaults.object(forKey: prefix + "firstObserved") as? Date
        let firstObserved = first ?? now
        if first == nil {
            defaults.set(now, forKey: prefix + "firstObserved")
            defaults.set(existingInstallation ? "existing" : "new_or_incomplete", forKey: prefix + "cohort")
        }
        let newSession = sessionID == nil || lastBackground.map { now.timeIntervalSince($0) >= 1_800 } == true
        if newSession { sessionID = UUID().uuidString.lowercased() }
        activeSince = now
        return ForegroundUpdate(isFirstObservation: first == nil, isNewSession: newSession, properties: [
            "session_id": sessionID!,
            "days_since_first_observed": max(0, Int(now.timeIntervalSince(firstObserved) / 86_400)),
            "measurement_cohort": defaults.string(forKey: prefix + "cohort") ?? "unknown",
            "retention_basis": "first_observed_with_acquisition_v3",
        ])
    }

    mutating func leaveForeground(now: Date) -> Int? {
        guard let activeSince else { return nil }
        self.activeSince = nil
        lastBackground = now
        return max(0, Int(now.timeIntervalSince(activeSince) * 1_000))
    }

    func markActivation() -> Bool {
        let key = prefix + "activated"
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        return true
    }
}
