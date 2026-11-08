import Foundation
import Observation

enum HardModeChallengeStep: Int, CaseIterable, Equatable {
    case trace = 1
    case shade = 2
    case draw = 3
    case wait = 4

    var title: String {
        switch self {
        case .trace: "trace the phrases"
        case .shade: "sort by size"
        case .draw: "draw this"
        case .wait: "wait for the timer"
        }
    }
}

enum HardModeRequestedMutation: Equatable {
    case disableClientProtection(appID: String)
    case disableBlockingOption(appID: String, optionID: String)
    case endActiveWindows(appID: String)
    case setWindowEnabled(windowID: String, enabled: Bool)
    case updateWindow(TimeWindow, expectedUpdatedAt: Date)
    case deleteWindow(windowID: String)
    case updateAppRule(ruleID: String, kind: AppControlKind, dailyMinutes: Int?, affectedAppIDs: Set<String>)
    case deleteAppRule(ruleID: String, affectedAppIDs: Set<String>)
    case pauseAllWindows
    case turnOffHardMode
}

struct HardModeRequestedChange: Identifiable, Equatable {
    let id: UUID
    let mutation: HardModeRequestedMutation
    let affectedAppIDs: Set<String>
    let source: String
    let requestedAt: Date

    init(
        id: UUID = UUID(),
        mutation: HardModeRequestedMutation,
        affectedAppIDs: Set<String>? = nil,
        source: String,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.mutation = mutation
        self.source = source
        self.requestedAt = requestedAt
        self.affectedAppIDs = affectedAppIDs ?? mutation.defaultAffectedAppIDs
    }
}

enum HardModeCommitChoice: Equatable {
    case direct
    case pause(minutes: Int)
    case off
    case batch(HardModeBatchSelection)
}

enum HardModeAppChoice: Equatable {
    case keep
    case pause(minutes: Int)
    case off
}

struct HardModeBatchSelection: Equatable {
    let appChoices: [String: HardModeAppChoice]
    let turnOffHardMode: Bool

    var hasChanges: Bool {
        turnOffHardMode || appChoices.values.contains { $0 != .keep }
    }
}

struct HardModeCommit: Identifiable, Equatable {
    let id: UUID
    let change: HardModeRequestedChange
    let choice: HardModeCommitChoice
}

enum HardModeCommitResult: Equatable {
    case success
    case failure(String)
    case stale(String)
}

enum HardModeDrawTarget: String, CaseIterable, Equatable, Sendable {
    case umbrella
    case rocket
    case fish
    case palmTree

    var drawTitle: String {
        switch self {
        case .umbrella: "Draw an umbrella"
        case .rocket: "Draw a rocket"
        case .fish: "Draw a fish"
        case .palmTree: "Draw a palm tree"
        }
    }

    var referenceImageName: String {
        switch self {
        case .umbrella: "HardModeDrawUmbrella"
        case .rocket: "HardModeDrawRocket"
        case .fish: "HardModeDrawFish"
        case .palmTree: "HardModeDrawPalm"
        }
    }
}

struct HardModeAttempt: Equatable {
    let id: UUID
    let change: HardModeRequestedChange
    let drawTarget: HardModeDrawTarget
    var step: HardModeChallengeStep
    var stepFourStartedAt: Date?
}

@MainActor
@Observable
final class HardModeCoordinator {
    private(set) var isEnabled: Bool
    private(set) var activeAttempt: HardModeAttempt?
    private(set) var isShowingActivationWarning = false
    private(set) var authorizedCommit: HardModeCommit?
    private(set) var errorMessage: String?
    private(set) var stepHint: String?

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let drawTargetProvider: () -> HardModeDrawTarget
    @ObservationIgnored private var performer: ((HardModeCommit) -> HardModeCommitResult)?

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        now: @escaping () -> Date = Date.init,
        drawTargetProvider: @escaping () -> HardModeDrawTarget = {
            HardModeDrawTarget.allCases.randomElement() ?? .palmTree
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.drawTargetProvider = drawTargetProvider
        isEnabled = HardModeProtectionState.isEnabled(defaults: defaults)
        HardModeProtectionState.purgeExpiredPauses(defaults: defaults, now: now())
    }

    var isPresentingChallenge: Bool {
        activeAttempt != nil
    }

    var isAwaitingFinalChoice: Bool {
        activeAttempt?.step == .wait
            && stepFourSecondsRemaining <= 0
            && authorizedCommit == nil
    }

    var stepFourSecondsRemaining: Int {
        guard let startedAt = activeAttempt?.stepFourStartedAt else { return 60 }
        let elapsed = max(0, now().timeIntervalSince(startedAt))
        return max(0, Int(ceil(60 - elapsed)))
    }

    var stepFourProgress: Double {
        guard let startedAt = activeAttempt?.stepFourStartedAt else { return 0 }
        return min(1, max(0, now().timeIntervalSince(startedAt) / 60))
    }

    func configure(performer: @escaping (HardModeCommit) -> HardModeCommitResult) {
        self.performer = performer
    }

    func requestActivationWarning() {
        guard !isEnabled, activeAttempt == nil else { return }
        isShowingActivationWarning = true
    }

    func confirmActivation() {
        isShowingActivationWarning = false
        isEnabled = true
        HardModeProtectionState.setEnabled(true, defaults: defaults)
    }

    func dismissActivationWarning() {
        isShowingActivationWarning = false
    }

    @discardableResult
    func requestOff(
        _ mutation: HardModeRequestedMutation,
        affectedAppIDs: Set<String>? = nil,
        source: String
    ) -> Bool {
        let change = HardModeRequestedChange(
            mutation: mutation,
            affectedAppIDs: affectedAppIDs,
            source: source,
            requestedAt: now()
        )
        guard isEnabled else {
            guard let performer else { return false }
            let result = performer(HardModeCommit(id: UUID(), change: change, choice: .direct))
            if case .failure(let message) = result {
                errorMessage = message
            } else if case .stale(let message) = result {
                errorMessage = message
            }
            return true
        }
        guard activeAttempt == nil else { return true }
        activeAttempt = HardModeAttempt(
            id: UUID(),
            change: change,
            drawTarget: drawTargetProvider(),
            step: .trace,
            stepFourStartedAt: nil
        )
        authorizedCommit = nil
        errorMessage = nil
        stepHint = nil
        return true
    }

    func advanceStep() {
        guard let attempt = activeAttempt, authorizedCommit == nil else { return }
        switch attempt.step {
        case .trace:
            activeAttempt?.step = .shade
        case .shade:
            activeAttempt?.step = .draw
        case .draw:
            activeAttempt?.step = .wait
            activeAttempt?.stepFourStartedAt = now()
        case .wait:
            break
        }
        stepHint = nil
    }

    func showStepHint(_ message: String) {
        stepHint = message
    }

    func clearStepHint() {
        stepHint = nil
    }

    func refreshTimer() {
        // Reading the clock-backed computed values is enough for SwiftUI.
    }

    @discardableResult
    func authorizeFinalChoice(_ choice: HardModeCommitChoice) -> HardModeCommit? {
        guard let attempt = activeAttempt,
              attempt.step == .wait,
              stepFourSecondsRemaining == 0,
              authorizedCommit == nil else {
            return nil
        }
        switch attempt.change.mutation {
        case .turnOffHardMode:
            guard choice == .off || isValidBatch(choice) else { return nil }
        case .disableClientProtection:
            guard choice != .direct else { return nil }
            if case .batch = choice, !isValidBatch(choice) { return nil }
        default:
            guard choice != .direct else { return nil }
            if case .batch = choice { return nil }
        }
        let commit = HardModeCommit(id: UUID(), change: attempt.change, choice: choice)
        authorizedCommit = commit
        return commit
    }

    func finishCommit(_ commit: HardModeCommit, result: HardModeCommitResult) {
        guard authorizedCommit?.id == commit.id else { return }
        switch result {
        case .success:
            let turnsOffHardMode: Bool
            if case .batch(let selection) = commit.choice {
                turnsOffHardMode = selection.turnOffHardMode
            } else {
                turnsOffHardMode = commit.change.mutation == .turnOffHardMode
            }
            if turnsOffHardMode {
                isEnabled = false
                HardModeProtectionState.setEnabled(false, defaults: defaults)
            }
            resetAttempt()
        case .failure(let message), .stale(let message):
            authorizedCommit = nil
            errorMessage = message
        }
    }

    func cancelChallenge() {
        resetAttempt()
        errorMessage = nil
    }

    func dismissErrorMessage() {
        errorMessage = nil
    }

    func reconcilePauses() {
        HardModeProtectionState.purgeExpiredPauses(defaults: defaults, now: now())
    }

    func resetForAccountDeletion() {
        resetAttempt()
        isShowingActivationWarning = false
        isEnabled = false
        HardModeProtectionState.reset(defaults: defaults)
    }

    private func resetAttempt() {
        activeAttempt = nil
        authorizedCommit = nil
        stepHint = nil
        errorMessage = nil
    }

    private func isValidBatch(_ choice: HardModeCommitChoice) -> Bool {
        guard case .batch(let selection) = choice, selection.hasChanges else { return false }
        let supportedIDs: Set<String> = ["instagram", "tiktok", "x"]
        guard Set(selection.appChoices.keys).isSubset(of: supportedIDs) else { return false }
        return selection.appChoices.values.allSatisfy {
            if case .pause(let minutes) = $0 { return [5, 10, 15].contains(minutes) }
            return true
        }
    }
}

private extension HardModeRequestedMutation {
    var defaultAffectedAppIDs: Set<String> {
        switch self {
        case .disableClientProtection(let appID),
             .disableBlockingOption(let appID, _),
             .endActiveWindows(let appID):
            [appID]
        case .setWindowEnabled, .deleteWindow, .pauseAllWindows, .turnOffHardMode:
            []
        case .updateWindow(let window, _):
            Set(window.apps)
        case .updateAppRule(_, _, _, let affectedAppIDs),
             .deleteAppRule(_, let affectedAppIDs):
            affectedAppIDs
        }
    }
}
