import XCTest
@testable import Bubble

final class TimeWindowScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testRepeatSummaries() {
        XCTAssertEqual(TimeWindowScheduleEvaluator.repeatSummary(for: TimeWindowWeekday.weekdays), "Mon-Fri")
        XCTAssertEqual(TimeWindowScheduleEvaluator.repeatSummary(for: TimeWindowWeekday.weekend), "Weekends")
        XCTAssertEqual(TimeWindowScheduleEvaluator.repeatSummary(for: TimeWindowWeekday.allCases), "Every day")
        XCTAssertEqual(TimeWindowScheduleEvaluator.repeatSummary(for: [.monday]), "Every Monday")
        XCTAssertEqual(TimeWindowScheduleEvaluator.repeatSummary(for: [.monday, .wednesday, .friday]), "Mon, Wed, Fri")
    }

    func testMiddaySameDayWindowIsActiveOnlyInsideRange() {
        let window = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"])

        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 1, hour: 8, minute: 59), calendar: calendar))
        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 1, hour: 9, minute: 0), calendar: calendar))
        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 1, hour: 16, minute: 59), calendar: calendar))
        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 1, hour: 17, minute: 0), calendar: calendar))
    }

    func testOvernightWindowUsesPreviousSelectedDayBeforeEndTime() {
        let window = TimeWindow(startTime: "22:00", endTime: "07:00", repeatDays: TimeWindowWeekday.weekdays, apps: ["instagram"])

        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 1, hour: 23, minute: 0), calendar: calendar))
        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 2, hour: 6, minute: 0), calendar: calendar))
        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 6, hour: 6, minute: 0), calendar: calendar))
        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(window, now: date(year: 2026, month: 6, day: 6, hour: 22, minute: 0), calendar: calendar))
    }

    func testDisabledAndPauseAllWindowsAreInactive() {
        let disabled = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"], enabled: false)
        let enabled = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"], enabled: true)
        let now = date(year: 2026, month: 6, day: 1, hour: 12, minute: 0)

        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(disabled, now: now, calendar: calendar))
        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(enabled, now: now, calendar: calendar, pauseAll: true))
    }

    func testOverlappingWindowsUnionScheduledApps() {
        let tiktok = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"])
        let instagram = TimeWindow(startTime: "13:00", endTime: "18:00", repeatDays: [.monday], apps: ["instagram"])

        let twoPM = TimeWindowScheduleEvaluator.scheduledAppIDs(
            from: [tiktok, instagram],
            now: date(year: 2026, month: 6, day: 1, hour: 14, minute: 0),
            calendar: calendar
        )
        XCTAssertEqual(twoPM, Set(["instagram", "tiktok"]))

        let fiveThirty = TimeWindowScheduleEvaluator.scheduledAppIDs(
            from: [tiktok, instagram],
            now: date(year: 2026, month: 6, day: 1, hour: 17, minute: 30),
            calendar: calendar
        )
        XCTAssertEqual(fiveThirty, Set(["instagram"]))
    }

    func testEndedWindowIDSuppressesCurrentWindow() {
        let window = TimeWindow(id: "tw_focus", startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"])
        let noon = date(year: 2026, month: 6, day: 1, hour: 12, minute: 0)

        XCTAssertTrue(TimeWindowScheduleEvaluator.isActive(window, now: noon, calendar: calendar))
        XCTAssertFalse(TimeWindowScheduleEvaluator.isActive(window, now: noon, calendar: calendar, endedWindowIDs: ["tw_focus"]))
        XCTAssertEqual(
            TimeWindowScheduleEvaluator.scheduledAppIDs(from: [window], now: noon, calendar: calendar, endedWindowIDs: ["tw_focus"]),
            Set<String>()
        )
    }

    func testActiveEndDateForMiddayWindow() {
        let window = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"])

        XCTAssertEqual(
            TimeWindowScheduleEvaluator.activeEndDate(
                for: window,
                now: date(year: 2026, month: 6, day: 1, hour: 12, minute: 30),
                calendar: calendar
            ),
            date(year: 2026, month: 6, day: 1, hour: 17, minute: 0)
        )
    }

    func testActiveEndDateForOvernightWindowUsesCorrectEndDay() {
        let window = TimeWindow(startTime: "22:00", endTime: "07:00", repeatDays: TimeWindowWeekday.weekdays, apps: ["instagram"])

        XCTAssertEqual(
            TimeWindowScheduleEvaluator.activeEndDate(
                for: window,
                now: date(year: 2026, month: 6, day: 1, hour: 23, minute: 0),
                calendar: calendar
            ),
            date(year: 2026, month: 6, day: 2, hour: 7, minute: 0)
        )
        XCTAssertEqual(
            TimeWindowScheduleEvaluator.activeEndDate(
                for: window,
                now: date(year: 2026, month: 6, day: 2, hour: 6, minute: 0),
                calendar: calendar
            ),
            date(year: 2026, month: 6, day: 2, hour: 7, minute: 0)
        )
    }

    func testSoonestActiveEndDateForOverlappingWindows() {
        let tiktok = TimeWindow(startTime: "09:00", endTime: "17:00", repeatDays: [.monday], apps: ["tiktok"])
        let instagram = TimeWindow(startTime: "13:00", endTime: "18:00", repeatDays: [.monday], apps: ["instagram"])

        XCTAssertEqual(
            TimeWindowScheduleEvaluator.soonestActiveEndDate(
                from: [tiktok, instagram],
                now: date(year: 2026, month: 6, day: 1, hour: 14, minute: 0),
                calendar: calendar
            ),
            date(year: 2026, month: 6, day: 1, hour: 17, minute: 0)
        )
    }

    func testNotificationIdentifierIsStablePerWindowAndDay() {
        XCTAssertEqual(
            TimeWindowNotificationScheduler.startNotificationID(windowID: "tw_123", weekday: .monday),
            "time-window-start-tw_123-monday"
        )
        XCTAssertEqual(TimeWindowNotificationScheduler.startNotificationIDs(for: TimeWindow(id: "tw_123")).count, 7)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}

final class EmojiCatalogTests: XCTestCase {
    func testEmojiCatalogSearchAndCategoryFiltering() {
        let sections = [
            EmojiCatalogSection(
                group: "Objects",
                entries: [
                    EmojiCatalogEntry(emoji: "💼", name: "briefcase", group: "Objects", subgroup: "office"),
                    EmojiCatalogEntry(emoji: "⏰", name: "alarm clock", group: "Objects", subgroup: "time")
                ]
            ),
            EmojiCatalogSection(
                group: "Food & Drink",
                entries: [
                    EmojiCatalogEntry(emoji: "🍕", name: "pizza", group: "Food & Drink", subgroup: "prepared-food")
                ]
            ),
            EmojiCatalogSection(
                group: "People & Body",
                entries: [
                    EmojiCatalogEntry(emoji: "👋", name: "waving hand", group: "People & Body", subgroup: "hand-fingers-open"),
                    EmojiCatalogEntry(emoji: "👋🏻", name: "waving hand: light skin tone", group: "People & Body", subgroup: "hand-fingers-open")
                ]
            )
        ]

        let searchResult = EmojiCatalog.filteredSections(in: sections, query: "briefcase", selectedGroup: nil)
        XCTAssertEqual(searchResult.flatMap(\.entries).map(\.emoji), ["💼"])

        let categoryResult = EmojiCatalog.filteredSections(in: sections, query: "", selectedGroup: "Food & Drink")
        XCTAssertEqual(categoryResult.flatMap(\.entries).map(\.emoji), ["🍕"])

        let allResult = EmojiCatalog.filteredSections(in: sections, query: "", selectedGroup: nil)
        XCTAssertEqual(allResult.flatMap(\.entries).map(\.emoji), ["💼", "⏰", "🍕", "👋"])

        let skinToneResult = EmojiCatalog.filteredSections(in: sections, query: "skin tone", selectedGroup: nil)
        XCTAssertTrue(skinToneResult.isEmpty)
    }
}

final class TimeWindowEditorDefaultsTests: XCTestCase {
    func testNewWindowHasNoDefaultRepeatDays() {
        XCTAssertEqual(TimeWindowEditorDefaults.repeatDays(for: nil), [])
        XCTAssertEqual(TimeWindowEditorDefaults.repeatSummaryText(for: []), "Choose days")
    }

    func testEditingWindowPreservesRepeatDays() {
        let window = TimeWindow(repeatDays: [.monday, .wednesday])

        XCTAssertEqual(TimeWindowEditorDefaults.repeatDays(for: window), [.monday, .wednesday])
        XCTAssertEqual(TimeWindowEditorDefaults.repeatSummaryText(for: [.monday, .wednesday]), "Mon, Wed")
    }
}

final class TimeWindowNotificationRoutingTests: XCTestCase {
    func testNotificationActionParsing() {
        XCTAssertEqual(
            TimeWindowNotificationCoordinator.action(from: [
                TimeWindowNotificationScheduler.notificationKindUserInfoKey: TimeWindowNotificationKind.windowStart.rawValue,
                TimeWindowNotificationScheduler.windowIDUserInfoKey: "tw_123"
            ]),
            .windowStart(windowID: "tw_123")
        )
        XCTAssertEqual(
            TimeWindowNotificationCoordinator.action(from: [
                TimeWindowNotificationScheduler.notificationKindUserInfoKey: TimeWindowNotificationKind.pauseReminder.rawValue
            ]),
            .pauseReminder
        )
        XCTAssertEqual(
            TimeWindowNotificationCoordinator.action(from: [
                TimeWindowNotificationScheduler.windowIDUserInfoKey: "tw_legacy"
            ]),
            .windowStart(windowID: "tw_legacy")
        )
    }

    func testPauseReminderDatesRepeatEveryTenMinutesUntilWindowEnd() {
        let first = Date(timeIntervalSince1970: 1_000)
        let end = first.addingTimeInterval(25 * 60)

        XCTAssertEqual(
            TimeWindowNotificationScheduler.pauseReminderDates(firstReminderAt: first, windowEndDate: end),
            [
                first,
                first.addingTimeInterval(10 * 60),
                first.addingTimeInterval(20 * 60)
            ]
        )
    }
}

final class TimeWindowStorePauseTests: XCTestCase {
    func testPauseClearsScheduledBlockersAndSchedulesReminder() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults, scheduler: scheduler)
        var applied: [Set<String>] = []

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["tiktok"]))

        XCTAssertEqual(applied.last, Set(["tiktok"]))

        store.setPauseAll(true)

        XCTAssertTrue(store.pauseAll)
        XCTAssertNotNil(store.pauseExpiresAt)
        XCTAssertTrue(defaults.bool(forKey: BubbleConstants.timeWindowsPauseAllKey))
        XCTAssertEqual(applied.last, Set<String>())
        XCTAssertEqual(scheduler.pauseReminderRequests.count, 1)
        XCTAssertTrue(scheduler.startNotificationRequests.last?.pauseAll == true)
    }

    func testManualResumeRestoresScheduledBlockersAndStartsProtection() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let store = makeStore(scheduler: scheduler)
        var applied: [Set<String>] = []
        var startSources: [String] = []

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { startSources.append($0) },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.setPauseAll(true)
        store.setPauseAll(false)

        XCTAssertFalse(store.pauseAll)
        XCTAssertNil(store.pauseExpiresAt)
        XCTAssertEqual(applied.last, Set(["instagram"]))
        XCTAssertEqual(startSources.last, "time_windows.pause_all.manual_resume")
        XCTAssertEqual(scheduler.cancelPauseReminderCount, 1)
    }

    func testPauseReminderTapRestoresScheduledBlockersStartsProtectionAndRequestsHome() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let store = makeStore(scheduler: scheduler)
        var applied: [Set<String>] = []
        var startSources: [String] = []
        var homeFocusCount = 0

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { startSources.append($0) },
            requestHomeFocus: { homeFocusCount += 1 }
        )
        store.addWindow(activeWindow(apps: ["instagram", "tiktok"]))
        store.setPauseAll(true)
        store.handlePauseReminderActivation()

        XCTAssertFalse(store.pauseAll)
        XCTAssertEqual(applied.last, Set(["instagram", "tiktok"]))
        XCTAssertEqual(startSources.last, "time_windows.pause_reminder_tap")
        XCTAssertEqual(homeFocusCount, 1)
        XCTAssertNotNil(store.homeFocusRequestID)
    }

    func testWindowStartNotificationTapStartsProtectionAndRequestsHome() {
        let store = makeStore()
        var startSources: [String] = []
        var homeFocusCount = 0
        let window = activeWindow(apps: ["tiktok"])

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { startSources.append($0) },
            requestHomeFocus: { homeFocusCount += 1 }
        )
        store.addWindow(window)
        store.handleNotificationActivation(windowID: window.id)

        XCTAssertEqual(startSources.last, "time_windows.notification_tap")
        XCTAssertEqual(homeFocusCount, 1)
        XCTAssertNotNil(store.homeFocusRequestID)
    }

    func testConfigureAppliesAlreadyEvaluatedSchedule() {
        let store = makeStore()
        var applied: [Set<String>] = []

        store.addWindow(activeWindow(apps: ["instagram"]))
        XCTAssertEqual(store.scheduledAppIDs, Set(["instagram"]))

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(applied.last, Set(["instagram"]))
    }

    func testEndingActiveWindowClearsScheduledBlockersWithoutDisablingWindow() {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)
        var applied: [Set<String>] = []

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram", "tiktok"]))

        XCTAssertEqual(applied.last, Set(["instagram", "tiktok"]))
        XCTAssertTrue(store.endActiveWindow(for: "instagram"))

        XCTAssertEqual(applied.last, Set<String>())
        XCTAssertTrue(store.windows.first?.enabled == true)
        XCTAssertTrue(store.scheduledAppIDs.isEmpty)
        XCTAssertFalse(defaults.dictionary(forKey: BubbleConstants.timeWindowsEndedUntilKey)?.isEmpty ?? true)
    }

    func testEndingOneOverlappingWindowLeavesOtherScheduledAppActive() {
        let store = makeStore()
        var applied: [Set<String>] = []

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.addWindow(activeWindow(apps: ["tiktok"]))

        XCTAssertEqual(applied.last, Set(["instagram", "tiktok"]))
        XCTAssertTrue(store.endActiveWindow(for: "instagram"))

        XCTAssertEqual(applied.last, Set(["tiktok"]))
        XCTAssertEqual(store.scheduledAppIDs, Set(["tiktok"]))
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        scheduler: FakeTimeWindowNotificationScheduler = FakeTimeWindowNotificationScheduler()
    ) -> TimeWindowStore {
        TimeWindowStore(
            defaults: defaults ?? testDefaults(),
            notificationScheduler: scheduler,
            shouldRegisterLifecycleObservers: false,
            startForegroundTimer: false
        )
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "TimeWindowStorePauseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func activeWindow(apps: [String]) -> TimeWindow {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinute = currentMinute == 0 ? 0 : currentMinute - 1
        let endMinute = (currentMinute + 60) % (24 * 60)
        let today = TimeWindowWeekday.from(calendarWeekday: components.weekday ?? 2)

        return TimeWindow(
            startTime: timeString(fromMinuteOfDay: startMinute),
            endTime: timeString(fromMinuteOfDay: endMinute),
            repeatDays: [today],
            apps: apps
        )
    }

    private func timeString(fromMinuteOfDay minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private final class FakeTimeWindowNotificationScheduler: TimeWindowNotificationScheduling {
    var startNotificationRequests: [(pauseAll: Bool, requestAuthorizationIfNeeded: Bool)] = []
    var pauseReminderRequests: [(firstReminderAt: Date, windowEndDate: Date?, requestAuthorizationIfNeeded: Bool)] = []
    var cancelPauseReminderCount = 0

    func rescheduleStartNotifications(
        for windows: [TimeWindow],
        pauseAll: Bool,
        requestAuthorizationIfNeeded: Bool
    ) {
        startNotificationRequests.append((pauseAll, requestAuthorizationIfNeeded))
    }

    func schedulePauseReminderNotifications(
        firstReminderAt: Date,
        windowEndDate: Date?,
        requestAuthorizationIfNeeded: Bool
    ) {
        pauseReminderRequests.append((firstReminderAt, windowEndDate, requestAuthorizationIfNeeded))
    }

    func cancelPauseReminderNotifications() {
        cancelPauseReminderCount += 1
    }
}
