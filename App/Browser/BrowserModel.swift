import Observation
import WebKit

@MainActor
@Observable
final class BrowserModel {
    private(set) var currentURL: URL?
    private(set) var pageTitle = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(home: URL? = URL(string: "https://m.youtube.com")) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        startObserving()
        if let home {
            webView.load(URLRequest(url: home))
        }
    }

    func load(_ input: String) {
        guard let url = Self.normalizedURL(from: input) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    private func startObserving() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.isLoading = wv.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.progress = wv.estimatedProgress }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.pageTitle = wv.title ?? "" }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.currentURL = wv.url }
            },
        ]
    }

    /// Turns address-bar text into a URL: an explicit http(s) URL, a bare
    /// domain (prefixed with https://), or otherwise a DuckDuckGo search.
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return url
        }

        let looksLikeDomain = !trimmed.contains(" ") && trimmed.contains(".")
        if looksLikeDomain, let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}
