import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        ScheduleMonitorDiagnostics.recordCallback(activity: activity.rawValue, event: "start_received", defaults: defaults)
        guard !PaywallBlockingState.isActive(defaults: defaults), !ExperienceModeState.isLegacy(defaults: defaults) else {
            ScheduleMonitorDiagnostics.recordCallback(
                activity: activity.rawValue,
                event: PaywallBlockingState.isActive(defaults: defaults) ? "start_skipped_paywall" : "start_skipped_legacy",
                defaults: defaults
            )
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
        guard isScheduledWindowActivity(activity) else { return }
        reconcileScheduledApps(for: activity, event: "start")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ScheduleMonitorDiagnostics.recordCallback(activity: activity.rawValue, event: "end_received", defaults: defaults)
        guard !PaywallBlockingState.isActive(defaults: defaults), !ExperienceModeState.isLegacy(defaults: defaults) else {
            ScheduleMonitorDiagnostics.recordCallback(
                activity: activity.rawValue,
                event: PaywallBlockingState.isActive(defaults: defaults) ? "end_skipped_paywall" : "end_skipped_legacy",
                defaults: defaults
            )
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
        guard isScheduledWindowActivity(activity) else { return }
        reconcileScheduledApps(for: activity, event: "end")
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
            .filter {
                $0.kind == .limit && reached.contains($0.id)
                    && !AppControlRuleState.isRulePaused($0.id, defaults: defaults)
            }
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
                now: now,
                checkProcessAuthorization: false
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
                now: now,
                checkProcessAuthorization: false
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

    private func isScheduledWindowActivity(_ activity: DeviceActivityName) -> Bool {
        ["nima.window.", "nima.instagram.", "nima.tiktok.", "nima.x."].contains {
            activity.rawValue.hasPrefix($0)
        }
    }

    private func reconcileScheduledApps(for activity: DeviceActivityName, event: String) {
        ManagedSettingsStore(named: .init(activity.rawValue)).shield.applications = nil
        ClientShieldPolicy.clearLegacyWindowActivityShields()
        for appID in ["instagram", "tiktok", "x"] {
            let decision = ClientShieldPolicy.reconcile(
                for: appID,
                defaults: defaults,
                checkProcessAuthorization: false
            )
            let shieldCount = ManagedSettingsStore(named: .init("nima.\(appID)"))
                .shield.applications?.count ?? 0
            ScheduleMonitorDiagnostics.recordCallback(
                activity: activity.rawValue,
                event: event,
                appID: appID,
                decision: decision,
                shieldCount: shieldCount,
                defaults: defaults
            )
            if event == "start" && decision.shouldShield && shieldCount > 0 {
                StreakStore(defaults: defaults).markTodayEarned(source: "\(appID)_scheduled")
            }
        }
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
