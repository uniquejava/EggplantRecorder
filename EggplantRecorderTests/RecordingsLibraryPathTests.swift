import XCTest

@testable import EggplantRecorder

/// Library path resolution, filename sanitising, and the path-traversal guard that stands between
/// a user-supplied name and `trashItem` / `moveItem`.
final class RecordingsLibraryPathTests: XCTestCase {
    private var fixture: LibraryRootFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fixture = try LibraryRootFixture()
        self.fixture = fixture
        addTeardownBlock { fixture.restore() }
    }

    // MARK: resolve

    func testMissingPathFallsBackToTheDefaultFolder() {
        XCTAssertEqual(
            RecordingsLibraryPaths.resolve(rawPath: nil),
            RecordingsLibraryPaths.defaultFolderURL
        )
    }

    func testBlankPathFallsBackToTheDefaultFolder() {
        XCTAssertEqual(
            RecordingsLibraryPaths.resolve(rawPath: ""),
            RecordingsLibraryPaths.defaultFolderURL
        )
        XCTAssertEqual(
            RecordingsLibraryPaths.resolve(rawPath: "   \n\t "),
            RecordingsLibraryPaths.defaultFolderURL
        )
    }

    func testDefaultFolderIsUnderMovies() {
        XCTAssertEqual(
            RecordingsLibraryPaths.defaultFolderURL.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies/EggplantRecorder").path
        )
    }

    func testExplicitPathIsUsedAndTrimmed() {
        XCTAssertEqual(
            RecordingsLibraryPaths.resolve(rawPath: "  /Users/someone/Clips  ").path,
            "/Users/someone/Clips"
        )
    }

    func testLibraryAndPreferencesResolveToTheSamePlace() {
        // Audit #4: the key + fallback rule now live in one helper. This is the test that would
        // fail if they ever drift apart again.
        XCTAssertEqual(RecordingsLibrary.directoryURL.path, fixture.root.path)
        XCTAssertEqual(
            RecordingsLibraryPaths.resolve(rawPath: fixture.root.path).path,
            RecordingsLibrary.directoryURL.path
        )
    }

    // MARK: sanitizeBaseName

    func testSanitizeStripsTheExtensionCaseInsensitively() {
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("Clip.mp4"), "Clip")
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("Clip.MP4"), "Clip")
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("  Clip.mp4  "), "Clip")
    }

    func testSanitizeKeepsAnInnerDot() {
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("v1.2 final"), "v1.2 final")
    }

    func testSanitizeCannotProduceMoreThanOnePathComponent() {
        // The result is appended to the library URL as a single component, so a separator has to go.
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("a/b"), "a-b")
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("../../etc/passwd"), "..-..-etc-passwd")
        XCTAssertFalse(RecordingsLibrary.sanitizeBaseName("../../etc/passwd").contains("/"))
    }

    func testSanitizeMapsTheFinderPathSeparator() {
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("2026:08:15"), "2026-08-15")
    }

    func testSanitizeDropsNulBytes() {
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("Clip\0evil"), "Clipevil")
    }

    func testSanitizeCanReturnEmptyForAWorthlessName() {
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName("   "), "")
        XCTAssertEqual(RecordingsLibrary.sanitizeBaseName(".mp4"), "")
    }

    // MARK: makeOutputURL

    func testOutputURLLandsInTheLibraryWithTheKindPrefix() {
        let url = RecordingsLibrary.makeOutputURL(kind: .area)
        XCTAssertEqual(url.deletingLastPathComponent().path, fixture.root.path)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Area-"))
        XCTAssertEqual(url.pathExtension, "mp4")
    }

    func testOutputURLUsesEachKindsPrefix() {
        XCTAssertTrue(RecordingsLibrary.makeOutputURL(kind: .screen).lastPathComponent.hasPrefix("Screen-"))
        XCTAssertTrue(RecordingsLibrary.makeOutputURL(kind: .window).lastPathComponent.hasPrefix("Window-"))
    }

    // MARK: makeEditOutputURL

    func testEditURLAddsTheEditSuffix() throws {
        try fixture.touch("Clip.mp4")
        let url = try RecordingsLibrary.makeEditOutputURL(from: fixture.path("Clip.mp4"))
        XCTAssertEqual(url.lastPathComponent, "Clip-Edit.mp4")
    }

    func testEditURLCountsUpWhenTaken() throws {
        try fixture.touch("Clip.mp4")
        try fixture.touch("Clip-Edit.mp4")
        XCTAssertEqual(
            try RecordingsLibrary.makeEditOutputURL(from: fixture.path("Clip.mp4")).lastPathComponent,
            "Clip-Edit-2.mp4"
        )

        try fixture.touch("Clip-Edit-2.mp4")
        XCTAssertEqual(
            try RecordingsLibrary.makeEditOutputURL(from: fixture.path("Clip.mp4")).lastPathComponent,
            "Clip-Edit-3.mp4"
        )
    }

    func testEditingAnEditDoesNotDoubleTheSuffix() throws {
        // Re-editing must not produce "Clip-Edit-Edit.mp4".
        try fixture.touch("Clip-Edit.mp4")
        XCTAssertEqual(
            try RecordingsLibrary.makeEditOutputURL(from: fixture.path("Clip-Edit.mp4")).lastPathComponent,
            "Clip-Edit-2.mp4"
        )
    }

    func testEditURLRejectsASourceOutsideTheLibrary() {
        let outside = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/NotOurs.mp4").path
        XCTAssertThrowsError(try RecordingsLibrary.makeEditOutputURL(from: outside))
    }

    // MARK: ensureLibraryPath — the traversal guard

    func testAcceptsAFileInTheLibraryRoot() {
        XCTAssertNoThrow(try RecordingsLibrary.ensureLibraryPath(fixture.path("Clip.mp4")))
    }

    func testAcceptsTheRootItself() {
        XCTAssertNoThrow(try RecordingsLibrary.ensureLibraryPath(fixture.root.path))
    }

    func testAcceptsANestedFile() {
        XCTAssertNoThrow(
            try RecordingsLibrary.ensureLibraryPath(fixture.path("sub/deeper/Clip.mp4"))
        )
    }

    func testRejectsAnAbsolutePathElsewhere() {
        XCTAssertThrowsError(try RecordingsLibrary.ensureLibraryPath("/etc/passwd"))
        XCTAssertThrowsError(
            try RecordingsLibrary.ensureLibraryPath(
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("secret.mp4").path
            )
        )
    }

    func testRejectsDotDotEscapes() {
        // Standardising resolves "..", so this lands beside the root rather than inside it.
        XCTAssertThrowsError(
            try RecordingsLibrary.ensureLibraryPath(fixture.path("../escaped.mp4"))
        )
        XCTAssertThrowsError(
            try RecordingsLibrary.ensureLibraryPath(fixture.path("sub/../../escaped.mp4"))
        )
    }

    func testRejectsASiblingWithTheRootAsAStringPrefix() {
        // "<root>Evil" shares a string prefix with "<root>" but is a different directory —
        // the guard appends a "/" before comparing precisely so this fails.
        XCTAssertThrowsError(
            try RecordingsLibrary.ensureLibraryPath(fixture.root.path + "Evil/Clip.mp4")
        )
    }

    func testAcceptsAnExistingFileThatOnlyResolvesInsideAfterFollowingSymlinks() throws {
        // The `resolvingSymlinksInPath()` fallback exists for this: a path that doesn't look like
        // it's under the root, but is once symlinks are followed. Delete / rename / Quick Look all
        // operate on files that exist, which is the case this covers.
        let link = try makeSymlinkToRoot()
        try fixture.touch("Clip.mp4")

        XCTAssertNoThrow(
            try RecordingsLibrary.ensureLibraryPath(link.appendingPathComponent("Clip.mp4").path)
        )
    }

    func testASymlinkedPathToAMissingFileIsRejected() throws {
        // Worth pinning because it's asymmetric and surprising: `resolvingSymlinksInPath()` only
        // resolves a symlink when the *whole* path exists, so the same symlinked location is
        // accepted for an existing file and rejected for one that hasn't been created yet.
        // Harmless today (recordings are always written to `directoryURL` directly), but it would
        // bite anything that validates an output path through a symlinked library folder.
        let link = try makeSymlinkToRoot()

        XCTAssertThrowsError(
            try RecordingsLibrary.ensureLibraryPath(link.appendingPathComponent("NotYet.mp4").path)
        )
    }

    private func makeSymlinkToRoot() throws -> URL {
        let link = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EggplantRecorderTests-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root)
        addTeardownBlock { try? FileManager.default.removeItem(at: link) }
        return link
    }

    // MARK: entry formatting

    func testEntryFormatsSizeAndDuration() {
        let entry = RecordingEntry(
            name: "Clip",
            path: fixture.path("Clip.mp4"),
            duration: 65,
            size: 1_048_576,
            kind: .screen,
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(entry.formattedDuration, "00:01:05")
        XCTAssertEqual(entry.id, entry.path)
        XCTAssertFalse(entry.formattedSize.isEmpty)
    }
}
