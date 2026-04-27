import Foundation
import Observation

struct FeaturePolicyV1: Codable {
    let version: Int
    var profile: String
    var shadowModeEnabled: Bool
    var appToggles: [String: [String: Bool]]

    init(
        version: Int = 1,
        profile: String = "minimal-impact",
        shadowModeEnabled: Bool = false,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles
    ) {
        self.version = version
        self.profile = profile
        self.shadowModeEnabled = shadowModeEnabled
        self.appToggles = appToggles
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
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
