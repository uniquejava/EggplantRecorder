import AppKit
import AVFoundation
import Foundation

struct RecordingEntry: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let duration: TimeInterval
    let size: Int64
    let kind: RecordingKind
    let date: Date

    var formattedDuration: String {
        MediaProbe.formatClock(duration)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

enum RecordingsLibrary {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/EggplantRecorder", isDirectory: true)
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    static func makeOutputURL(kind: RecordingKind, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "\(kind.filePrefix)-\(formatter.string(from: date)).mp4"
        return directoryURL.appendingPathComponent(name)
    }

    static func list() async -> [RecordingEntry] {
        try? ensureDirectory()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [RecordingEntry] = []
        for url in urls where url.pathExtension.lowercased() == "mp4" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? Date()
            let duration = await MediaProbe.duration(of: url)
            let base = url.deletingPathExtension().lastPathComponent
            entries.append(
                RecordingEntry(
                    name: base,
                    path: url.path,
                    duration: duration,
                    size: size,
                    kind: .from(filename: base),
                    date: date
                )
            )
        }
        return entries.sorted { $0.date > $1.date }
    }

    static func delete(path: String) throws {
        try ensureLibraryPath(path)
        var trashed: NSURL?
        try FileManager.default.trashItem(
            at: URL(fileURLWithPath: path),
            resultingItemURL: &trashed
        )
    }

    /// Next free `Name-Edit.mp4` (then `-2`, `-3`, …) in the library.
    static func makeEditOutputURL(from path: String) throws -> URL {
        try ensureLibraryPath(path)
        try ensureDirectory()
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix("-Edit") ? base : "\(base)-Edit"
        var candidate = directoryURL.appendingPathComponent("\(stem).mp4")
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        var n = 2
        while true {
            candidate = directoryURL.appendingPathComponent("\(stem)-\(n).mp4")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            n += 1
        }
    }

    /// Renames the file's base name (`.mp4` is kept). Returns the new absolute path.
    @discardableResult
    static func rename(path: String, to newBaseName: String) throws -> String {
        try ensureLibraryPath(path)
        let cleaned = sanitizeBaseName(newBaseName)
        guard !cleaned.isEmpty else {
            throw NSError(
                domain: "RecordingsLibrary",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty."]
            )
        }

        let source = URL(fileURLWithPath: path)
        let destination = directoryURL.appendingPathComponent(cleaned + ".mp4")
        if source.standardizedFileURL == destination.standardizedFileURL {
            return path
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw NSError(
                domain: "RecordingsLibrary",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "A recording named “\(cleaned)” already exists."]
            )
        }
        try FileManager.default.moveItem(at: source, to: destination)
        return destination.path
    }

    /// Strips extension / path pieces and rejects characters illegal in a single path component.
    static func sanitizeBaseName(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(".mp4") {
            base = String(base.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        base = base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        return base
    }

    static func revealInFinder(path: String) throws {
        try ensureLibraryPath(path)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Open with the default app (usually QuickTime for MP4).
    static func play(path: String) throws {
        try ensureLibraryPath(path)
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                Self.presentOpenError(error, path: path)
            }
        }
    }

    /// Finder Spacebar-style Quick Look (`QLPreviewPanel`), not Preview.app.
    @MainActor
    static func quickLook(path: String, neighbors: [String] = []) throws {
        try ensureLibraryPath(path)
        for neighbor in neighbors {
            try ensureLibraryPath(neighbor)
        }
        QuickLookController.shared.preview(path: path, neighbors: neighbors)
    }

    private static func presentOpenError(_ error: Error, path: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Could not open recording"
            alert.informativeText = "\(error.localizedDescription)\n\n\(path)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private static func ensureLibraryPath(_ path: String) throws {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let root = directoryURL.standardizedFileURL
        if urlIsInside(file, root: root) { return }

        let fileResolved = file.resolvingSymlinksInPath()
        let rootResolved = root.resolvingSymlinksInPath()
        guard urlIsInside(fileResolved, root: rootResolved) else {
            throw NSError(
                domain: "RecordingsLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Path is outside the recordings library."]
            )
        }
    }

    private static func urlIsInside(_ file: URL, root: URL) -> Bool {
        let rootPath = root.path
        let filePath = file.path
        if filePath == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return filePath.hasPrefix(prefix)
    }
}
