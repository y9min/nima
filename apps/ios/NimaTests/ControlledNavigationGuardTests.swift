import XCTest
@testable import Nima

final class ControlledNavigationGuardTests: XCTestCase {
    func testRepeatedBlockedRouteIsDetectedInsideDecisionWindow() {
        var guardState = ControlledNavigationGuard()
        let url = URL(string: "https://x.com/explore")!
        let now = Date()

        XCTAssertFalse(guardState.recordBlockedNavigation(to: url, now: now))
        XCTAssertTrue(
            guardState.recordBlockedNavigation(
                to: url,
                now: now.addingTimeInterval(1)
            )
        )
    }

    func testBlockedRouteDetectionExpires() {
        var guardState = ControlledNavigationGuard()
        let url = URL(string: "https://x.com/explore")!
        let now = Date()

        XCTAssertFalse(guardState.recordBlockedNavigation(to: url, now: now))
        XCTAssertFalse(
            guardState.recordBlockedNavigation(
                to: url,
                now: now.addingTimeInterval(4)
            )
        )
    }

    func testStaleNavigationGenerationIsRejected() {
        var guardState = ControlledNavigationGuard()
        let first = guardState.beginNavigation()
        let second = guardState.beginNavigation()

        XCTAssertFalse(guardState.isCurrent(first))
        XCTAssertTrue(guardState.isCurrent(second))
    }
}
