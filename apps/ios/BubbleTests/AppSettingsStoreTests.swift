import XCTest
@testable import Bubble

final class AppSettingsStoreTests: XCTestCase {
    func testDisplayNameFallbackUsesLocalNameEmailThenDefault() {
        XCTAssertEqual(
            AppSettingsStore.resolvedDisplayName(localOverride: " Nima ", userEmail: "person@example.com"),
            "Nima"
        )
        XCTAssertEqual(
            AppSettingsStore.resolvedDisplayName(localOverride: " ", userEmail: "Yamin.Ahmed@example.com"),
            "yamin"
        )
        XCTAssertEqual(
            AppSettingsStore.resolvedDisplayName(localOverride: nil, userEmail: ""),
            "emily"
        )
    }

    func testBlankDisplayNameClearsLocalOverrideAndPreservesDefaultFallback() {
        let defaults = testDefaults()
        let scheduler = FakeStreakReminderScheduler()
        defaults.set("Nima", forKey: BubbleConstants.displayNameKey)

        let store = AppSettingsStore(defaults: defaults, streakReminderScheduler: scheduler)

        XCTAssertEqual(store.displayName, "Nima")

        store.setDisplayName(" ")

        XCTAssertEqual(store.displayName, "")
        XCTAssertNil(defaults.string(forKey: BubbleConstants.displayNameKey))
        XCTAssertEqual(
            AppSettingsStore.resolvedDisplayName(
                localOverride: store.normalizedDisplayName,
                userEmail: ""
            ),
            "emily"
        )
    }

    func testStreakReminderSchedulerSkipsTodayAfterStreakEarned() {
        let defaults = testDefaults()
        let scheduler = FakeStreakReminderScheduler()
        let store = AppSettingsStore(defaults: defaults, streakReminderScheduler: scheduler)
        let calendar = testCalendar()
        let now = date(year: 2026, month: 6, day: 7, hour: 10, minute: 0, calendar: calendar)

        XCTAssertTrue(store.streakRemindersEnabled)
        XCTAssertEqual(scheduler.scheduledRequests.last?.dates.count, AppSettingsStore.scheduledStreakReminderDayCount)
        XCTAssertEqual(scheduler.scheduledRequests.last?.requestAuthorizationIfNeeded, false)

        store.syncStreakReminder(hasEarnedToday: false, now: now, calendar: calendar)

        XCTAssertEqual(
            scheduler.scheduledRequests.last?.dates.first,
            date(year: 2026, month: 6, day: 7, hour: 20, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(scheduler.scheduledRequests.last?.dates.count, AppSettingsStore.scheduledStreakReminderDayCount)

        store.syncStreakReminder(hasEarnedToday: true, now: now, calendar: calendar)

        XCTAssertEqual(
            scheduler.scheduledRequests.last?.dates.first,
            date(year: 2026, month: 6, day: 8, hour: 20, minute: 0, calendar: calendar)
        )

        store.setStreakRemindersEnabled(true, hasEarnedToday: true, now: now, calendar: calendar)

        XCTAssertEqual(
            scheduler.scheduledRequests.last?.dates.first,
            date(year: 2026, month: 6, day: 8, hour: 20, minute: 0, calendar: calendar)
        )
        XCTAssertEqual(scheduler.scheduledRequests.last?.requestAuthorizationIfNeeded, true)

        store.setStreakReminderTime(hour: 9, minute: 30, hasEarnedToday: false, now: now, calendar: calendar)

        XCTAssertEqual(
            scheduler.scheduledRequests.last?.dates.first,
            date(year: 2026, month: 6, day: 8, hour: 9, minute: 30, calendar: calendar)
        )

        store.setStreakRemindersEnabled(false)

        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testStreakReminderNotificationCopyMatchesProductText() {
        XCTAssertEqual(StreakReminderScheduler.notificationTitle, "Don't lose your streak 🔥")
        XCTAssertEqual(StreakReminderScheduler.notificationBody, "Activate Nima and protect your focus")
    }

    func testAdvancedResetRestoresTunnelDefaultsOnly() {
        let defaults = testDefaults()
        defaults.set(false, forKey: BubbleConstants.udpSelectiveSafeModeEnabledKey)
        defaults.set(true, forKey: BubbleConstants.udpDisabledFastRejectEnabledKey)
        defaults.set(
            BubbleConstants.tun2socksStartupModeBypassDiagnostic,
            forKey: BubbleConstants.tun2socksStartupModeKey
        )

        AppSettingsStore.resetAdvancedDefaults(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: BubbleConstants.udpSelectiveSafeModeEnabledKey))
        XCTAssertFalse(defaults.bool(forKey: BubbleConstants.udpDisabledFastRejectEnabledKey))
        XCTAssertEqual(
            defaults.string(forKey: BubbleConstants.tun2socksStartupModeKey),
            BubbleConstants.tun2socksStartupModeStagedAfterConnect
        )
    }

    private func testDefaults() -> UserDefaults {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

private final class FakeStreakReminderScheduler: StreakReminderScheduling {
    var scheduledRequests: [(dates: [Date], requestAuthorizationIfNeeded: Bool)] = []
    var cancelCount = 0

    func scheduleStreakReminders(
        at dates: [Date],
        requestAuthorizationIfNeeded: Bool
    ) {
        scheduledRequests.append((dates, requestAuthorizationIfNeeded))
    }

    func cancelStreakReminder() {
        cancelCount += 1
    }
}
