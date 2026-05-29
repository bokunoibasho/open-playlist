import Foundation
import OSLog

/// Where downloaded media lives on disk and how its filename is derived
/// (Phase 7, DESIGN.md §6.6). Files go under Application Support so they are not
/// user-visible, and are excluded from iCloud/iTunes backup because a download is
/// always re-fetchable from its source.
///
/// `Track` stores only the *filename* (`downloadFileName`), never an absolute
/// path: the app container path changes between launches/updates, so absolute
/// `file://` URLs would dangle. The absolute URL is rebuilt here on demand.
enum DownloadLocations {
    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "Downloads")

    /// `Application Support/Downloads/`, created on first access and excluded
    /// from backup.
    static var directory: URL {
        let base = URL.applicationSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        ensureExists(base)
        return base
    }

    private static func ensureExists(_ url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            var mutable = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutable.setResourceValues(values)
        } catch {
            logger.error("Failed to create downloads directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A fresh, collision-free filename for a finished download, e.g.
    /// `<uuid>.mp4`. Extension is inferred from the response so the on-disk file
    /// keeps a meaningful type; defaults to `mp4` (YouTube progressive itag 18).
    static func makeFileName(for response: URLResponse?) -> String {
        "\(UUID().uuidString).\(fileExtension(for: response))"
    }

    private static func fileExtension(for response: URLResponse?) -> String {
        if let name = response?.suggestedFilename {
            let ext = (name as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        if let url = response?.url {
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        switch response?.mimeType?.lowercased() {
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
        case "audio/mpeg": return "mp3"
        case "video/webm", "audio/webm": return "webm"
        case "video/mp4": return "mp4"
        default: return "mp4"
        }
    }
}
