import Foundation
import Observation

struct FeaturePolicyV1: Codable {
    let version: Int
    var profile: String
    var shadowModeEnabled: Bool
    var transportStabilityMode: Bool
    var appToggles: [String: [String: Bool]]
    var appStrategies: [String: String]
    var revision: Int
    var updatedAt: TimeInterval
    var updatedBy: String

    init(
        version: Int = 1,
        profile: String = "minimal-impact",
        shadowModeEnabled: Bool = false,
        transportStabilityMode: Bool = true,
        appToggles: [String: [String: Bool]] = FeaturePolicyV1.defaultToggles,
        appStrategies: [String: String] = FeaturePolicyV1.defaultStrategies,
        revision: Int = 0,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        updatedBy: String = "app.options.init"
    ) {
        self.version = version
        self.profile = profile
        self.shadowModeEnabled = shadowModeEnabled
        self.transportStabilityMode = transportStabilityMode
        self.appToggles = appToggles
        self.appStrategies = appStrategies
        self.revision = revision
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    static let defaultToggles: [String: [String: Bool]] = [
        "instagram": [
            "reels": false,
            "strict_reels": false
        ],
        "tiktok": [
            "video_block": false
        ]
    ]
    static let defaultStrategies: [String: String] = [
        "instagram": "legacy_reels",
        "tiktok": "hardened_video"
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
        for (appId, strategy) in Self.defaultStrategies where appStrategies[appId] == nil {
            appStrategies[appId] = strategy
        }
        normalizeInstagramStrictReels()
    }

    @discardableResult
    mutating func normalizeInstagramStrictReels() -> Bool {
        let legacyWasEnabled = appToggles["instagram"]?["reels"] == true
        let strictWasEnabled = appToggles["instagram"]?["strict_reels"] == true
        guard legacyWasEnabled || strictWasEnabled else { return false }

        if appToggles["instagram"] == nil {
            appToggles["instagram"] = Self.defaultToggles["instagram"] ?? [:]
        }
        appToggles["instagram"]?["strict_reels"] = true
        appToggles["instagram"]?["reels"] = false
        return legacyWasEnabled || !strictWasEnabled
    }

    mutating func bumpRevision(updatedBy: String) {
        revision += 1
        updatedAt = Date().timeIntervalSince1970
        self.updatedBy = updatedBy
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case profile
        case shadowModeEnabled
        case transportStabilityMode = "transport_stability_mode"
        case appToggles
        case appStrategies = "app_strategies"
        case revision
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? "minimal-impact"
        shadowModeEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowModeEnabled) ?? false
        transportStabilityMode = try c.decodeIfPresent(Bool.self, forKey: .transportStabilityMode) ?? true
        appToggles = try c.decodeIfPresent([String: [String: Bool]].self, forKey: .appToggles) ?? Self.defaultToggles
        appStrategies = try c.decodeIfPresent([String: String].self, forKey: .appStrategies) ?? Self.defaultStrategies
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy) ?? "unknown"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(profile, forKey: .profile)
        try c.encode(shadowModeEnabled, forKey: .shadowModeEnabled)
        try c.encode(transportStabilityMode, forKey: .transportStabilityMode)
        try c.encode(appToggles, forKey: .appToggles)
        try c.encode(appStrategies, forKey: .appStrategies)
        try c.encode(revision, forKey: .revision)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
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
        syncFeaturePolicyIfMissing()
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
            let shouldPersistMigration = policy.appToggles["instagram"]?["reels"] == true
            mergedPolicy.mergeDefaults()
            if shouldPersistMigration {
                mergedPolicy.bumpRevision(updatedBy: "app.options.migrate_strict_reels")
                persistPolicy(mergedPolicy)
            }
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

    private func syncFeaturePolicyIfMissing() {
        guard defaults?.data(forKey: BubbleConstants.featurePolicyKey) == nil else { return }
        var policy = FeaturePolicyV1.defaultPolicy()
        policy.mergeDefaults()
        policy.bumpRevision(updatedBy: "app.options.bootstrap")
        persistPolicy(policy)
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

    func toggleOption(appId: String, optionId: String, source: String = "unknown") {
        if optionStates[appId] == nil {
            optionStates[appId] = [:]
        }
        var policy = loadFeaturePolicy()
        let effectiveOptionId = appId == "instagram" && optionId == "reels" ? "strict_reels" : optionId
        let currentState = policy.appToggles[appId]?[effectiveOptionId] ?? false
        let newState = !currentState
        policy.set(appId: appId, optionId: effectiveOptionId, isEnabled: newState)
        if appId == "instagram" {
            policy.set(appId: appId, optionId: "reels", isEnabled: false)
        }
        policy.mergeDefaults()
        policy.bumpRevision(updatedBy: "app.options.toggle")
        persistPolicy(policy)
        if let updatedStates = policy.appToggles[appId] {
            for (updatedOptionId, isEnabled) in updatedStates {
                optionStates[appId]?[updatedOptionId] = isEnabled
            }
        }
        AppDiagnosticsLogger.log(
            "OPTION_TOGGLE app=\(appId) option=\(optionId) new_state=\(newState) revision=\(policy.revision) source=\(source)"
        )
    }

    private func persistPolicy(_ policy: FeaturePolicyV1) {
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: BubbleConstants.featurePolicyKey)
        }
    }

    func isOptionSelected(appId: String, optionId: String) -> Bool {
        return optionStates[appId]?[optionId] ?? false
    }
}

enum AppDiagnosticsLogger {
    private static let lock = NSLock()
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BubbleConstants.appGroupID)?
            .appendingPathComponent(BubbleConstants.appLogFileName)
    }

    static func log(_ message: String, function: String = #function) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(function)] \(message)\n"

        guard let fileURL else { return }

        lock.lock()
        defer { lock.unlock() }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int,
           size > BubbleConstants.maxLogSizeBytes {
            rotateLog(at: fileURL)
        }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
        applyLockSafeProtection(to: fileURL)
    }

    static func readLog() -> String {
        guard let fileURL else { return "(no app diagnostic log yet)" }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "(no app diagnostic log yet)"
    }

    private static func rotateLog(at fileURL: URL) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let keepFrom = lines.count / 2
        let trimmed = lines[keepFrom...].joined(separator: "\n")
        try? trimmed.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        applyLockSafeProtection(to: fileURL)
    }

    private static func applyLockSafeProtection(to fileURL: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
