import FamilyControls
import Foundation
import ManagedSettings

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
            guard hasPremium else { return .paywall }
            return .mainApp
        case .idle, .loading, .failed:
            guard hasPremium else { return .subscriptionLoading }
            return .mainApp
        }
    }
}

struct InstagramGuidedPracticePolicy {
    static func isReadyForControlsExplanation(
        sessionStatus: InstagramSessionStatus,
        mode: InstagramMode,
        filteringHealth: InstagramFilteringHealth
    ) -> Bool {
        sessionStatus == .authenticated
            && mode == .clean
            && filteringHealth == .healthy
    }
}

enum NimaLaunchConfiguration {
    #if DEBUG
    static let skipExternalGuidedPracticeArgument = "-NimaSkipExternalGuidedPractice"
    #endif

    static func skipsExternalGuidedPractice(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains(skipExternalGuidedPracticeArgument)
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

enum GuidedPracticeStep: String, Codable, CaseIterable {
    case introSlides = "intro_slides"
    case readyCoachMark = "ready_coach_mark"
    case appSelection = "app_selection"
    case familyPickerVideo = "family_picker_video"
    case appConnections = "app_connections"
    case dragTikTokCoachMark = "drag_tiktok_coach_mark"
    case openAppPrompt = "open_app_prompt"
    case waitingForReturn = "waiting_for_return"
    case success
    case windowsHomeCoachMark = "windows_home_coach_mark"
    case windowsEditorName = "windows_editor_name"
    case windowsEditorTime = "windows_editor_time"
    case windowsEditorApps = "windows_editor_apps"
    case windowsEditorRepeatDays = "windows_editor_repeat_days"
    case windowsEditorIcon = "windows_editor_icon"
    case windowsEditorSaveOrCancel = "windows_editor_save_or_cancel"
    case windowsReady = "windows_ready"
    case reviewPrompt = "review_prompt"
    case troubleshooting
    case completed

    var phase: GuidedPracticePhase {
        switch self {
        case .introSlides: return .introSlides
        case .readyCoachMark: return .readyCoachMark
        case .appSelection: return .appSelection
        case .familyPickerVideo: return .familyPickerVideo
        case .appConnections: return .appConnections
        case .dragTikTokCoachMark: return .dragTikTokCoachMark
        case .openAppPrompt: return .openAppPrompt
        case .waitingForReturn: return .waitingForReturn
        case .success: return .success
        case .windowsHomeCoachMark: return .windowsHomeCoachMark
        case .windowsEditorName: return .windowsEditor(.name)
        case .windowsEditorTime: return .windowsEditor(.time)
        case .windowsEditorApps: return .windowsEditor(.apps)
        case .windowsEditorRepeatDays: return .windowsEditor(.repeatDays)
        case .windowsEditorIcon: return .windowsEditor(.icon)
        case .windowsEditorSaveOrCancel: return .windowsEditor(.saveOrCancel)
        case .windowsReady: return .windowsReady
        case .reviewPrompt: return .reviewPrompt
        case .troubleshooting: return .troubleshooting
        case .completed: return .completed
        }
    }

    init?(phase: GuidedPracticePhase) {
        switch phase {
        case .hidden:
            return nil
        case .introSlides:
            self = .introSlides
        case .readyCoachMark:
            self = .readyCoachMark
        case .appSelection:
            self = .appSelection
        case .familyPickerVideo:
            self = .familyPickerVideo
        case .appConnections:
            self = .appConnections
        case .dragTikTokCoachMark:
            self = .dragTikTokCoachMark
        case .openAppPrompt:
            self = .openAppPrompt
        case .waitingForReturn:
            self = .waitingForReturn
        case .success:
            self = .success
        case .windowsHomeCoachMark:
            self = .windowsHomeCoachMark
        case .windowsEditor(.name):
            self = .windowsEditorName
        case .windowsEditor(.time):
            self = .windowsEditorTime
        case .windowsEditor(.apps):
            self = .windowsEditorApps
        case .windowsEditor(.repeatDays):
            self = .windowsEditorRepeatDays
        case .windowsEditor(.icon):
            self = .windowsEditorIcon
        case .windowsEditor(.saveOrCancel):
            self = .windowsEditorSaveOrCancel
        case .windowsReady:
            self = .windowsReady
        case .reviewPrompt:
            self = .reviewPrompt
        case .troubleshooting:
            self = .troubleshooting
        case .completed:
            self = .completed
        }
    }

    var isWindowsEditorStep: Bool {
        switch self {
        case .windowsEditorName, .windowsEditorTime, .windowsEditorApps,
             .windowsEditorRepeatDays, .windowsEditorIcon, .windowsEditorSaveOrCancel:
            return true
        default:
            return false
        }
    }
}

enum GuidedPracticePhase: Equatable {
    case hidden
    case introSlides
    case readyCoachMark
    case appSelection
    case familyPickerVideo
    case appConnections
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

    var showsOpenAppPromptOverlay: Bool {
        self == .openAppPrompt
    }
}

struct GuidedPracticeInstagramOpenGate {
    private(set) var isRouteActive = false

    mutating func requestOpen(
        from phase: GuidedPracticePhase,
        canOpenControlledClient: () -> Bool
    ) -> Bool {
        guard phase == .openAppPrompt,
              !isRouteActive,
              canOpenControlledClient() else {
            return false
        }

        isRouteActive = true
        return true
    }

    mutating func finishRoute() {
        isRouteActive = false
    }
}

struct GuidedWindowsDraft: Codable, Equatable {
    var emoji: String
    var name: String
    var startTime: String
    var endTime: String
    var selectedApps: Set<String>
    var selectedDays: Set<TimeWindowWeekday>

    init(
        emoji: String = "⏰",
        name: String = "",
        startTime: String = "09:00",
        endTime: String = "17:00",
        selectedApps: Set<String> = [],
        selectedDays: Set<TimeWindowWeekday> = []
    ) {
        self.emoji = emoji
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.selectedApps = selectedApps
        self.selectedDays = selectedDays
    }

    var repeatDays: [TimeWindowWeekday] {
        TimeWindowWeekday.allCases.filter(selectedDays.contains)
    }
}

struct GuidedPracticeAppConnection: Codable, Equatable {
    let appID: String
    let token: ApplicationToken
}

struct ScreenTimeAppConnections: Codable {
    private(set) var selectionsByAppID: [String: FamilyActivitySelection] = [:]

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) -> ScreenTimeAppConnections {
        guard let data = defaults?.data(forKey: NimaConstants.screenTimeAppConnectionsKey),
              let connections = try? JSONDecoder().decode(ScreenTimeAppConnections.self, from: data) else {
            return ScreenTimeAppConnections()
        }
        return connections
    }

    func selection(for appID: String) -> FamilyActivitySelection? {
        selectionsByAppID[appID]
    }

    mutating func connect(_ appID: String, to token: ApplicationToken) {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [token]
        selectionsByAppID[appID] = selection
    }

    func save(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: NimaConstants.screenTimeAppConnectionsKey)
    }

    static func reset(
        defaults: UserDefaults? = UserDefaults(suiteName: NimaConstants.appGroupID)
    ) {
        defaults?.removeObject(forKey: NimaConstants.screenTimeAppConnectionsKey)
    }
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

    var analyticsName: String {
        switch self {
        case .name: return "name"
        case .time: return "time"
        case .apps: return "apps"
        case .repeatDays: return "repeat_days"
        case .icon: return "icon"
        case .saveOrCancel: return "save_or_cancel"
        }
    }
}

enum GuidedPracticeLaunchApp: String, CaseIterable, Identifiable {
    case instagram
    case tiktok
    case x

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram:
            return "Instagram"
        case .tiktok:
            return "TikTok"
        case .x:
            return "X/Twitter"
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
        case .x:
            return [
                URL(string: "twitter://"),
                URL(string: "https://x.com/")
            ].compactMap { $0 }
        }
    }
}
