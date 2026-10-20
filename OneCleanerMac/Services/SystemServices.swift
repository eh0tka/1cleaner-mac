import AppKit
import Darwin
import Foundation

struct DiskSpace: Sendable, Equatable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(0, total - available) }

    /// The startup volume, as Finder reports it (purgeable space counts as available).
    static func current() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSpace(total: Int64(total), available: available)
    }
}

enum SystemAccess {
    /// Full Disk Access can't be queried; a protected file that opens proves it.
    static func hasFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let descriptor = open(probe, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func reveal(_ path: String) {
        if FileInfo.exists(path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).deletingLastPathComponent))
        }
    }

    /// Asks Finder to empty the Trash, so locked items, other volumes' Trash folders and Finder's own rules apply.
    /// macOS asks once whether 1Cleaner may control Finder.
    static func emptyTrash() async -> String? {
        // AppleScript waits 2 minutes for Finder's answer by default, and a Trash with many files (node_modules,
        // DerivedData) takes longer: the wait is raised so a slow emptying isn't reported as an error.
        let script = """
            with timeout of 3600 seconds
                tell application "Finder" to empty trash
            end timeout
            """
        do {
            let output = try await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: .seconds(3700))
            return output.succeeded ? nil : trashFailure(output)
        } catch {
            return error.localizedDescription
        }
    }

    /// Finder's error in plain words, without AppleScript's line numbers and codes.
    static func trashFailure(_ output: ProcessRunner.Output) -> String {
        if output.timedOut { return stillEmptying }
        let text = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = text.range(of: #"\((-?\d+)\)$"#, options: .regularExpression)
            .map { String(text[$0].dropFirst().dropLast()) }
        switch code {
        case "-1743":
            return String(localized: """
                macOS didn't allow 1Cleaner to control Finder. Allow it in System Settings › Privacy & Security › \
                Automation.
                """, comment: "Empty Trash error. Use macOS's own names of these System Settings sections.")
        case "-1712":
            return stillEmptying
        case "-128":
            return String(localized: "Emptying the Trash was stopped in Finder. What was already removed is gone.",
                          comment: "Empty Trash error")
        default:
            // "0:43: execution error: Finder got an error: The operation can’t be completed … (-8003)"
            var message = text
            if let range = message.range(of: "got an error: ") { message = String(message[range.upperBound...]) }
            if let range = message.range(of: #"\s*\(-?\d+\)$"#, options: .regularExpression) {
                message.removeSubrange(range)
            }
            if message.isEmpty { return output.errorMessage }
            let inUse = message.localizedCaseInsensitiveContains("in use")
            return inUse
                ? String(localized: """
                    Finder couldn't empty the whole Trash: \(message) Quit the app that uses it and empty the \
                    Trash again.
                    """, comment: "Empty Trash error. The placeholder is Finder's own message (a sentence), a file in use.")
                : String(localized: """
                    Finder couldn't empty the whole Trash: \(message) Empty the Trash again or use Finder.
                    """, comment: "Empty Trash error. The placeholder is Finder's own message (a sentence).")
        }
    }

    private static var stillEmptying: String {
        String(localized: "Finder is still emptying the Trash; it finishes on its own.", comment: "Empty Trash status")
    }
}
