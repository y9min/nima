import Foundation
import Observation
import SwiftUI
import UIKit
import WebKit

enum XSessionStatus: String, Equatable {
    case unknown
    case signingIn = "signing_in"
    case authenticated
}

@MainActor
@Observable
final class XWebSession: NSObject {
    // X redirects iPhone WebViews that look like Safari to its x-safari-https
    // handoff during authentication. A desktop Safari identity keeps the login
    // task in this persistent WKWebView while the layout remains responsive.
    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let messagesUserAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

    private(set) var webView: WKWebView!
    private(set) var canGoBack = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    private(set) var sessionStatus: XSessionStatus = .unknown
    private(set) var isAwaitingMessagesPresentation = false
    private(set) var messagesLoadTimedOut = false

    var isInboxSurface: Bool {
        isAwaitingMessagesPresentation
            || (XNavigationPolicy.isMessagesURL(currentURL) && !isConversationOpen)
    }

    var isConversationOpen: Bool {
        XNavigationPolicy.isConversationURL(currentURL)
    }

    @ObservationIgnored private weak var protectionStore: XProtectionStore?
    @ObservationIgnored private var mode: XMode = .clean
    @ObservationIgnored private var grantedPostURL: URL?
    @ObservationIgnored private var grantedProfileURL: URL?
    @ObservationIgnored private var returnURLAfterLinkedDestination: URL?
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var messagesLoadTask: Task<Void, Never>?
    @ObservationIgnored private var navigationGuard = ControlledNavigationGuard()
    @ObservationIgnored private var healthVerifier = XHomeHealthVerifier()
    @ObservationIgnored private var activeHealthDocumentToken: String?

    override init() {
        super.init()
        let controller = WKUserContentController()
        if let scriptURL = Bundle.main.url(forResource: "x_cleaner", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .defaultClient
            ))
        }
        controller.add(
            WeakXScriptHandler(target: self),
            contentWorld: .defaultClient,
            name: "nimaX"
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = XWebViewWithoutInputAccessory(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.customUserAgent = Self.desktopUserAgent
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
    }

    func configure(store: XProtectionStore) {
        protectionStore = store
    }

    func startIfNeeded(at initialURL: URL? = nil, mode initialMode: XMode) {
        guard webView.url == nil else { return }
        mode = initialMode
        syncFilterState()
        if let initialURL, initialURL == XNavigationPolicy.loginURL {
            load(initialURL)
        } else if mode == .dmOnly {
            openMessages()
        } else {
            openFollowing()
        }
    }

    func updateMode(_ newMode: XMode) {
        guard mode != newMode else { return }
        mode = newMode
        clearConversationGrants()
        syncFilterState()
    }

    func activateMode(_ newMode: XMode) {
        updateMode(newMode)
        guard webView.url != nil else { return }
        if newMode == .dmOnly {
            openMessages()
        } else {
            openFollowing()
        }
    }

    func openFollowing() {
        guard mode == .clean else { return }
        clearMessagesCover()
        clearConversationGrants()
        webView.customUserAgent = Self.desktopUserAgent
        load(XNavigationPolicy.homeURL)
    }

    func openSearch() {
        guard mode == .clean else { return }
        clearMessagesCover()
        clearConversationGrants()
        webView.customUserAgent = Self.desktopUserAgent
        load(XNavigationPolicy.searchURL)
    }

    func openNotifications() {
        guard mode == .clean else { return }
        clearMessagesCover()
        clearConversationGrants()
        webView.customUserAgent = Self.desktopUserAgent
        load(XNavigationPolicy.notificationsURL)
    }

    func openProfile() {
        guard mode == .clean else { return }
        clearMessagesCover()
        clearConversationGrants()
        webView.customUserAgent = Self.desktopUserAgent
        load(XNavigationPolicy.viewerProfileURL)
    }

    func openMessages(forceAfterAuthentication: Bool = false) {
        guard forceAfterAuthentication
                || (sessionStatus != .signingIn
                    && !XNavigationPolicy.isAuthenticationURL(webView.url)) else {
            logNavigation("X_MESSAGES_DEFERRED reason=authentication_in_progress")
            return
        }
        clearMessagesCover()
        clearConversationGrants()
        beginMessagesCover()
        webView.customUserAgent = Self.messagesUserAgent
        load(XNavigationPolicy.chatURL)
    }

    func reload() {
        if XNavigationPolicy.isMessagesURL(webView.url) {
            beginMessagesCover()
        }
        healthVerifier.beginNavigation()
        protectionStore?.setFilteringHealth(.checking)
        webView.reload()
    }

    func retryCleanMode() {
        healthVerifier.beginNavigation()
        protectionStore?.setFilteringHealth(.checking)
        updateMode(.clean)
        openFollowing()
    }

    @discardableResult
    func openLink(_ rawValue: String) -> Bool {
        guard let url = XNavigationPolicy.xURL(from: rawValue) else { return false }
        clearMessagesCover()
        clearConversationGrants()
        grantDirectLink(url)
        load(url)
        return true
    }

    func logOut() {
        clearMessagesCover()
        clearConversationGrants()
        load(URL(string: "https://x.com/logout")!)
    }

    func goBack(onRoot: @escaping @MainActor () -> Void) {
        if mode == .dmOnly {
            if let returnURL = returnURLAfterLinkedDestination {
                clearConversationGrants()
                load(returnURL)
            } else if !XNavigationPolicy.isMessagesURL(webView.url) {
                openMessages()
            } else {
                onRoot()
            }
            return
        }
        if XNavigationPolicy.isAuthenticationURL(webView.url) {
            onRoot()
        } else if webView.canGoBack {
            webView.goBack()
        } else {
            onRoot()
        }
    }

    private func openNativeSurface(_ surface: String, fallback: URL) {
        let startingURL = webView.url
        let script = "window.__nimaXOpenNativeSurface && window.__nimaXOpenNativeSurface('\(surface)')"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if (result as? Bool) == true {
                    try? await Task.sleep(for: .milliseconds(700))
                    if self.webView.url != startingURL { return }
                }
                self.load(fallback)
            }
        }
    }

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func grantConversationLink(_ url: URL, sourceURL: URL?) {
        guard mode == .dmOnly,
              XNavigationPolicy.mayGrantConversationLink(from: sourceURL) else {
            return
        }
        returnURLAfterLinkedDestination = sourceURL
        if XNavigationPolicy.isPostURL(url) {
            grantedPostURL = url
            grantedProfileURL = nil
        } else if XNavigationPolicy.isProfileURL(url) {
            grantedPostURL = nil
            grantedProfileURL = url
        }
        syncFilterState()
    }

    private func grantDirectLink(_ url: URL) {
        returnURLAfterLinkedDestination = webView.url
        if XNavigationPolicy.isPostURL(url) {
            grantedPostURL = url
            grantedProfileURL = nil
        } else if XNavigationPolicy.isProfileURL(url) {
            grantedPostURL = nil
            grantedProfileURL = url
        }
        syncFilterState()
    }

    private func clearConversationGrants() {
        grantedPostURL = nil
        grantedProfileURL = nil
        returnURLAfterLinkedDestination = nil
        syncFilterState()
    }

    private func syncFilterState() {
        let payload: [String: Any] = [
            "mode": mode.rawValue,
            "grantedPostURL": grantedPostURL?.absoluteString ?? NSNull(),
            "grantedProfileURL": grantedProfileURL?.absoluteString ?? NSNull(),
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.__nimaXConfigure && window.__nimaXConfigure(\(json))",
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    private func handleBlockedNavigation(blockedURL: URL) {
        logNavigation(
            "X_NAV_BLOCKED url=\(blockedURL.absoluteString) mode=\(mode.rawValue)"
        )
        let repeatedLoop = navigationGuard.recordBlockedNavigation(to: blockedURL)
        if repeatedLoop {
            protectionStore?.setFilteringHealth(.limited)
            clearMessagesCover()
            return
        }
        if mode == .dmOnly {
            if let returnURL = returnURLAfterLinkedDestination {
                clearConversationGrants()
                load(returnURL)
            } else {
                openMessages()
            }
        }
        clearMessagesCover()
        AnalyticsService.shared.capture("x_navigation_blocked")
    }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
        currentURL = webView.url
    }

    private func logNavigation(_ message: String) {
        let sanitizedMessage = Self.redactNavigationQueries(message)
        AppDiagnosticsLogger.log(sanitizedMessage)
        #if DEBUG
        print(sanitizedMessage)
        #endif

        guard let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return }
        let traceURL = cacheDirectory.appendingPathComponent("x_navigation_trace.txt")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(sanitizedMessage)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: traceURL.path),
           let size = attrs[.size] as? Int,
           size > 64 * 1024 {
            try? data.write(to: traceURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: traceURL.path),
                  let handle = try? FileHandle(forWritingTo: traceURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: traceURL, options: .atomic)
        }
    }

    private static func redactNavigationQueries(_ message: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#
        ) else {
            return message
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return expression.matches(in: message, range: range)
            .reversed()
            .reduce(message) { result, match in
                guard let matchRange = Range(match.range, in: result),
                      let urlRange = Range(match.range, in: message),
                      let originalURL = URL(string: String(message[urlRange])),
                      let components = URLComponents(
                        url: originalURL,
                        resolvingAgainstBaseURL: false
                      ) else {
                    return result
                }
                var redacted = components
                redacted.query = nil
                redacted.fragment = nil
                guard let replacement = redacted.url?.absoluteString else { return result }
                var updated = result
                updated.replaceSubrange(matchRange, with: replacement)
                return updated
            }
    }

    private func beginMessagesCover() {
        messagesLoadTask?.cancel()
        isAwaitingMessagesPresentation = true
        messagesLoadTimedOut = false
        messagesLoadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.isAwaitingMessagesPresentation else { return }
            self.messagesLoadTimedOut = true
        }
    }

    private func clearMessagesCover() {
        messagesLoadTask?.cancel()
        messagesLoadTask = nil
        isAwaitingMessagesPresentation = false
        messagesLoadTimedOut = false
    }

    private func scheduleHealthCheck(for url: URL?) {
        healthTask?.cancel()
        guard let url, XNavigationPolicy.isXHost(url.host),
              XNavigationPolicy.isFollowingFeedURL(url) else {
            return
        }
        let generation = navigationGuard.generation
        healthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            guard self.navigationGuard.isCurrent(generation) else { return }
            guard self.protectionStore?.filteringHealth == .checking else { return }
            let health = self.healthVerifier.markSlow()
            self.protectionStore?.setFilteringHealth(health)
            self.logNavigation("X_HEALTH status=\(health.rawValue) reason=no_home_observation")
            AnalyticsService.shared.capture("x_filter_health_slow")
        }
    }

    private func applyHomeHealth(from payload: [String: Any]) -> XFilteringHealth? {
        guard let rawURL = payload["url"] as? String,
              let reportedURL = URL(string: rawURL),
              let currentURL = webView.url,
              XNavigationPolicy.isFollowingFeedURL(currentURL),
              currentURL.path == reportedURL.path else {
            return nil
        }
        guard let rawPath = payload["path"] as? String,
              rawPath == "/" || rawPath == "/home" else {
            return nil
        }

        if let token = payload["documentToken"] as? String {
            if let activeHealthDocumentToken,
               activeHealthDocumentToken != token {
                return nil
            }
            activeHealthDocumentToken = token
        }

        let observation = XHomeHealthObservation(
            path: rawPath,
            documentReady: payload["documentReady"] as? Bool ?? false,
            homeSurfacePresent: payload["homeSurfacePresent"] as? Bool ?? false,
            timelineTabsPresent: payload["timelineTabsPresent"] as? Bool ?? false,
            followingPresent: payload["followingPresent"] as? Bool ?? false,
            followingSelected: payload["followingSelected"] as? Bool ?? false,
            forYouPresent: payload["forYouPresent"] as? Bool ?? false,
            isLoading: payload["loading"] as? Bool ?? false,
            loadError: payload["loadError"] as? Bool ?? false
        )
        let previous = protectionStore?.filteringHealth
        let health = healthVerifier.observe(observation)
        if health == .healthy || health == .limited {
            healthTask?.cancel()
        }
        if previous != health {
            let reason: String
            if observation.loadError {
                reason = "load_error"
            } else if observation.isLoading {
                reason = "page_loading"
            } else if observation.followingSelected {
                reason = "following_selected"
            } else if observation.followingPresent {
                reason = "following_not_selected"
            } else {
                reason = "following_not_found"
            }
            logNavigation(
                "X_HEALTH status=\(health.rawValue) reason=\(reason)"
            )
        }
        if previous != .limited && health == .limited {
            AnalyticsService.shared.capture("x_following_unavailable")
        }
        return health
    }
}

extension XWebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let navigationScheme = url.scheme?.lowercased() ?? ""
        if navigationScheme == "about"
            || (["data", "blob"].contains(navigationScheme)
                && navigationAction.targetFrame?.isMainFrame == false) {
            decisionHandler(.allow)
            return
        }

        if sessionStatus == .signingIn,
           navigationAction.targetFrame?.isMainFrame != false,
           XNavigationPolicy.isXHost(url.host) {
            if XNavigationPolicy.isMessagesURL(url) {
                logNavigation(
                    "X_NAV_BLOCKED_AUTH url=\(url.absoluteString) mode=\(mode.rawValue)"
                )
                decisionHandler(.cancel)
                return
            }
            if !XNavigationPolicy.isAuthenticationURL(url) {
                sessionStatus = .authenticated
                protectionStore?.setFilteringHealth(.checking)
                if mode == .dmOnly {
                    decisionHandler(.cancel)
                    openMessages(forceAfterAuthentication: true)
                    return
                }
            }
        }

        let sourceURL = navigationAction.sourceFrame.request.url ?? webView.url
        if XNavigationPolicy.isMessagesURL(url),
           XNavigationPolicy.isAuthenticationURL(webView.url)
                || XNavigationPolicy.isAuthenticationURL(sourceURL) {
            logNavigation(
                "X_NAV_BLOCKED_AUTH url=\(url.absoluteString) source=\(sourceURL?.absoluteString ?? "nil") mode=\(mode.rawValue)"
            )
            decisionHandler(.cancel)
            return
        }
        if navigationAction.sourceFrame.isMainFrame,
           navigationAction.navigationType == .linkActivated {
            grantConversationLink(url, sourceURL: sourceURL)
        }

        switch XNavigationPolicy.action(
            for: url,
            sourceURL: sourceURL,
            mode: mode,
            grantedPostURL: grantedPostURL,
            grantedProfileURL: grantedProfileURL
        ) {
        case .allow:
            logNavigation(
                "X_NAV_ALLOW url=\(url.absoluteString) source=\(sourceURL?.absoluteString ?? "nil") type=\(navigationAction.navigationType.rawValue)"
            )
            decisionHandler(.allow)
        case .block:
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false {
                handleBlockedNavigation(blockedURL: url)
            }
        case .openExternal:
            logNavigation(
                "X_NAV_EXTERNAL url=\(url.absoluteString) type=\(navigationAction.navigationType.rawValue)"
            )
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,
               navigationAction.sourceFrame.isMainFrame {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logNavigation(
            "X_NAV_START url=\(webView.url?.absoluteString ?? "nil")"
        )
        healthTask?.cancel()
        activeHealthDocumentToken = nil
        healthVerifier.beginNavigation()
        navigationGuard.beginNavigation()
        if let url = webView.url, XNavigationPolicy.isAuthenticationURL(url) {
            sessionStatus = .signingIn
        } else if XNavigationPolicy.isFollowingFeedURL(webView.url),
                  protectionStore?.filteringHealth != .limited {
            protectionStore?.setFilteringHealth(.checking)
        }
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logNavigation(
            "X_NAV_FINISH url=\(webView.url?.absoluteString ?? "nil")"
        )
        updateNavigationState()
        navigationGuard.resetLoopHistory()
        syncFilterState()
        scheduleHealthCheck(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logNavigation(
            "X_NAV_FAIL url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
        )
        updateNavigationState()
        if isAwaitingMessagesPresentation { messagesLoadTimedOut = true }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logNavigation(
            "X_NAV_PERMISSION_FAIL url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)"
        )
        updateNavigationState()
        if isAwaitingMessagesPresentation { messagesLoadTimedOut = true }
    }
}

extension XWebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let sourceURL = webView.url
        grantConversationLink(url, sourceURL: sourceURL)
        if XNavigationPolicy.action(
            for: url,
            sourceURL: sourceURL,
            mode: mode,
            grantedPostURL: grantedPostURL,
            grantedProfileURL: grantedProfileURL
        ) == .allow {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

extension XWebSession: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self, let payload = message.body as? [String: Any],
                  let event = payload["event"] as? String else { return }
            switch event {
            case "filterHealth":
                guard message.frameInfo.isMainFrame,
                      let health = self.applyHomeHealth(from: payload) else { return }
                self.protectionStore?.setFilteringHealth(health)
            case "messagesReady":
                if XNavigationPolicy.isMessagesURL(self.currentURL) {
                    self.clearMessagesCover()
                }
            case "pageError":
                if XNavigationPolicy.isMessagesURL(self.currentURL) {
                    self.isAwaitingMessagesPresentation = true
                    self.messagesLoadTimedOut = true
                }
            case "locationChanged":
                guard message.frameInfo.isMainFrame,
                      let raw = payload["url"] as? String,
                      let url = URL(string: raw) else { return }
                self.currentURL = url
                self.logNavigation("X_JS_LOCATION url=\(url.absoluteString)")
                if !XNavigationPolicy.isMessagesURL(url) {
                    self.clearMessagesCover()
                }
            case "clickedLink":
                guard message.frameInfo.isMainFrame,
                      let raw = payload["url"] as? String,
                      let url = URL(string: raw) else { return }
                self.grantConversationLink(url, sourceURL: self.currentURL ?? self.webView.url)
            case "sessionState":
                if let raw = payload["status"] as? String,
                   let status = XSessionStatus(rawValue: raw) {
                    self.sessionStatus = status
                }
            default:
                break
            }
        }
    }
}

private final class XWebViewWithoutInputAccessory: WKWebView {
    override var inputAccessoryView: UIView? { nil }
}

private final class WeakXScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

struct XWebView: UIViewRepresentable {
    let session: XWebSession
    let initialURL: URL?
    let mode: XMode
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
