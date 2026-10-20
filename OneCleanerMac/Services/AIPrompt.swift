import AppKit
import Foundation

/// "Copy for AI": a self-contained question about one item, to paste into any AI assistant. Built on this Mac only;
/// nothing is sent anywhere by 1Cleaner.
enum AIPrompt {
    static let listedChildren = 20

    static func make(for item: CleanupItem) async -> String {
        let contents = await Task.detached { listing(item.removal.paths) }.value
        let os = ProcessInfo.processInfo.operatingSystemVersion

        let itemLine = item.badge.map {
            String(localized: "Item: \(item.title) (\($0))",
                   comment: "AI prompt line. Placeholders: item name; its tag")
        } ?? String(localized: "Item: \(item.title)", comment: "AI prompt line. The placeholder is the item's name.")
        var lines = [
            String(localized: """
                I'm cleaning up my Mac with 1Cleaner and want to know whether it's safe to remove this item.
                """, comment: "First line of the question the person pastes into an AI assistant (ChatGPT, Claude)"),
            "",
            itemLine,
            String(localized: "1Cleaner category: \(item.category.title). \(item.category.explanation)",
                   comment: "AI prompt line. Placeholders: category title; its explanation"),
            String(localized: "1Cleaner's note: \(item.detail)",
                   comment: "AI prompt line. The placeholder is the row's details."),
            String(localized: "1Cleaner's safety hint: \(item.safety.title)",
                   comment: "AI prompt line. The placeholder is Safe, Ask AI or Risky."),
            String(localized: "Size on disk: \(item.size.formattedBytes)",
                   comment: "AI prompt line. The placeholder is a size."),
        ]
        if let date = item.date {
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            lines.append(String(localized: "Last changed or used: \(formatted)",
                                comment: "AI prompt line. The placeholder is a date and time."))
        }
        let removal = removalDescription(item.removal)
        lines.append(String(localized: "How 1Cleaner would remove it: \(removal)",
                            comment: "AI prompt line. The placeholder says how, e.g. \"moves it to the Trash ...\""))
        if !item.removal.paths.isEmpty {
            lines.append(String(localized: "Paths:", comment: "AI prompt heading above the item's file paths"))
            lines += item.removal.paths.map { "- \($0)" }
        }
        if !contents.isEmpty {
            lines.append(String(localized: "Largest contents:",
                                comment: "AI prompt heading above the folder's largest entries"))
            lines += contents
        }
        lines += [
            macLine(os),
            "",
            String(localized: "Please tell me:", comment: "AI prompt heading above the numbered questions"),
            String(localized: "1. What this is and which app or tool uses it.", comment: "AI prompt question 1"),
            String(localized: "2. What breaks or is lost if I remove it, and whether it comes back on its own.",
                   comment: "AI prompt question 2"),
            String(localized: "3. How I could restore it if I need it later.", comment: "AI prompt question 3"),
            String(localized: """
                4. Your recommendation: remove, keep, or check something first (say exactly what to check).
                """, comment: "AI prompt question 4"),
            answerLanguageLine,
        ]
        return lines.joined(separator: "\n")
    }

    static let batchLimit = 150

    /// One question about many rows at once (the Ask AI rows a list shows), answered as a table.
    static func makeBatch(for items: [CleanupItem], category: CategoryID) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let removal = items.contains { $0.removal.isPermanent }
            ? String(localized: "Removal: some items are removed permanently by their tool.",
                     comment: "AI prompt line about many items")
            : String(localized: """
                Removal: everything goes to the Trash (it can be put back until the Trash is emptied).
                """, comment: "AI prompt line about many items")
        var lines = [
            String(localized: """
                I'm cleaning up my Mac with 1Cleaner. For each item below, tell me whether it's safe to remove.
                """, comment: "First line of the question about many items the person pastes into an AI assistant"),
            "",
            String(localized: "1Cleaner category: \(category.title). \(category.explanation)",
                   comment: "AI prompt line. Placeholders: category title; its explanation"),
            removal,
            macLine(os),
            "",
        ]
        for (index, item) in items.prefix(batchLimit).enumerated() {
            var line = "\(index + 1). \(item.title) — \(item.size.formattedBytes) — \(item.detail)"
            let paths = item.removal.paths.map(PathDisplay.abbreviated)
            if !paths.isEmpty { line += " — " + paths.prefix(4).joined(separator: "; ") + (paths.count > 4 ? "; …" : "") }
            lines.append(line)
        }
        if items.count > batchLimit {
            let more = items.count - batchLimit
            lines.append(String(localized: "(\(more) more not listed)",
                                comment: "AI prompt: items left out of the list"))
        }
        lines += [
            "",
            String(localized: """
                Answer as a table: number, item, verdict (Remove / Keep / Check), and one short reason. For Check, \
                say exactly what to check (for example, whether saved passwords are synced elsewhere). Then list the \
                numbers to remove.
                """, comment: "AI prompt instructions for many items. Translate Remove / Keep / Check as well."),
            answerLanguageLine,
        ]
        return lines.joined(separator: "\n")
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The assistant answers in the Mac's first language. When 1Cleaner runs in that language, the localized line
    /// says it in that language; otherwise (a language 1Cleaner isn't translated into) the language is named in
    /// English, as before.
    private static var answerLanguageLine: String {
        let preferred = Locale(identifier: Locale.preferredLanguages.first ?? "en").language.languageCode
        let appLanguage = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en").language.languageCode
        if preferred == nil || preferred == appLanguage {
            return String(localized: "Answer in English.",
                          comment: "Last AI prompt line: name your language, e.g. \"Ответь на русском.\"")
        }
        return "Answer in \(language)."
    }

    /// "Mac: macOS 15.1.0, Apple silicon." The version stays plain digits.
    private static func macLine(_ os: OperatingSystemVersion) -> String {
        let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return String(localized: "Mac: macOS \(version), \(architecture).",
                      comment: "AI prompt line. Placeholders: macOS version; Apple silicon or Intel")
    }

    /// The Mac's first language in English: "ru-PL" → "Russian".
    private static var language: String {
        let code = Locale(identifier: Locale.preferredLanguages.first ?? "en").language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        "Intel"
        #endif
    }

    private static func removalDescription(_ removal: Removal) -> String {
        switch removal {
        case .trash:
            String(localized: "moves it to the Trash (it can be put back until the Trash is emptied)",
                   comment: "AI prompt: how an item is removed, after \"How 1Cleaner would remove it:\"")
        case .docker(.container(let id)):
            runs("docker rm \(id.prefix(12))")
        case .docker(.image(let id, let containers, _)):
            imageRemoval("docker rmi \(id.replacingOccurrences(of: "sha256:", with: "").prefix(12))", containers.count)
        case .docker(.volume(let name, _)):
            runs("docker volume rm \(name)")
        case .docker(.buildCache):
            runs("docker builder prune --all --force")
        case .simulatorDevice(let udid, _):
            runs("xcrun simctl delete \(udid)")
        case .simulatorRuntime(let id):
            runs("xcrun simctl runtime delete \(id)")
        case .emptyTrash:
            String(localized: "empties the Trash (permanent)",
                   comment: "AI prompt: how an item is removed, after \"How 1Cleaner would remove it:\"")
        }
    }

    private static func runs(_ command: String) -> String {
        String(localized: "runs `\(command)` (permanent)",
               comment: "AI prompt: how an item is removed. The placeholder is a command line; keep the backticks.")
    }

    private static func imageRemoval(_ command: String, _ stoppedContainers: Int) -> String {
        if stoppedContainers == 0 { return runs(command) }
        return String(localized: """
            runs `\(command)` after `docker rm` of \(stoppedContainers) stopped containers (permanent)
            """, comment: "AI prompt: how a Docker image is removed. Placeholders: command line; number of containers.")
    }

    /// For folders: the largest entries one level down, with sizes, so the assistant has something concrete.
    private static func listing(_ paths: [String]) -> [String] {
        var lines: [String] = []
        for path in paths.prefix(3) where FileInfo.isDirectory(path) {
            let children = FileInfo.children(path).prefix(400)
            let sized = children.map { name -> (String, Int64, Bool) in
                let child = path + "/" + name
                return (name, FileSizer.measure(child).bytes, FileInfo.isDirectory(child))
            }.sorted { $0.1 > $1.1 }
            let prefix = paths.count > 1 ? "\((path as NSString).lastPathComponent)/" : ""
            for (name, bytes, isFolder) in sized.prefix(listedChildren) {
                lines.append("- \(prefix)\(name)\(isFolder ? "/" : "") — \(bytes.formattedBytes)")
            }
            if children.count > listedChildren {
                let more = FileInfo.children(path).count - listedChildren
                lines.append(String(localized: "- … \(more) more entries",
                                    comment: "AI prompt: folder entries left out"))
            }
        }
        return lines
    }
}
