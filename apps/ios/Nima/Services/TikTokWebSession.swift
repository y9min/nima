import Foundation
import Observation
import SwiftUI
import UIKit
import WebKit

enum TikTokSessionStatus: String, Equatable {
    case unknown
    case signingIn = "signing_in"
    case authenticated
}

enum TikTokInboxTab {
    case notifications
    case messages
}

@MainActor
@Observable
final class TikTokWebSession: NSObject {
    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private(set) var webView: WKWebView!
    private(set) var canGoBack = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    private(set) var sessionStatus: TikTokSessionStatus = .unknown
    private(set) var isDirectMessageOpen = false
    private(set) var directMessageName = ""
    private(set) var directMessageHandle = ""
    private(set) var directMessageAvatarURL: URL?
    private(set) var inboxTab: TikTokInboxTab = .messages
    private(set) var isAwaitingInboxPresentation = false
    private(set) var inboxLoadTimedOut = false

    var isInboxSurface: Bool {
        isAwaitingInboxPresentation
            || (TikTokNavigationPolicy.isMessagesURL(currentURL) && !isDirectMessageOpen)
    }

    @ObservationIgnored private weak var protectionStore: TikTokProtectionStore?
    @ObservationIgnored private var mode: TikTokMode = .clean
    @ObservationIgnored private var grantedVideoURL: URL?
    @ObservationIgnored private var grantedProfileURL: URL?
    @ObservationIgnored private var returnURLAfterVideo: URL?
    @ObservationIgnored private var isVideoOverlayOpen = false
    @ObservationIgnored private var isScrollableFeedActive = false
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var receivedHealthPing = false
    @ObservationIgnored private var isUsingDesktopMessages = false
    @ObservationIgnored private var shouldOpenInboxAfterSignIn = false
    @ObservationIgnored private var inboxLoadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingNotificationVideoTap: (source: URL, date: Date)?
    @ObservationIgnored private var navigationGuard = ControlledNavigationGuard()

    override init() {
        super.init()
        let controller = WKUserContentController()
        if let scriptURL = Bundle.main.url(forResource: "tiktok_cleaner", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            ))
        }
        controller.add(
            WeakTikTokScriptHandler(target: self),
            contentWorld: .defaultClient,
            name: "nimaTikTok"
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = TikTokWebViewWithoutInputAccessory(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
    }

    func configure(store: TikTokProtectionStore) {
        protectionStore = store
    }

    func startIfNeeded(at initialURL: URL? = nil, mode initialMode: TikTokMode) {
        guard webView.url == nil else { return }
        mode = initialMode
        webView.allowsBackForwardNavigationGestures = mode == .clean
        syncFilterState()
        if initialURL == TikTokNavigationPolicy.loginURL {
            load(TikTokNavigationPolicy.loginURL)
        } else {
            openMessages()
        }
    }

    func updateMode(_ newMode: TikTokMode) {
        guard mode != newMode else { return }
        mode = newMode
        webView.allowsBackForwardNavigationGestures = mode == .clean
        clearVideoGrant()
        syncFilterState()
    }

    func activateMode(_ newMode: TikTokMode) {
        updateMode(newMode)
        guard webView.url != nil else { return }
        openMessages()
    }

    func openFollowing() {
        openNativeSurface("following", fallback: TikTokNavigationPolicy.followingURL)
    }
    func openFriends() {
        openNativeSurface("friends", fallback: TikTokNavigationPolicy.friendsURL)
    }
    func openSearch() {
        openNativeSurface("search", fallback: TikTokNavigationPolicy.searchURL)
    }

    private func openSearchQuery(_ rawQuery: String) {
        guard mode == .clean else { return }
        clearInboxCover()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // TikTok's mobile search handler never finishes and its explicit
        // result route redirects back to Following. Loading the canonical
        // result URL with TikTok's desktop response renders the result tabs.
        guard !query.isEmpty,
              var components = URLComponents(
                url: TikTokNavigationPolicy.searchURL,
                resolvingAgainstBaseURL: false
              ) else { return }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "lang", value: "en")
        ]
        guard let url = components.url else { return }
        setScrollableFeedActive(false)
        clearVideoGrant()
        isUsingDesktopMessages = false
        webView.customUserAgent = Self.desktopUserAgent
        load(url)
    }
    func openProfile() {
        openNativeSurface("profile", fallback: TikTokNavigationPolicy.profileURL)
    }
    func openMessages() {
        inboxTab = .messages
        beginInboxCover()
        resetDirectMessageState()
        setScrollableFeedActive(false)
        clearVideoGrant()
        isUsingDesktopMessages = true
        webView.customUserAgent = Self.desktopUserAgent
        load(TikTokNavigationPolicy.messagesURL)
    }

    func openNotifications() {
        guard mode == .clean else { return }
        inboxTab = .notifications
        clearInboxCover()
        resetDirectMessageState()
        clearVideoGrant()
        isUsingDesktopMessages = false
        webView.customUserAgent = nil
        load(URL(string: "https://www.tiktok.com/inbox")!)
    }

    func reload() {
        if TikTokNavigationPolicy.isMessagesURL(webView.url), inboxTab == .messages {
            beginInboxCover()
        }
        protectionStore?.setFilteringHealth(.checking)
        receivedHealthPing = false
        webView.reload()
    }

    @discardableResult
    func openLink(_ rawValue: String) -> Bool {
        guard let url = TikTokNavigationPolicy.tiktokURL(from: rawValue) else { return false }
        clearInboxCover()
        setScrollableFeedActive(false)
        clearVideoGrant()
        if TikTokNavigationPolicy.isIndividualVideoURL(url) {
            returnURLAfterVideo = webView.url ?? TikTokNavigationPolicy.followingURL
            grantedVideoURL = url
            isVideoOverlayOpen = true
            updateScrollLock()
            syncFilterState()
        } else if mode == .dmOnly, TikTokNavigationPolicy.isProfileURL(url) {
            returnURLAfterVideo = webView.url
            grantedProfileURL = url
            syncFilterState()
        }
        load(url)
        return true
    }

    func logOut() {
        clearInboxCover()
        clearVideoGrant()
        load(URL(string: "https://www.tiktok.com/logout")!)
    }

    private func openMobileDestination(_ url: URL) {
        clearInboxCover()
        clearVideoGrant()
        isUsingDesktopMessages = false
        webView.customUserAgent = nil
        load(url)
    }

    private func openNativeSurface(
        _ surface: String,
        fallback: URL,
        usesDesktopFallback: Bool = false
    ) {
        guard mode == .clean else { return }
        clearInboxCover()
        resetDirectMessageState()
        setScrollableFeedActive(surface == "following" || surface == "friends")
        clearVideoGrant()
        isUsingDesktopMessages = false
        webView.customUserAgent = nil
        let script = "window.__nimaTikTokOpenNativeSurface && window.__nimaTikTokOpenNativeSurface('\(surface)')"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if (result as? Bool) == true {
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !self.isOnSurface(surface) else { return }
                }
                self.loadFallback(
                    fallback,
                    usesDesktopUserAgent: usesDesktopFallback
                )
            }
        }
    }

    private func isOnSurface(_ surface: String) -> Bool {
        switch surface {
        case "following": TikTokNavigationPolicy.isFollowingURL(webView.url)
        case "friends": TikTokNavigationPolicy.isFriendsURL(webView.url)
        case "search": TikTokNavigationPolicy.isSearchURL(webView.url)
        case "inbox": TikTokNavigationPolicy.isMessagesURL(webView.url)
        case "profile": TikTokNavigationPolicy.isProfileURL(webView.url)
        default: false
        }
    }

    private func loadFallback(_ url: URL, usesDesktopUserAgent: Bool) {
        isUsingDesktopMessages = usesDesktopUserAgent
        if usesDesktopUserAgent { webView.customUserAgent = Self.desktopUserAgent }
        load(url)
    }

    func goBack(onRoot: @escaping @MainActor () -> Void) {
        if isDirectMessageOpen {
            // A conversation is a state inside TikTok's inbox, not a separate
            // page in WKWebView's history. Never use browser Back for this.
            resetDirectMessageState()
            webView.evaluateJavaScript(
                "window.__nimaTikTokCloseDirectMessage && window.__nimaTikTokCloseDirectMessage()"
            ) { [weak self] result, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if result as? Bool != true { self.openMessages() }
                }
            }
            return
        }
        if TikTokNavigationPolicy.isMessagesURL(webView.url) {
            webView.evaluateJavaScript(
                "window.__nimaTikTokCloseDirectMessage && window.__nimaTikTokCloseDirectMessage()"
            ) { [weak self] result, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if result as? Bool == true { return }
                    self.performBackNavigation(onRoot: onRoot)
                }
            }
            return
        }
        performBackNavigation(onRoot: onRoot)
    }

    private func performBackNavigation(onRoot: @escaping @MainActor () -> Void) {
        if mode == .dmOnly {
            let isOpenLinkedDestination = isVideoOverlayOpen
                || TikTokNavigationPolicy.isIndividualVideoURL(webView.url)
                || TikTokNavigationPolicy.isProfileURL(webView.url)
            if isOpenLinkedDestination, let destination = returnURLAfterVideo {
                clearVideoGrant()
                load(destination)
            } else if !TikTokNavigationPolicy.isMessagesURL(webView.url) {
                openMessages()
            } else {
                onRoot()
            }
            return
        }
        if isVideoOverlayOpen || TikTokNavigationPolicy.isIndividualVideoURL(webView.url) {
            let destination = returnURLAfterVideo ?? TikTokNavigationPolicy.followingURL
            clearVideoGrant()
            load(destination)
        } else if webView.canGoBack {
            webView.goBack()
        } else {
            onRoot()
        }
    }

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func grantVideo(_ url: URL?, sourceURL: URL?) {
        guard !isScrollableFeedActive else { return }
        if mode == .dmOnly {
            guard isDirectMessageOpen,
                  TikTokNavigationPolicy.isDirectMessagesURL(sourceURL) else { return }
        }
        guard TikTokNavigationPolicy.mayGrantVideo(from: sourceURL) else { return }
        if returnURLAfterVideo == nil { returnURLAfterVideo = sourceURL }
        if let url, TikTokNavigationPolicy.isIndividualVideoURL(url) {
            grantedVideoURL = url
            pendingNotificationVideoTap = nil
        }
        isVideoOverlayOpen = true
        updateScrollLock()
        syncFilterState()
    }

    private func clearVideoGrant() {
        grantedVideoURL = nil
        grantedProfileURL = nil
        returnURLAfterVideo = nil
        isVideoOverlayOpen = false
        pendingNotificationVideoTap = nil
        updateScrollLock()
        syncFilterState()
    }

    private func resetDirectMessageState() {
        isDirectMessageOpen = false
        directMessageName = ""
        directMessageHandle = ""
        directMessageAvatarURL = nil
    }

    private func updateScrollLock() {
        let locked = !isScrollableFeedActive
            && (isVideoOverlayOpen || TikTokNavigationPolicy.isIndividualVideoURL(grantedVideoURL))
        webView.scrollView.isScrollEnabled = !locked
        webView.scrollView.bounces = !locked
        webView.scrollView.alwaysBounceVertical = !locked
    }

    private func grantTappedNotificationVideo(_ url: URL) {
        guard TikTokNavigationPolicy.isIndividualVideoURL(url),
              let tap = pendingNotificationVideoTap,
              Date().timeIntervalSince(tap.date) < 4 else { return }
        pendingNotificationVideoTap = nil
        grantVideo(url, sourceURL: tap.source)
    }

    private func syncFilterState() {
        let videoURL: Any = grantedVideoURL?.absoluteString ?? NSNull()
        let payload: [String: Any] = [
            "grantedVideoURL": videoURL,
            "videoOverlayOpen": isVideoOverlayOpen,
            "feedScrollingEnabled": isScrollableFeedActive,
            "mode": mode.rawValue,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.__nimaTikTokConfigure && window.__nimaTikTokConfigure(\(json))",
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    private func handleBlockedNavigation(blockedURL: URL? = nil) {
        clearInboxCover()
        if let blockedURL,
           navigationGuard.recordBlockedNavigation(to: blockedURL) {
            return
        }
        if mode == .dmOnly {
            openMessages()
            AnalyticsService.shared.capture("tiktok_navigation_blocked")
            return
        }
        let destination = returnURLAfterVideo
            ?? TikTokNavigationPolicy.followingURL
        clearVideoGrant()
        if isUsingDesktopMessages && mode == .clean {
            isUsingDesktopMessages = false
            webView.customUserAgent = nil
        }
        load(destination)
        AnalyticsService.shared.capture("tiktok_navigation_blocked")
    }

    private func grantConversationLink(_ url: URL, sourceURL: URL?) {
        guard isDirectMessageOpen,
              TikTokNavigationPolicy.isDirectMessagesURL(sourceURL) else { return }
        if TikTokNavigationPolicy.isIndividualVideoURL(url) {
            grantVideo(url, sourceURL: sourceURL)
        } else if mode == .dmOnly, TikTokNavigationPolicy.isProfileURL(url) {
            grantedProfileURL = url
            returnURLAfterVideo = sourceURL
            syncFilterState()
        }
    }

    private func setScrollableFeedActive(_ active: Bool) {
        guard isScrollableFeedActive != active else { return }
        isScrollableFeedActive = active
        updateScrollLock()
        syncFilterState()
    }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
        currentURL = webView.url
        if let currentURL, !TikTokNavigationPolicy.isMessagesURL(currentURL),
           isDirectMessageOpen {
            resetDirectMessageState()
        }
    }

    private func beginInboxCover() {
        inboxLoadTask?.cancel()
        isAwaitingInboxPresentation = true
        inboxLoadTimedOut = false
        inboxLoadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.isAwaitingInboxPresentation else { return }
            self.inboxLoadTimedOut = true
        }
    }

    private func clearInboxCover() {
        inboxLoadTask?.cancel()
        inboxLoadTask = nil
        isAwaitingInboxPresentation = false
        inboxLoadTimedOut = false
    }

    private func scheduleHealthCheck(for url: URL?) {
        healthTask?.cancel()
        guard TikTokNavigationPolicy.isTikTokHost(url?.host),
              !TikTokNavigationPolicy.isAuthenticationURL(url) else {
            protectionStore?.setFilteringHealth(.healthy)
            return
        }
        if receivedHealthPing {
            protectionStore?.setFilteringHealth(.healthy)
            return
        }
        let generation = navigationGuard.generation
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.receivedHealthPing else { return }
            guard self.navigationGuard.isCurrent(generation) else { return }
            self.protectionStore?.setFilteringHealth(.limited)
            AnalyticsService.shared.capture("tiktok_filter_health_failed")
        }
    }
}

extension TikTokWebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if shouldOpenInboxAfterSignIn,
           navigationAction.targetFrame?.isMainFrame != false,
           TikTokNavigationPolicy.isTikTokHost(url.host),
           !TikTokNavigationPolicy.isAuthenticationURL(url),
           !TikTokNavigationPolicy.isDirectMessagesURL(url) {
            shouldOpenInboxAfterSignIn = false
            sessionStatus = .authenticated
            decisionHandler(.cancel)
            openMessages()
            return
        }
        let sourceURL = navigationAction.sourceFrame.request.url ?? webView.url
        if navigationAction.sourceFrame.isMainFrame {
            grantConversationLink(url, sourceURL: sourceURL)
        }
        if TikTokNavigationPolicy.isFollowingURL(url) || TikTokNavigationPolicy.isFriendsURL(url) {
            setScrollableFeedActive(true)
        } else if !TikTokNavigationPolicy.isIndividualVideoURL(url),
                  TikTokNavigationPolicy.isSearchURL(url)
                    || TikTokNavigationPolicy.isMessagesURL(url)
                    || TikTokNavigationPolicy.isProfileURL(url) {
            setScrollableFeedActive(false)
        }
        if mode == .clean, isScrollableFeedActive, TikTokNavigationPolicy.isIndividualVideoURL(url) {
            decisionHandler(.allow)
            return
        }
        if TikTokNavigationPolicy.isIndividualVideoURL(url) {
            grantTappedNotificationVideo(url)
            grantVideo(url, sourceURL: sourceURL)
        }
        switch TikTokNavigationPolicy.action(
            for: url,
            sourceURL: sourceURL,
            grantedVideoURL: grantedVideoURL,
            mode: mode,
            grantedProfileURL: grantedProfileURL
        ) {
        case .allow:
            decisionHandler(.allow)
        case .block:
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false {
                handleBlockedNavigation(blockedURL: url)
            }
        case .openExternal:
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,
               navigationAction.sourceFrame.isMainFrame {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        healthTask?.cancel()
        receivedHealthPing = false
        navigationGuard.beginNavigation()
        if let url = webView.url, TikTokNavigationPolicy.isAuthenticationURL(url) {
            sessionStatus = .signingIn
            shouldOpenInboxAfterSignIn = true
        }
        protectionStore?.setFilteringHealth(.checking)
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState()
        navigationGuard.resetLoopHistory()
        if shouldOpenInboxAfterSignIn,
           let url = webView.url,
           TikTokNavigationPolicy.isTikTokHost(url.host),
           !TikTokNavigationPolicy.isAuthenticationURL(url) {
            shouldOpenInboxAfterSignIn = false
            sessionStatus = .authenticated
            if !TikTokNavigationPolicy.isDirectMessagesURL(url) {
                openMessages()
                return
            }
        }
        if mode == .dmOnly, TikTokNavigationPolicy.isDirectMessagesURL(webView.url),
           grantedVideoURL != nil || grantedProfileURL != nil {
            clearVideoGrant()
        }
        if !TikTokNavigationPolicy.isMessagesURL(webView.url) { clearInboxCover() }
        syncFilterState()
        scheduleHealthCheck(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState()
        if isAwaitingInboxPresentation { inboxLoadTimedOut = true }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateNavigationState()
        if isAwaitingInboxPresentation { inboxLoadTimedOut = true }
    }
}

extension TikTokWebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let sourceURL = webView.url
        grantConversationLink(url, sourceURL: sourceURL)
        if TikTokNavigationPolicy.isIndividualVideoURL(url) {
            grantVideo(url, sourceURL: sourceURL)
        }
        let action = TikTokNavigationPolicy.action(
            for: url,
            sourceURL: sourceURL,
            grantedVideoURL: grantedVideoURL,
            mode: mode,
            grantedProfileURL: grantedProfileURL
        )
        if action == .allow { webView.load(navigationAction.request) }
        return nil
    }
}

extension TikTokWebSession: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self, let payload = message.body as? [String: Any],
                  let event = payload["event"] as? String else { return }
            switch event {
            case "health":
                self.receivedHealthPing = true
                self.healthTask?.cancel()
                self.protectionStore?.setFilteringHealth(.healthy)
            case "sessionState":
                if let raw = payload["status"] as? String,
                   let status = TikTokSessionStatus(rawValue: raw) {
                    self.sessionStatus = status
                }
            case "videoActivated":
                let url = (payload["url"] as? String)
                    .flatMap { URL(string: $0, relativeTo: self.webView.url)?.absoluteURL }
                self.grantVideo(url, sourceURL: self.currentURL ?? self.webView.url)
            case "notificationTapped":
                if let raw = payload["sourceURL"] as? String,
                   let source = URL(string: raw),
                   TikTokNavigationPolicy.isTikTokHost(source.host),
                   ["/inbox", "/inbox/"].contains(source.path.lowercased()) {
                    self.pendingNotificationVideoTap = (source, Date())
                }
            case "locationChanged":
                guard message.frameInfo.isMainFrame else { return }
                guard let raw = payload["url"] as? String, let url = URL(string: raw) else { return }
                if self.shouldOpenInboxAfterSignIn,
                   TikTokNavigationPolicy.isTikTokHost(url.host),
                   !TikTokNavigationPolicy.isAuthenticationURL(url),
                   !TikTokNavigationPolicy.isDirectMessagesURL(url) {
                    self.shouldOpenInboxAfterSignIn = false
                    self.sessionStatus = .authenticated
                    self.openMessages()
                    return
                }
                self.grantConversationLink(url, sourceURL: self.currentURL)
                if payload["feedScrolling"] as? Bool == true,
                   TikTokNavigationPolicy.isIndividualVideoURL(url) {
                    return
                }
                if TikTokNavigationPolicy.isIndividualVideoURL(url),
                   let sourceRaw = payload["notificationTapSourceURL"] as? String,
                   let source = URL(string: sourceRaw),
                   TikTokNavigationPolicy.isTikTokHost(source.host),
                   ["/inbox", "/inbox/"].contains(source.path.lowercased()) {
                    self.grantVideo(url, sourceURL: source)
                }
                self.grantTappedNotificationVideo(url)
                let action = TikTokNavigationPolicy.action(
                    for: url,
                    sourceURL: self.currentURL,
                    grantedVideoURL: self.grantedVideoURL,
                    mode: self.mode,
                    grantedProfileURL: self.grantedProfileURL
                )
                if action == .block {
                    self.handleBlockedNavigation(blockedURL: url)
                } else if action == .allow {
                    // pushState does not call didFinish, so keep SwiftUI's
                    // header and Back destination aligned with the web page.
                    self.currentURL = url
                }
            case "videoClosed":
                self.clearVideoGrant()
            case "openInbox":
                self.openMessages()
            case "submitSearch":
                if let query = payload["query"] as? String {
                    self.openSearchQuery(query)
                }
            case "directMessageSelected":
                guard TikTokNavigationPolicy.isMessagesURL(self.webView.url) else { return }
                let panelIsActive = try? await self.webView.evaluateJavaScript(
                    "document.documentElement.hasAttribute('data-nima-dm-active')"
                ) as? Bool
                guard panelIsActive == true,
                      TikTokNavigationPolicy.isMessagesURL(self.webView.url) else { return }
                self.isDirectMessageOpen = true
                self.directMessageName = payload["name"] as? String ?? ""
                self.directMessageHandle = payload["handle"] as? String ?? ""
                self.directMessageAvatarURL = (payload["avatarURL"] as? String)
                    .flatMap(URL.init(string:))
            case "directMessageClosed":
                self.isDirectMessageOpen = false
                self.directMessageName = ""
                self.directMessageHandle = ""
                self.directMessageAvatarURL = nil
            case "inboxReady":
                if TikTokNavigationPolicy.isMessagesURL(self.webView.url) {
                    self.clearInboxCover()
                }
            default:
                break
            }
        }
    }
}

// The default WebKit form toolbar adds a second row between the chat composer
// and the keyboard. Keep TikTok's editable field and send handling intact.
private final class TikTokWebViewWithoutInputAccessory: WKWebView {
    override var inputAccessoryView: UIView? { nil }
}

private final class WeakTikTokScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

struct TikTokWebView: UIViewRepresentable {
    let session: TikTokWebSession
    let initialURL: URL?
    let mode: TikTokMode
    let userInterfaceStyle: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WKWebView {
        updateAppearance(of: session.webView)
        session.startIfNeeded(at: initialURL, mode: mode)
        return session.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        updateAppearance(of: uiView)
        session.updateMode(mode)
    }

    private func updateAppearance(of webView: WKWebView) {
        webView.overrideUserInterfaceStyle = userInterfaceStyle
        let background: UIColor = userInterfaceStyle == .dark ? .black : .white
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
    }
}
