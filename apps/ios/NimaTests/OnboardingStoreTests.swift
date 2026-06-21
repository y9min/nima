import XCTest
@testable import Nima

final class OnboardingStoreTests: XCTestCase {
    func testDefaultsAreIncompleteAndEmpty() {
        let store = OnboardingStore(defaults: testDefaults())

        XCTAssertFalse(store.isCompleted)
        XCTAssertNil(store.phoneHours)
        XCTAssertNil(store.age)
        XCTAssertTrue(store.selectedHabits.isEmpty)
        XCTAssertTrue(store.selectedApps.isEmpty)
        XCTAssertFalse(store.vpnPermissionRequested)
        XCTAssertFalse(store.hasSeenGuidedOnboarding)
        XCTAssertFalse(store.hasCompletedGuidedPractice)
        XCTAssertFalse(store.hasGuidedPracticeReturnPending)
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

    func testGuidedOnboardingSeenPersists() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.markGuidedOnboardingSeen()

        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertTrue(reloaded.hasSeenGuidedOnboarding)
    }

    func testGuidedPracticeCompletionPersists() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.markGuidedPracticeCompleted()

        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertTrue(reloaded.hasCompletedGuidedPractice)
    }

    func testGuidedPracticeReturnPendingPersistsAndClears() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.setGuidedPracticeReturnPending(true)
        XCTAssertTrue(OnboardingStore(defaults: defaults).hasGuidedPracticeReturnPending)

        store.setGuidedPracticeReturnPending(false)
        XCTAssertFalse(OnboardingStore(defaults: defaults).hasGuidedPracticeReturnPending)
    }

    func testGuidedPracticeReviewPromptDefaultsToNotAttempted() {
        let store = GuidedPracticeReviewPromptStore(defaults: testDefaults())

        XCTAssertFalse(store.hasAttemptedPrompt(for: "user@nima.so"))
    }

    func testGuidedPracticeReviewPromptPersistsAttempt() {
        let defaults = testDefaults()
        let store = GuidedPracticeReviewPromptStore(defaults: defaults)

        store.markPromptAttempted(for: "user@nima.so")
        let reloaded = GuidedPracticeReviewPromptStore(defaults: defaults)

        XCTAssertTrue(reloaded.hasAttemptedPrompt(for: "user@nima.so"))
    }

    func testGuidedPracticeReviewPromptNormalizesIdentifiers() {
        let defaults = testDefaults()
        let store = GuidedPracticeReviewPromptStore(defaults: defaults)

        store.markPromptAttempted(for: " USER@NIMA.SO ")

        XCTAssertTrue(store.hasAttemptedPrompt(for: "user@nima.so"))
    }

    func testGuidedPracticeReviewPromptKeepsUsersSeparate() {
        let defaults = testDefaults()
        let store = GuidedPracticeReviewPromptStore(defaults: defaults)

        store.markPromptAttempted(for: "first@nima.so")

        XCTAssertTrue(store.hasAttemptedPrompt(for: "first@nima.so"))
        XCTAssertFalse(store.hasAttemptedPrompt(for: "second@nima.so"))
    }

    func testResetForOnboardingRestartClearsOnboardingAndGuidedPracticeState() {
        let defaults = testDefaults()
        let store = OnboardingStore(defaults: defaults)

        store.setPhoneHours(7)
        store.setAge(23)
        store.setSelectedHabits(["Checking apps automatically"])
        store.setSelectedApps(["TikTok"])
        store.markVPNPermissionRequested()
        store.markCompleted()
        store.markGuidedOnboardingSeen()
        store.markGuidedPracticeCompleted()
        store.setGuidedPracticeReturnPending(true)

        store.resetForOnboardingRestart()
        let reloaded = OnboardingStore(defaults: defaults)

        XCTAssertFalse(reloaded.isCompleted)
        XCTAssertFalse(reloaded.hasSeenGuidedOnboarding)
        XCTAssertFalse(reloaded.hasCompletedGuidedPractice)
        XCTAssertFalse(reloaded.hasGuidedPracticeReturnPending)
        XCTAssertNil(reloaded.phoneHours)
        XCTAssertNil(reloaded.age)
        XCTAssertTrue(reloaded.selectedHabits.isEmpty)
        XCTAssertTrue(reloaded.selectedApps.isEmpty)
        XCTAssertFalse(reloaded.vpnPermissionRequested)
    }

    func testNumericAnswersAreClampedToSupportedRanges() {
        let store = OnboardingStore(defaults: testDefaults())

        store.setPhoneHours(99)
        store.setAge(4)

        XCTAssertEqual(store.phoneHours, 16)
        XCTAssertEqual(store.age, 13)
    }

    func testPhoneProjectionUsesWholeNumbers() {
        let projection = OnboardingProjection.calculate(
            dailyPhoneHours: 8,
            userAge: 25,
            date: testDate(year: 2026, month: 1, day: 1),
            calendar: testCalendar
        )

        XCTAssertEqual(projection.daysThisYear, 122)
        XCTAssertEqual(projection.lifeYears, 30)
        XCTAssertEqual(projection.yearsBack, 9)
    }

    func testDaysRemainingIncludesToday() {
        let date = testDate(year: 2026, month: 12, day: 31)

        XCTAssertEqual(OnboardingProjection.daysRemainingInYearIncludingToday(from: date, calendar: testCalendar), 1)

        let projection = OnboardingProjection.calculate(
            dailyPhoneHours: 12,
            userAge: 25,
            date: date,
            calendar: testCalendar
        )

        XCTAssertEqual(projection.daysThisYear, 1)
    }

    func testProjectionMinimumsClampToOneForLifeYearsAndYearsBack() {
        let projection = OnboardingProjection.calculate(
            dailyPhoneHours: 0,
            userAge: 85,
            date: testDate(year: 2026, month: 1, day: 1),
            calendar: testCalendar
        )

        XCTAssertEqual(projection.daysThisYear, 0)
        XCTAssertEqual(projection.lifeYears, 1)
        XCTAssertEqual(projection.yearsBack, 1)
    }

    func testCarouselValuesNeverGoBelowOne() {
        XCTAssertEqual(OnboardingProjection.carouselValues(for: 1), [1, 1, 2])
        XCTAssertEqual(OnboardingProjection.carouselValues(for: 9), [8, 9, 10])
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func testDate(year: Int, month: Int, day: Int) -> Date {
        testCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
