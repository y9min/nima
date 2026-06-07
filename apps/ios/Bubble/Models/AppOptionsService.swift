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
        ],
        "x": [
            "feed_block": false,
            "strict_feed_block": false
        ]
    ]
    static let defaultStrategies: [String: String] = [
        "instagram": "legacy_reels",
        "tiktok": "hardened_video",
        "x": "dm_preserving_feed"
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
    private var optionStates: [String: [String: Bool]] = [:] // effective appId -> optionId -> isSelected
    private var manualPolicy: FeaturePolicyV1 = .defaultPolicy()
    private var scheduledAppIDs: Set<String> = []
    private let defaults = UserDefaults(suiteName: BubbleConstants.appGroupID)

    private init() {
        loadData()
        loadSavedStates()
        persistEffectivePolicy(updatedBy: "app.options.init")
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
        let persistedManual = loadPersistedPolicy(forKey: BubbleConstants.manualFeaturePolicyKey)
        let legacyEffective = loadPersistedPolicy(forKey: BubbleConstants.featurePolicyKey)
        var loadedPolicy = persistedManual ?? legacyEffective ?? FeaturePolicyV1.defaultPolicy()
        let shouldPersistMigration = loadedPolicy.appToggles["instagram"]?["reels"] == true

        loadedPolicy.mergeDefaults()
        if shouldPersistMigration || persistedManual == nil {
            loadedPolicy.bumpRevision(updatedBy: persistedManual == nil ? "app.options.bootstrap_manual" : "app.options.migrate_strict_reels")
        }

        manualPolicy = loadedPolicy
        persistManualPolicy()
    }

    private func loadPersistedPolicy(forKey key: String) -> FeaturePolicyV1? {
        guard let data = defaults?.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FeaturePolicyV1.self, from: data) else {
            return nil
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
        let effectiveOptionId = appId == "instagram" && optionId == "reels" ? "strict_reels" : optionId
        let currentState = manualPolicy.appToggles[appId]?[effectiveOptionId] ?? false
        let newState = !currentState
        manualPolicy.set(appId: appId, optionId: effectiveOptionId, isEnabled: newState)
        if appId == "instagram" {
            manualPolicy.set(appId: appId, optionId: "reels", isEnabled: false)
        }
        manualPolicy.mergeDefaults()
        manualPolicy.bumpRevision(updatedBy: "app.options.toggle")
        persistManualPolicy()
        let effectivePolicy = persistEffectivePolicy(updatedBy: "app.options.toggle")
        AppDiagnosticsLogger.log(
            "OPTION_TOGGLE app=\(appId) option=\(optionId) manual_state=\(newState) effective_revision=\(effectivePolicy.revision) source=\(source)"
        )
    }

    @discardableResult
    func setScheduledBlockedAppIDs(_ appIDs: Set<String>, source: String = "time_windows") -> Bool {
        let normalized = appIDs.intersection(["instagram", "tiktok"])
        guard normalized != scheduledAppIDs else { return false }
        scheduledAppIDs = normalized
        let effectivePolicy = persistEffectivePolicy(updatedBy: source)
        AppDiagnosticsLogger.log(
            "SCHEDULED_BLOCKERS apps=\(normalized.sorted()) effective_revision=\(effectivePolicy.revision) source=\(source)"
        )
        return true
    }

    func isAppScheduled(_ appId: String) -> Bool {
        scheduledAppIDs.contains(appId)
    }

    func isOptionManuallySelected(appId: String, optionId: String) -> Bool {
        let effectiveOptionId = appId == "instagram" && optionId == "reels" ? "strict_reels" : optionId
        return manualPolicy.appToggles[appId]?[effectiveOptionId] ?? false
    }

    @discardableResult
    private func persistEffectivePolicy(updatedBy: String) -> FeaturePolicyV1 {
        var effectivePolicy = manualPolicy
        applyScheduledApps(to: &effectivePolicy)
        effectivePolicy.mergeDefaults()
        let currentRevision = loadPersistedPolicy(forKey: BubbleConstants.featurePolicyKey)?.revision ?? 0
        effectivePolicy.revision = max(currentRevision, manualPolicy.revision) + 1
        effectivePolicy.updatedAt = Date().timeIntervalSince1970
        effectivePolicy.updatedBy = updatedBy
        persistPolicy(effectivePolicy, forKey: BubbleConstants.featurePolicyKey)
        refreshOptionStates(from: effectivePolicy)
        return effectivePolicy
    }

    private func persistManualPolicy() {
        persistPolicy(manualPolicy, forKey: BubbleConstants.manualFeaturePolicyKey)
    }

    private func persistPolicy(_ policy: FeaturePolicyV1, forKey key: String) {
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: key)
        }
    }

    func isOptionSelected(appId: String, optionId: String) -> Bool {
        return optionStates[appId]?[optionId] ?? false
    }

    var hasAnyEnabledBlockingOption: Bool {
        firstEnabledBlockerSource != nil
    }

    var firstEnabledBlockerSource: String? {
        let preferredAppOrder = ["instagram", "tiktok", "x"]
        let otherAppIDs = optionStates.keys
            .filter { !preferredAppOrder.contains($0) }
            .sorted()

        for appId in preferredAppOrder + otherAppIDs {
            guard let enabledOptionID = optionStates[appId]?
                .filter({ $0.value })
                .map(\.key)
                .sorted()
                .first else {
                continue
            }
            return "\(appId)_\(enabledOptionID)"
        }

        return nil
    }

    private func refreshOptionStates(from policy: FeaturePolicyV1) {
        for (appId, states) in policy.appToggles {
            if optionStates[appId] == nil {
                optionStates[appId] = [:]
            }
            for (optionId, isSelected) in states {
                optionStates[appId]?[optionId] = isSelected
            }
        }
    }

    private func applyScheduledApps(to policy: inout FeaturePolicyV1) {
        if scheduledAppIDs.contains("instagram") {
            policy.set(appId: "instagram", optionId: "strict_reels", isEnabled: true)
            policy.set(appId: "instagram", optionId: "reels", isEnabled: false)
        }
        if scheduledAppIDs.contains("tiktok") {
            policy.set(appId: "tiktok", optionId: "video_block", isEnabled: true)
        }
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
