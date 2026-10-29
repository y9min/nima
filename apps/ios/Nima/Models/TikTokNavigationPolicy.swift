import Foundation

enum TikTokFilteringHealth: String, Codable {
    case checking
    case healthy
    case limited
}

enum TikTokMode: String, Codable, CaseIterable, Identifiable {
    case clean
    case dmOnly = "dm_only"

    var id: String { rawValue }
    var title: String { self == .clean ? "Clean" : "DM only" }
}

enum TikTokNavigationAction: Equatable {
    case allow
    case block
    case openExternal
}

struct TikTokNavigationPolicy {
    static let followingURL = URL(string: "https://www.tiktok.com/following")!
    static let friendsURL = URL(string: "https://www.tiktok.com/friends")!
    static let searchURL = URL(string: "https://www.tiktok.com/search")!
    static let messagesURL = URL(string: "https://www.tiktok.com/messages?lang=en")!
    static let profileURL = URL(string: "https://www.tiktok.com/profile")!
    static let loginURL = URL(string: "https://www.tiktok.com/login")!

    static func tiktokURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              isTikTokHost(url.host) else { return nil }
        return url
    }

    static func action(
        for url: URL,
        sourceURL: URL?,
        grantedVideoURL: URL? = nil,
        mode: TikTokMode = .clean,
        grantedProfileURL: URL? = nil
    ) -> TikTokNavigationAction {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return .openExternal
        }
        guard isTrustedTikTokHost(url.host) else { return .openExternal }
        guard isTikTokHost(url.host) else {
            return isAuthenticationURL(url) ? .allow : .openExternal
        }

        if isAuthenticationURL(url) {
            return .allow
        }
        if mode == .dmOnly {
            if isDirectMessagesURL(url) { return .allow }
            if isIndividualVideoURL(url) {
                return sameResource(url, grantedVideoURL) ? .allow : .block
            }
            if isProfileURL(url) {
                return sameResource(url, grantedProfileURL) ? .allow : .block
            }
            return .block
        }
        if isAllowedUtilityURL(url) { return .allow }
        if isForYouURL(url) || isBlockedDiscoveryURL(url) {
            return .block
        }
        if isIndividualVideoURL(url) {
            return sameResource(url, grantedVideoURL) ? .allow : .block
        }
        if isFollowingURL(url) || isFriendsURL(url) || isSearchURL(url)
            || isMessagesURL(url) || isProfileURL(url) {
            return .allow
        }

        return .block
    }

    static func mayGrantVideo(from sourceURL: URL?) -> Bool {
        // Following and Friends are the two intentionally scrollable feeds.
        // Single-video grants only come from non-feed surfaces.
        isSearchURL(sourceURL) || isMessagesURL(sourceURL) || isProfileURL(sourceURL)
    }

    static func isTikTokHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    static func isTrustedTikTokHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return isTikTokHost(host)
            || host == "tiktokv.com" || host.hasSuffix(".tiktokv.com")
            || host == "byteoversea.com" || host.hasSuffix(".byteoversea.com")
    }

    static func isFollowingURL(_ url: URL?) -> Bool {
        normalizedPath(url) == "/following" || normalizedPath(url).hasPrefix("/following/")
    }

    static func isFriendsURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/friends" || path.hasPrefix("/friends/")
    }

    static func isSearchURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/search" || path.hasPrefix("/search/")
    }

    static func isMessagesURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/messages" || path.hasPrefix("/messages/")
            || path == "/inbox" || path.hasPrefix("/inbox/")
    }

    static func isDirectMessagesURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path == "/messages" || path.hasPrefix("/messages/")
    }

    static func isIndividualVideoURL(_ url: URL?) -> Bool {
        let parts = normalizedPath(url).split(separator: "/")
        return parts.count >= 3 && parts[0].hasPrefix("@") && parts[1] == "video"
    }

    static func isProfileURL(_ url: URL?) -> Bool {
        guard isTikTokHost(url?.host) else { return false }
        if normalizedPath(url) == "/profile" || normalizedPath(url).hasPrefix("/profile/") {
            return true
        }
        let parts = normalizedPath(url).split(separator: "/")
        return parts.first?.hasPrefix("@") == true && !isIndividualVideoURL(url)
    }

    static func isForYouURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.isEmpty || path == "/" || path == "/foryou" || path.hasPrefix("/foryou/")
    }

    static func isAuthenticationURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/login") || path.hasPrefix("/signup")
            || path.hasPrefix("/auth") || path.hasPrefix("/passport")
            || path.hasPrefix("/logout")
            || path.contains("challenge") || path.contains("captcha")
    }

    static func sameResource(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        if let leftVideoID = videoID(lhs), let rightVideoID = videoID(rhs) {
            return leftVideoID == rightVideoID
        }
        return isTikTokHost(lhs.host) && isTikTokHost(rhs.host)
            && normalizedPath(lhs) == normalizedPath(rhs)
    }

    private static func videoID(_ url: URL) -> String? {
        guard isTikTokHost(url.host) else { return nil }
        let parts = normalizedPath(url).split(separator: "/")
        guard parts.count == 3, parts[0].hasPrefix("@"), parts[1] == "video",
              !parts[2].isEmpty else { return nil }
        return String(parts[2])
    }

    private static func isAllowedUtilityURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/setting") || path.hasPrefix("/legal")
            || path.hasPrefix("/feedback") || path.hasPrefix("/download")
    }

    private static func isBlockedDiscoveryURL(_ url: URL?) -> Bool {
        let path = normalizedPath(url)
        return path.hasPrefix("/live") || path.hasPrefix("/shop")
            || path.hasPrefix("/discover") || path.hasPrefix("/explore")
            || path.hasPrefix("/story") || path.hasPrefix("/music/")
            || path.hasPrefix("/tag/") || path.hasPrefix("/topic/")
    }

    private static func normalizedPath(_ url: URL?) -> String {
        guard var path = url?.path.lowercased() else { return "" }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
