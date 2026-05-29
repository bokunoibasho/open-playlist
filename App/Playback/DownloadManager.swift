import Foundation
import Observation
import OSLog
import SwiftData

/// Downloads a Track's media for offline playback (Phase 7, DESIGN.md §6.6).
/// Progressive only: re-resolve the stream URL (same mechanism playback uses),
/// then pull it to `DownloadLocations.directory` with a foreground URLSession
/// download task. Once finished the Track's `downloadFileName` is set and
/// playback plays from disk without re-resolving.
///
/// Out of scope (see DESIGN/Issues): HLS (`AVAssetDownloadURLSession`) and
/// background continuation — closing/suspending the app cancels in-flight tasks.
@MainActor
@Observable
final class DownloadManager: NSObject {
    enum State: Equatable {
        case downloading(Double)   // 0...1 fraction
        case failed(String)
    }

    /// Per-track transient state. A *finished* download is reflected by the
    /// persisted `Track.downloadFileName`, not kept here.
    private(set) var states: [PersistentIdentifier: State] = [:]

    @ObservationIgnored private let resolver: any StreamResolver
    @ObservationIgnored private lazy var session = URLSession(
        configuration: .default, delegate: self, delegateQueue: nil
    )
    @ObservationIgnored private var taskByTrack: [PersistentIdentifier: URLSessionTask] = [:]
    @ObservationIgnored private var trackByTask: [Int: Track] = [:]

    private static let logger = Logger(subsystem: "com.openplaylist.app", category: "Downloads")

    /// Its own resolver so the offscreen web view never contends with playback's.
    init(resolver: any StreamResolver = UserScriptStreamResolver()) {
        self.resolver = resolver
        super.init()
    }

    // MARK: - Queries

    func state(for track: Track) -> State? { states[track.persistentModelID] }

    func isDownloaded(_ track: Track) -> Bool {
        guard let url = track.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Commands

    func download(_ track: Track) {
        let id = track.persistentModelID
        if case .downloading = states[id] { return }
        guard !isDownloaded(track) else { return }

        states[id] = .downloading(0)
        // @MainActor so the post-resolve continuation mutates download state on
        // the main actor (consistent with Issue #21's main-actor hop fix).
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let url = try await self.resolver.resolve(track)
                // A cancel may have landed while resolving.
                guard case .downloading = self.states[id] else { return }
                let task = self.session.downloadTask(with: url)
                self.taskByTrack[id] = task
                self.trackByTask[task.taskIdentifier] = track
                task.resume()
            } catch is CancellationError {
                self.states[id] = nil
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Self.logger.error("Download resolve failed: \(message, privacy: .public)")
                self.states[id] = .failed(message)
            }
        }
    }

    func cancel(_ track: Track) {
        let id = track.persistentModelID
        if let task = taskByTrack[id] {
            task.cancel()
            trackByTask[task.taskIdentifier] = nil
            taskByTrack[id] = nil
        }
        states[id] = nil
    }

    func removeDownload(_ track: Track) {
        cancel(track)
        if let url = track.localFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        track.downloadFileName = nil
        try? track.modelContext?.save()
    }

    // MARK: - Delegate hand-offs (main actor)

    private func progress(taskID: Int, fraction: Double) {
        guard let track = trackByTask[taskID] else { return }
        states[track.persistentModelID] = .downloading(fraction)
    }

    private func complete(taskID: Int, fileName: String) {
        guard let track = trackByTask[taskID] else { return }
        let id = track.persistentModelID
        let url = DownloadLocations.directory.appendingPathComponent(fileName)
        trackByTask[taskID] = nil
        taskByTrack[id] = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Self.validatePlayableFile(at: url)
                track.downloadFileName = fileName
                try track.modelContext?.save()
                states[id] = nil
            } catch {
                try? FileManager.default.removeItem(at: url)
                track.downloadFileName = nil
                states[id] = .failed(Self.message(for: error))
            }
        }
    }

    private func fail(taskID: Int, message: String) {
        guard let track = trackByTask[taskID] else { return }
        trackByTask[taskID] = nil
        taskByTrack[track.persistentModelID] = nil
        states[track.persistentModelID] = .failed(message)
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move synchronously: `location` is removed once this method returns.
        let fileName = DownloadLocations.makeFileName(for: downloadTask.response)
        let destination = DownloadLocations.directory.appendingPathComponent(fileName)
        let taskID = downloadTask.taskIdentifier
        do {
            try Self.validateResponse(downloadTask.response)
            try Self.validateNonEmptyFile(at: location)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            let message = Self.message(for: error)
            Task { @MainActor [weak self] in self?.fail(taskID: taskID, message: message) }
            return
        }
        Task { @MainActor [weak self] in self?.complete(taskID: taskID, fileName: fileName) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let taskID = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in self?.progress(taskID: taskID, fraction: fraction) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // Success lands in didFinishDownloadingTo; an explicit cancel is already
        // cleared. Report only genuine failures.
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        let taskID = task.taskIdentifier
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.fail(taskID: taskID, message: message) }
    }
}

private enum DownloadValidationError: LocalizedError {
    case badStatus(Int)
    case unsupportedMime(String)
    case emptyFile
    case notPlayable

    var errorDescription: String? {
        switch self {
        case .badStatus(let status):
            "ダウンロードに失敗しました (HTTP \(status))"
        case .unsupportedMime(let mime):
            "この形式はローカル再生に対応していません (\(mime))"
        case .emptyFile:
            "ダウンロードしたファイルが空でした"
        case .notPlayable:
            "ダウンロードしたファイルを再生できません"
        }
    }
}

private extension DownloadManager {
    nonisolated static func validateResponse(_ response: URLResponse?) throws {
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw DownloadValidationError.badStatus(http.statusCode)
        }

        if response?.url?.pathExtension.lowercased() == "m3u8" {
            throw DownloadValidationError.unsupportedMime("application/x-mpegURL")
        }

        guard let mime = response?.mimeType?.lowercased(), !mime.isEmpty else { return }
        if mime.contains("webm") || mime.contains("mpegurl") || mime.contains("m3u8") {
            throw DownloadValidationError.unsupportedMime(mime)
        }
        if mime.hasPrefix("text/") || mime == "application/json" {
            throw DownloadValidationError.unsupportedMime(mime)
        }
    }

    nonisolated static func validateNonEmptyFile(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        if size <= 0 { throw DownloadValidationError.emptyFile }
    }

    static func validatePlayableFile(at url: URL) async throws {
        guard await MediaValidation.hasPlayableMedia(at: url) else {
            throw DownloadValidationError.notPlayable
        }
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
