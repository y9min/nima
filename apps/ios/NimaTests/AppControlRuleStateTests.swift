import XCTest
@testable import Nima

final class AppControlRuleStateTests: XCTestCase {
    func testReachedLimitExpiresAtNextLocalDay() {
        let suite = "app-controls-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let today = Date(timeIntervalSince1970: 1_780_336_800)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        AppControlRuleState.saveReachedLimitIDs(["limit-1"], defaults: defaults, now: today)

        XCTAssertEqual(AppControlRuleState.reachedLimitIDs(defaults: defaults, now: today), ["limit-1"])
        XCTAssertTrue(AppControlRuleState.reachedLimitIDs(defaults: defaults, now: tomorrow).isEmpty)
    }

    func testPausedRuleExpiresBeforeShieldTreatsItAsActive() {
        let suite = "app-controls-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Date(timeIntervalSince1970: 1_780_336_800)
        defaults.set(["rule-1": now.addingTimeInterval(300).timeIntervalSince1970],
                     forKey: "hard_mode.pause_rule_expiries")

        XCTAssertTrue(AppControlRuleState.isRulePaused("rule-1", defaults: defaults, now: now))
        XCTAssertFalse(AppControlRuleState.isRulePaused("rule-1", defaults: defaults, now: now.addingTimeInterval(300)))
        XCTAssertFalse(AppControlRuleState.isRulePaused("other-rule", defaults: defaults, now: now))
    }
}
