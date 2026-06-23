import Foundation

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
