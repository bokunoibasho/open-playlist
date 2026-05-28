import Foundation

/// Resolves a saved `Track` into a currently-playable stream URL (DESIGN.md §6.2).
///
/// Stream URLs are short-lived and signed, so they are never persisted (DESIGN.md
/// §5). Instead the page is re-opened and the detection UserScript is re-run at
/// playback time. The detection half of the design's `StreamResolver` already
/// lives in `MediaStreamDetecting`; this protocol is the `resolve(_:)` half.
@MainActor
protocol StreamResolver {
    /// Re-resolves the live stream URL for `track`. Throws if no playable stream
    /// is found in time.
    func resolve(_ track: Track) async throws -> URL
}

enum StreamResolverError: LocalizedError {
    case timedOut
    case noPlayableStream
    case invalidStreamURL

    var errorDescription: String? {
        switch self {
        case .timedOut: "ストリームの解決がタイムアウトしました"
        case .noPlayableStream: "再生可能なストリームが見つかりませんでした"
        case .invalidStreamURL: "ストリーム URL が不正です"
        }
    }
}
