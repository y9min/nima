import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard !PaywallBlockingState.isActive(defaults: defaults), !ExperienceModeState.isLegacy(defaults: defaults) else {
            clearAppControlShields()
            return
        }
        if activity.rawValue == AppControlRuleState.limitActivityName {
            if defaults?.double(forKey: AppControlRuleState.reachedDayKey) != AppControlRuleState.dayStart() {
                AppControlRuleState.saveReachedLimitIDs([], defaults: defaults)
                ManagedSettingsStore(named: .init("nima.controls.limits")).shield.applications = nil
            }
            return
        }
        if activity.rawValue == "nima.pause_mode" { return }
        if activity.rawValue == "nima.hard_mode_pause" { return }
        guard let appID = scheduledFeedAppID(for: activity) else { return }
        ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        ClientShieldPolicy.clearLegacyWindowActivityShields(for: [appID])
        let decision = ClientShieldPolicy.reconcile(
            for: appID,
            defaults: defaults
        )
        if decision.shouldShield {
            StreakStore(defaults: defaults).markTodayEarned(source: "\(appID)_scheduled")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard !PaywallBlockingState.isActive(defaults: defaults), !ExperienceModeState.isLegacy(defaults: defaults) else {
            clearAppControlShields()
            return
        }
        if activity.rawValue == AppControlRuleState.limitActivityName { return }
        if activity.rawValue == "nima.pause_mode" {
            restorePausedShields()
            return
        }
        if activity.rawValue == "nima.hard_mode_pause" {
            restoreHardModePauseShields()
            return
        }
        guard let appID = scheduledFeedAppID(for: activity) else { return }
        ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        ClientShieldPolicy.clearLegacyWindowActivityShields(for: [appID])
        ClientShieldPolicy.reconcile(for: appID, defaults: defaults)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard !PaywallBlockingState.isActive(defaults: defaults), !ExperienceModeState.isLegacy(defaults: defaults) else {
            clearAppControlShields()
            return
        }
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
        for appID in paused {
            ClientShieldPolicy.reconcile(
                for: appID,
                defaults: defaults,
                now: now
            )
        }
        PauseModeState.clear(defaults: defaults)
    }

    private func restoreHardModePauseShields() {
        let now = Date()
        HardModeProtectionState.purgeExpiredPauses(defaults: defaults, now: now)
        for appID in ["instagram", "tiktok", "x"] {
            ClientShieldPolicy.reconcile(
                for: appID,
                defaults: defaults,
                now: now
            )
        }

        let rules = AppControlRuleState.rules(defaults: defaults)
        let blockedTokens = Set(rules.filter {
            $0.kind == .blocked
                && !HardModeProtectionState.isRulePaused($0.id, defaults: defaults, now: now)
        }.map(\.applicationToken))
        ManagedSettingsStore(named: .init("nima.controls.blocked")).shield.applications =
            blockedTokens.isEmpty ? nil : blockedTokens

        let reached = AppControlRuleState.reachedLimitIDs(defaults: defaults, now: now)
        let limitedTokens = Set(rules.filter {
            $0.kind == .limit
                && reached.contains($0.id)
                && !HardModeProtectionState.isRulePaused($0.id, defaults: defaults, now: now)
        }.map(\.applicationToken))
        ManagedSettingsStore(named: .init("nima.controls.limits")).shield.applications =
            limitedTokens.isEmpty ? nil : limitedTokens

        if let nextExpiry = HardModeProtectionState.nextPauseExpiry(defaults: defaults, now: now) {
            let center = DeviceActivityCenter()
            let activity = DeviceActivityName("nima.hard_mode_pause")
            center.stopMonitoring([activity])
            let start = min(now, nextExpiry.addingTimeInterval(-15 * 60))
            let calendar = Calendar.current
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents([.hour, .minute, .second], from: start),
                intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: nextExpiry),
                repeats: false
            )
            if schedule.nextInterval != nil {
                do {
                    try center.startMonitoring(activity, during: schedule)
                } catch {
                    // Foreground reconciliation will still restore the shield.
                }
            }
        }
    }

    private func scheduledFeedAppID(for activity: DeviceActivityName) -> String? {
        if activity.rawValue.hasPrefix("nima.instagram.") { return "instagram" }
        if activity.rawValue.hasPrefix("nima.tiktok.") { return "tiktok" }
        if activity.rawValue.hasPrefix("nima.x.") { return "x" }
        return nil
    }

    private func clearAppControlShields() {
        ManagedSettingsStore(named: .init("nima.controls.blocked")).shield.applications = nil
        ManagedSettingsStore(named: .init("nima.controls.limits")).shield.applications = nil
        ClientShieldPolicy.clearLegacyWindowActivityShields()
        for appID in ClientShieldAppID.allCases {
            ManagedSettingsStore(named: .init(appID.managedSettingsStoreName)).shield.applications = nil
        }
    }
}
