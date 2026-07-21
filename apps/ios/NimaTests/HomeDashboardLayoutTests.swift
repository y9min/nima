import SwiftUI
import XCTest
@testable import Nima

final class HomeDashboardLayoutTests: XCTestCase {
    func testStandardIPhoneFitsWithoutScroll() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0),
            contentSizeCategory: .large
        )

        XCTAssertFalse(layout.requiresScroll)
        XCTAssertLessThanOrEqual(layout.contentHeight, layout.availableHeight + 0.5)
        XCTAssertEqual(layout.contentWidth, 354, accuracy: 0.5)
    }

    func testSmallIPhoneUsesScrollFallback() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 375, height: 667),
            safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0),
            contentSizeCategory: .large
        )

        XCTAssertTrue(layout.requiresScroll)
        XCTAssertGreaterThan(layout.scale, 0.9)
    }

    func testProMaxDoesNotOverStretch() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 430, height: 932),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            contentSizeCategory: .large
        )

        XCTAssertFalse(layout.requiresScroll)
        XCTAssertLessThanOrEqual(layout.contentWidth, 357)
        XCTAssertLessThanOrEqual(layout.contentHeight, layout.availableHeight + 0.5)
    }

    func testIPadCentersPhoneWidthLayout() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 834, height: 1194),
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
            contentSizeCategory: .large
        )

        XCTAssertFalse(layout.requiresScroll)
        XCTAssertEqual(layout.contentWidth, 357, accuracy: 0.5)
        XCTAssertEqual(layout.contentMinX, 238.5, accuracy: 0.5)
    }

    func testAccessibilityTextUsesScrollFallback() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 47, leading: 0, bottom: 34, trailing: 0),
            contentSizeCategory: .accessibilityLarge
        )

        XCTAssertTrue(layout.requiresScroll)
    }
}

final class AdaptiveScreenMetricsTests: XCTestCase {
    func testSEUsesCompactHeightAndKeepsCardInsideSafeArea() {
        let metrics = AdaptiveScreenMetrics(
            screenSize: CGSize(width: 375, height: 667),
            safeAreaInsets: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        )

        let card = metrics.cardSize()

        XCTAssertTrue(metrics.isCompactHeight)
        XCTAssertLessThanOrEqual(card.width, 347)
        XCTAssertLessThanOrEqual(card.height, metrics.safeContentHeight - 24)
        XCTAssertLessThan(metrics.scale(referenceHeight: 760), 0.9)
    }

    func testMiniUsesBothWidthAndSafeHeight() {
        let metrics = AdaptiveScreenMetrics(
            screenSize: CGSize(width: 375, height: 812),
            safeAreaInsets: EdgeInsets(top: 44, leading: 0, bottom: 34, trailing: 0)
        )

        XCTAssertFalse(metrics.isCompactHeight)
        XCTAssertEqual(metrics.scale(referenceHeight: 760), 375.0 / 390.0, accuracy: 0.001)
    }

    func testStandardAndMaxPhonesNeverScalePastOne() {
        let standard = AdaptiveScreenMetrics(
            screenSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )
        let max = AdaptiveScreenMetrics(
            screenSize: CGSize(width: 440, height: 956),
            safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        )

        XCTAssertLessThanOrEqual(standard.scale(referenceHeight: 760), 1)
        XCTAssertEqual(max.scale(referenceHeight: 760), 1)
        XCTAssertLessThanOrEqual(max.cardSize().width, 430)
        XCTAssertLessThanOrEqual(max.cardSize().height, 780)
    }

    func testLargeDynamicTypeStillForcesHomeScroll() {
        let layout = HomeDashboardLayout(
            screenSize: CGSize(width: 375, height: 812),
            safeAreaInsets: EdgeInsets(top: 44, leading: 0, bottom: 34, trailing: 0),
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        XCTAssertTrue(layout.requiresScroll)
    }
}

final class BlockingRingStateTests: XCTestCase {
    func testNoBlockedAppsShowsEmptyRingAndBlockCopy() {
        let state = BlockingRingState(blockedAppIDs: [])

        XCTAssertEqual(state, .empty)
        XCTAssertFalse(state.isInstagramBlocked)
        XCTAssertFalse(state.isTikTokBlocked)
        XCTAssertFalse(state.hasBlockedApp)
        XCTAssertEqual(state.centerTitle, "BLOCK")
    }

    func testInstagramBlockedLightsLeftHalf() {
        let state = BlockingRingState(blockedAppIDs: ["instagram"])

        XCTAssertEqual(state, .instagramOnly)
        XCTAssertTrue(state.isInstagramBlocked)
        XCTAssertFalse(state.isTikTokBlocked)
        XCTAssertTrue(state.hasBlockedApp)
        XCTAssertEqual(state.centerTitle, "BLOCK")
    }

    func testTikTokBlockedLightsRightHalf() {
        let state = BlockingRingState(blockedAppIDs: ["tiktok"])

        XCTAssertEqual(state, .tiktokOnly)
        XCTAssertFalse(state.isInstagramBlocked)
        XCTAssertTrue(state.isTikTokBlocked)
        XCTAssertTrue(state.hasBlockedApp)
        XCTAssertEqual(state.centerTitle, "BLOCK")
    }

    func testBothBlockedShowsFullRingAndUnblockCopy() {
        let state = BlockingRingState(blockedAppIDs: ["instagram", "tiktok"])

        XCTAssertEqual(state, .both)
        XCTAssertTrue(state.isInstagramBlocked)
        XCTAssertTrue(state.isTikTokBlocked)
        XCTAssertTrue(state.hasBlockedApp)
        XCTAssertEqual(state.centerTitle, "UNBLOCK")
    }
}

final class BlockingConnectionIndicatorStateTests: XCTestCase {
    func testDisconnectedVPNShowsDisconnectedIndicator() {
        XCTAssertEqual(BlockingVPNState.disconnected.connectionIndicatorState, .disconnected)
    }

    func testConnectingVPNShowsTransitioningIndicator() {
        XCTAssertEqual(BlockingVPNState.connecting.connectionIndicatorState, .transitioning)
    }

    func testDisconnectingVPNShowsTransitioningIndicator() {
        XCTAssertEqual(BlockingVPNState.disconnecting.connectionIndicatorState, .transitioning)
    }

    func testConnectedVPNShowsConnectedIndicator() {
        XCTAssertEqual(BlockingVPNState.connected.connectionIndicatorState, .connected)
    }

    func testPermissionRequiredShowsPermissionIndicator() {
        XCTAssertEqual(BlockingVPNState.permissionRequired.connectionIndicatorState, .permissionRequired)
    }
}

final class StreakStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: StreakStore!

    override func setUp() {
        super.setUp()
        suiteName = "StreakStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = StreakStore(defaults: defaults, storageKey: "streakDaysTest")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMarkTodayEarnedStoresOneRecordOnly() {
        let calendar = londonCalendar()
        let now = date(year: 2026, month: 6, day: 3, hour: 23, minute: 59, calendar: calendar)

        XCTAssertTrue(store.markTodayEarned(source: "instagram_strict_reels", now: now, calendar: calendar))
        XCTAssertFalse(store.markTodayEarned(source: "tiktok_video_block", now: now, calendar: calendar))

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.date, "2026-06-03")
        XCTAssertEqual(store.records.first?.source, "instagram_strict_reels")
        XCTAssertEqual(store.records.first?.timezone, "Europe/London")
    }

    func testMidweekStartLeavesEarlierDaysMutedAndTodayPending() {
        let calendar = londonCalendar()
        let wednesday = date(year: 2026, month: 6, day: 3, calendar: calendar)
        let thursday = date(year: 2026, month: 6, day: 4, calendar: calendar)

        store.markTodayEarned(source: "instagram_strict_reels", now: wednesday, calendar: calendar)
        let states = store.weekStates(now: thursday, calendar: calendar)

        XCTAssertEqual(states.map(\.label), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(states.map(\.status), [
            .beforeTrackingStarted,
            .beforeTrackingStarted,
            .earned,
            .todayPending,
            .future,
            .future,
            .future
        ])
    }

    func testCurrentStreakCountsThroughYesterdayWhenTodayIsPending() {
        let calendar = londonCalendar()
        store.markTodayEarned(source: "instagram_strict_reels", now: date(year: 2026, month: 6, day: 1, calendar: calendar), calendar: calendar)
        store.markTodayEarned(source: "tiktok_video_block", now: date(year: 2026, month: 6, day: 2, calendar: calendar), calendar: calendar)

        let wednesday = date(year: 2026, month: 6, day: 3, calendar: calendar)

        XCTAssertEqual(store.currentStreak(now: wednesday, calendar: calendar), 2)
        XCTAssertEqual(store.weekStates(now: wednesday, calendar: calendar)[2].status, .todayPending)
    }

    func testMissingYesterdayBreaksStreakUnlessTodayIsEarned() {
        let calendar = londonCalendar()
        store.markTodayEarned(source: "instagram_strict_reels", now: date(year: 2026, month: 6, day: 1, calendar: calendar), calendar: calendar)

        let wednesday = date(year: 2026, month: 6, day: 3, calendar: calendar)
        XCTAssertEqual(store.currentStreak(now: wednesday, calendar: calendar), 0)

        store.markTodayEarned(source: "tiktok_video_block", now: wednesday, calendar: calendar)
        XCTAssertEqual(store.currentStreak(now: wednesday, calendar: calendar), 1)
    }

    func testWeeklyDotsResetOnMondayWhileHistoricalStreakCounts() {
        let calendar = londonCalendar()
        store.markTodayEarned(source: "instagram_strict_reels", now: date(year: 2026, month: 6, day: 5, calendar: calendar), calendar: calendar)
        store.markTodayEarned(source: "instagram_strict_reels", now: date(year: 2026, month: 6, day: 6, calendar: calendar), calendar: calendar)
        store.markTodayEarned(source: "instagram_strict_reels", now: date(year: 2026, month: 6, day: 7, calendar: calendar), calendar: calendar)
        let monday = date(year: 2026, month: 6, day: 8, calendar: calendar)
        store.markTodayEarned(source: "instagram_strict_reels", now: monday, calendar: calendar)

        XCTAssertEqual(store.currentStreak(now: monday, calendar: calendar), 4)
        XCTAssertEqual(store.weekStates(now: monday, calendar: calendar).map(\.status), [
            .earned,
            .future,
            .future,
            .future,
            .future,
            .future,
            .future
        ])
    }

    func testZeroRecordStateShowsStartableWeek() {
        let calendar = londonCalendar()
        let wednesday = date(year: 2026, month: 6, day: 3, calendar: calendar)

        XCTAssertEqual(store.currentStreak(now: wednesday, calendar: calendar), 0)
        XCTAssertEqual(store.weekStates(now: wednesday, calendar: calendar).map(\.status), [
            .beforeTrackingStarted,
            .beforeTrackingStarted,
            .todayPending,
            .future,
            .future,
            .future,
            .future
        ])
    }

    private func londonCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
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
