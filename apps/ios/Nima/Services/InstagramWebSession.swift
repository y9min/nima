import Foundation
import Observation
import SafariServices
import SwiftUI
import UIKit
import WebKit

enum InstagramSessionStatus: String, Equatable {
    case unknown
    case signingIn = "signing_in"
    case authenticated
}

@MainActor
@Observable
final class InstagramWebSession: NSObject {
    private(set) var webView: WKWebView!
    private(set) var canGoBack = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    private(set) var sessionStatus: InstagramSessionStatus = .unknown

    @ObservationIgnored private weak var protectionStore: InstagramProtectionStore?
    @ObservationIgnored private var mode: InstagramMode = .clean
    @ObservationIgnored private var grantedSharedURL: URL?
    @ObservationIgnored private var isSharedReelOverlayOpen = false
    @ObservationIgnored private var returnURLAfterSharedContent: URL?
    @ObservationIgnored private var healthCheckTask: Task<Void, Never>?
    @ObservationIgnored private var receivedHealthPing = false
    @ObservationIgnored private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    override init() {
        super.init()

        let controller = WKUserContentController()
        if let scriptURL = Bundle.main.url(forResource: "instagram_cleaner", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            controller.addUserScript(
                WKUserScript(
                    source: source,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false,
                    in: .defaultClient
                )
            )
        }
        controller.add(
            WeakInstagramScriptHandler(target: self),
            contentWorld: .defaultClient,
            name: "nimaInstagram"
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    func configure(store: InstagramProtectionStore) {
        protectionStore = store
    }

    func startIfNeeded(at initialURL: URL? = nil, mode initialMode: InstagramMode) {
        guard webView.url == nil else { return }
        mode = initialMode
        syncFilterState()
        updateNativeScrollLock()
        load(
            initialURL
                ?? (mode == .dmOnly
                    ? InstagramNavigationPolicy.inboxURL
                    : InstagramNavigationPolicy.homeURL)
        )
    }

    func updateMode(_ newMode: InstagramMode, forceNavigation: Bool = false) {
        let changed = mode != newMode
        mode = newMode
        syncFilterState()
        updateNativeScrollLock()

        guard changed || forceNavigation else { return }
        grantedSharedURL = nil
        isSharedReelOverlayOpen = false
        returnURLAfterSharedContent = nil
        updateNativeScrollLock()
        if newMode == .dmOnly {
            load(InstagramNavigationPolicy.inboxURL)
        } else {
            load(InstagramNavigationPolicy.homeURL)
        }
    }

    func goBack() {
        if (isSharedReelOverlayOpen || InstagramNavigationPolicy.isIndividualReelURL(webView.url)),
           let returnURLAfterSharedContent {
            clearSharedContentState()
            load(returnURLAfterSharedContent)
            return
        }

        if mode == .dmOnly {
            if webView.url != InstagramNavigationPolicy.inboxURL {
                clearSharedContentState()
                load(InstagramNavigationPolicy.inboxURL)
            }
            return
        }

        if webView.canGoBack {
            webView.goBack()
        }
    }

    func reload() {
        protectionStore?.setFilteringHealth(.checking)
        receivedHealthPing = false
        webView.reload()
    }

    func goHome() {
        grantedSharedURL = nil
        isSharedReelOverlayOpen = false
        returnURLAfterSharedContent = nil
        updateNativeScrollLock()
        syncFilterState()
        load(InstagramNavigationPolicy.homeURL)
    }

    @discardableResult
    func openLink(_ rawValue: String) -> Bool {
        guard let url = InstagramNavigationPolicy.instagramURL(from: rawValue) else { return false }

        if InstagramNavigationPolicy.isConversationLinkedDestination(url),
           InstagramNavigationPolicy.isInstagramHost(url.host) {
            returnURLAfterSharedContent = webView.url
            grantedSharedURL = url
            isSharedReelOverlayOpen = InstagramNavigationPolicy.isIndividualReelURL(url)
            updateNativeScrollLock()
            syncFilterState()
        }
        load(url)
        return true
    }

    func logOut() {
        load(URL(string: "https://www.instagram.com/accounts/logout/")!)
    }

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    private func handleBlockedNavigation() {
        AnalyticsService.shared.capture(
            "instagram_navigation_blocked",
            properties: ["mode": mode.rawValue]
        )

        // A pasted/shared post is a one-destination grant. If Instagram tries to
        // advance to a neighbouring Reel, keep the approved post open instead of
        // dropping the user on the home screen.
        if isSharedReelOverlayOpen, let grantedSharedURL {
            updateNativeScrollLock()
            syncFilterState()
            if !InstagramNavigationPolicy.sameResource(webView.url, grantedSharedURL) {
                load(grantedSharedURL)
            }
            return
        }

        grantedSharedURL = nil
        isSharedReelOverlayOpen = false
        returnURLAfterSharedContent = nil
        updateNativeScrollLock()
        load(mode == .dmOnly ? InstagramNavigationPolicy.inboxURL : InstagramNavigationPolicy.homeURL)
    }

    private func grantConversationDestination(_ url: URL) {
        guard InstagramNavigationPolicy.isMessagesURL(webView.url),
              InstagramNavigationPolicy.isConversationLinkedDestination(url) else { return }
        returnURLAfterSharedContent = webView.url
        grantedSharedURL = url
        updateNativeScrollLock()
        syncFilterState()
    }

    private func grantProfileReelDestination(_ url: URL, sourceURL: URL?) {
        guard mode == .clean,
              InstagramNavigationPolicy.isIndividualReelURL(url),
              InstagramNavigationPolicy.isProfileURL(sourceURL) else { return }
        returnURLAfterSharedContent = sourceURL
        grantedSharedURL = url
        isSharedReelOverlayOpen = true
        updateNativeScrollLock()
        syncFilterState()
    }

    private func armSharedReelOverlay(_ url: URL?) {
        let sourceURL = webView.url
        let isDMReel = mode == .dmOnly && InstagramNavigationPolicy.isMessagesURL(sourceURL)
        let isProfileReel = mode == .clean && InstagramNavigationPolicy.isProfileURL(sourceURL)
        guard isDMReel || isProfileReel else { return }

        if returnURLAfterSharedContent == nil {
            returnURLAfterSharedContent = sourceURL
        }
        if InstagramNavigationPolicy.isIndividualReelURL(url) {
            grantedSharedURL = url
        }
        isSharedReelOverlayOpen = true
        updateNativeScrollLock()
        syncFilterState()
    }

    private func clearSharedContentState() {
        grantedSharedURL = nil
        isSharedReelOverlayOpen = false
        returnURLAfterSharedContent = nil
        updateNativeScrollLock()
        syncFilterState()
    }

    private func clearSharedContentStateIfReturned(to url: URL?) {
        guard let returnURLAfterSharedContent,
              InstagramNavigationPolicy.sameResource(url, returnURLAfterSharedContent) else { return }
        clearSharedContentState()
    }

    private func updateNativeScrollLock() {
        let locksSharedReel = isSharedReelOverlayOpen
            || InstagramNavigationPolicy.isIndividualReelURL(grantedSharedURL)
        // The Reel carousel can advance without a URL navigation, so disable
        // WebKit's native pan scrolling while the approved Reel is open. Page
        // layout and media loading continue while user-driven scrolling is off.
        webView.scrollView.isScrollEnabled = !locksSharedReel
        webView.scrollView.bounces = !locksSharedReel
        webView.scrollView.alwaysBounceVertical = !locksSharedReel
    }

    private func syncFilterState() {
        let sharedURL: Any
        if let value = grantedSharedURL?.absoluteString {
            sharedURL = value
        } else {
            sharedURL = NSNull()
        }
        let payload: [String: Any] = [
            "mode": mode.rawValue,
            "sharedURL": sharedURL,
            "sharedReelOpen": isSharedReelOverlayOpen
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.__nimaConfigure && window.__nimaConfigure(\(json))",
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
        currentURL = webView.url
    }

    private func scheduleHealthCheck(for url: URL?) {
        healthCheckTask?.cancel()

        guard mode == .clean,
              InstagramNavigationPolicy.isInstagramHost(url?.host),
              !InstagramNavigationPolicy.isMessagesURL(url),
              url?.path.contains("login") != true,
              url?.path.contains("challenge") != true else {
            protectionStore?.setFilteringHealth(.healthy)
            return
        }

        if receivedHealthPing {
            protectionStore?.setFilteringHealth(.healthy)
            return
        }

        healthCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.receivedHealthPing else { return }
            self.protectionStore?.setFilteringHealth(.limited)
            AnalyticsService.shared.capture("instagram_filter_health_failed")
            self.updateMode(.dmOnly, forceNavigation: true)
        }
    }
}

extension InstagramWebSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Instagram injects this advertising pixel as a background iframe during
        // login. Drop it before the external-link policy can promote it to Safari.
        guard !InstagramNavigationPolicy.isPaidAdsTrackingURL(url) else {
            decisionHandler(.cancel)
            return
        }

        let sourceURL = navigationAction.sourceFrame.request.url ?? webView.url
        grantProfileReelDestination(url, sourceURL: sourceURL)

        let action = InstagramNavigationPolicy.action(
            for: url,
            mode: mode,
            sourceURL: sourceURL,
            grantedSharedURL: grantedSharedURL
        )
        switch action {
        case .allow:
            decisionHandler(.allow)
        case .block:
            decisionHandler(.cancel)
            handleBlockedNavigation()
        case .openExternal:
            decisionHandler(.cancel)
            if shouldOpenExternal(navigationAction) {
                UIApplication.shared.open(url)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        healthCheckTask?.cancel()
        receivedHealthPing = false
        if let url = webView.url,
           InstagramNavigationPolicy.isAuthenticationURL(url) {
            sessionStatus = .signingIn
        }
        protectionStore?.setFilteringHealth(.checking)
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState()
        clearSharedContentStateIfReturned(to: webView.url)
        syncFilterState()
        scheduleHealthCheck(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateNavigationState()
    }
}

extension InstagramWebSession: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let safeFilename = (suggestedFilename as NSString).lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(safeFilename)")
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)),
              let presenter = Self.topViewController() else { return }
        let share = UIActivityViewController(activityItems: [destination], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 1, height: 1)
        }
        presenter.present(share, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

extension InstagramWebSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        guard !InstagramNavigationPolicy.isPaidAdsTrackingURL(url) else { return nil }
        grantProfileReelDestination(url, sourceURL: webView.url)
        let action = InstagramNavigationPolicy.action(
            for: url,
            mode: mode,
            sourceURL: webView.url,
            grantedSharedURL: grantedSharedURL
        )
        if action == .allow {
            webView.load(navigationAction.request)
        } else if action == .openExternal, shouldOpenExternal(navigationAction) {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(InstagramNavigationPolicy.isInstagramHost(origin.host) ? .prompt : .deny)
    }
}

private extension InstagramWebSession {
    func shouldOpenExternal(_ navigationAction: WKNavigationAction) -> Bool {
        guard navigationAction.navigationType == .linkActivated,
              navigationAction.sourceFrame.isMainFrame else { return false }
        return navigationAction.targetFrame?.isMainFrame ?? true
    }
}

extension InstagramWebSession: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch message.body {
            case let payload as [String: Any]:
                let event = payload["event"] as? String
                if event == "health" {
                    self.receivedHealthPing = true
                    self.healthCheckTask?.cancel()
                    self.protectionStore?.setFilteringHealth(.healthy)
                } else if event == "sessionState",
                          let rawStatus = payload["status"] as? String,
                          let status = InstagramSessionStatus(rawValue: rawStatus) {
                    self.sessionStatus = status
                } else if event == "linkActivated",
                          let rawURL = payload["url"] as? String,
                          let url = URL(string: rawURL, relativeTo: self.webView.url)?.absoluteURL {
                    self.grantConversationDestination(url)
                    self.grantProfileReelDestination(url, sourceURL: self.webView.url)
                } else if event == "sharedReelOpened" {
                    let url = (payload["url"] as? String)
                        .flatMap { URL(string: $0, relativeTo: self.webView.url)?.absoluteURL }
                    self.armSharedReelOverlay(url)
                } else if event == "locationChanged",
                          let rawURL = payload["url"] as? String,
                          let url = URL(string: rawURL) {
                    if InstagramNavigationPolicy.action(
                              for: url,
                              mode: self.mode,
                              sourceURL: self.currentURL,
                              grantedSharedURL: self.grantedSharedURL
                    ) == .block {
                        self.handleBlockedNavigation()
                    } else {
                        self.clearSharedContentStateIfReturned(to: url)
                    }
                } else if event == "blockedClientNavigation" {
                    self.handleBlockedNavigation()
                } else if event == "dmBack" {
                    let returnURL = self.isSharedReelOverlayOpen
                        ? (self.returnURLAfterSharedContent ?? InstagramNavigationPolicy.inboxURL)
                        : InstagramNavigationPolicy.inboxURL
                    self.clearSharedContentState()
                    self.load(returnURL)
                } else if event == "reelFinished" {
                    // In DM-only, a shared Reel is a temporary message attachment and
                    // returns to the conversation when playback ends. On a profile,
                    // leave the single Reel open so the user can replay or go back.
                    if self.mode == .dmOnly {
                        let returnURL = self.returnURLAfterSharedContent ?? InstagramNavigationPolicy.inboxURL
                        self.clearSharedContentState()
                        self.load(returnURL)
                    }
                }
            default:
                break
            }
        }
    }
}

private final class WeakInstagramScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

struct InstagramWebView: UIViewRepresentable {
    let session: InstagramWebSession
    let mode: InstagramMode
    let initialURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        session.startIfNeeded(at: initialURL, mode: mode)
        return session.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        session.updateMode(mode)
    }
}
