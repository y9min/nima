import AppTrackingTransparency
import Foundation
import RevenueCat
import StoreKit
import TenjinSDK
import UIKit

struct TenjinConfiguration {
    let sdkKey: String
    let enabled: Bool

    init(info: [String: Any]) {
        sdkKey = (info["TENJIN_SDK_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        enabled = ["YES", "TRUE", "1"].contains(String(describing: info["TENJIN_ENABLED"] ?? "").uppercased())
    }

    var isValid: Bool {
        enabled && !sdkKey.isEmpty && !sdkKey.contains("$(") && !sdkKey.hasPrefix("your-")
    }
}

/// Names only cross the advertising boundary. Never forward arbitrary PostHog properties.
enum AcquisitionMilestone: Int, CaseIterable {
    case installed = 0, onboardingCompleted, paywallViewed, checkoutStarted, trialStarted, paidSubscription

    var coarseValue: SKAdNetwork.CoarseConversionValue {
        switch self {
        case .installed, .onboardingCompleted, .paywallViewed, .checkoutStarted: return .low
        case .trialStarted: return .medium
        case .paidSubscription: return .high
        }
    }

    static func from(productEvent: String) -> Self? {
        switch productEvent {
        case AnalyticsEvent.onboardingCompleted: return .onboardingCompleted
        case AnalyticsEvent.paywallViewed: return .paywallViewed
        case AnalyticsEvent.purchaseStarted: return .checkoutStarted
        default: return nil
        }
    }

    var tenjinEvent: String? {
        switch self {
        case .onboardingCompleted: return "onboarding_completed"
        case .paywallViewed: return "paywall_viewed"
        case .checkoutStarted: return "checkout_started"
        // RevenueCat owns these events, including their delivery to Meta.
        case .installed, .trialStarted, .paidSubscription: return nil
        }
    }
}

enum AcquisitionContext {
    /// Discard advertising IDs, device data, click IDs, arbitrary fields and deep-link URLs.
    static func properties(from payload: [AnyHashable: Any]) -> [String: String] {
        guard let network = payload["ad_network"] as? String, !network.isEmpty else { return [:] }
        let source = network.lowercased()
        // Meta's AMM data has separate restrictions on individual profiles and
        // third-party sharing. Keep it in the MMP; don't enrich PostHog/RC users.
        guard !["facebook", "meta", "instagram", "audience_network"].contains(where: source.contains) else { return [:] }
        var result: [String: String] = [:]
        for key in ["ad_network", "campaign_id", "campaign_name", "remote_campaign_id", "creative_name"] {
            if let value = payload[key] as? String, !value.isEmpty {
                result["acquisition_" + key] = String(value.prefix(200))
            }
        }
        return result
    }
}

/// Persists progress separately from successful Apple delivery, so failures can retry.
struct AcquisitionConversionState {
    let defaults: UserDefaults
    private let prefix = "acquisition.skan.v1."

    var firstObserved: Date? { defaults.object(forKey: prefix + "firstObserved") as? Date }

    var milestone: AcquisitionMilestone {
        AcquisitionMilestone(rawValue: defaults.integer(forKey: prefix + "milestone")) ?? .installed
    }

    func advance(to next: AcquisitionMilestone) {
        defaults.set(max(milestone.rawValue, next.rawValue), forKey: prefix + "milestone")
    }

    /// Reassert daily so Apple can apply progress in its current window.
    /// An upgrade observation is not a reliable estimate of Apple’s install timer.
    func currentUpdate(now: Date) -> (milestone: AcquisitionMilestone, day: Int)? {
        let first = defaults.object(forKey: prefix + "firstObserved") as? Date ?? now
        if defaults.object(forKey: prefix + "firstObserved") == nil {
            defaults.set(first, forKey: prefix + "firstObserved")
        }
        let age = max(0, now.timeIntervalSince(first))
        guard age < 35 * 86_400 else { return nil }
        let day = Int(age / 86_400)
        return (milestone, day)
    }

    func pendingUpdate(now: Date) -> (milestone: AcquisitionMilestone, day: Int)? {
        guard let update = currentUpdate(now: now) else { return nil }
        let day = update.day
        let key = prefix + "delivered.\(day)"
        if let previous = defaults.object(forKey: key) as? Int, previous >= milestone.rawValue { return nil }
        return update
    }

    func markDelivered(_ value: AcquisitionMilestone, day: Int) {
        let key = prefix + "delivered.\(day)"
        let previous = defaults.object(forKey: key) as? Int ?? -1
        defaults.set(max(previous, value.rawValue), forKey: key)
    }
}

/// Tenjin supplies attribution; RevenueCat is the only subscription revenue sender.
/// Apple aggregate measurement is independent of individual tracking permission.
@MainActor
final class AcquisitionTrackingService {
    static let shared = AcquisitionTrackingService()
    private let configuration = TenjinConfiguration(info: Bundle.main.infoDictionary ?? [:])
    private let conversions = AcquisitionConversionState(defaults: .standard)
    private var initialized = false
    private var connectedThisForeground = false
    private var attachedIdentity: String?
    private var updatingConversion = false
    private var attributionTask: Task<Void, Never>?
    private var attributionGeneration = 0
    private var lastTenjinConversionSubmission: String?

    var isConfigured: Bool { configuration.isValid }

    func refreshConsent() {
        guard configuration.isValid, NSClassFromString("XCTestCase") == nil else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else {
            if initialized { TenjinSDK.optOut() }
            connectedThisForeground = false
            attachedIdentity = nil
            attributionTask?.cancel()
            attributionTask = nil
            attributionGeneration += 1
            AnalyticsService.shared.setAcquisitionContext([:])
            lastTenjinConversionSubmission = nil
            updateAppleConversion()
            return
        }
        if !initialized {
            TenjinSDK.getInstance(configuration.sdkKey)
            TenjinSDK.disableAutoSubscriptionTracking()
            TenjinSDK.disableAutoPurchaseTracking()
            TenjinSDK.setCacheEventSetting(false)
            TenjinSDK.optOutGoogleDMA()
            initialized = true
        }
        TenjinSDK.optIn()
        if !connectedThisForeground && UIApplication.shared.applicationState == .active {
            TenjinSDK.connect()
            connectedThisForeground = true
            requestAttributionContext()
        }
        syncRevenueCatIdentity()
        updateAppleConversion()
    }

    func leaveForeground() {
        connectedThisForeground = false
        attributionTask?.cancel()
        attributionTask = nil
        attributionGeneration += 1
        lastTenjinConversionSubmission = nil
    }

    func captureProductEvent(_ event: String) {
        guard configuration.isValid, NSClassFromString("XCTestCase") == nil,
              let milestone = AcquisitionMilestone.from(productEvent: event) else { return }
        conversions.advance(to: milestone)
        refreshConsent()
        guard connectedThisForeground,
              ATTrackingManager.trackingAuthorizationStatus == .authorized,
              let name = milestone.tenjinEvent else { return }
        TenjinSDK.sendEvent(withName: name)
    }

    /// Called only from successful purchase callbacks, never from restore or cached access.
    /// This updates Apple's aggregate value, without sending a second revenue event.
    func purchaseCompleted(_ info: CustomerInfo) {
        guard configuration.isValid,
              let entitlement = info.entitlements.active[SubscriptionStore.premiumEntitlementID],
              entitlement.ownershipType == .purchased,
              !entitlement.isSandbox else { return }
        let milestone: AcquisitionMilestone = entitlement.periodType == .trial ? .trialStarted : .paidSubscription
        conversions.advance(to: milestone)
        updateAppleConversion()
    }

    /// A trial may convert while the app is closed. Refresh aggregate progress on
    /// return only for a new transaction, not an old/restored subscriber's access.
    func subscriptionUpdated(_ info: CustomerInfo) {
        guard let firstObserved = conversions.firstObserved,
              let entitlement = info.entitlements.active[SubscriptionStore.premiumEntitlementID],
              let latestPurchaseDate = entitlement.latestPurchaseDate,
              latestPurchaseDate >= firstObserved else { return }
        purchaseCompleted(info)
    }

    func syncRevenueCatIdentity() {
        guard initialized, Purchases.isConfigured,
              ATTrackingManager.trackingAuthorizationStatus == .authorized,
              let installationID = TenjinSDK.getAnalyticsInstallationId(), !installationID.isEmpty else { return }
        let identity = "\(Purchases.shared.appUserID):\(installationID)"
        guard identity != attachedIdentity else { return }
        attachedIdentity = identity
        Purchases.shared.attribution.setTenjinAnalyticsInstallationID(installationID)
        Purchases.shared.syncAttributesAndOfferingsIfNeeded { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor in
                if self?.attachedIdentity == identity { self?.attachedIdentity = nil }
            }
        }
    }

    private func requestAttributionContext() {
        attributionTask?.cancel()
        attributionGeneration += 1
        let generation = attributionGeneration
        attributionTask = Task { @MainActor [weak self] in
            for attempt in 0..<3 {
                do { try await Task.sleep(nanoseconds: attempt == 0 ? 3_000_000_000 : 2_000_000_000) }
                catch { return }
                guard let self, generation == self.attributionGeneration,
                      ATTrackingManager.trackingAuthorizationStatus == .authorized else { return }
                // Tenjin only returns fields allowed by the network and account plan.
                let properties: [String: String] = await withCheckedContinuation { continuation in
                    TenjinSDK.sharedInstance().getAttributionInfo { payload, _ in
                        continuation.resume(returning: payload.map { AcquisitionContext.properties(from: $0) } ?? [:])
                    }
                }
                guard !Task.isCancelled, generation == self.attributionGeneration,
                      ATTrackingManager.trackingAuthorizationStatus == .authorized else { return }
                if !properties.isEmpty {
                    AnalyticsService.shared.setAcquisitionContext(properties)
                    AnalyticsService.shared.capture("acquisition_attribution_resolved", properties: properties)
                    if Purchases.isConfigured {
                        var attributes: [String: String] = [:]
                        attributes["$mediaSource"] = properties["acquisition_ad_network"]
                        attributes["$campaign"] = properties["acquisition_campaign_name"]
                        attributes["$creative"] = properties["acquisition_creative_name"]
                        Purchases.shared.attribution.setAttributes(attributes)
                        Purchases.shared.syncAttributesAndOfferingsIfNeeded { _, _ in }
                    }
                    return
                }
            }
        }
    }

    private func updateAppleConversion() {
        guard !updatingConversion else { return }
        if initialized, connectedThisForeground,
           ATTrackingManager.trackingAuthorizationStatus == .authorized {
            guard let update = conversions.currentUpdate(now: Date()) else { return }
            let submission = "\(update.day):\(update.milestone.rawValue)"
            guard lastTenjinConversionSubmission != submission else { return }
            lastTenjinConversionSubmission = submission
            // Tenjin updates Apple and reports the same value to its servers. Do
            // not also call Apple for this update. Its API has no acknowledgement;
            // retain progress and resubmit next foreground rather than claim delivery.
            TenjinSDK.updatePostbackConversionValue(Int32(update.milestone.rawValue),
                                                     coarseValue: update.milestone.coarseValue.rawValue,
                                                     lockWindow: false)
            AnalyticsService.shared.capture("attribution_conversion_update", properties: [
                "conversion_value": update.milestone.rawValue,
                "measurement_day": update.day,
                "transport": "tenjin",
                "status": "submitted",
            ])
            return
        }
        guard let update = conversions.pendingUpdate(now: Date()) else { return }
        updatingConversion = true
        // Without individual tracking consent, only call Apple's aggregate API.
        // This coordinator serializes both routes using the same monotonic schema;
        // Meta's independent updater stays disabled. Never lock a window early.
        SKAdNetwork.updatePostbackConversionValue(update.milestone.rawValue,
                                                  coarseValue: update.milestone.coarseValue,
                                                  lockWindow: false) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.updatingConversion = false
                if error == nil {
                    self.conversions.markDelivered(update.milestone, day: update.day)
                    self.updateAppleConversion()
                }
                AnalyticsService.shared.capture("attribution_conversion_update", properties: [
                    "conversion_value": update.milestone.rawValue,
                    "measurement_day": update.day,
                    "transport": "apple_aggregate",
                    "status": error == nil ? "succeeded" : "failed",
                ])
            }
        }
    }
}
