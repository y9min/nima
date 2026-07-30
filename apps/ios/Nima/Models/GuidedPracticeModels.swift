import Foundation

enum AppRootDestination: Equatable {
    case onboarding
    case guidedExperience
    case subscriptionLoading
    case paywall
    case mainApp
}

struct AppAccessPolicy {
    static func destination(
        onboardingCompleted: Bool,
        guidedExperienceCompleted: Bool,
        hasPremium: Bool,
        verificationState: SubscriptionVerificationState
    ) -> AppRootDestination {
        guard onboardingCompleted else { return .onboarding }
        guard guidedExperienceCompleted else { return .guidedExperience }

        switch verificationState {
        case .verified:
            return hasPremium ? .mainApp : .paywall
        case .idle, .loading, .failed:
            return .subscriptionLoading
        }
    }
}

struct GuidedPracticeAccessPolicy {
    static func showsSkipPractice(for identity: SubscriptionIdentity) -> Bool {
        guard case .demo(let email) = identity else { return false }
        return AuthStore.isAppStoreReviewAccount(email: email)
    }
}

enum NimaLaunchConfiguration {
    #if DEBUG
    static let skipExternalGuidedPracticeArgument = "-NimaSkipExternalGuidedPractice"
    static let simulateExpiredReviewSubscriptionArgument = "-NimaSimulateExpiredReviewSubscription"
    #endif

    static func skipsExternalGuidedPractice(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains(skipExternalGuidedPracticeArgument)
        #else
        false
        #endif
    }

    static func simulatesExpiredReviewSubscription(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains(simulateExpiredReviewSubscriptionArgument)
        #else
        false
        #endif
    }
}

enum GuidedOnboardingPresentationMode: Equatable {
    case firstRunPractice
    case manualReplay

    var completionTitle: String {
        switch self {
        case .firstRunPractice:
            return "Try it out"
        case .manualReplay:
            return "Done"
        }
    }
}

enum GuidedPracticePhase: Equatable {
    case hidden
    case introSlides
    case readyCoachMark
    case dragTikTokCoachMark
    case openAppPrompt
    case waitingForReturn
    case success
    case windowsHomeCoachMark
    case windowsEditor(GuidedWindowsEditorStep)
    case windowsReady
    case reviewPrompt
    case troubleshooting
    case completed
}

enum GuidedPracticeCardStep: Equatable {
    case ready
    case dragTikTok
}

enum GuidedWindowsEditorStep: Equatable {
    case name
    case time
    case apps
    case repeatDays
    case icon
    case saveOrCancel
}

enum GuidedPracticeLaunchApp: String, CaseIterable, Identifiable {
    case instagram
    case tiktok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram:
            return "Instagram"
        case .tiktok:
            return "TikTok"
        }
    }

    var platform: String {
        rawValue
    }

    var launchURLs: [URL] {
        switch self {
        case .instagram:
            return [
                URL(string: "instagram://app"),
                URL(string: "https://www.instagram.com/")
            ].compactMap { $0 }
        case .tiktok:
            return [
                URL(string: "snssdk1233://"),
                URL(string: "musically://"),
                URL(string: "https://www.tiktok.com/")
            ].compactMap { $0 }
        }
    }
}
