import AppKit

/// The app's language: macOS's language by default, or one chosen in About. Stored where macOS
/// keeps a per-app language (`AppleLanguages` in the app's own defaults, the same setting as System Settings ›
/// General › Language & Region › Applications), so it applies from the next launch.
enum AppLanguage {
    /// The languages 1Cleaner ships, in the picker's order, with their own names.
    static let all: [(code: String, name: String)] = [
        ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("fr", "Français"), ("id", "Bahasa Indonesia"),
        ("it", "Italiano"), ("nl", "Nederlands"), ("pl", "Polski"), ("pt-BR", "Português (Brasil)"),
        ("tr", "Türkçe"), ("vi", "Tiếng Việt"), ("ru", "Русский"), ("uk", "Українська"), ("ja", "日本語"),
        ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"),
    ]

    private static let key = "AppleLanguages"

    /// The chosen language code, or nil for "same as macOS".
    static var chosen: String? {
        guard let id = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: id)?[key] as? [String] else { return nil }
        return languages.first
    }

    /// The choice the app was launched with (read at launch by `AppModel`); the UI keeps that language until a
    /// restart.
    static let launchChoice: String? = chosen

    static func choose(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Opens a new copy of 1Cleaner and quits this one, so the new language applies. If macOS can't open the new
    /// copy, this one keeps running and `onFailure` says so.
    @MainActor
    static func relaunch(onFailure: (@MainActor @Sendable () -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            let opened = error == nil
            Task { @MainActor in
                if opened { NSApp.terminate(nil) } else { onFailure?() }
            }
        }
    }
}
