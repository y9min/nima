import XCTest
@testable import Bubble

final class OnboardingStoreTests: XCTestCase {
    func testDefaultsAreIncompleteAndEmpty() {
        let store = OnboardingStore(defaults: testDefaults())

        XCTAssertFalse(store.isCompleted)
        XCTAssertNil(store.phoneHours)
        XCTAssertNil(store.age)
        XCTAssertTrue(store.selectedHabits.isEmpty)
        XCTAssertTrue(store.selectedApps.isEmpty)
        XCTAssertFalse(store.vpnPermissionRequested)
    }

    func testSavingAnswersPersistsAndReloads() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.setPhoneHours(9)
        store.setAge(21)
        store.setSelectedHabits(["Scrolling in bed", "Feeling bad after using my phone"])
        store.setSelectedApps(["Instagram", "Facebook"])
        store.markVPNPermissionRequested()

        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertEqual(reloaded.phoneHours, 9)
        XCTAssertEqual(reloaded.age, 21)
        XCTAssertEqual(reloaded.selectedHabits, ["Scrolling in bed", "Feeling bad after using my phone"])
        XCTAssertEqual(reloaded.selectedApps, ["Instagram", "Facebook"])
        XCTAssertTrue(reloaded.vpnPermissionRequested)
        XCTAssertFalse(reloaded.isCompleted)
    }

    func testSkipEquivalentEmptyAnswersPersist() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.setPhoneHours(nil)
        store.setAge(nil)
        store.setSelectedHabits([])
        store.setSelectedApps([])

        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertNil(reloaded.phoneHours)
        XCTAssertNil(reloaded.age)
        XCTAssertTrue(reloaded.selectedHabits.isEmpty)
        XCTAssertTrue(reloaded.selectedApps.isEmpty)
        XCTAssertFalse(reloaded.isCompleted)
    }

    func testCompletionPersistsSeparatelyFromAnswers() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.setPhoneHours(8)
        store.markCompleted()

        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertTrue(reloaded.isCompleted)
        XCTAssertEqual(reloaded.phoneHours, 8)
    }

    func testNumericAnswersAreClampedToSupportedRanges() {
        let store = OnboardingStore(defaults: testDefaults())

        store.setPhoneHours(99)
        store.setAge(4)

        XCTAssertEqual(store.phoneHours, 16)
        XCTAssertEqual(store.age, 13)
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
