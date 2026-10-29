import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.rawValue == AppControlRuleState.limitActivityName {
            if defaults?.double(forKey: AppControlRuleState.reachedDayKey) != AppControlRuleState.dayStart() {
                AppControlRuleState.saveReachedLimitIDs([], defaults: defaults)
                ManagedSettingsStore(named: .init("nima.controls.limits")).shield.applications = nil
            }
            return
        }
        if activity.rawValue == "nima.pause_mode" { return }
        guard let appID = scheduledFeedAppID(for: activity) else { return }
        if PauseModeState.isPaused(appID, defaults: defaults) {
            let windowID = activity.rawValue
                .dropFirst("nima.\(appID).".count)
                .split(separator: ".")
                .first
                .map(String.init)
            let pausedWindows = Set(defaults?.stringArray(forKey: NimaConstants.pauseModeWindowIDsKey) ?? [])
            if let windowID, pausedWindows.contains(windowID) { return }
        }
        let selection = loadSelection(for: appID)
        guard !selection.applicationTokens.isEmpty else { return }
        store(for: activity).shield.applications = selection.applicationTokens
        StreakStore(defaults: defaults).markTodayEarned(source: "\(appID)_scheduled")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue == AppControlRuleState.limitActivityName { return }
        if activity.rawValue == "nima.pause_mode" {
            restorePausedShields()
            return
        }
        guard scheduledFeedAppID(for: activity) != nil else { return }
        store(for: activity).shield.applications = nil
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity.rawValue == AppControlRuleState.limitActivityName,
              event.rawValue.hasPrefix(AppControlRuleState.limitEventPrefix) else { return }
        let id = String(event.rawValue.dropFirst(AppControlRuleState.limitEventPrefix.count))
        guard AppControlRuleState.rules(defaults: defaults).contains(where: { $0.id == id && $0.kind == .limit }) else { return }
        var reached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        reached.insert(id)
        AppControlRuleState.saveReachedLimitIDs(reached, defaults: defaults)
        let tokens = Set(AppControlRuleState.rules(defaults: defaults)
            .filter { $0.kind == .limit && reached.contains($0.id) }
            .map(\.applicationToken))
        ManagedSettingsStore(named: .init("nima.controls.limits")).shield.applications = tokens.isEmpty ? nil : tokens
    }

    private func restorePausedShields() {
        let now = Date()
        guard (defaults?.object(forKey: NimaConstants.pauseModeExpiresAtKey) as? Date).map({ $0 <= now }) == true else { return }
        let paused = Set(defaults?.stringArray(forKey: NimaConstants.pauseModeAppIDsKey) ?? [])
        let scheduledEnds = defaults?.dictionary(forKey: NimaConstants.clientScheduleEndDatesKey) as? [String: Date] ?? [:]
        for appID in paused {
            let manuallyEnabled: Bool
            let selectionKey: String
            switch appID {
            case "instagram":
                manuallyEnabled = defaults?.bool(forKey: "instagram.client.protection_enabled") ?? false
                selectionKey = NimaConstants.instagramFamilySelectionKey
            case "tiktok":
                manuallyEnabled = defaults?.bool(forKey: "tiktok.client.protection_enabled") ?? false
                selectionKey = NimaConstants.tiktokFamilySelectionKey
            default: continue
            }
            let scheduled = (scheduledEnds[appID] ?? .distantPast) > now
            let target = ManagedSettingsStore(named: .init("nima.\(appID)"))
            guard manuallyEnabled || scheduled,
                  let data = defaults?.data(forKey: selectionKey),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
                  !selection.applicationTokens.isEmpty else {
                target.shield.applications = nil
                continue
            }
            target.shield.applications = selection.applicationTokens
        }
        PauseModeState.clear(defaults: defaults)
    }

    private func loadSelection(for appID: String) -> FamilyActivitySelection {
        let key = appID == "instagram"
            ? NimaConstants.instagramFamilySelectionKey
            : NimaConstants.tiktokFamilySelectionKey
        guard let data = defaults?.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    private func scheduledFeedAppID(for activity: DeviceActivityName) -> String? {
        if activity.rawValue.hasPrefix("nima.instagram.") { return "instagram" }
        if activity.rawValue.hasPrefix("nima.tiktok.") { return "tiktok" }
        return nil
    }

    private func store(for activity: DeviceActivityName) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init(activity.rawValue))
    }
}
