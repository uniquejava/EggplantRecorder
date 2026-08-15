import AppKit
import Combine
import Foundation

/// Single owner of "where do recordings live". Deliberately **not** actor-isolated: both
/// `AppPreferences` (main actor) and `RecordingsLibrary` (off the main actor) resolve the
/// library folder through here, so the key and the fallback rule can't drift apart.
enum RecordingsLibraryPaths {
    static let defaultFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/EggplantRecorder", isDirectory: true)

    static let folderPathKey = "click.yinsb.eggplantrecorder.libraryFolderPath"

    /// Blank / whitespace-only / unset all mean "use the default folder".
    static func resolve(rawPath: String?) -> URL {
        let trimmed = (rawPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultFolderURL
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    static var currentFolderURL: URL {
        resolve(rawPath: UserDefaults.standard.string(forKey: folderPathKey))
    }
}

/// UserDefaults-backed preferences shown in Preferences → General.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let libraryFolderPath = RecordingsLibraryPaths.folderPathKey
        static let displayRecordingTime = "click.yinsb.eggplantrecorder.displayRecordingTime"
        static let openFilesListAfterRecording = "click.yinsb.eggplantrecorder.openFilesListAfterRecording"
        static let openFilesListAfterEditing = "click.yinsb.eggplantrecorder.openFilesListAfterEditing"
        static let openFolderAfterEditing = "click.yinsb.eggplantrecorder.openFolderAfterEditing"
        static let deleteOriginalAfterEditing = "click.yinsb.eggplantrecorder.deleteOriginalAfterEditing"
        static let hideDockIcon = "click.yinsb.eggplantrecorder.hideDockIcon"
        static let frameRate = "click.yinsb.eggplantrecorder.captureFrameRate"
        static let resolution = "click.yinsb.eggplantrecorder.captureResolution"
        static let countdown = "click.yinsb.eggplantrecorder.captureCountdown"
        static let exportQuality = "click.yinsb.eggplantrecorder.exportQuality"
        static let exportAudioChannels = "click.yinsb.eggplantrecorder.exportAudioChannels"
        static let editPreviewSeconds = "click.yinsb.eggplantrecorder.editPreviewSeconds"
    }

    /// Absolute path, or empty for the default `~/Movies/EggplantRecorder`.
    @Published var libraryFolderPath: String {
        didSet { UserDefaults.standard.set(libraryFolderPath, forKey: Key.libraryFolderPath) }
    }

    @Published var displayRecordingTime: Bool {
        didSet { UserDefaults.standard.set(displayRecordingTime, forKey: Key.displayRecordingTime) }
    }

    @Published var openFilesListAfterRecording: Bool {
        didSet { UserDefaults.standard.set(openFilesListAfterRecording, forKey: Key.openFilesListAfterRecording) }
    }

    @Published var openFilesListAfterEditing: Bool {
        didSet { UserDefaults.standard.set(openFilesListAfterEditing, forKey: Key.openFilesListAfterEditing) }
    }

    @Published var openFolderAfterEditing: Bool {
        didSet { UserDefaults.standard.set(openFolderAfterEditing, forKey: Key.openFolderAfterEditing) }
    }

    @Published var deleteOriginalAfterEditing: Bool {
        didSet { UserDefaults.standard.set(deleteOriginalAfterEditing, forKey: Key.deleteOriginalAfterEditing) }
    }

    /// When true (default), Dock icon only appears while a window (Preferences / Files List / Edit) is up.
    @Published var hideDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(hideDockIcon, forKey: Key.hideDockIcon)
            guard !isBootstrapping else { return }
            AppActivation.applyPreferredPolicy()
        }
    }

    @Published var defaultFrameRate: CaptureFrameRate {
        didSet { UserDefaults.standard.set(defaultFrameRate.rawValue, forKey: Key.frameRate) }
    }

    @Published var defaultResolution: CaptureResolution {
        didSet { UserDefaults.standard.set(defaultResolution.rawValue, forKey: Key.resolution) }
    }

    @Published var defaultCountdown: CaptureCountdown {
        didSet { UserDefaults.standard.set(defaultCountdown.rawValue, forKey: Key.countdown) }
    }

    @Published var defaultExportQuality: ExportSettings.Quality {
        didSet { UserDefaults.standard.set(defaultExportQuality.rawValue, forKey: Key.exportQuality) }
    }

    @Published var defaultExportAudioChannels: ExportSettings.AudioChannels {
        didSet { UserDefaults.standard.set(defaultExportAudioChannels.rawValue, forKey: Key.exportAudioChannels) }
    }

    /// Length of the Editor “Preview” export clip (seconds).
    @Published var editPreviewSeconds: Int {
        didSet { UserDefaults.standard.set(editPreviewSeconds, forKey: Key.editPreviewSeconds) }
    }

    var libraryDirectoryURL: URL {
        RecordingsLibraryPaths.resolve(rawPath: libraryFolderPath)
    }

    var libraryFolderDisplayPath: String {
        libraryDirectoryURL.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    func defaultExportSettings() -> ExportSettings {
        var settings = ExportSettings()
        settings.quality = defaultExportQuality
        settings.audioChannels = defaultExportAudioChannels
        return settings
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where recorded files are saved by default."
        panel.directoryURL = libraryDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryFolderPath = url.path
        try? RecordingsLibrary.ensureDirectory()
    }

    func revealLibraryFolder() {
        try? RecordingsLibrary.ensureDirectory()
        NSWorkspace.shared.open(libraryDirectoryURL)
    }

    func resetLibraryFolder() {
        libraryFolderPath = ""
        try? RecordingsLibrary.ensureDirectory()
    }

    private var isBootstrapping = true

    private init() {
        let defaults = UserDefaults.standard

        libraryFolderPath = defaults.string(forKey: Key.libraryFolderPath) ?? ""

        displayRecordingTime = defaults.object(forKey: Key.displayRecordingTime) as? Bool ?? true
        openFilesListAfterRecording = defaults.object(forKey: Key.openFilesListAfterRecording) as? Bool ?? true
        openFilesListAfterEditing = defaults.object(forKey: Key.openFilesListAfterEditing) as? Bool ?? true
        openFolderAfterEditing = defaults.object(forKey: Key.openFolderAfterEditing) as? Bool ?? true
        deleteOriginalAfterEditing = defaults.bool(forKey: Key.deleteOriginalAfterEditing)
        hideDockIcon = defaults.object(forKey: Key.hideDockIcon) as? Bool ?? true

        let fps = defaults.integer(forKey: Key.frameRate)
        defaultFrameRate = CaptureFrameRate(rawValue: fps) ?? .fps30

        let res = defaults.string(forKey: Key.resolution) ?? ""
        defaultResolution = CaptureResolution(rawValue: res) ?? .native

        if defaults.object(forKey: Key.countdown) == nil {
            defaultCountdown = .none
        } else {
            defaultCountdown = CaptureCountdown(rawValue: defaults.integer(forKey: Key.countdown)) ?? .none
        }

        if let raw = defaults.string(forKey: Key.exportQuality),
           let quality = ExportSettings.Quality(rawValue: raw)
        {
            defaultExportQuality = quality
        } else {
            defaultExportQuality = .high
        }

        if let raw = defaults.string(forKey: Key.exportAudioChannels),
           let channels = ExportSettings.AudioChannels(rawValue: raw)
        {
            defaultExportAudioChannels = channels
        } else {
            defaultExportAudioChannels = .stereo
        }

        let preview = defaults.integer(forKey: Key.editPreviewSeconds)
        editPreviewSeconds = [15, 30, 60].contains(preview) ? preview : 30
        isBootstrapping = false
    }
}

/// Coordinates Dock visibility for this LSUIElement app.
@MainActor
enum AppActivation {
    static func preferForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drop back to accessory when Dock should stay hidden and no titled windows remain.
    static func preferBackgroundIfIdle(excluding excluded: NSWindow? = nil) {
        guard AppPreferences.shared.hideDockIcon else {
            NSApp.setActivationPolicy(.regular)
            return
        }
        let stillVisible = NSApp.windows.contains { win in
            win !== excluded && win.isVisible && win.styleMask.contains(.titled)
        }
        if !stillVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    static func applyPreferredPolicy() {
        if AppPreferences.shared.hideDockIcon {
            preferBackgroundIfIdle()
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
}
