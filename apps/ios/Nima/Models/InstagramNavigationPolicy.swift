import Foundation

enum InstagramFilteringHealth: String, Codable {
    case checking
    case healthy
    case limited

    var title: String {
        switch self {
        case .checking: return "Checking filter"
        case .healthy: return "Reels removed"
        case .limited: return "Instagram changed"
        }
    }
}

enum InstagramNavigationAction: Equatable {
    case allow
    case block
    case openExternal
}

struct InstagramNavigationPolicy {
    static let homeURL = URL(string: "https://www.instagram.com/")!
    static let inboxURL = URL(string: "https://www.instagram.com/direct/inbox/")!
    static let loginURL = URL(string: "https://www.instagram.com/accounts/login/")!

    private static let knownInstagramSections: Set<String> = [
        "about", "accounts", "api", "challenge", "developer", "direct", "emails",
        "explore", "legal", "oauth", "p", "privacy", "reel", "reels", "stories",
        "terms", "web"
    ]

    static func instagramURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              isInstagramHost(url.host) else { return nil }
        return url
    }

    static func action(
        for url: URL,
        mode: InstagramMode,
        sourceURL: URL?,
        grantedSharedURL: URL? = nil
    ) -> InstagramNavigationAction {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return .openExternal
        }

        guard isTrustedMetaHost(url.host) else {
            return .openExternal
        }

        if isAuthenticationURL(url) {
            return .allow
        }

        // Meta and Facebook are only trusted inside the client for authentication.
        // Other destinations on those hosts should behave like any external link.
        guard isInstagramHost(url.host) else { return .openExternal }

        if isReelsFeedURL(url) {
            return .block
        }

        if isIndividualReelURL(url) {
            return sameResource(url, grantedSharedURL) ? .allow : .block
        }

        guard mode == .dmOnly else {
            return .allow
        }

        if isMessagesURL(url) || isAccountUtilityURL(url) {
            return .allow
        }

        if sameResource(url, grantedSharedURL), isConversationLinkedDestination(url) {
            return .allow
        }

        // A navigation directly out of a conversation may receive a one-shot grant from
        // the web-session coordinator before this policy is evaluated. Without that grant,
        // DM-only fails closed.
        if isMessagesURL(sourceURL), isConversationLinkedDestination(url) {
            return .block
        }

        return .block
    }

    static func isTrustedMetaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "instagram.com"
            || host.hasSuffix(".instagram.com")
            || host == "facebook.com"
            || host.hasSuffix(".facebook.com")
            || host == "meta.com"
            || host.hasSuffix(".meta.com")
    }

    static func isInstagramHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    static func isPaidAdsTrackingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "fbsbx.com" || host.hasSuffix(".fbsbx.com") else { return false }
        return normalizedPath(url).hasPrefix("/paid_ads_pixel/iframe")
    }

    static func isMessagesURL(_ url: URL?) -> Bool {
        normalizedPath(url).hasPrefix("/direct")
    }

    static func isReelsFeedURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/reels" || path.hasPrefix("/reels/")
    }

    static func isIndividualReelURL(_ url: URL?) -> Bool {
        normalizedPath(url).hasPrefix("/reel/")
    }

    static func isProfileURL(_ url: URL?) -> Bool {
        guard isInstagramHost(url?.host) else { return false }
        let components = normalizedPath(url)
            .split(separator: "/")
            .map { String($0).lowercased() }
        guard let first = components.first,
              !first.isEmpty,
              !knownInstagramSections.contains(first) else { return false }
        return true
    }

    static func isConversationLinkedDestination(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        if path.hasPrefix("/p/") || path.hasPrefix("/reel/") || path.hasPrefix("/stories/") {
            return true
        }

        let first = path.split(separator: "/").first.map(String.init) ?? ""
        return !first.isEmpty && !knownInstagramSections.contains(first.lowercased())
    }

    static func isAuthenticationURL(_ url: URL) -> Bool {
        guard isTrustedMetaHost(url.host) else { return false }
        let path = normalizedPath(url)
        return path.hasPrefix("/accounts/login")
            || path.hasPrefix("/accounts/signup")
            || path.hasPrefix("/challenge")
            || path.hasPrefix("/two_factor")
            || path == "/instagram/login_sync"
            || path.hasPrefix("/oauth")
            || path.hasPrefix("/dialog/oauth")
            || path.hasPrefix("/login")
            || path.contains("checkpoint")
            || path.contains("accountscenter")
            || url.host?.lowercased().contains("accountscenter") == true
    }

    private static func isAccountUtilityURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/accounts/") || path.hasPrefix("/emails/")
    }

    private static func normalizedPath(_ url: URL?) -> String {
        guard let path = url?.path.lowercased() else { return "" }
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }

    static func sameResource(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        let sameHost = lhs.host?.lowercased() == rhs.host?.lowercased()
            || (isInstagramHost(lhs.host) && isInstagramHost(rhs.host))
        return sameHost
            && normalizedPath(lhs) == normalizedPath(rhs)
    }
}
