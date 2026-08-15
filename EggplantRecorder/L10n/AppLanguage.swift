import AppKit
import Foundation

/// User-facing language preference (mirrors EggplantTinyPNG / EggplantShot).
enum AppLanguagePreference: String, CaseIterable, Identifiable, Hashable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    /// Endonyms for concrete languages (always native script); only "Follow System" is localized.
    var menuTitle: String {
        switch self {
        case .system: return L10n.tr("lang.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

/// Persist language via `AppleLanguages` so `String(localized:)` / xcstrings pick it up after relaunch.
enum AppLanguage {
    private static let preferenceKey = "appLanguagePreference"

    static var preference: AppLanguagePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: preferenceKey)
                ?? AppLanguagePreference.system.rawValue
            return AppLanguagePreference(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
            applyAppleLanguages(newValue)
        }
    }

    static var resolvedCode: String {
        switch preference {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system: return systemPrefersSimplifiedChinese ? "zh-Hans" : "en"
        }
    }

    static var systemPrefersSimplifiedChinese: Bool {
        for identifier in Locale.preferredLanguages {
            let id = identifier.lowercased()
            if id.hasPrefix("zh-hans") || id.hasPrefix("zh-cn") { return true }
            if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw")
                || id.hasPrefix("zh-hk") || id.hasPrefix("zh-mo") { return false }
        }
        let language = Locale.current.language
        guard language.languageCode?.identifier == "zh" else { return false }
        if language.script?.identifier == "Hans" { return true }
        if language.script?.identifier == "Hant" { return false }
        return language.region?.identifier == "CN"
    }

    static func applyAppleLanguages(_ preference: AppLanguagePreference) {
        switch preference {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .simplifiedChinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    @MainActor
    static func setPreferenceAndRelaunch(_ preference: AppLanguagePreference) {
        guard preference != self.preference else { return }
        self.preference = preference
        relaunch()
    }

    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale(identifier: AppLanguage.resolvedCode), arguments: args)
    }
}
