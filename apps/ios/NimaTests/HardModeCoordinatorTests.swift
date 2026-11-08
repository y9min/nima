import XCTest
import Lottie
import UIKit
@testable import Nima

@MainActor
final class HardModeCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now: Date!

    override func setUp() {
        super.setUp()
        suiteName = "HardModeCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        now = nil
        super.tearDown()
    }

    func testActivationWarningPersistsOnlyAfterConfirmation() {
        let coordinator = makeCoordinator()

        coordinator.requestActivationWarning()
        XCTAssertTrue(coordinator.isShowingActivationWarning)
        XCTAssertFalse(coordinator.isEnabled)

        coordinator.dismissActivationWarning()
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertFalse(HardModeProtectionState.isEnabled(defaults: defaults))

        coordinator.requestActivationWarning()
        coordinator.confirmActivation()
        XCTAssertTrue(coordinator.isEnabled)
        XCTAssertTrue(HardModeProtectionState.isEnabled(defaults: defaults))
    }

    func testDisabledHardModePerformsDirectAction() {
        var performedChoice: HardModeCommitChoice?
        let coordinator = makeCoordinator()
        coordinator.configure { commit in
            performedChoice = commit.choice
            return .success
        }

        XCTAssertTrue(coordinator.requestOff(
            .disableClientProtection(appID: "instagram"),
            source: "test"
        ))
        XCTAssertEqual(performedChoice, .direct)
        XCTAssertNil(coordinator.activeAttempt)
    }

    func testFourStepsAndFullTimerAreRequiredBeforeAuthorization() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(
            .disableClientProtection(appID: "tiktok"),
            source: "test"
        )

        XCTAssertEqual(coordinator.activeAttempt?.step, .trace)
        coordinator.advanceStep()
        XCTAssertEqual(coordinator.activeAttempt?.step, .shade)
        coordinator.advanceStep()
        XCTAssertEqual(coordinator.activeAttempt?.step, .draw)
        coordinator.advanceStep()
        XCTAssertEqual(coordinator.activeAttempt?.step, .wait)
        XCTAssertEqual(coordinator.stepFourSecondsRemaining, 60)
        XCTAssertNil(coordinator.authorizeFinalChoice(.pause(minutes: 5)))

        now = now.addingTimeInterval(59)
        XCTAssertEqual(coordinator.stepFourSecondsRemaining, 1)
        XCTAssertNil(coordinator.authorizeFinalChoice(.off))

        now = now.addingTimeInterval(1)
        let commit = coordinator.authorizeFinalChoice(.pause(minutes: 5))
        XCTAssertEqual(commit?.change.affectedAppIDs, ["tiktok"])
        XCTAssertEqual(commit?.choice, .pause(minutes: 5))
    }

    func testCancellationDiscardsAttemptAndTimer() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(
            .disableClientProtection(appID: "x"),
            source: "test"
        )
        coordinator.advanceStep()
        coordinator.advanceStep()
        coordinator.advanceStep()
        now = now.addingTimeInterval(30)

        coordinator.cancelChallenge()

        XCTAssertNil(coordinator.activeAttempt)
        XCTAssertNil(coordinator.authorizedCommit)
        XCTAssertEqual(coordinator.stepFourSecondsRemaining, 60)
    }

    func testDrawTargetIsChosenOncePerAttempt() {
        var targets: [HardModeDrawTarget] = [.umbrella, .rocket]
        let coordinator = HardModeCoordinator(
            defaults: defaults,
            now: { [unowned self] in self.now },
            drawTargetProvider: { targets.removeFirst() }
        )
        coordinator.configure { _ in .success }
        coordinator.requestActivationWarning()
        coordinator.confirmActivation()

        _ = coordinator.requestOff(
            .disableClientProtection(appID: "instagram"),
            source: "test"
        )
        XCTAssertEqual(coordinator.activeAttempt?.drawTarget, .umbrella)

        coordinator.cancelChallenge()
        _ = coordinator.requestOff(
            .disableClientProtection(appID: "instagram"),
            source: "test"
        )
        XCTAssertEqual(coordinator.activeAttempt?.drawTarget, .rocket)
    }

    func testAuthorizedCompletionIsOneUseAndHardModeOffDoesNotChangeAttemptType() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(.turnOffHardMode, source: "test")
        coordinator.advanceStep()
        coordinator.advanceStep()
        coordinator.advanceStep()
        now = now.addingTimeInterval(60)

        let commit = coordinator.authorizeFinalChoice(.off)
        XCTAssertNotNil(commit)
        XCTAssertNil(coordinator.authorizeFinalChoice(.off))

        coordinator.finishCommit(commit!, result: .success)
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertNil(coordinator.activeAttempt)
    }

    func testHardModeOffRejectsBlockerPauseChoice() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(.turnOffHardMode, source: "test")
        coordinator.advanceStep()
        coordinator.advanceStep()
        coordinator.advanceStep()
        now = now.addingTimeInterval(60)

        XCTAssertNil(coordinator.authorizeFinalChoice(.pause(minutes: 10)))
    }

    func testBatchSelectionRequiresCompletedChallengeAndIsOneUse() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(.disableClientProtection(appID: "x"), source: "test")
        let selection = HardModeBatchSelection(
            appChoices: [
                "x": .pause(minutes: 10),
                "instagram": .keep,
                "tiktok": .off
            ],
            turnOffHardMode: true
        )
        XCTAssertNil(coordinator.authorizeFinalChoice(.batch(selection)))
        coordinator.advanceStep()
        coordinator.advanceStep()
        coordinator.advanceStep()
        now = now.addingTimeInterval(60)

        let commit = coordinator.authorizeFinalChoice(.batch(selection))
        XCTAssertNotNil(commit)
        XCTAssertNil(coordinator.authorizeFinalChoice(.batch(selection)))

        coordinator.finishCommit(commit!, result: .success)
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertNil(coordinator.activeAttempt)
    }

    func testBatchRejectsEmptyOrInvalidChoices() {
        let coordinator = makeEnabledCoordinator()
        _ = coordinator.requestOff(.disableClientProtection(appID: "x"), source: "test")
        coordinator.advanceStep()
        coordinator.advanceStep()
        coordinator.advanceStep()
        now = now.addingTimeInterval(60)

        XCTAssertNil(coordinator.authorizeFinalChoice(.batch(.init(
            appChoices: ["x": .keep], turnOffHardMode: false
        ))))
        XCTAssertNil(coordinator.authorizeFinalChoice(.batch(.init(
            appChoices: ["x": .pause(minutes: 30)], turnOffHardMode: false
        ))))
        XCTAssertNil(coordinator.authorizeFinalChoice(.batch(.init(
            appChoices: ["unknown": .off], turnOffHardMode: false
        ))))
    }

    func testPauseAndScheduleSuppressionExpireIndependently() {
        let start = now!
        HardModeProtectionState.pause(
            appIDs: ["instagram"],
            minutes: 5,
            defaults: defaults,
            now: start
        )
        HardModeProtectionState.markProtectionOff("tiktok", defaults: defaults)

        XCTAssertTrue(HardModeProtectionState.isPaused(
            "instagram",
            defaults: defaults,
            now: start.addingTimeInterval(299)
        ))
        XCTAssertFalse(HardModeProtectionState.isPaused(
            "instagram",
            defaults: defaults,
            now: start.addingTimeInterval(301)
        ))
        XCTAssertFalse(HardModeProtectionState.effectivelyScheduled(
            "tiktok",
            scheduled: true,
            defaults: defaults
        ))

        HardModeProtectionState.markProtectionOn("tiktok", defaults: defaults)
        XCTAssertTrue(HardModeProtectionState.effectivelyScheduled(
            "tiktok",
            scheduled: true,
            defaults: defaults
        ))
    }

    private func makeCoordinator() -> HardModeCoordinator {
        HardModeCoordinator(defaults: defaults, now: { [unowned self] in self.now })
    }

    private func makeEnabledCoordinator() -> HardModeCoordinator {
        let coordinator = makeCoordinator()
        coordinator.configure { _ in .success }
        coordinator.requestActivationWarning()
        coordinator.confirmActivation()
        return coordinator
    }
}

final class HardModeChallengeLogicTests: XCTestCase {
    func testDrawTargetsHaveDistinctReferenceAssets() {
        XCTAssertEqual(HardModeDrawTarget.allCases.count, 4)
        XCTAssertEqual(
            Set(HardModeDrawTarget.allCases.map(\.referenceImageName)).count,
            HardModeDrawTarget.allCases.count
        )
    }

    func testEveryDrawTargetAssetLoadsAndCanBeTraced() throws {
        let canvasSize = CGSize(width: 346, height: 330)
        for target in HardModeDrawTarget.allCases {
            let image = try XCTUnwrap(
                UIImage(named: target.referenceImageName),
                "Missing draw target asset: \(target.referenceImageName)"
            )
            let targetPoints = HardModeRasterTraceScorer.targetPoints(
                image: image,
                canvasSize: canvasSize,
                imageInset: 12
            )
            let result = HardModeRasterTraceScorer.evaluate(
                image: image,
                drawingGroups: [targetPoints],
                canvasSize: canvasSize,
                imageInset: 12,
                tolerance: 0.075,
                minimumCoverage: 0.35,
                minimumInkPrecision: 0.35,
                minimumRegions: 2
            )

            XCTAssertFalse(targetPoints.isEmpty, target.referenceImageName)
            XCTAssertTrue(result.passed, target.referenceImageName)
        }
    }

    func testPaintDryingLottieAssetIsBundled() throws {
        let animation = try XCTUnwrap(
            LottieAnimation.named(
                "nima_paint_drying",
                subdirectory: "PaintDrying"
            )
        )

        XCTAssertEqual(animation.framerate, 30)
        XCTAssertEqual(animation.endFrame, 1_800)
    }

    func testPerfectPhraseTracePassesAtNormalizedSizes() {
        let target = HardModeChallengeGeometry.phraseTargetGroups[0]
        let result = HardModePathScorer.evaluate(
            targetGroups: target,
            drawingGroups: target,
            tolerance: 0.07
        )

        XCTAssertTrue(result.passed)
        XCTAssertGreaterThan(result.targetCoverage, 0.99)
        XCTAssertGreaterThan(result.inkPrecision, 0.99)
    }

    func testShortScribbleCannotPassPhraseTrace() {
        let target = HardModeChallengeGeometry.phraseTargetGroups[0]
        let scribble = [
            CGPoint(x: 0.10, y: 0.30),
            CGPoint(x: 0.15, y: 0.31)
        ]
        let result = HardModePathScorer.evaluate(
            targetGroups: target,
            drawingGroups: [scribble],
            tolerance: 0.07
        )

        XCTAssertFalse(result.passed)
    }

    func testPalmTraceRequiresTrunkAndFronds() {
        let trunkOnly = HardModeChallengeGeometry.palmTrunk
        let trunkResult = HardModePathScorer.evaluate(
            targetGroups: [
                HardModeChallengeGeometry.palmTrunk,
                HardModeChallengeGeometry.palmFronds
            ],
            drawingGroups: [trunkOnly],
            tolerance: 0.07,
            minimumCoveragePerRequiredGroup: 0.18
        )
        XCTAssertFalse(trunkResult.passed)

        let fullResult = HardModePathScorer.evaluate(
            targetGroups: [
                HardModeChallengeGeometry.palmTrunk,
                HardModeChallengeGeometry.palmFronds
            ],
            drawingGroups: [
                HardModeChallengeGeometry.palmTrunk,
                HardModeChallengeGeometry.palmFronds
            ],
            tolerance: 0.07,
            minimumCoveragePerRequiredGroup: 0.18
        )
        XCTAssertTrue(fullResult.passed)
    }

    func testShadeAndSizeOrdersUseExplicitRanks() {
        XCTAssertEqual(HardModeSortChallenge.items.count, 15)
        XCTAssertEqual(HardModeSortChallenge.items.map(\.lightness), HardModeSortChallenge.items.map(\.lightness).sorted())
        XCTAssertEqual(HardModeSortChallenge.items.map(\.size), HardModeSortChallenge.items.map(\.size).sorted())
        XCTAssertTrue(HardModeSortChallenge.isCorrect(HardModeSortChallenge.rankedItemIDs.map(Optional.some)))

        var wrong = HardModeSortChallenge.rankedItemIDs.map(Optional.some)
        wrong.swapAt(3, 4)
        XCTAssertFalse(HardModeSortChallenge.isCorrect(wrong))
        XCTAssertEqual(HardModeSortChallenge.firstIncorrectPair(wrong), 2...3)
        XCTAssertEqual(HardModeSortChallenge.incorrectSlotIndices(wrong), [3, 4])
    }
}
