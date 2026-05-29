import OSLog
import WebKit

/// Brave-踏襲 media detection. Injects the vendored `PlaylistSwizzlerScript.js`
/// (disables MediaSource so progressive `src` URLs are exposed) and
/// `PlaylistScript.js` (reports media elements), bridging their
/// `window.__firefox__` expectations with a minimal shim and substituting the
/// `$<...>` / `SECURITY_TOKEN` placeholders the way Brave's `secureScript` does.
@MainActor
final class UserScriptMediaDetector: NSObject, MediaStreamDetecting {
    var onDetect: ((DetectedStream) -> Void)?

    private let uniqueID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let securityToken = UUID().uuidString
    private lazy var messageHandlerName = "PlaylistScript_\(uniqueID)"

    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "MediaDetection")

    func install(on controller: WKUserContentController) {
        for script in makeUserScripts() {
            controller.addUserScript(script)
        }
        controller.add(self, contentWorld: .page, name: messageHandlerName)
    }

    // MARK: - Script assembly

    private func makeUserScripts() -> [WKUserScript] {
        var scripts = [userScript(source: Self.bootstrapShim)]
        if let swizzler = loadBundledScript("PlaylistSwizzlerScript") {
            scripts.append(userScript(source: swizzler))
        }
        if let playlist = loadBundledScript("PlaylistScript") {
            scripts.append(userScript(source: secure(playlist)))
        }
        return scripts
    }

    private func userScript(source: String) -> WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
    }

    private func loadBundledScript(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Missing bundled UserScript \(name).js")
            return nil
        }
        return source
    }

    /// Mirrors Brave's `secureScript`: replaces the `$<...>` placeholders with
    /// per-instance identifiers and `SECURITY_TOKEN` with this instance's token.
    private func secure(_ script: String) -> String {
        var result = script
        let names = [
            "$<message_handler>": messageHandlerName,
            "$<tagUUID>": "tagId_\(uniqueID)",
            "$<playlistLongPressed>": "plp_\(uniqueID)",
            "$<playlistProcessDocumentLoad>": "ppdl_\(uniqueID)",
            "$<mediaCurrentTimeFromTag>": "mctft_\(uniqueID)",
        ]
        for (placeholder, value) in names {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result.replacingOccurrences(of: "SECURITY_TOKEN", with: "\"\(securityToken)\"")
    }

    /// Just enough of Brave's UserScript bootstrap for the vendored scripts:
    /// `window.__firefox__.includeOnce`, the `$` wrapper, and
    /// `$.postNativeMessage`. We skip Brave's closure-sealing security layer;
    /// spoofing is mitigated by the random handler name + security token.
    private static let bootstrapShim = """
    (function() {
      if (!window.__firefox__) { window.__firefox__ = {}; }
      function wrap(fn) { return fn; }
      wrap.postNativeMessage = function(handlerName, payload) {
        try {
          window.webkit.messageHandlers[handlerName].postMessage(payload);
        } catch (e) {}
      };
      if (!window.__firefox__.includeOnce) {
        window.__firefox__.__included = window.__firefox__.__included || {};
        window.__firefox__.includeOnce = function(name, fn) {
          if (window.__firefox__.__included[name]) { return; }
          window.__firefox__.__included[name] = true;
          if (typeof fn === "function") { fn(wrap); }
        };
      }
    })();
    """

    // MARK: - Message handling

    private func handle(message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        guard body["securityToken"] as? String == securityToken else {
            Self.logger.error("Rejected media message: missing/invalid security token")
            return
        }

        if let state = body["state"] as? String {
            Self.logger.debug("Page media state: \(state, privacy: .public)")
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let stream = try? JSONDecoder().decode(DetectedStream.self, from: data),
              !stream.src.isEmpty
        else {
            return
        }

        Self.logger.log(
            "Detected stream: type=\(stream.mimeType ?? "?", privacy: .public) dur=\(stream.duration ?? 0) detected=\(stream.detected ?? false) src=\(stream.src, privacy: .public)"
        )
        onDetect?(stream)
    }
}

extension UserScriptMediaDetector: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(message: message)
        }
    }
}
