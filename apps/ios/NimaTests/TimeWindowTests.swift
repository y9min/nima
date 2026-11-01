import XCTest
@testable import Nima

final class TimeWindowInstagramModeCompatibilityTests: XCTestCase {
    func testLegacyInstagramWindowWithoutModeStillDecodes() throws {
        let legacy = TimeWindow(apps: ["instagram"])
        let data = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "appActions")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TimeWindow.self, from: legacyData)
        XCTAssertEqual(decoded.apps, ["instagram"])
        XCTAssertTrue(decoded.appActions.isEmpty)
    }

    func testNewWindowDoesNotSaveAnInstagramMode() {
        XCTAssertTrue(TimeWindow(apps: ["instagram"]).appActions.isEmpty)
    }

    func testExistingWindowWithModeStillDecodes() throws {
        let existing = TimeWindow(
            apps: ["instagram"],
            appActions: ["instagram": .instagramDMOnly]
        )
        let decoded = try JSONDecoder().decode(TimeWindow.self, from: JSONEncoder().encode(existing))
        XCTAssertEqual(decoded.appActions["instagram"], .instagramDMOnly)
    }

    @MainActor
    func testDefaultModeSurvivesEnablingAndScheduling() {
        let suiteName = "InstagramDefaultModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let protection = InstagramProtectionStore(defaults: defaults)

        protection.setManualMode(.dmOnly, source: "test")
        protection.setProtectionEnabled(true, source: "test")
        protection.setScheduled(true, source: "test")

        XCTAssertEqual(protection.manualMode, .dmOnly)
        XCTAssertEqual(protection.effectiveMode, .dmOnly)
        XCTAssertEqual(defaults.string(forKey: InstagramProtectionStore.manualModeKey), InstagramMode.dmOnly.rawValue)
    }
}

final class FeaturePolicyBlockerResetTests: XCTestCase {
    func testDisablingManualTogglesPreservesPolicySettingsAndUnknownOptions() {
        var policy = FeaturePolicyV1(
            profile: "custom-profile",
            shadowModeEnabled: true,
            transportStabilityMode: false,
            appToggles: [
                "instagram": ["strict_reels": true],
                "tiktok": ["video_block": true],
                "future_app": ["future_blocker": true]
            ],
            appStrategies: ["future_app": "future-strategy"]
        )

        policy.disableAllAppToggles()

        XCTAssertTrue(policy.appToggles.values.flatMap(\.values).allSatisfy { !$0 })
        XCTAssertEqual(policy.profile, "custom-profile")
        XCTAssertTrue(policy.shadowModeEnabled)
        XCTAssertFalse(policy.transportStabilityMode)
        XCTAssertEqual(policy.appStrategies["future_app"], "future-strategy")
        XCTAssertEqual(policy.appToggles["future_app"]?["future_blocker"], false)
    }
}

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

    func testActiveOccurrenceUsesPreviousDayStartForOvernightWindow() {
        let window = TimeWindow(
            id: "overnight",
            startTime: "22:00",
            endTime: "09:00",
            repeatDays: [.monday],
            apps: ["instagram"]
        )
        let now = date(year: 2026, month: 6, day: 2, hour: 8, minute: 0)

        let occurrence = TimeWindowScheduleEvaluator.activeOccurrence(
            for: window,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(occurrence?.startDate, date(year: 2026, month: 6, day: 1, hour: 22, minute: 0))
        XCTAssertEqual(occurrence?.endDate, date(year: 2026, month: 6, day: 2, hour: 9, minute: 0))
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
                TimeWindowNotificationScheduler.notificationKindUserInfoKey: TimeWindowNotificationKind.pauseReminder.rawValue
            ]),
            .pauseReminder
        )
        XCTAssertNil(
            TimeWindowNotificationCoordinator.action(from: [
                TimeWindowNotificationScheduler.notificationKindUserInfoKey: "window_start"
            ])
        )
        XCTAssertNil(TimeWindowNotificationCoordinator.action(from: [:]))
    }

    func testPauseReminderDatesRepeatEveryTenMinutesUntilWindowEnd() {
        let first = Date(timeIntervalSince1970: 1_000)
        let end = first.addingTimeInterval(25 * 60)

        XCTAssertEqual(
            TimeWindowNotificationScheduler.pauseReminderDates(
                firstReminderAt: first,
                windowEndDate: end,
                reminderInterval: 10 * 60
            ),
            [
                first,
                first.addingTimeInterval(10 * 60),
                first.addingTimeInterval(20 * 60)
            ]
        )
    }
}

final class ClientShieldPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testOvernightWindowUnshieldsAfterScheduledEnd() {
        let defaults = testDefaults()
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 8, minute: 16),
                calendar: calendar
            ),
            .unshield(.noActiveTimeWindow)
        )
    }

    func testOvernightWindowShieldsBeforeScheduledEnd() {
        let defaults = testDefaults()
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 7, minute: 59),
                calendar: calendar
            ),
            .shield(.timeWindow)
        )
    }

    func testManualProtectionKeepsAppShieldedAfterWindowEnds() {
        let defaults = testDefaults()
        defaults.set(true, forKey: NimaConstants.instagramProtectionEnabledKey)
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 8, minute: 16),
                calendar: calendar
            ),
            .shield(.manualProtection)
        )
    }

    func testAnotherActiveWindowKeepsAppShielded() {
        let defaults = testDefaults()
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            ),
            TimeWindow(
                startTime: "22:00",
                endTime: "09:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 8, minute: 16),
                calendar: calendar
            ),
            .shield(.timeWindow)
        )
    }

    func testPauseAllWindowsUnshieldsEvenWhenWindowIsActive() {
        let defaults = testDefaults()
        defaults.set(true, forKey: NimaConstants.timeWindowsPauseAllKey)
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 7, minute: 0),
                calendar: calendar
            ),
            .unshield(.pauseAllWindows)
        )
    }

    func testHardModeScheduleOffPreventsScheduledShield() {
        let defaults = testDefaults()
        defaults.set(
            ["instagram"],
            forKey: NimaConstants.hardModeOffAppIDsKey
        )
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: date(day: 3, hour: 7, minute: 0),
                calendar: calendar
            ),
            .unshield(.hardModeScheduleOff)
        )
    }

    func testPauseModeTemporarilyPreventsScheduledShield() {
        let defaults = testDefaults()
        let now = date(day: 3, hour: 7, minute: 0)
        PauseModeState.start(
            appIDs: ["instagram"],
            minutes: 10,
            defaults: defaults,
            now: now
        )
        setWindows([
            TimeWindow(
                startTime: "22:00",
                endTime: "08:00",
                repeatDays: [.monday],
                apps: ["instagram"]
            )
        ], defaults: defaults)

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: now.addingTimeInterval(60),
                calendar: calendar
            ),
            .unshield(.pauseMode)
        )
    }

    func testEndingCurrentWindowPreventsScheduledShield() {
        let defaults = testDefaults()
        let now = date(day: 3, hour: 7, minute: 0)
        let window = TimeWindow(
            startTime: "22:00",
            endTime: "08:00",
            repeatDays: [.monday],
            apps: ["instagram"]
        )
        setWindows([window], defaults: defaults)
        defaults.set(
            [window.id: now.addingTimeInterval(30 * 60).timeIntervalSince1970],
            forKey: NimaConstants.timeWindowsEndedUntilKey
        )

        XCTAssertEqual(
            ClientShieldPolicy.decision(
                for: "instagram",
                defaults: defaults,
                now: now,
                calendar: calendar
            ),
            .unshield(.noActiveTimeWindow)
        )
    }

    private func setWindows(_ windows: [TimeWindow], defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try! encoder.encode(windows),
            forKey: NimaConstants.timeWindowsKey
        )
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "ClientShieldPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func date(day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

final class TimeWindowStorePauseTests: XCTestCase {
    func testEligibleWindowStartsBlockingImmediately() {
        let store = makeStore()
        let window = activeWindow(apps: ["instagram"])
        store.windows = [window]
        var instagramScheduled = false

        store.configure(
            applyScheduledApps: { _, _ in },
            applyInstagramProtection: { enabled, _ in instagramScheduled = enabled },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(store.scheduledAppIDs, Set(["instagram"]))
        XCTAssertTrue(instagramScheduled)
        XCTAssertEqual(store.activeWindowIDs, Set([window.id]))
    }

    func testActiveOccurrenceStaysActiveAfterRelaunchWithoutConfirmation() {
        let defaults = testDefaults()
        let firstStore = makeStore(defaults: defaults)
        let window = activeWindow(apps: ["instagram"])
        firstStore.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        firstStore.addWindow(window)

        let relaunchedStore = makeStore(defaults: defaults)
        relaunchedStore.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(relaunchedStore.scheduledAppIDs, Set(["instagram"]))
    }

    func testWindowWithLessThanFiveMinutesRemainingStillStartsImmediately() {
        let store = makeStore()
        store.windows = [currentWindow(id: "near-end", apps: ["instagram"], endOffsetMinutes: 4)]

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(store.scheduledAppIDs, Set(["instagram"]))
    }

    func testOverlappingWindowsStartIndependently() throws {
        let now = Date()
        let instagram = currentWindow(id: "first", apps: ["instagram"], endOffsetMinutes: 20, now: now)
        let tiktok = currentWindow(id: "second", apps: ["tiktok"], endOffsetMinutes: 40, now: now)
        let store = makeStore()
        store.windows = [instagram, tiktok]
        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(store.scheduledAppIDs, Set(["instagram", "tiktok"]))

        let firstEnd = try XCTUnwrap(
            TimeWindowScheduleEvaluator.activeEndDate(for: instagram, now: now)
        )
        store.evaluateSchedules(source: "test.first_end", now: firstEnd)

        XCTAssertEqual(store.scheduledAppIDs, Set(["tiktok"]))
    }

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
        XCTAssertTrue(defaults.bool(forKey: NimaConstants.timeWindowsPauseAllKey))
        XCTAssertEqual(applied.last, Set<String>())
        XCTAssertEqual(scheduler.pauseReminderRequests.count, 1)
    }

    func testManualResumeRestoresInstagramWithoutStartingVPN() {
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
        XCTAssertTrue(startSources.isEmpty)
        XCTAssertEqual(scheduler.cancelPauseReminderCount, 1)
    }

    func testDefaultPauseIntervalSchedulesReminderAfterFiveMinutes() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults, scheduler: scheduler)
        let now = Date(timeIntervalSince1970: 1_000)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.setPauseAll(true, now: now)

        XCTAssertEqual(scheduler.pauseReminderRequests.last?.firstReminderAt, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(scheduler.pauseReminderRequests.last?.reminderInterval, 5 * 60)
    }

    func testSelectedPauseIntervalChangesFirstReminderAndCadence() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults, scheduler: scheduler)
        let now = Date(timeIntervalSince1970: 2_000)

        store.setPauseIntervalMinutes(15, now: now)
        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["tiktok"]))
        store.setPauseAll(true, now: now)

        XCTAssertEqual(scheduler.pauseReminderRequests.last?.firstReminderAt, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(scheduler.pauseReminderRequests.last?.reminderInterval, 15 * 60)
    }

    func testChangingIntervalWhilePausedReschedulesFromNow() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults, scheduler: scheduler)
        let now = Date(timeIntervalSince1970: 3_000)
        let changedAt = now.addingTimeInterval(60)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.setPauseAll(true, now: now)
        store.setPauseIntervalMinutes(30, now: changedAt)

        XCTAssertEqual(scheduler.pauseReminderRequests.last?.firstReminderAt, changedAt.addingTimeInterval(30 * 60))
        XCTAssertEqual(scheduler.pauseReminderRequests.last?.reminderInterval, 30 * 60)
    }

    func testDisabledWindowsNotificationsCancelAndAvoidScheduling() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        defaults.set(false, forKey: NimaConstants.windowsNotificationsEnabledKey)
        let store = makeStore(defaults: defaults, scheduler: scheduler)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.setPauseAll(true, now: Date(timeIntervalSince1970: 4_000))

        XCTAssertTrue(scheduler.pauseReminderRequests.isEmpty)
        XCTAssertGreaterThanOrEqual(scheduler.cancelPauseReminderCount, 1)
    }

    func testReEnablingPauseRemindersSchedulesTheActivePause() {
        let scheduler = FakeTimeWindowNotificationScheduler()
        let defaults = testDefaults()
        defaults.set(false, forKey: NimaConstants.windowsNotificationsEnabledKey)
        let store = makeStore(defaults: defaults, scheduler: scheduler)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["instagram"]))
        store.setPauseAll(true)
        store.setWindowsNotificationsEnabled(true)

        XCTAssertEqual(scheduler.pauseReminderRequests.last?.requestAuthorizationIfNeeded, true)
    }

    func testPauseReminderTapRestoresScheduledBlockersWithoutStartingVPNAndRequestsHome() {
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
        XCTAssertNil(startSources.last)
        XCTAssertEqual(homeFocusCount, 1)
        XCTAssertNotNil(store.homeFocusRequestID)
    }

    func testConfigureAppliesAnAlreadyActiveSchedule() {
        let store = makeStore()
        var applied: [Set<String>] = []

        store.addWindow(activeWindow(apps: ["instagram"]))

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )

        XCTAssertEqual(applied.last, Set(["instagram"]))
    }

    func testInstagramOnlyScheduleDoesNotPersistDesiredVPNState() {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)
        var applied: [Set<String>] = []

        store.configure(
            applyScheduledApps: { appIDs, _ in applied.append(appIDs) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        let window = activeWindow(apps: ["instagram"])
        store.addWindow(window)

        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: defaults)
        XCTAssertEqual(applied.last, Set(["instagram"]))
        XCTAssertFalse(snapshot.desiredVPNOn)
        XCTAssertFalse(snapshot.isDesiredProtectionActive())
        XCTAssertTrue(snapshot.activeAppIDs.isEmpty)
        XCTAssertTrue(snapshot.activeWindowIDs.isEmpty)
        XCTAssertEqual(snapshot.desiredUntil, 0)
    }

    func testControlledClientScheduleDoesNotPersistDesiredVPNState() {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        let window = activeWindow(apps: ["tiktok"])
        store.addWindow(window)

        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: defaults)
        XCTAssertFalse(snapshot.desiredVPNOn)
        XCTAssertFalse(snapshot.isDesiredProtectionActive())
        XCTAssertTrue(snapshot.activeAppIDs.isEmpty)
        XCTAssertTrue(snapshot.activeWindowIDs.isEmpty)
        XCTAssertEqual(snapshot.desiredUntil, 0)
    }

    func testXScheduleUsesControlledClientWithoutStartingVPN() {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)
        var xScheduleStates: [Bool] = []

        store.configure(
            applyScheduledApps: { _, _ in },
            applyXProtection: { enabled, _ in xScheduleStates.append(enabled) },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["x"]))

        XCTAssertEqual(xScheduleStates.last, true)
        XCTAssertTrue(store.isAppScheduled("x"))
        XCTAssertFalse(
            ScheduledProtectionStateStore.snapshot(defaults: defaults).desiredVPNOn
        )
    }

    func testControlledScheduleDoesNotCreateManualVPNSuppressionState() {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)

        store.configure(
            applyScheduledApps: { _, _ in },
            startProtection: { _ in },
            requestHomeFocus: {}
        )
        store.addWindow(activeWindow(apps: ["tiktok"]))

        ScheduledProtectionStateStore.suppressCurrentScheduleWindow(defaults: defaults, source: "settings.toggle_button")

        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: defaults)
        XCTAssertFalse(snapshot.desiredVPNOn)
        XCTAssertFalse(snapshot.isManualOverrideActive())
        XCTAssertFalse(snapshot.isDesiredProtectionActive())
        XCTAssertTrue(snapshot.lastRepairResult.isEmpty)
    }

    func testExpiredManualOffDoesNotSuppressNextWindow() {
        let defaults = testDefaults()
        let now = Date(timeIntervalSince1970: 1_000)
        let firstEnd = now.addingTimeInterval(60)
        ScheduledProtectionStateStore.persistScheduleEvaluation(
            appIDs: ["instagram"],
            windowIDs: ["first"],
            desiredUntil: firstEnd,
            source: "test.first",
            defaults: defaults,
            now: now
        )
        ScheduledProtectionStateStore.suppressCurrentScheduleWindow(
            defaults: defaults,
            source: "settings.toggle_button",
            now: now
        )

        let nextStart = firstEnd.addingTimeInterval(1)
        ScheduledProtectionStateStore.persistScheduleEvaluation(
            appIDs: ["instagram"],
            windowIDs: ["next"],
            desiredUntil: nextStart.addingTimeInterval(60),
            source: "test.next",
            defaults: defaults,
            now: nextStart
        )

        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: defaults)
        XCTAssertFalse(snapshot.isManualOverrideActive(now: nextStart))
        XCTAssertTrue(snapshot.isDesiredProtectionActive(now: nextStart))
        XCTAssertEqual(snapshot.activeWindowIDs, Set(["next"]))
    }

    func testInterruptionAndRepairResultArePersistedForDiagnostics() {
        let defaults = testDefaults()
        let now = Date(timeIntervalSince1970: 2_000)

        ScheduledProtectionStateStore.recordInterruption(
            defaults: defaults,
            result: "unexpected_drop_reconnect_attempt_1",
            now: now
        )
        ScheduledProtectionStateStore.recordRepairResult(defaults: defaults, result: "schedule.repair_start_called")

        let snapshot = ScheduledProtectionStateStore.snapshot(defaults: defaults)
        XCTAssertEqual(snapshot.lastInterruptionAt, now.timeIntervalSince1970)
        XCTAssertEqual(snapshot.lastRepairResult, "schedule.repair_start_called")
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
        XCTAssertFalse(defaults.dictionary(forKey: NimaConstants.timeWindowsEndedUntilKey)?.isEmpty ?? true)
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

    private func currentWindow(
        id: String,
        apps: [String],
        endOffsetMinutes: Int,
        now: Date = Date()
    ) -> TimeWindow {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .minute, value: -1, to: now) ?? now
        let endDate = calendar.date(byAdding: .minute, value: endOffsetMinutes, to: now) ?? now
        let startWeekday = TimeWindowWeekday.from(
            calendarWeekday: calendar.component(.weekday, from: startDate)
        )
        return TimeWindow(
            id: id,
            startTime: TimeWindowScheduleEvaluator.timeString(from: startDate, calendar: calendar),
            endTime: TimeWindowScheduleEvaluator.timeString(from: endDate, calendar: calendar),
            repeatDays: [startWeekday],
            apps: apps
        )
    }

    private func timeString(fromMinuteOfDay minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

private final class FakeTimeWindowNotificationScheduler: TimeWindowNotificationScheduling {
    var pauseReminderRequests: [(firstReminderAt: Date, windowEndDate: Date?, reminderInterval: TimeInterval, requestAuthorizationIfNeeded: Bool)] = []
    var cancelPauseReminderCount = 0

    func schedulePauseReminderNotifications(
        firstReminderAt: Date,
        windowEndDate: Date?,
        reminderInterval: TimeInterval,
        requestAuthorizationIfNeeded: Bool
    ) {
        pauseReminderRequests.append((firstReminderAt, windowEndDate, reminderInterval, requestAuthorizationIfNeeded))
    }

    func cancelPauseReminderNotifications() {
        cancelPauseReminderCount += 1
    }
}
