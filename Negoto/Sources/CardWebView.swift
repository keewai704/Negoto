import SwiftUI
import UIKit
import WebKit

/// Lets SwiftUI code talk to the web view (e.g. read the typed answer).
@MainActor
final class CardWebController {
    fileprivate weak var webView: WKWebView?

    func typedAnswer() async -> String {
        guard let webView else { return "" }
        let value = try? await webView.evaluateJavaScript("window.negotoTypedAnswer ? negotoTypedAnswer() : ''")
        return value as? String ?? ""
    }

    func run(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// Displays a card page. The HTML is written next to the media files so that relative
/// references (`<img src="foo.jpg">`, CSS `url()`, `<script src="_x.js">`) work exactly as in Anki.
struct CardWebView: UIViewRepresentable {
    var html: String
    var mediaFolder: URL
    var readAccessRoot: URL
    var zoom: Double = 1
    /// Space taken by floating controls above/below the card (content scrolls underneath them).
    var contentInsets = EdgeInsets()
    var controller: CardWebController?
    var onMessage: ([String: Any]) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(WeakMessageHandler(context.coordinator), name: "negoto")
        config.preferences.isElementFullscreenEnabled = true
        config.dataDetectorTypes = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        context.coordinator.webView = webView
        controller?.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        controller?.webView = webView
        if abs(webView.pageZoom - zoom) > 0.001 { webView.pageZoom = zoom }
        let insets = UIEdgeInsets(top: contentInsets.top, left: contentInsets.leading,
                                  bottom: contentInsets.bottom, right: contentInsets.trailing)
        if insets != .zero {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            let scrollView = webView.scrollView
            if scrollView.contentInset != insets {
                // Insets often arrive after the page loaded (header measured later): keep a page that
                // sits at the top pinned to the top, instead of leaving its first lines under the header.
                let wasAtTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1
                scrollView.contentInset = insets
                if wasAtTop { scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -insets.top), animated: false) }
                webView.scrollView.verticalScrollIndicatorInsets = insets
            }
        }
        context.coordinator.load(html, in: webView, mediaFolder: mediaFolder, readAccessRoot: readAccessRoot)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "negoto")
        coordinator.cleanup()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onMessage: ([String: Any]) -> Void = { _ in }
        private var loadedHTML: String?
        private var pageFile: URL?
        private let pageID = UUID().uuidString

        func load(_ html: String, in webView: WKWebView, mediaFolder: URL, readAccessRoot: URL) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            let file = mediaFolder.appendingPathComponent(".negoto-card-\(pageID).html")
            do {
                try Data(html.utf8).write(to: file, options: .atomic)
                pageFile = file
                webView.loadFileURL(file, allowingReadAccessTo: readAccessRoot)
            } catch {
                webView.loadHTMLString(html, baseURL: mediaFolder)
            }
        }

        func cleanup() {
            if let pageFile { try? FileManager.default.removeItem(at: pageFile) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            onMessage(body)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.isFileURL || url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" {
                // Allow our own page and in-page anchors; block navigating to other local files.
                if navigationAction.navigationType == .linkActivated, url.isFileURL, url.path != pageFile?.path {
                    return .cancel
                }
                return .allow
            }
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                // External links (dictionary lookups etc.) open in the browser.
                if ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                    _ = await UIApplication.shared.open(url)
                }
                return .cancel
            }
            // Sub-resources/iframes from the web are allowed (e.g. embedded fonts or videos).
            return .allow
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Start below the floating header.
            let top = webView.scrollView.contentInset.top
            if top > 0 { webView.scrollView.setContentOffset(CGPoint(x: 0, y: -top), animated: false) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Reload after the web content process was killed (e.g. memory pressure).
            if let pageFile { webView.loadFileURL(pageFile, allowingReadAccessTo: pageFile.deletingLastPathComponent().deletingLastPathComponent()) }
        }
    }
}

/// Breaks the retain cycle between WKUserContentController and the coordinator.
@MainActor
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
