import Foundation
import Observation

struct OnboardingStateV1: Codable, Equatable {
    var phoneHours: Int?
    var age: Int?
    var selectedHabits: Set<String>
    var selectedApps: Set<String>
    var vpnPermissionRequested: Bool

    init(
        phoneHours: Int? = nil,
        age: Int? = nil,
        selectedHabits: Set<String> = [],
        selectedApps: Set<String> = [],
        vpnPermissionRequested: Bool = false
    ) {
        self.phoneHours = phoneHours
        self.age = age
        self.selectedHabits = selectedHabits
        self.selectedApps = selectedApps
        self.vpnPermissionRequested = vpnPermissionRequested
    }
}

@Observable
final class OnboardingStore {
    var isCompleted: Bool = false
    var hasSeenGuidedOnboarding: Bool = false
    var hasCompletedGuidedPractice: Bool = false
    var hasGuidedPracticeReturnPending: Bool = false
    var phoneHours: Int?
    var age: Int?
    var selectedHabits: Set<String> = []
    var selectedApps: Set<String> = []
    var vpnPermissionRequested: Bool = false

    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: BubbleConstants.appGroupID)) {
        self.defaults = defaults
        load()
    }

    func setPhoneHours(_ hours: Int?) {
        phoneHours = hours.map { min(16, max(0, $0)) }
        persist()
    }

    func setAge(_ value: Int?) {
        age = value.map { min(80, max(13, $0)) }
        persist()
    }

    func setSelectedHabits(_ values: Set<String>) {
        selectedHabits = values
        persist()
    }

    func setSelectedApps(_ values: Set<String>) {
        selectedApps = values
        persist()
    }

    func markVPNPermissionRequested() {
        vpnPermissionRequested = true
        persist()
    }

    func markCompleted() {
        isCompleted = true
        persist()
    }

    func markGuidedOnboardingSeen() {
        hasSeenGuidedOnboarding = true
        defaults?.set(true, forKey: BubbleConstants.guidedOnboardingSeenKey)
    }

    func markGuidedPracticeCompleted() {
        hasCompletedGuidedPractice = true
        defaults?.set(true, forKey: BubbleConstants.guidedPracticeCompletedKey)
    }

    func setGuidedPracticeReturnPending(_ isPending: Bool) {
        hasGuidedPracticeReturnPending = isPending
        defaults?.set(isPending, forKey: BubbleConstants.guidedPracticeReturnPendingKey)
    }

    func resetForOnboardingRestart() {
        isCompleted = false
        hasSeenGuidedOnboarding = false
        hasCompletedGuidedPractice = false
        hasGuidedPracticeReturnPending = false
        phoneHours = nil
        age = nil
        selectedHabits = []
        selectedApps = []
        vpnPermissionRequested = false

        defaults?.set(false, forKey: BubbleConstants.onboardingCompletedKey)
        defaults?.set(false, forKey: BubbleConstants.guidedOnboardingSeenKey)
        defaults?.set(false, forKey: BubbleConstants.guidedPracticeCompletedKey)
        defaults?.set(false, forKey: BubbleConstants.guidedPracticeReturnPendingKey)
        defaults?.removeObject(forKey: BubbleConstants.onboardingStateKey)
    }

    private func load() {
        isCompleted = defaults?.bool(forKey: BubbleConstants.onboardingCompletedKey) ?? false
        hasSeenGuidedOnboarding = defaults?.bool(forKey: BubbleConstants.guidedOnboardingSeenKey) ?? false
        hasCompletedGuidedPractice = defaults?.bool(forKey: BubbleConstants.guidedPracticeCompletedKey) ?? false
        hasGuidedPracticeReturnPending = defaults?.bool(forKey: BubbleConstants.guidedPracticeReturnPendingKey) ?? false
        guard let data = defaults?.data(forKey: BubbleConstants.onboardingStateKey),
              let state = try? JSONDecoder().decode(OnboardingStateV1.self, from: data) else {
            return
        }

        phoneHours = state.phoneHours.map { min(16, max(0, $0)) }
        age = state.age.map { min(80, max(13, $0)) }
        selectedHabits = state.selectedHabits
        selectedApps = state.selectedApps
        vpnPermissionRequested = state.vpnPermissionRequested
    }

    private func persist() {
        defaults?.set(isCompleted, forKey: BubbleConstants.onboardingCompletedKey)
        let state = OnboardingStateV1(
            phoneHours: phoneHours,
            age: age,
            selectedHabits: selectedHabits,
            selectedApps: selectedApps,
            vpnPermissionRequested: vpnPermissionRequested
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: BubbleConstants.onboardingStateKey)
    }
}
