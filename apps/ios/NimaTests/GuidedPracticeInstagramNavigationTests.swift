import XCTest
@testable import Nima

final class GuidedPracticeInstagramNavigationTests: XCTestCase {
    func testOpenAppPromptIsHiddenWhileWaitingForInstagramReturn() {
        XCTAssertTrue(GuidedPracticePhase.openAppPrompt.showsOpenAppPromptOverlay)
        XCTAssertFalse(GuidedPracticePhase.waitingForReturn.showsOpenAppPromptOverlay)
    }

    func testOpenRequestRequiresOpenAppPromptAndAvailableClient() {
        var gate = GuidedPracticeInstagramOpenGate()

        XCTAssertFalse(
            gate.requestOpen(
                from: .waitingForReturn,
                canOpenControlledClient: { true }
            )
        )
        XCTAssertFalse(
            gate.requestOpen(
                from: .openAppPrompt,
                canOpenControlledClient: { false }
            )
        )
        XCTAssertTrue(
            gate.requestOpen(
                from: .openAppPrompt,
                canOpenControlledClient: { true }
            )
        )
    }

    func testOpenGatePreventsDuplicateInstagramRoutesUntilRouteFinishes() {
        var gate = GuidedPracticeInstagramOpenGate()

        XCTAssertTrue(
            gate.requestOpen(
                from: .openAppPrompt,
                canOpenControlledClient: { true }
            )
        )
        XCTAssertFalse(
            gate.requestOpen(
                from: .openAppPrompt,
                canOpenControlledClient: { true }
            )
        )

        gate.finishRoute()

        XCTAssertTrue(
            gate.requestOpen(
                from: .openAppPrompt,
                canOpenControlledClient: { true }
            )
        )
    }
}
