import OSLog
import UIKit
import WebKit

/// Re-resolves a Track's live stream URL by re-opening its page in an offscreen
/// WKWebView and re-running the vendored detection UserScript — the same
/// mechanism the in-app browser uses, headless. Reuses `UserScriptMediaDetector`
/// and the `BrowserModel` web-view recipe so detection behaves identically.
@MainActor
final class UserScriptStreamResolver: NSObject, StreamResolver {
    private static let timeout: TimeInterval = 15
    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "StreamResolver")

    private let detector: any MediaStreamDetecting
    private let webView: WKWebView

    private var pending: CheckedContinuation<URL, Error>?
    private var targetVideoID: String?
    private var timeoutTask: Task<Void, Never>?

    init(detector: any MediaStreamDetecting = UserScriptMediaDetector()) {
        self.detector = detector

        let config = WKWebViewConfiguration()
        // Mirror BrowserModel.init: ephemeral store, inline + autoplay so the
        // page actually starts media (the trigger the detection script needs).
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        detector.install(on: config.userContentController)

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
    }

    func resolve(_ track: Track) async throws -> URL {
        // Defend against broken saved data (Issue #16): never feed a raw media URL
        // to the offscreen web view. Loading an expired googlevideo… stream URL
        // crashes the process. Only real web pages are resolvable; bail gracefully
        // otherwise so the UI shows an error instead of dying.
        guard Self.isResolvablePage(track.sourceURL) else {
            Self.logger.error("Refusing to resolve non-page URL \(track.sourceURL.absoluteString, privacy: .public)")
            throw StreamResolverError.noPlayableStream
        }

        // Cancel any resolve still in flight (e.g. rapid next/prev taps).
        finish(throwing: CancellationError())
        attachToWindowIfNeeded()

        let target = track.providerID
        Self.logger.log("Resolving stream for \(track.sourceURL.absoluteString, privacy: .public)")

        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            targetVideoID = target
            detector.onDetect = { [weak self] stream in
                self?.consider(stream)
            }
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeout))
                guard !Task.isCancelled else { return }
                self?.finish(throwing: StreamResolverError.timedOut)
            }
            webView.load(URLRequest(url: track.sourceURL))
        }
    }

    /// A headless WKWebView only runs page media reliably while it is in a
    /// window, so park it 1×1 and transparent behind everything rather than
    /// hiding it (which can suppress autoplay).
    private func attachToWindowIfNeeded() {
        guard webView.superview == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else {
            Self.logger.error("No window to host the resolver web view")
            return
        }
        webView.alpha = 0
        window.insertSubview(webView, at: 0)
    }

    /// A `sourceURL` is resolvable only if it's an http(s) *page* — not a media
    /// stream URL. `googlevideo.com` is YouTube's media CDN and the documented
    /// broken-data case from Issue #16.
    private static func isResolvablePage(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        if url.host()?.lowercased().contains("googlevideo.com") == true { return false }
        return true
    }

    private func consider(_ stream: DetectedStream) {
        guard pending != nil, !stream.src.isEmpty else { return }

        // When we know the YouTube videoID, require the reporting page to match
        // so we don't pick up a related/preview clip from the same document.
        if let target = targetVideoID {
            let pageID = stream.pageSrc
                .flatMap { URL(string: $0) }
                .flatMap(PlaylistStore.youTubeVideoID(from:))
            if let pageID, pageID != target { return }
        }

        guard let url = URL(string: stream.src) else {
            finish(throwing: StreamResolverError.invalidStreamURL)
            return
        }
        Self.logger.log("Resolved stream: \(url.absoluteString, privacy: .public)")
        finish(returning: url)
    }

    private func finish(returning url: URL) {
        guard let continuation = takePending() else { return }
        webView.stopLoading()
        continuation.resume(returning: url)
    }

    private func finish(throwing error: Error) {
        guard let continuation = takePending() else { return }
        continuation.resume(throwing: error)
    }

    private func takePending() -> CheckedContinuation<URL, Error>? {
        guard let continuation = pending else { return nil }
        pending = nil
        targetVideoID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        detector.onDetect = nil
        return continuation
    }
}

extension UserScriptStreamResolver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("Resolver navigation failed: \(error.localizedDescription, privacy: .public)")
        finish(throwing: StreamResolverError.noPlayableStream)
    }
}
