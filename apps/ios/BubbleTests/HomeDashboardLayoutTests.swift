import SwiftUI
import XCTest
@testable import Bubble

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
