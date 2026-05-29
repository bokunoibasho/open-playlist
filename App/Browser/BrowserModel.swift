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
    private(set) var detectedStreams: [DetectedStream] = []

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private let detector: any MediaStreamDetecting
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(
        home: URL? = URL(string: "https://m.youtube.com"),
        detector: any MediaStreamDetecting = UserScriptMediaDetector()
    ) {
        self.detector = detector

        let config = WKWebViewConfiguration()
        // Issue #7: コールド起動ごとに閲覧データ（履歴 / Cookie / キャッシュ / localStorage）を
        // 残さない。YouTube にログインしない運用なので非永続ストアで全消去して支障なし。
        // 非永続ストアはディスクに書かずプロセス生存中のみメモリ保持するため、新プロセス＝空、
        // バックグラウンド→復帰（同一プロセス）では維持、という Issue の受け入れ条件を満たす。
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        detector.install(on: config.userContentController)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true

        startObserving()
        detector.onDetect = { [weak self] stream in
            self?.addDetectedStream(stream)
        }
        if let home {
            webView.load(URLRequest(url: home))
        }
    }

    private func addDetectedStream(_ stream: DetectedStream) {
        guard !detectedStreams.contains(where: { $0.src == stream.src }) else { return }
        detectedStreams.append(stream)
    }

    private func handleURLChange(_ url: URL?) {
        if url?.absoluteString != currentURL?.absoluteString {
            detectedStreams.removeAll()
        }
        currentURL = url
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
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.canGoBack = wv?.canGoBack ?? false
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.canGoForward = wv?.canGoForward ?? false
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.isLoading = wv?.isLoading ?? false
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.progress = wv?.estimatedProgress ?? 0
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.pageTitle = wv?.title ?? ""
                }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                DispatchQueue.main.async { [weak self, weak wv] in
                    self?.handleURLChange(wv?.url)
                }
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
