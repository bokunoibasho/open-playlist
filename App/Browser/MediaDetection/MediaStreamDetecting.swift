import WebKit

/// Detects playable media streams within a web page (DESIGN.md §6.2). The
/// UserScript implementation follows Brave; the design's `resolve(_:)` half
/// (re-resolving a saved Track for playback) lands in Phase 5 with playback.
@MainActor
protocol MediaStreamDetecting: AnyObject {
    /// Called on the main actor for each media stream detected in the page.
    var onDetect: ((DetectedStream) -> Void)? { get set }

    /// Registers the detection UserScripts and message handler on a web view's
    /// content controller. Call before the `WKWebView` is created.
    func install(on controller: WKUserContentController)
}
