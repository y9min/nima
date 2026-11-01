import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

@MainActor
@Observable
final class AppControlRulesStore {
    private(set) var rules: [AppControlRule]
    private(set) var monitoringError: String?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let blockedStore = ManagedSettingsStore(named: .init("nima.controls.blocked"))
    @ObservationIgnored private let limitsStore = ManagedSettingsStore(named: .init("nima.controls.limits"))
    @ObservationIgnored private let activityCenter = DeviceActivityCenter()

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppControlRuleState.appGroupID)) {
        self.defaults = defaults
        rules = AppControlRuleState.rules(defaults: defaults)
        reconcile()
    }

    var limits: [AppControlRule] { rules.filter { $0.kind == .limit } }
    var blocked: [AppControlRule] { rules.filter { $0.kind == .blocked } }

    func rule(for token: ApplicationToken) -> AppControlRule? {
        rules.first { $0.applicationToken == token }
    }

    func activeKind(for tokens: Set<ApplicationToken>) -> AppControlKind? {
        if blocked.contains(where: { tokens.contains($0.applicationToken) }) { return .blocked }
        let reached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        if limits.contains(where: { tokens.contains($0.applicationToken) && reached.contains($0.id) }) { return .limit }
        return nil
    }

    @discardableResult
    func save(token: ApplicationToken, kind: AppControlKind, dailyMinutes: Int?, replacing id: String? = nil) -> Bool {
        let prior = rules
        let priorReached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        let priorLimits = limitSignature(prior)
        let existing = rules.first { $0.applicationToken == token }
        rules.removeAll { $0.id == id || $0.applicationToken == token }
        let rule = AppControlRule(
            id: id ?? existing?.id ?? UUID().uuidString,
            applicationToken: token,
            kind: kind,
            dailyMinutes: kind == .limit ? dailyMinutes : nil
        )
        rules.append(rule)
        AppControlRuleState.save(rules, defaults: defaults)
        let limitsChanged = priorLimits != limitSignature(rules)
        var reached = priorReached
        if limitsChanged {
            reached.remove(rule.id)
            if let existing { reached.remove(existing.id) }
            AppControlRuleState.saveReachedLimitIDs(reached, defaults: defaults)
        }
        if !limitsChanged || syncMonitoring() {
            applyShields()
            return true
        }
        rules = prior
        AppControlRuleState.save(prior, defaults: defaults)
        AppControlRuleState.saveReachedLimitIDs(priorReached, defaults: defaults)
        _ = syncMonitoring()
        applyShields()
        return false
    }

    @discardableResult
    func delete(id: String) -> Bool {
        let prior = rules
        let priorReached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        let hadLimit = rules.contains { $0.id == id && $0.kind == .limit }
        rules.removeAll { $0.id == id }
        AppControlRuleState.save(rules, defaults: defaults)
        if hadLimit {
            var reached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
            reached.remove(id)
            AppControlRuleState.saveReachedLimitIDs(reached, defaults: defaults)
        }
        if hadLimit && !syncMonitoring() {
            rules = prior
            AppControlRuleState.save(prior, defaults: defaults)
            AppControlRuleState.saveReachedLimitIDs(priorReached, defaults: defaults)
            _ = syncMonitoring()
            applyShields()
            return false
        }
        applyShields()
        return true
    }

    func reconcile() {
        // A shield from yesterday must not linger if the extension's midnight
        // callback was delayed until the next device use.
        let reached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        AppControlRuleState.saveReachedLimitIDs(reached, defaults: defaults)
        HardModeProtectionState.purgeExpiredPauses(defaults: defaults)
        applyShields()
        if !limits.isEmpty && !activityCenter.activities.contains(DeviceActivityName(AppControlRuleState.limitActivityName)) {
            _ = syncMonitoring()
        }
    }

    func resetForAccountDeletion() {
        rules = []
        defaults?.removeObject(forKey: AppControlRuleState.rulesKey)
        defaults?.removeObject(forKey: AppControlRuleState.reachedLimitIDsKey)
        defaults?.removeObject(forKey: AppControlRuleState.reachedDayKey)
        activityCenter.stopMonitoring([DeviceActivityName(AppControlRuleState.limitActivityName)])
        blockedStore.shield.applications = nil
        limitsStore.shield.applications = nil
    }

    private func applyShields() {
        let blockedTokens = Set(blocked.filter {
            !HardModeProtectionState.isRulePaused($0.id, defaults: defaults)
        }.map(\.applicationToken))
        blockedStore.shield.applications = blockedTokens.isEmpty ? nil : blockedTokens
        let reached = AppControlRuleState.reachedLimitIDs(defaults: defaults)
        let limitedTokens = Set(limits.filter {
            reached.contains($0.id)
                && !HardModeProtectionState.isRulePaused($0.id, defaults: defaults)
        }.map(\.applicationToken))
        limitsStore.shield.applications = limitedTokens.isEmpty ? nil : limitedTokens
    }

    private func limitSignature(_ rules: [AppControlRule]) -> [AppControlRule] {
        rules.filter { $0.kind == .limit }
            .sorted { $0.id < $1.id }
    }

    @discardableResult
    private func syncMonitoring() -> Bool {
        let name = DeviceActivityName(AppControlRuleState.limitActivityName)
        if limits.isEmpty {
            activityCenter.stopMonitoring([name])
            monitoringError = nil
            return true
        }

        let events = Dictionary(uniqueKeysWithValues: limits.compactMap { rule -> (DeviceActivityEvent.Name, DeviceActivityEvent)? in
            guard let minutes = rule.dailyMinutes, minutes > 0 else { return nil }
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(
                    applications: [rule.applicationToken],
                    threshold: DateComponents(minute: minutes),
                    includesPastActivity: true
                )
            } else {
                event = DeviceActivityEvent(
                    applications: [rule.applicationToken],
                    threshold: DateComponents(minute: minutes)
                )
            }
            return (DeviceActivityEvent.Name(AppControlRuleState.limitEventPrefix + rule.id), event)
        })
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            try activityCenter.startMonitoring(name, during: schedule, events: events)
            monitoringError = nil
            return true
        } catch {
            monitoringError = "Could not start this daily limit. Please try again."
            return false
        }
    }
}
