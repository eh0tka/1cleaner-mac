import AppKit
import Darwin
import Foundation

/// AI coding agents and assistants: what each one keeps on this Mac, row by row, with its own
/// safety level. Live databases and settings are never offered. Session histories are Ask AI (they're what
/// "resume" uses) and are locked while changed in the last day, so a running session is never touched.
/// An agent that is no longer installed offers its whole data folders.
struct AgentsScanner: Scanner {
    struct Agent: Sendable {
        let name: String
        let bundleIDs: [String]
        /// Command-line tool names looked up in the usual install folders.
        let commands: [String]
        /// Home-relative folders with all of the agent's data, offered whole only when it's not installed.
        let dataFolders: [String]
        /// Folder name prefixes of the agent as an editor extension or JetBrains plugin.
        var editorExtensions: [String] = []
    }

    static let agents: [Agent] = [
        Agent(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"], commands: ["claude"],
              dataFolders: [".claude", "Library/Application Support/Claude"]),
        Agent(name: "ChatGPT & Codex", bundleIDs: ["com.openai.chat", "com.openai.codex"], commands: ["codex"],
              dataFolders: [".codex", "Library/Application Support/Codex"]),
        Agent(name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], commands: ["cursor", "cursor-agent"],
              dataFolders: [".cursor", "Library/Application Support/Cursor"]),
        Agent(name: "Antigravity & Gemini", bundleIDs: ["com.google.antigravity"], commands: ["gemini", "antigravity"],
              dataFolders: [".gemini", "Library/Application Support/Antigravity"]),
        Agent(name: "Qwen Code", bundleIDs: [], commands: ["qwen"], dataFolders: [".qwen"]),
        Agent(name: "Windsurf", bundleIDs: ["com.exafunction.windsurf"], commands: ["windsurf"],
              dataFolders: [".codeium", ".windsurf", "Library/Application Support/Windsurf"]),
        Agent(name: "Kiro", bundleIDs: ["dev.kiro.desktop"], commands: ["kiro"],
              dataFolders: [".kiro", "Library/Application Support/Kiro"]),
        Agent(name: "Trae", bundleIDs: ["com.trae.app"], commands: ["trae"],
              dataFolders: [".trae", "Library/Application Support/Trae"]),
        Agent(name: "Continue", bundleIDs: [], commands: [], dataFolders: [".continue"],
              editorExtensions: ["continue.continue-", "continue-"]),
        Agent(name: "Aider", bundleIDs: [], commands: ["aider"], dataFolders: [".aider"]),
        Agent(name: "OpenCode", bundleIDs: [], commands: ["opencode"], dataFolders: [".local/share/opencode"]),
    ]

    static let commandFolders = [
        "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.npm-global/bin", "~/.bun/bin", "~/.volta/bin",
        "~/.claude/local", "~/.cargo/bin",
    ]

    var categories: [CategoryID] { [.aiAgents] }

    /// Version managers keep one bin folder per Node or tool version: every installed version counts.
    static let versionedCommandFolders: [(root: String, inside: String)] = [
        ("~/.nvm/versions/node", "bin"), ("~/.local/share/fnm/node-versions", "installation/bin"),
        ("~/Library/Application Support/fnm/node-versions", "installation/bin"),
    ]
    static let moreCommandFolders = [
        "~/Library/pnpm", "~/.local/share/pnpm", "~/.asdf/shims", "~/.local/share/mise/shims", "~/.yarn/bin",
        "~/.deno/bin", "/opt/local/bin",
    ]
    /// Extension folders of VS Code and its forks; JetBrains plugins live under each IDE's own folder.
    static let editorExtensionFolders = [
        "~/.vscode/extensions", "~/.vscode-insiders/extensions", "~/.cursor/extensions", "~/.windsurf/extensions",
        "~/.antigravity/extensions", "~/.kiro/extensions", "~/.trae/extensions",
    ]

    static var historyNote: String {
        String(localized: "Chat history and checkpoints; resuming and restoring use them",
               comment: "AI Agents row note for Gemini CLI's and Qwen Code's temporary folder")
    }

    static func isInstalled(_ agent: Agent, home: String) -> Bool {
        if agent.bundleIDs.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) {
            return true
        }
        let expand = { (path: String) in path.replacingOccurrences(of: "~", with: home) }
        var folders = (commandFolders + moreCommandFolders).map(expand)
        for (root, inside) in versionedCommandFolders {
            folders += FileInfo.children(expand(root)).map { expand(root) + "/" + $0 + "/" + inside }
        }
        if agent.commands.contains(where: { command in folders.contains { FileInfo.exists($0 + "/" + command) } }) {
            return true
        }
        guard !agent.editorExtensions.isEmpty else { return false }
        let jetBrains = expand("~/Library/Application Support/JetBrains")
        let extensionFolders = editorExtensionFolders.map(expand)
            + FileInfo.children(jetBrains).map { jetBrains + "/" + $0 + "/plugins" }
        return extensionFolders.contains { folder in
            FileInfo.children(folder).contains { name in agent.editorExtensions.contains { name.lowercased().hasPrefix($0) } }
        }
    }

    /// Application Support folders of agents that aren't installed: offered here whole, so other categories
    /// (web caches inside app data) skip them and a path never shows twice.
    static func uninstalledAppSupportFolders(home: String) -> Set<String> {
        Set(agents.filter { !isInstalled($0, home: home) }.flatMap { agent in
            agent.dataFolders.filter { $0.hasPrefix("Library/Application Support/") }
                .map { String($0.dropFirst("Library/Application Support/".count)) }
        })
    }

    struct Row: Sendable {
        let agent: String
        let title: String
        let paths: [String]
        let safety: Safety
        let note: String
        var lockIfRecent = false
        var lockIfRunning: String?
        /// The English title the item id was built from before localization, for rows that can hold several
        /// paths, so the id (and the Safe List key) stays the same in every language.
        var idTitle: String?
    }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        let home = context.home
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var rows: [Row] = []

        for agent in Self.agents where !Self.isInstalled(agent, home: home) {
            for folder in agent.dataFolders where FileInfo.exists(context.homePath(folder)) {
                rows.append(Row(agent: agent.name,
                                title: String(localized: "\(agent.name) data · \(PathDisplay.abbreviated(context.homePath(folder)))",
                                              comment: "AI Agents row title; first %@ is an agent name, second %@ a folder path"),
                                paths: [context.homePath(folder)], safety: .askAI,
                                note: String(localized: "\(agent.name) isn't installed; its chats, settings and caches are here",
                                             comment: "AI Agents row note; %@ is an agent name (Claude, Cursor…)"),
                                lockIfRecent: true))
            }
        }
        let installed = Set(Self.agents.filter { Self.isInstalled($0, home: home) }.map(\.name))

        if installed.contains("Claude") {
            let vm = context.homePath("Library/Application Support/Claude/vm_bundles")
            if FileInfo.exists(vm) {
                rows.append(Row(agent: "Claude",
                                title: String(localized: "Claude virtual machine image", comment: "AI Agents row title"),
                                paths: [vm], safety: .safe,
                                note: String(localized: "Used by Claude's agent mode; downloaded again the next time it's needed",
                                             comment: "AI Agents row note for Claude's virtual machine image"),
                                lockIfRunning: "com.anthropic.claudefordesktop"))
            }
            for project in FileInfo.children(context.homePath(".claude/projects")) where !project.hasPrefix(".") {
                rows.append(Row(agent: "Claude",
                                title: String(localized: "Claude Code sessions · \(Self.projectName(project, home: home))",
                                              comment: "AI Agents row title; %@ is a project path like ~/www/app"),
                                paths: [context.homePath(".claude/projects/" + project)], safety: .askAI,
                                note: String(localized: "Session history /resume uses",
                                             comment: "AI Agents row note; /resume is Claude Code's command, keep it as is"),
                                lockIfRecent: true))
            }
        }
        if installed.contains("ChatGPT & Codex") {
            let sessions = context.homePath(".codex/sessions")
            for year in FileInfo.children(sessions) where !year.hasPrefix(".") {
                for month in FileInfo.children(sessions + "/" + year) where !month.hasPrefix(".") {
                    rows.append(Row(agent: "Codex",
                                    title: String(localized: "Codex sessions · \(year)-\(month)",
                                                  comment: "AI Agents row title; first %@ is a year, second %@ a month number, e.g. 2026-08"),
                                    paths: [sessions + "/\(year)/\(month)"], safety: .askAI,
                                    note: String(localized: "Session history `codex resume` uses",
                                                 comment: "AI Agents row note; `codex resume` is a command, keep it as is"),
                                    lockIfRecent: true))
                }
            }
            for (folder, title, note) in [
                (".codex/archived_sessions", String(localized: "Codex archived sessions", comment: "AI Agents row title"),
                 String(localized: "Sessions you archived", comment: "AI Agents row note for Codex archived sessions")),
                (".codex/migration-backups", String(localized: "Codex migration backups", comment: "AI Agents row title"),
                 String(localized: "Copies Codex made while migrating its data",
                        comment: "AI Agents row note for Codex migration backups")),
            ] where FileInfo.exists(context.homePath(folder)) {
                rows.append(Row(agent: "Codex", title: title, paths: [context.homePath(folder)], safety: .askAI, note: note))
            }
            let backups = FileInfo.children(context.homePath(".codex"))
                .filter { $0.contains(".bak") }.map { context.homePath(".codex/" + $0) }
            if !backups.isEmpty {
                rows.append(Row(agent: "Codex",
                                title: String(localized: "Codex backup files (\(backups.count))",
                                              comment: "AI Agents row title; %lld is the number of files"),
                                paths: backups, safety: .askAI,
                                note: String(localized: "Old copies of Codex's databases and settings (*.bak)",
                                             comment: "AI Agents row note; *.bak is a file pattern, keep it as is"),
                                idTitle: "Codex backup files (\(backups.count))"))
            }
        }
        if installed.contains("Cursor") {
            let backup = context.homePath("Library/Application Support/Cursor/User/globalStorage/state.vscdb.backup")
            if FileInfo.exists(backup) {
                rows.append(Row(agent: "Cursor", title: String(localized: "Cursor state backup", comment: "AI Agents row title"),
                                paths: [backup], safety: .askAI,
                                note: String(localized: "One-time backup of Cursor's state database (chat history lives in the live copy)",
                                             comment: "AI Agents row note for Cursor's state backup"),
                                lockIfRunning: "com.todesktop.230313mzl4w4u92"))
            }
            let chats = context.homePath(".cursor/chats")
            if FileInfo.exists(chats) {
                rows.append(Row(agent: "Cursor", title: String(localized: "Cursor agent chats", comment: "AI Agents row title"),
                                paths: [chats], safety: .askAI,
                                note: String(localized: "Saved chats of Cursor's agent", comment: "AI Agents row note for Cursor agent chats"),
                                lockIfRecent: true))
            }
        }
        if installed.contains("Antigravity & Gemini") {
            for (folder, title, note) in [
                (".gemini/antigravity-backup", String(localized: "Antigravity backup", comment: "AI Agents row title"),
                 String(localized: "A backup copy of Antigravity's data", comment: "AI Agents row note for Antigravity backup")),
                (".gemini/antigravity-browser-profile",
                 String(localized: "Antigravity browser profile", comment: "AI Agents row title"),
                 String(localized: "The browser profile the agent uses; may hold sign-ins",
                        comment: "AI Agents row note for Antigravity's browser profile")),
                // Gemini CLI keeps its chat history and checkpoints here (Ask AI, locked while fresh).
                (".gemini/tmp", String(localized: "Gemini CLI temporary files", comment: "AI Agents row title"),
                 Self.historyNote),
            ] where FileInfo.exists(context.homePath(folder)) {
                rows.append(Row(agent: "Antigravity", title: title, paths: [context.homePath(folder)],
                                safety: .askAI, note: note, lockIfRecent: folder.hasSuffix("tmp")))
            }
        }
        if installed.contains("Qwen Code"), FileInfo.exists(context.homePath(".qwen/tmp")) {
            rows.append(Row(agent: "Qwen Code", title: String(localized: "Qwen Code temporary files", comment: "AI Agents row title"),
                            paths: [context.homePath(".qwen/tmp")], safety: .askAI, note: Self.historyNote,
                            lockIfRecent: true))
        }

        // VS Code-based editors: state of projects that no longer exist, old extension versions, and the task
        // histories of agent extensions (Cline, Roo Code, Kilo Code).
        for (editor, app, extensions) in [
            ("Cursor", "Cursor", ".cursor/extensions"), ("VS Code", "Code", ".vscode/extensions"),
            ("Windsurf", "Windsurf", ".windsurf/extensions"), ("Antigravity", "Antigravity", ".antigravity/extensions"),
        ] {
            let user = context.homePath("Library/Application Support/\(app)/User")
            let orphans = Self.orphanWorkspaces(user + "/workspaceStorage")
            if !orphans.isEmpty {
                rows.append(Row(agent: editor,
                                title: String(localized: "\(editor) state of deleted projects (\(orphans.count))",
                                              comment: "AI Agents row title; %@ is an editor (Cursor, VS Code…), %lld the number of projects"),
                                paths: orphans, safety: .safe,
                                note: String(localized: "Saved editor state of folders that no longer exist",
                                             comment: "AI Agents row note for an editor's state of deleted projects"),
                                idTitle: "\(editor) state of deleted projects (\(orphans.count))"))
            }
            let old = Self.oldExtensionVersions(context.homePath(extensions), profiles: user + "/profiles")
            if !old.isEmpty {
                rows.append(Row(agent: editor,
                                title: String(localized: "\(editor) old extension versions (\(old.count))",
                                              comment: "AI Agents row title; %@ is an editor (Cursor, VS Code…), %lld the number of versions"),
                                paths: old, safety: .safe,
                                note: String(localized: "Older copies kept after extensions updated",
                                             comment: "AI Agents row note for an editor's old extension versions"),
                                idTitle: "\(editor) old extension versions (\(old.count))"))
            }
            for (extensionID, name) in [
                ("saoudrizwan.claude-dev", "Cline"), ("rooveterinaryinc.roo-cline", "Roo Code"),
                ("kilocode.kilo-code", "Kilo Code"),
            ] {
                let tasks = user + "/globalStorage/\(extensionID)/tasks"
                if FileInfo.exists(tasks) {
                    rows.append(Row(agent: name,
                                    title: String(localized: "\(name) task history in \(editor)",
                                                  comment: "AI Agents row title; first %@ is an extension (Cline…), second %@ an editor"),
                                    paths: [tasks], safety: .askAI,
                                    note: String(localized: "Saved tasks and conversations",
                                                 comment: "AI Agents row note for an agent extension's task history"),
                                    lockIfRecent: true))
                }
            }
        }

        let recent = context.now.addingTimeInterval(-86_400)
        let items: [CleanupItem?] = await Concurrency.map(rows) { row -> CleanupItem? in
            var bytes: Int64 = 0
            var newest: Date?
            for path in row.paths {
                bytes += FileSizer.measure(path, progress: context.progress).bytes
                if let date = TemporaryScanner.newestChange(path) { newest = max(newest ?? date, date) }
            }
            // Removed only as the scan saw it: a session written since, even days ago, keeps the row's files.
            let targets = row.paths.compactMap { path in
                FileTarget(watching: path).map { target in
                    var target = target
                    target.quietForADay = row.lockIfRecent
                    target.usedWhileRunning = row.lockIfRunning.map { [$0] } ?? []
                    return target
                }
            }
            guard bytes >= ScanContext.minimumItemSize, !targets.isEmpty, targets.count == row.paths.count else { return nil }
            var locked: String?
            if let app = row.lockIfRunning, running.contains(app) {
                locked = String(localized: "Running. Quit \(row.agent) to remove it.",
                                comment: "Why a row can't be selected; %@ is an app or agent name")
            } else if row.lockIfRecent, let newest, newest > recent {
                locked = String(localized: "Changed in the last day; a session may be running.",
                                comment: "Why an AI agent's session history can't be selected")
            }
            return CleanupItem(
                id: row.paths.count == 1 ? row.paths[0] : "agents:" + (row.idTitle ?? row.title),
                category: .aiAgents,
                title: row.title,
                badge: row.agent,
                detail: row.note + (newest.map {
                    " · " + String(localized: "last changed \($0.relativeDescription)",
                                   comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                } ?? ""),
                size: bytes,
                removal: .trash(targets),
                lockedReason: locked,
                date: newest,
                safetyLevel: row.safety
            )
        }
        return [.aiAgents: ScanOutput(items: items.compactMap { $0 }.sorted { $0.size > $1.size })]
    }

    /// Claude Code names a project's folder after its path with "/" as "-": "-Users-name-www-app" → "~/www/app".
    /// Hyphens inside folder names can't be told apart, so this is a readable approximation.
    static func projectName(_ folder: String, home: String) -> String {
        // "." is encoded as "-" too, so "--claude" was "/.claude".
        let path = folder.replacingOccurrences(of: "--", with: "/.").replacingOccurrences(of: "-", with: "/")
        // Folders named after the Claude app's own scratch and sandbox paths get a short name.
        if path.contains("/Claude/scratch/") {
            return String(localized: "Claude app scratch", comment: "Short name of the Claude app's scratch folder in a row title")
        }
        if path.contains("/claude/sandbox/status") {
            return String(localized: "Claude sandbox status", comment: "Short name of Claude's sandbox status folder in a row title")
        }
        let homeEncoded = home.replacingOccurrences(of: "-", with: "/")
        if path == homeEncoded { return "~" }
        if path.hasPrefix(homeEncoded + "/") { return "~" + path.dropFirst(homeEncoded.count) }
        return path
    }

    /// workspaceStorage entries whose project folder (from workspace.json) is gone.
    static func orphanWorkspaces(_ storage: String) -> [String] {
        FileInfo.children(storage).compactMap { name in
            let entry = storage + "/" + name
            guard let data = FileManager.default.contents(atPath: entry + "/workspace.json"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let folder = (json["folder"] ?? json["workspace"]) as? String,
                  let url = URL(string: folder), url.isFileURL else { return nil }
            // Only a project that is really gone: one on a disk that isn't connected, or a path that can't be
            // checked, keeps its state.
            let path = url.path
            var info = stat()
            guard lstat(path, &info) != 0, errno == ENOENT else { return nil }
            let parts = path.split(separator: "/")
            if path.hasPrefix("/Volumes/"), parts.count >= 2, !FileInfo.exists("/Volumes/" + parts[1]) { return nil }
            return entry
        }
    }

    /// Extension folders "publisher.name-1.2.3" older than the newest version of the same extension that no list of
    /// installed extensions (the editor's own and each profile's `extensions.json`) still points to. Without a
    /// readable list nothing is offered.
    static func oldExtensionVersions(_ folder: String, profiles: String) -> [String] {
        // A profiles folder that can't be listed, or a profile list that exists but can't be read, hides which
        // versions are in use: nothing is offered then.
        var profileNames: [String] = []
        if FileInfo.exists(profiles) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: profiles) else { return [] }
            profileNames = names
        }
        var lists = [folder + "/extensions.json"]
        for name in profileNames where !name.hasPrefix(".") && FileInfo.isDirectory(profiles + "/" + name) {
            let list = profiles + "/" + name + "/extensions.json"
            var info = stat()
            if lstat(list, &info) == 0 { lists.append(list) } else if errno != ENOENT { return [] }
        }
        var inUse = Set<String>()
        for list in lists {
            // The editor's own list must be readable; a profile's list that exists but can't be read hides which
            // versions it uses, so nothing is offered then either.
            guard let data = FileManager.default.contents(atPath: list),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            for entry in entries {
                if let relative = entry["relativeLocation"] as? String { inUse.insert(relative) }
                if let location = entry["location"] as? [String: Any],
                   let path = (location["fsPath"] ?? location["path"]) as? String {
                    inUse.insert((path as NSString).lastPathComponent)
                }
            }
        }
        var byID: [String: [(version: [Int], name: String)]] = [:]
        for name in FileInfo.children(folder) where !name.hasPrefix(".") {
            // The version starts at the first "-<digit>": "ms-python.python-2024.1.0-darwin-arm64".
            let chars = Array(name)
            guard let dash = chars.indices.first(where: { chars[$0] == "-" && $0 + 1 < chars.count && chars[$0 + 1].isNumber })
            else { continue }
            let id = String(chars[..<dash])
            let rest = String(chars[(dash + 1)...])
            let platform = rest.split(separator: "-").dropFirst().joined(separator: "-")
            let version = (rest.split(separator: "-").first ?? "").split(separator: ".").compactMap { Int($0) }
            guard !version.isEmpty else { continue }
            byID[id + "|" + platform, default: []].append((version, name))
        }
        return byID.values.flatMap { versions -> [String] in
            guard versions.count > 1 else { return [] }
            let sorted = versions.sorted { $0.version.lexicographicallyPrecedes($1.version) }
            return sorted.dropLast().filter { !inUse.contains($0.name) }.map { folder + "/" + $0.name }
        }
    }
}
