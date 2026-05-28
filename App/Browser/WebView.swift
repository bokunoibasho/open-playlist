import SwiftUI
import WebKit

/// Hosts a model-owned WKWebView. Keeping the WKWebView (and its
/// WKWebViewConfiguration) outside SwiftUI lets Phase 2 inject UserScripts
/// and a WKScriptMessageHandler with full control.
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
