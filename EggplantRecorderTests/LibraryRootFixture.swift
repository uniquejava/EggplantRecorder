import Foundation
import XCTest

@testable import EggplantRecorder

/// Points `RecordingsLibrary` at a throwaway folder for the duration of one test.
///
/// The library root is resolved from `UserDefaults.standard` on every access
/// (`RecordingsLibraryPaths.currentFolderURL`), and these tests run *inside* the real app, so the
/// real preference domain is what we are borrowing. `restore()` puts the user's value back —
/// always call it from an `addTeardownBlock` so a failing assertion can't leave the app's save
/// folder pointing at a temp directory.
final class LibraryRootFixture {
    let root: URL
    private let previousValue: String?

    init() throws {
        previousValue = UserDefaults.standard.string(forKey: RecordingsLibraryPaths.folderPathKey)
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EggplantRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        UserDefaults.standard.set(root.path, forKey: RecordingsLibraryPaths.folderPathKey)
    }

    func restore() {
        if let previousValue {
            UserDefaults.standard.set(previousValue, forKey: RecordingsLibraryPaths.folderPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RecordingsLibraryPaths.folderPathKey)
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates an empty file in the library root and returns its URL.
    @discardableResult
    func touch(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func path(_ name: String) -> String {
        root.appendingPathComponent(name).path
    }
}
