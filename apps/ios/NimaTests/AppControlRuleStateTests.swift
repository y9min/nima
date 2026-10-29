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
}
