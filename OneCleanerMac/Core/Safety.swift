import Foundation
import SwiftUI

/// How safe removing an item is. A hint shown on every row; it never selects anything.
enum Safety: Hashable, Sendable {
    /// Rebuilt or downloaded again on its own; only time is lost.
    case safe
    /// Probably fine, but it depends on how the person uses it: check, or ask an AI assistant.
    case askAI
    /// Can lose something that exists nowhere else.
    case risky

    var title: String {
        switch self {
        case .safe:
            String(localized: "Safe", comment: "Safety label on a row: removing it is safe, it comes back on its own")
        case .askAI:
            String(localized: "Ask AI",
                   comment: "Safety label on a row: depends on use, check with an AI assistant. Short, a button.")
        case .risky:
            String(localized: "Risky", comment: "Safety label on a row: removing it may lose data that exists nowhere else")
        }
    }

    var systemImage: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .askAI: "sparkles"
        case .risky: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: Theme.success
        case .askAI: Theme.accentDeep
        case .risky: Theme.danger
        }
    }

    /// The label's meaning in a few words, shown next to it in the legend above every list.
    var meaning: String {
        switch self {
        case .safe:
            String(localized: "comes back on its own",
                   comment: "Legend next to the Safe label: what deleting such an item means. Lowercase, a few words.")
        case .askAI:
            String(localized: "depends on how you use it",
                   comment: "Legend next to the Ask AI label: whether deleting is fine depends on the person's use.")
        case .risky:
            String(localized: "may hold data you can't get back",
                   comment: "Legend next to the Risky label: deleting it may lose data that exists nowhere else.")
        }
    }

    var help: String {
        switch self {
        case .safe:
            String(localized: """
                Safe to remove: it comes back on its own when needed; you only lose the time to rebuild or download it.
                """, comment: "Tooltip of the Safe label")
        case .askAI:
            String(localized: """
                Depends on how you use it. Click to copy a description for an AI assistant (Claude, Codex, ChatGPT) \
                and ask.
                """, comment: "Tooltip of the Ask AI label; clicking it copies a question to paste into an AI assistant")
        case .risky:
            String(localized: "Risky: you can lose data that exists nowhere else. Remove only if you're sure.",
                   comment: "Tooltip of the Risky label")
        }
    }
}

extension CleanupItem {
    /// The single table of safety levels; change the mapping only with the maintainer.
    var safety: Safety {
        let path = revealPath ?? ""
        switch category {
        case .projects:
            // A build folder holding files git tracks is Ask AI (ProjectScanner sets it).
            return safetyLevel ?? .safe
        case .editors, .logs, .browserCaches:
            // JetBrains IDEs keep Local History (earlier versions of files) in this cache folder.
            if path.contains("/Library/Caches/JetBrains/") { return .askAI }
            return .safe
        case .xcode:
            // Archives: newest per app Risky, older ones Ask AI (XcodeScanner.labelArchives).
            if path.contains("/Xcode/Archives/") { return safetyLevel ?? .risky }
            // Another copy of Xcode in /Applications (badges are translated, so paths decide).
            if path.hasPrefix("/Applications/"), path.hasSuffix(".app") { return .askAI }
            return .safe
        case .simulators:
            // A device is one disposable virtual phone (Ask AI); one whose iOS is gone can't run
            // at all (Safe); a runtime is the iOS version its devices need (Ask AI).
            if case .simulatorRuntime = removal { return .askAI }
            // SimulatorScanner marks devices whose iOS is gone as Safe.
            return safetyLevel ?? .askAI
        case .android:
            if path.contains("/.android/avd/") { return .risky }
            // Android Studio keeps Local History in its cache folder, as JetBrains IDEs do.
            if path.contains("/Library/Caches/Google/AndroidStudio") { return .askAI }
            if path.contains("/Android/sdk/") || path.contains("/.gradle/jdks/") { return .askAI }
            return .safe
        case .packageCaches:
            if path.hasSuffix("/.m2/repository") { return .risky }
            if path.hasSuffix("/pnpm/store") || path.contains("ms-playwright") || path.contains("/.cache/puppeteer")
                || path.hasSuffix("/pypoetry") {
                return .askAI
            }
            return .safe
        case .docker:
            switch removal {
            case .docker(.buildCache): return .safe
            case .docker(.volume): return .risky
            default: return .askAI
            }
        case .leftovers:
            // An app that's gone: its settings and caches are safe; anything that looks like the person's data
            // (passwords, bookmarks, databases, documents) is worth a look first.
            return userData.isEmpty ? .safe : .askAI
        case .aiAgents:
            // Each agent row carries its level from the agent table in AgentsScanner.
            return safetyLevel ?? .askAI
        case .worktrees:
            // WorktreeFinder: everything committed is Ask AI, anything that would be lost (or unknown) Risky.
            return safetyLevel ?? .risky
        case .aiModels, .installers, .oldDownloads:
            return .askAI
        case .temporary:
            // Simulator devices and Claude Code session files carry their own level (TemporaryScanner).
            // System temp is cleared by macOS anyway; ~/tmp is the person's own folder.
            if let safetyLevel { return safetyLevel }
            return path.hasPrefix(NSHomeDirectory() + "/") ? .askAI : .safe
        case .apps, .largeFiles:
            return .risky
        case .duplicates:
            // Another copy stays, but an app or project may use this one by its path.
            return .askAI
        case .appCaches:
            // Apple's own caches, also inside containers (`Containers/com.apple.Notes/...`,
            // `Group Containers/group.com.apple.notes/...`), are worth a question first.
            if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/"),
               !path.hasSuffix("/Mail Downloads") {
                return path.contains("com.apple.") ? .askAI : .safe
            }
            return (path as NSString).lastPathComponent.hasPrefix("com.apple.") ? .askAI : .safe
        case .devices:
            return path.contains("/MobileSync/Backup/") ? .risky : .safe
        case .trash:
            return .risky
        }
    }
}
