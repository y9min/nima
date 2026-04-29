import Foundation
import Observation

struct FeaturePolicyV1: Codable {
    enum ReelsBlockMode: String, Codable {
        case legacySafe = "legacy_safe"
        case strict
        case hardPreload = "hard_preload"
    }

    struct AppMetaIPGuardConfig: Codable {
        var enabled: Bool
    }

    struct MetaIPGuardConfig: Codable {
        var instagram: AppMetaIPGuardConfig
        var facebook: AppMetaIPGuardConfig
    }

    struct ReelsPolicyConfig: Codable {
        var instagramMode: ReelsBlockMode
        var facebookMode: ReelsBlockMode
    }

    let version: Int
    var profile: String
    var shadowModeEnabled: Bool
    var adaptiveBackoffEnabled: Bool
    var udpDecoderFailOpenEnabled: Bool
    var retryStormThreshold: Int
    var retryStormWindowSec: Int
    var backoffMinSec: Int
    var backoffMaxSec: Int
    var metaIpGuard: MetaIPGuardConfig
    var reelsPolicy: ReelsPolicyConfig
    var appToggles: [String: [String: Bool]]

    init(
        version: Int = 1,
        profile: String = "minimal-impact",
        shadowModeEnabled: Bool = false,
        adaptiveBackoffEnabled: Bool = true,
        udpDecoderFailOpenEnabled: Bool = true,
        retryStormThreshold: Int = 8,
        retryStormWindowSec: Int = 3,
        backoffMinSec: Int = 10,
        backoffMaxSec: Int = 30,
        metaIpGuard: MetaIPGuardConfig = MetaIPGuardConfig(
            instagram: AppMetaIPGuardConfig(enabled: true),
            facebook: AppMetaIPGuardConfig(enabled: true)
        ),
        reelsPolicy: ReelsPolicyConfig = ReelsPolicyConfig(instagramMode: .legacySafe, facebookMode: .hardPreload),
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles
    ) {
        self.version = version
        self.profile = profile
        self.shadowModeEnabled = shadowModeEnabled
        self.adaptiveBackoffEnabled = adaptiveBackoffEnabled
        self.udpDecoderFailOpenEnabled = udpDecoderFailOpenEnabled
        self.retryStormThreshold = retryStormThreshold
        self.retryStormWindowSec = retryStormWindowSec
        self.backoffMinSec = backoffMinSec
        self.backoffMaxSec = backoffMaxSec
        self.metaIpGuard = metaIpGuard
        self.reelsPolicy = reelsPolicy
        self.appToggles = appToggles
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false
        ],
        "facebook": [
            "reels": false
        ]
    ]

    static func defaultPolicy() -> FeaturePolicyV1 {
        FeaturePolicyV1()
    }

    mutating func set(appId: String, optionId: String, isEnabled: Bool) {
        if appToggles[appId] == nil {
            appToggles[appId] = [:]
        }
        appToggles[appId]?[optionId] = isEnabled
    }

    mutating func mergeDefaults() {
        retryStormThreshold = max(retryStormThreshold, 1)
        retryStormWindowSec = max(retryStormWindowSec, 1)
        backoffMinSec = max(backoffMinSec, 1)
        backoffMaxSec = max(backoffMaxSec, backoffMinSec)
        for (appId, defaults) in Self.defaultToggles {
            if appToggles[appId] == nil {
                appToggles[appId] = defaults
                continue
            }
            for (optionId, value) in defaults where appToggles[appId]?[optionId] == nil {
                appToggles[appId]?[optionId] = value
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case profile
        case shadowModeEnabled
        case adaptiveBackoffEnabled
        case udpDecoderFailOpenEnabled
        case retryStormThreshold
        case retryStormWindowSec
        case backoffMinSec
        case backoffMaxSec
        case metaIpGuard
        case reelsPolicy
        case appToggles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? "minimal-impact"
        shadowModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .shadowModeEnabled) ?? false
        adaptiveBackoffEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveBackoffEnabled) ?? true
        udpDecoderFailOpenEnabled = try container.decodeIfPresent(Bool.self, forKey: .udpDecoderFailOpenEnabled) ?? true
        retryStormThreshold = max(1, try container.decodeIfPresent(Int.self, forKey: .retryStormThreshold) ?? 8)
        retryStormWindowSec = max(1, try container.decodeIfPresent(Int.self, forKey: .retryStormWindowSec) ?? 3)
        backoffMinSec = max(1, try container.decodeIfPresent(Int.self, forKey: .backoffMinSec) ?? 10)
        backoffMaxSec = max(backoffMinSec, try container.decodeIfPresent(Int.self, forKey: .backoffMaxSec) ?? 30)
        metaIpGuard = try container.decodeIfPresent(MetaIPGuardConfig.self, forKey: .metaIpGuard)
            ?? MetaIPGuardConfig(instagram: AppMetaIPGuardConfig(enabled: true), facebook: AppMetaIPGuardConfig(enabled: true))
        reelsPolicy = try container.decodeIfPresent(ReelsPolicyConfig.self, forKey: .reelsPolicy)
            ?? ReelsPolicyConfig(instagramMode: .legacySafe, facebookMode: .hardPreload)
        appToggles = try container.decodeIfPresent([String: [String: Bool]].self, forKey: .appToggles) ?? FeaturePolicyV1.defaultToggles
    }
}

struct AppOption: Codable, Identifiable {
    let id: String
    let label: String
    var isSelected: Bool
}

struct AppOptionsData: Codable {
    let appId: String
    let options: [AppOption]
}

struct AppOptionsResponse: Codable {
    let apps: [String: AppOptionsData]

    enum CodingKeys: String, CodingKey {
        case apps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([String: AppOptionsData].self, forKey: .apps)
    }
}

@Observable
final class AppOptionsService {
    static let shared = AppOptionsService()

    private var cachedData: [String: AppOptionsData] = [:]
    private var optionStates: [String: [String: Bool]] = [:] // appId -> optionId -> isSelected
    private let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)

    private init() {
        loadData()
        loadSavedStates()
        syncFeaturePolicy()
    }

    func loadData() {
        guard let url = Bundle.main.url(forResource: "app_options", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: AppOptionsData].self, from: data) else {
            return
        }
        cachedData = decoded

        // Initialize option states from cached data (all default to false from JSON)
        for (appId, appData) in decoded {
            var states: [String: Bool] = [:]
            for option in appData.options {
                states[option.id] = option.isSelected
            }
            optionStates[appId] = states
        }
    }

    private func loadSavedStates() {
        if let policyData = defaults?.data(forKey: BubbleConstants.featurePolicyKey),
           let policy = try? JSONDecoder().decode(FeaturePolicyV1.self, from: policyData) {
            var mergedPolicy = policy
            mergedPolicy.mergeDefaults()
            for (appId, states) in mergedPolicy.appToggles {
                if optionStates[appId] == nil {
                    optionStates[appId] = [:]
                }
                for (optionId, isSelected) in states {
                    optionStates[appId]?[optionId] = isSelected
                }
            }
            return
        }
    }

    private func syncFeaturePolicy() {
        var policy = loadFeaturePolicy()
        for (appId, appStates) in optionStates {
            for (optionId, isSelected) in appStates {
                policy.set(appId: appId, optionId: optionId, isEnabled: isSelected)
            }
        }
        policy.adaptiveBackoffEnabled = defaults?.bool(forKey: BubbleConstants.adaptiveBackoffEnabledKey) ?? policy.adaptiveBackoffEnabled
        policy.udpDecoderFailOpenEnabled = defaults?.bool(forKey: BubbleConstants.udpDecoderFailOpenEnabledKey) ?? policy.udpDecoderFailOpenEnabled
        policy.mergeDefaults()
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
    }

    private func loadFeaturePolicy() -> FeaturePolicyV1 {
        guard let data = defaults?.data(forKey: BubbleConstants.featurePolicyKey),
              let decoded = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return .defaultPolicy()
        }
        var policy = decoded
        policy.mergeDefaults()
        return policy
    }

    func setAdaptiveBackoffEnabled(_ isEnabled: Bool) {
        defaults?.set(isEnabled, forKey: BubbleConstants.adaptiveBackoffEnabledKey)
        var policy = loadFeaturePolicy()
        policy.adaptiveBackoffEnabled = isEnabled
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
    }

    func setUDPDecoderFailOpenEnabled(_ isEnabled: Bool) {
        defaults?.set(isEnabled, forKey: BubbleConstants.udpDecoderFailOpenEnabledKey)
        var policy = loadFeaturePolicy()
        policy.udpDecoderFailOpenEnabled = isEnabled
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
    }

    func getOptions(for appId: String) -> AppOptionsData? {
        return cachedData[appId]
    }

    func getSelectedOptions(for appId: String) -> [AppOption] {
        return getAllOptions(for: appId).filter { $0.isSelected }
    }

    func getAllOptions(for appId: String) -> [AppOption] {
        guard let appData = cachedData[appId] else { return [] }
        return appData.options.map { option in
            var mutableOption = option
            mutableOption.isSelected = optionStates[appId]?[option.id] ?? false
            return mutableOption
        }
    }

    func toggleOption(appId: String, optionId: String) {
        if optionStates[appId] == nil {
            optionStates[appId] = [:]
        }
        let currentState = optionStates[appId]?[optionId] ?? false
        optionStates[appId]?[optionId] = !currentState
        syncFeaturePolicy()
    }

    func isOptionSelected(appId: String, optionId: String) -> Bool {
        return optionStates[appId]?[optionId] ?? false
    }
}
