import Foundation

/// "Check for Updates…" (only when the person asks, never in the background). Reads one public
/// JSON file on the site; nothing about the Mac is sent.
enum UpdateChecker {
    static var feedURL: URL {
        #if DEBUG
        // `-updateFeed file:///…/version.json`: a test run of Install and Relaunch against a local release.
        if let feed = UserDefaults.standard.string(forKey: "updateFeed"), let url = URL(string: feed) { return url }
        #endif
        return URL(string: "https://onebuckapps.com/1cleaner-mac/version.json")!
    }
    static let pageURL = URL(string: "https://onebuckapps.com/1cleaner-mac/")!

    /// `{"version": "1.3.0", "build": 8, "url": "https://onebuckapps.com/1cleaner-mac/",
    ///   "dmg": "https://onebuckapps.com/downloads/1Cleaner-1.3.0-8.dmg", "sha256": "…"}`; Install and Relaunch
    /// needs `dmg` and `sha256` (`Updater`), the website's Download only `url`.
    struct Release: Decodable, Sendable {
        let version: String
        let build: Int
        let url: URL?
        let dmg: URL?
        let sha256: String?

        /// Where Download goes: the release's page only on this site over HTTPS, otherwise the app's page.
        var downloadURL: URL {
            guard let url, url.scheme == "https", url.host == UpdateChecker.pageURL.host else { return UpdateChecker.pageURL }
            return url
        }
    }

    enum Result: Sendable {
        case upToDate
        case available(Release)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    static func check() async -> Result {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(from: feedURL)
            guard feedURL.isFileURL || (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .failed(String(localized: "The update information isn't available right now. Try again later.",
                                      comment: "Check for Updates error"))
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            return release.build > currentBuild ? .available(release) : .upToDate
        } catch {
            return .failed(String(localized: "Couldn't check for updates: \(error.localizedDescription)",
                                  comment: "Check for Updates error. The placeholder is the system's error message."))
        }
    }
}
