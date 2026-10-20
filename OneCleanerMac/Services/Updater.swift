import CryptoKit
import Darwin
import Foundation
import Security

/// Install and Relaunch: on the person's click, downloads the DMG the release names, checks it
/// and puts the new app in place of this copy, then starts it. Nothing is checked or downloaded in the background.
/// Anything that can't be done safely leaves this copy as it is; the website's Download stays.
enum Updater {
    private static let downloads = "/downloads/"

    /// Where this copy can replace itself: a bundle in a folder the person can write to, not one macOS runs from a
    /// temporary place (App Translocation) or from a disk image, and signed by a developer team to compare with.
    static var canInstallHere: Bool {
        let app = Bundle.main.bundlePath
        let folder = (app as NSString).deletingLastPathComponent
        return !app.contains("/AppTranslocation/") && !app.hasPrefix("/Volumes/") && access(folder, W_OK) == 0
            && access(app, W_OK) == 0 && ownTeam != nil
    }

    /// The release's DMG, only from this site's downloads over HTTPS (a local file only in DEBUG test runs).
    static func dmgURL(of release: UpdateChecker.Release) -> URL? {
        guard let url = release.dmg, url.pathExtension == "dmg" else { return nil }
        #if DEBUG
        if url.isFileURL { return url }
        #endif
        guard url.scheme == "https", url.host == UpdateChecker.pageURL.host, url.path.hasPrefix(downloads) else { return nil }
        return url
    }

    /// Downloads, checks and installs the release; nil when the new copy is in place (the caller relaunches), or
    /// why not. This copy is changed only in the last step, after every check passed.
    static func install(_ release: UpdateChecker.Release) async -> String? {
        let refused = String(localized: "The downloaded update didn't pass the check. This copy wasn't changed.",
                             comment: "Install and Relaunch error")
        guard let source = dmgURL(of: release), let expectedHash = release.sha256?.lowercased(), expectedHash.count == 64,
              let team = ownTeam, let bundleID = Bundle.main.bundleIdentifier else { return refused }
        let app = Bundle.main.bundlePath
        let folder = (app as NSString).deletingLastPathComponent
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("1Cleaner-update-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // Download.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 15 * 60
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (downloaded, response) = try await session.download(from: source)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return failed(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            }
            let dmg = work.appendingPathComponent("update.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)
            guard sha256(of: dmg.path) == expectedHash else { return refused }

            // Open the disk image where only this app sees it, and copy the app out next to this copy.
            let mount = work.appendingPathComponent("disk").path
            let attach = try await ProcessRunner.run(
                "/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount],
                timeout: .seconds(120))
            guard attach.succeeded else { return failed(attach.errorMessage) }
            let newApp = mount + "/1Cleaner.app"
            let staged = folder + "/.1Cleaner-update-" + UUID().uuidString.prefix(8) + ".app"
            let copied: String? = await {
                guard isGenuine(newApp, team: team, bundleID: bundleID), build(of: newApp) == release.build,
                      release.build > UpdateChecker.currentBuild else { return refused }
                let copy = try? await ProcessRunner.run("/usr/bin/ditto", [newApp, staged], timeout: .seconds(300))
                guard let copy, copy.succeeded else { return failed(copy?.errorMessage ?? "ditto") }
                return isGenuine(staged, team: team, bundleID: bundleID) ? nil : refused
            }()
            _ = try? await ProcessRunner.run("/usr/bin/hdiutil", ["detach", mount, "-force"], timeout: .seconds(60))
            if let copied {
                try? FileManager.default.removeItem(atPath: staged)
                return copied
            }

            // Swap: this copy steps aside under a hidden name, the new one takes its name; on failure it comes back.
            let previous = folder + "/.1Cleaner-previous-" + UUID().uuidString.prefix(8) + ".app"
            guard rename(app, previous) == 0 else {
                let reason = String(cString: strerror(errno))
                try? FileManager.default.removeItem(atPath: staged)
                return failed(reason)
            }
            guard rename(staged, app) == 0 else {
                let reason = String(cString: strerror(errno))
                _ = rename(previous, app)
                try? FileManager.default.removeItem(atPath: staged)
                return failed(reason)
            }
            // The old copy goes to the Trash under a name the Trash shows ("1Cleaner 1.2.0"), where it can be put back.
            let named = folder + "/1Cleaner \(UpdateChecker.currentVersion).app"
            let old = renamex_np(previous, named, UInt32(RENAME_EXCL)) == 0 ? named : previous
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: old), resultingItemURL: nil)
            return nil
        } catch {
            return failed(error.localizedDescription)
        }
    }

    private static func failed(_ reason: String) -> String {
        String(localized: "Couldn't install the update (\(reason)). This copy wasn't changed.",
               comment: "Install and Relaunch error. The placeholder is the system's or a tool's message.")
    }

    /// The developer team that signed this copy (none for a local build without a Developer ID).
    static var ownTeam: String? {
        var me: SecCode?
        var code: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Signed with a Developer ID of the same team as this copy, as the same app, and intact (every architecture and
    /// everything nested in it).
    private static func isGenuine(_ path: String, team: String, bundleID: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return false
        }
        let text = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] "
            + "exists and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement else {
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func build(of app: String) -> Int? {
        let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
        return (info?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    private static func sha256(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
