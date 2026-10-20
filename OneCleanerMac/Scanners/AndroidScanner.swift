import Foundation

/// Gradle and Android caches from `KnownLocations`, plus emulators: an AVD is its `.avd` folder and the `.ini`
/// file next to it, moved to the Trash together.
struct AndroidScanner: Scanner {
    var categories: [CategoryID] { [.android] }

    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput] {
        var output = await LocationScanner(category: .android, locations: KnownLocations.android).scan(context)[.android]
            ?? ScanOutput()

        let avdFolder = context.homePath(".android/avd")
        let avds = FileInfo.children(avdFolder).filter { $0.hasSuffix(".avd") }
        // Unknown (ps failed): every emulator counts as running.
        let runningAVDs = avds.isEmpty ? [] : await Self.runningAVDs()
        let emulators: [CleanupItem?] = await Concurrency.map(avds) { name -> CleanupItem? in
            let path = avdFolder + "/" + name
            let ini = avdFolder + "/" + (name as NSString).deletingPathExtension + ".ini"
            let measurement = FileSizer.measure(path, progress: context.progress)
            guard measurement.rootReadable, let target = FileTarget(path: path) else { return nil }
            var targets = [target]
            if let iniTarget = FileTarget(path: ini) { targets.append(iniTarget) }
            let lastUsed = FileInfo.modificationDate(path)
            let running = runningAVDs.map { $0.contains((name as NSString).deletingPathExtension) } ?? true
            return CleanupItem(
                id: path,
                category: .android,
                title: (name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " "),
                badge: String(localized: "Emulator", comment: "Badge of an Android emulator (AVD) row"),
                detail: String(localized: "Android emulator with its apps and data", comment: "Detail of an Android emulator row")
                    + (lastUsed.map {
                        " · " + String(localized: "changed \($0.relativeDescription)",
                                       comment: "Fact in a row's detail line; %@ is a relative date like '3 months ago'")
                    } ?? ""),
                size: measurement.bytes,
                removal: .trash(targets),
                lockedReason: running
                    ? String(localized: "Running. Quit it to remove it.", comment: "Why a running app can't be selected") : nil,
                date: lastUsed
            )
        }
        output.items = (output.items + emulators.compactMap { $0 }).sorted { $0.size > $1.size }
        return [.android: output]
    }

    /// Names of the emulators running now, from their command lines (`emulator -avd Pixel_9`); the lock files in an
    /// AVD folder outlive the emulator.
    static func runningAVDs() async -> Set<String>? {
        guard let output = try? await ProcessRunner.run("/bin/ps", ["-axww", "-o", "command="], timeout: .seconds(10)),
              output.succeeded else { return nil }
        var names = Set<String>()
        for line in output.stdout.split(separator: "\n") {
            // The executable's path may hold spaces, so the line is matched as a whole; a stray match only locks an AVD.
            guard line.contains("qemu-system") || line.contains("emulator") else { continue }
            let words = line.split(separator: " ")
            for (index, word) in words.enumerated() {
                if word == "-avd", index + 1 < words.count { names.insert(String(words[index + 1])) }
                if word.hasPrefix("@"), word.count > 1 { names.insert(String(word.dropFirst())) }
            }
        }
        return names
    }
}
