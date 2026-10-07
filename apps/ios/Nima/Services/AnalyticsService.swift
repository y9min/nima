import Foundation
import PostHog

enum AnalyticsEvent {
    static let onboardingStarted = "onboarding_started"
    static let onboardingStepViewed = "onboarding_step_viewed"
    static let onboardingStepCompleted = "onboarding_step_completed"
    static let onboardingCompleted = "onboarding_completed"
    static let paywallViewed = "paywall_screen_viewed"
    static let paywallUnlocked = "paywall_unlocked"
    static let purchaseStarted = "purchase_started"
    static let purchaseSucceeded = "purchase_succeeded"
    static let purchaseFailed = "purchase_failed"
    static let accountScreenViewed = "account_screen_viewed"
    static let authStarted = "auth_started"
    static let authSucceeded = "auth_succeeded"
    static let authFailed = "auth_failed"
    static let accountLinkDeferred = "account_link_deferred"
    static let restoreStarted = "restore_started"
    static let restoreSucceeded = "restore_succeeded"
    static let restoreFailed = "restore_failed"
    static let appUnlocked = "app_unlocked"
}

final class AnalyticsService {
    static let shared = AnalyticsService()
    static let flowVersion = "post_paywall_account_v1"

    private(set) var isConfigured = false

    private init() {}

    func configure() {
        guard !isConfigured,
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

    func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isConfigured else { return }
        var safeProperties = properties
        safeProperties["flow_version"] = Self.flowVersion
        PostHogSDK.shared.capture(event, properties: safeProperties)
    }

    func identify(userID: UUID) {
        guard isConfigured else { return }
        PostHogSDK.shared.identify(userID.uuidString.lowercased())
    }

    func resetIdentity() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
    }

    var distinctID: String? {
        guard isConfigured else { return nil }
        return PostHogSDK.shared.getDistinctId()
    }

    private static func bundleValue(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
