import SwiftUI
import WebKit
import KLYCKit

/// A store's website, in a real browser view inside the app. Epic does not give other apps a catalogue to read (its servers
/// ask for a browser), and Steam's site is the only place for the cart and for signing in, so the page itself is shown: browsing, search and sign-in work as on the website, and what the
/// player types there goes to Epic and nowhere else. Sign-ins are kept by the web view like any browser keeps them.
@Observable @MainActor
final class WebStoreController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let home: URL
    let webView: WKWebView
    var canGoBack = false
    var canGoForward = false
    var loading = false
    var title = ""

    /// `chromeUserAgent`: Steam's web chat only starts voice in Chrome or Edge, so the chat window says it is Chrome. Nothing else changes.
    init(home: URL, chromeUserAgent: Bool = false) {
        self.home = home
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        if chromeUserAgent {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
        }
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    func loadIfNeeded() { if webView.url == nil { webView.load(URLRequest(url: home)) } }
    func open(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func goHome() { webView.load(URLRequest(url: home)) }
    var currentURL: URL? { webView.url }

    private func sync() { canGoBack = webView.canGoBack; canGoForward = webView.canGoForward; title = webView.title ?? "" }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { Task { @MainActor in self.loading = true; self.sync() } }
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in self.loading = false; self.sync() } }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.loading = false; self.sync() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.loading = false; self.sync() } }

    /// A link that wants a new window opens in the Mac's browser; only web links, nothing else.
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }

    /// The microphone, for Steam's voice chat only: asked of the player by macOS the first time, and only the Steam sites may use it.
    nonisolated func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                             type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        let host = origin.host.lowercased()
        let steam = host == "steamcommunity.com" || host.hasSuffix(".steamcommunity.com") || host == "steampowered.com" || host.hasSuffix(".steampowered.com")
        let wantsMic = type == .microphone
        Task { @MainActor in decisionHandler(steam && wantsMic ? .prompt : .deny) }
    }

    /// Pages inside the web view are web pages: a link to another app or file is not followed.
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        let allowed = ["http", "https", "about", "blob", "data"].contains(scheme)
        Task { @MainActor in decisionHandler(allowed ? .allow : .cancel) }
    }
}

struct WebStoreView: NSViewRepresentable {
    let controller: WebStoreController
    func makeNSView(context: Context) -> WKWebView { controller.loadIfNeeded(); return controller.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
