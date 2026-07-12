import Foundation
import Combine

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

final class OnboardingStore: ObservableObject {
    @Published var isCompleted: Bool = false
    @Published var hasSeenGuidedOnboarding: Bool = false
    @Published var hasCompletedGuidedPractice: Bool = false
    @Published var hasGuidedPracticeReturnPending: Bool = false
    @Published var hasCompletedGuidedWindowsOnboarding: Bool = false
    @Published var phoneHours: Int?
    @Published var age: Int?
    @Published var selectedHabits: Set<String> = []
    @Published var selectedApps: Set<String> = []
    @Published var vpnPermissionRequested: Bool = false

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)) {
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
        defaults?.set(true, forKey: NimaConstants.guidedOnboardingSeenKey)
    }

    func markGuidedPracticeCompleted() {
        hasCompletedGuidedPractice = true
        defaults?.set(true, forKey: NimaConstants.guidedPracticeCompletedKey)
    }

    func setGuidedPracticeReturnPending(_ isPending: Bool) {
        hasGuidedPracticeReturnPending = isPending
        defaults?.set(isPending, forKey: NimaConstants.guidedPracticeReturnPendingKey)
    }

    func markGuidedWindowsOnboardingPending() {
        hasCompletedGuidedWindowsOnboarding = false
        defaults?.set(false, forKey: NimaConstants.guidedWindowsOnboardingCompletedKey)
    }

    func markGuidedWindowsOnboardingCompleted() {
        hasCompletedGuidedWindowsOnboarding = true
        defaults?.set(true, forKey: NimaConstants.guidedWindowsOnboardingCompletedKey)
    }

    func resetForOnboardingRestart() {
        isCompleted = false
        hasSeenGuidedOnboarding = false
        hasCompletedGuidedPractice = false
        hasGuidedPracticeReturnPending = false
        hasCompletedGuidedWindowsOnboarding = false
        phoneHours = nil
        age = nil
        selectedHabits = []
        selectedApps = []
        vpnPermissionRequested = false

        defaults?.set(false, forKey: NimaConstants.onboardingCompletedKey)
        defaults?.set(false, forKey: NimaConstants.guidedOnboardingSeenKey)
        defaults?.set(false, forKey: NimaConstants.guidedPracticeCompletedKey)
        defaults?.set(false, forKey: NimaConstants.guidedPracticeReturnPendingKey)
        defaults?.set(false, forKey: NimaConstants.guidedWindowsOnboardingCompletedKey)
        defaults?.removeObject(forKey: NimaConstants.onboardingStateKey)
    }

    private func load() {
        isCompleted = defaults?.bool(forKey: NimaConstants.onboardingCompletedKey) ?? false
        hasSeenGuidedOnboarding = defaults?.bool(forKey: NimaConstants.guidedOnboardingSeenKey) ?? false
        hasCompletedGuidedPractice = defaults?.bool(forKey: NimaConstants.guidedPracticeCompletedKey) ?? false
        hasGuidedPracticeReturnPending = defaults?.bool(forKey: NimaConstants.guidedPracticeReturnPendingKey) ?? false
        if defaults?.object(forKey: NimaConstants.guidedWindowsOnboardingCompletedKey) == nil,
           hasCompletedGuidedPractice {
            hasCompletedGuidedWindowsOnboarding = true
            defaults?.set(true, forKey: NimaConstants.guidedWindowsOnboardingCompletedKey)
        } else {
            hasCompletedGuidedWindowsOnboarding = defaults?.bool(forKey: NimaConstants.guidedWindowsOnboardingCompletedKey) ?? false
        }
        guard let data = defaults?.data(forKey: NimaConstants.onboardingStateKey),
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
        defaults?.set(isCompleted, forKey: NimaConstants.onboardingCompletedKey)
        let state = OnboardingStateV1(
            phoneHours: phoneHours,
            age: age,
            selectedHabits: selectedHabits,
            selectedApps: selectedApps,
            vpnPermissionRequested: vpnPermissionRequested
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: NimaConstants.onboardingStateKey)
    }
}

final class GuidedPracticeReviewPromptStore {
    private let defaults: UserDefaults?
    private let key: String

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID),
        key: String = NimaConstants.guidedPracticeReviewPromptedUserIDsKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func hasAttemptedPrompt(for userIdentifier: String) -> Bool {
        guard let identifier = Self.normalizedIdentifier(userIdentifier) else { return false }
        return promptedUserIdentifiers.contains(identifier)
    }

    func markPromptAttempted(for userIdentifier: String) {
        guard let identifier = Self.normalizedIdentifier(userIdentifier) else { return }
        var identifiers = promptedUserIdentifiers
        identifiers.insert(identifier)
        defaults?.set(Array(identifiers).sorted(), forKey: key)
    }

    static func normalizedIdentifier(_ userIdentifier: String) -> String? {
        let normalized = userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private var promptedUserIdentifiers: Set<String> {
        Set(defaults?.stringArray(forKey: key) ?? [])
    }
}
