import Foundation

enum XFilteringHealth: String, Codable {
    case checking
    case healthy
    case slow
    case limited
}

struct XHomeHealthObservation: Equatable {
    let path: String
    let documentReady: Bool
    let homeSurfacePresent: Bool
    let timelineTabsPresent: Bool
    let followingPresent: Bool
    let followingSelected: Bool
    let forYouPresent: Bool
    let isLoading: Bool
    let loadError: Bool

    var isUnavailableCandidate: Bool {
        guard path == "/" || path == "/home" else { return false }
        guard documentReady, homeSurfacePresent, !followingSelected else { return false }
        guard !isLoading, !loadError else { return false }
        return followingPresent
            || timelineTabsPresent
            || forYouPresent
    }
}

struct XHomeHealthVerifier {
    static let unavailableDuration: TimeInterval = 20
    static let unavailableObservationCount = 4
    static let healthyObservationCount = 2

    private(set) var health: XFilteringHealth = .checking
    private var failureStartedAt: Date?
    private var failureObservationCount = 0
    private var healthyObservationCount = 0

    mutating func beginNavigation() {
        failureStartedAt = nil
        failureObservationCount = 0
        healthyObservationCount = 0
        if health != .limited {
            health = .checking
        }
    }

    @discardableResult
    mutating func observe(
        _ observation: XHomeHealthObservation,
        at now: Date = Date()
    ) -> XFilteringHealth {
        guard observation.path == "/" || observation.path == "/home" else {
            resetCandidateTracking()
            healthyObservationCount = 0
            if health != .limited {
                health = .checking
            }
            return health
        }

        if observation.followingSelected && observation.documentReady {
            resetCandidateTracking()
            healthyObservationCount += 1
            if healthyObservationCount >= Self.healthyObservationCount {
                health = .healthy
            }
            return health
        }

        healthyObservationCount = 0
        guard observation.isUnavailableCandidate else {
            resetCandidateTracking()
            if health != .healthy && health != .limited {
                health = .checking
            }
            return health
        }

        if failureStartedAt == nil {
            failureStartedAt = now
        }
        failureObservationCount += 1

        let duration = now.timeIntervalSince(failureStartedAt ?? now)
        if failureObservationCount >= Self.unavailableObservationCount,
           duration >= Self.unavailableDuration {
            health = .limited
        } else if health != .healthy && health != .limited {
            health = .checking
        }
        return health
    }

    @discardableResult
    mutating func markSlow() -> XFilteringHealth {
        if health == .checking {
            health = .slow
        }
        return health
    }

    private mutating func resetCandidateTracking() {
        failureStartedAt = nil
        failureObservationCount = 0
    }
}

enum XMode: String, Codable, CaseIterable, Identifiable {
    case clean
    case dmOnly = "dm_only"

    var id: String { rawValue }
    var title: String { self == .clean ? "Clean" : "DM only" }
}

enum XNavigationAction: Equatable {
    case allow
    case block
    case openExternal
}

struct XNavigationPolicy {
    static let homeURL = URL(string: "https://x.com/home")!
    static let viewerProfileURL = URL(string: "https://x.com/i/profile")!
    static let messagesURL = URL(string: "https://x.com/messages")!
    static let chatURL = URL(string: "https://x.com/i/chat")!
    static let notificationsURL = URL(string: "https://x.com/notifications")!
    static let searchURL = URL(string: "https://x.com/search")!
    static let loginURL = URL(string: "https://x.com/i/flow/login")!

    private static let reservedRoots: Set<String> = [
        "account", "compose", "explore", "home", "i", "jobs", "login", "logout",
        "messages", "notifications", "premium", "privacy", "search", "settings", "tos"
    ]

    static func xURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              isXHost(url.host) else { return nil }
        return url
    }

    static func action(
        for url: URL,
        sourceURL: URL?,
        mode: XMode,
        grantedPostURL: URL? = nil,
        grantedProfileURL: URL? = nil
    ) -> XNavigationAction {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return .openExternal
        }
        guard isTrustedXHost(url.host) || isTrustedAuthenticationHost(url.host) else {
            return .openExternal
        }
        if isAuthenticationURL(url) {
            return .allow
        }
        guard isXHost(url.host) else { return .openExternal }

        if mode == .dmOnly {
            if isMessagesURL(url) || isEssentialAccountURL(url) {
                return .allow
            }
            if isPostURL(url) {
                return samePost(url, grantedPostURL) ? .allow : .block
            }
            if isProfileURL(url) {
                return sameProfile(url, grantedProfileURL) ? .allow : .block
            }
            return .block
        }

        if isBlockedDiscoveryURL(url) {
            return .block
        }
        if isAllowedCleanURL(url) {
            return .allow
        }
        return .block
    }

    static func mayGrantConversationLink(from sourceURL: URL?) -> Bool {
        isMessagesURL(sourceURL)
    }

    static func isXHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "x.com" || host.hasSuffix(".x.com")
            || host == "twitter.com" || host.hasSuffix(".twitter.com")
    }

    static func isTrustedXHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return isXHost(host)
            || host == "twimg.com" || host.hasSuffix(".twimg.com")
            || host == "t.co"
    }

    static func isTrustedAuthenticationHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "appleid.apple.com"
            || host == "accounts.google.com"
            || host == "oauth.twitter.com"
    }

    static func isMessagesURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/messages" || path.hasPrefix("/messages/")
            || path == "/i/chat" || path.hasPrefix("/i/chat/")
    }

    static func isFollowingFeedURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.isEmpty || path == "/" || path == "/home"
    }

    static func isConversationURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/messages/") || path.hasPrefix("/i/chat/")
    }

    static func isPostURL(_ url: URL?) -> Bool {
        let parts = normalizedPath(url).split(separator: "/")
        return parts.count >= 3 && parts[1] == "status"
    }

    static func isProfileURL(_ url: URL?) -> Bool {
        guard isXHost(url?.host) else { return false }
        let parts = normalizedPath(url).split(separator: "/")
        if parts.count >= 3, parts[0] == "i", parts[1] == "user" {
            return true
        }
        guard let first = parts.first.map(String.init),
              !first.isEmpty,
              !reservedRoots.contains(first) else {
            return false
        }
        if parts.count == 1 { return true }
        let profileTabs: Set<Substring> = [
            "followers", "following", "highlights", "likes", "media", "photo", "with_replies"
        ]
        return parts.count == 2 && profileTabs.contains(parts[1])
    }

    static func isAuthenticationURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if isTrustedAuthenticationHost(host) { return true }
        guard isXHost(host) else { return false }
        let path = normalizedPath(url)
        return path.hasPrefix("/i/flow/login")
            || path.hasPrefix("/i/flow/signup")
            || path.hasPrefix("/i/flow/consent")
            || path.hasPrefix("/i/jf/onboarding/web")
            || path.hasPrefix("/i/jf/web/")
            || path.hasPrefix("/i/oauth2")
            || path.hasPrefix("/oauth/")
            || path.hasPrefix("/account/")
            || path.hasPrefix("/sessions")
            || path.hasPrefix("/login")
            || path.hasPrefix("/logout")
            || path.contains("challenge")
            || path.contains("captcha")
    }

    static func samePost(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let leftID = postID(lhs), let rightID = postID(rhs) else {
            return sameResource(lhs, rhs)
        }
        return leftID == rightID
    }

    static func sameProfile(_ lhs: URL?, _ rhs: URL?) -> Bool {
        sameResource(lhs, rhs)
    }

    private static func isAllowedCleanURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        if path.isEmpty || path == "/home" {
            return !isForYouQuery(url)
        }
        return isMessagesURL(url)
            || path.hasPrefix("/notifications")
            || path.hasPrefix("/search")
            || path.hasPrefix("/compose")
            || isPostURL(url)
            || path == "/i/profile"
            || isProfileURL(url)
            || isEssentialAccountURL(url)
    }

    private static func isEssentialAccountURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/settings")
            || path.hasPrefix("/account")
            || path.hasPrefix("/i/account")
            || path.hasPrefix("/privacy")
            || path.hasPrefix("/tos")
            || path.hasPrefix("/i/flow/verify")
            || path.hasPrefix("/i/flow/password_reset")
            || path.hasPrefix("/i/flow/consent")
    }

    private static func isBlockedDiscoveryURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return isForYouQuery(url)
            || path.hasPrefix("/explore")
            || path.hasPrefix("/i/trending")
            || path.hasPrefix("/i/explore")
            || path.hasPrefix("/trending")
            || path == "/following"
            || path.hasPrefix("/following/")
            || path.hasPrefix("/topics")
            || path.hasPrefix("/live")
    }

    private static func isForYouQuery(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains {
            let name = $0.name.lowercased()
            let value = ($0.value ?? "").lowercased()
            return (name == "f" || name == "feed") && value == "for_you"
        } == true
    }

    private static func postID(_ url: URL?) -> String? {
        guard let url, isXHost(url.host) else { return nil }
        let parts = normalizedPath(url).split(separator: "/")
        guard parts.count >= 3, parts[1] == "status" else { return nil }
        return String(parts[2])
    }

    private static func sameResource(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              isXHost(lhs.host), isXHost(rhs.host) else {
            return false
        }
        return normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func normalizedPath(_ url: URL?) -> String {
        guard var path = url?.path.lowercased(), !path.isEmpty else { return "" }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
