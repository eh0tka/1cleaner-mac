import Foundation
import Observation

/// What 1Cleaner did on this Mac, for the dashboard. Stored locally in UserDefaults; never leaves the Mac.
@MainActor
@Observable
final class StatsStore {
    struct ScanSummary: Codable {
        let date: Date
        let seconds: Int
        let found: Int64
        /// `CategoryID.rawValue` → size found.
        let categorySizes: [String: Int64]

        func size(of category: CategoryID) -> Int64 { categorySizes[category.rawValue] ?? 0 }
    }

    struct CleanupRecord: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let movedToTrash: Int64
        let removedByTools: Int64
        let items: Int

        var bytes: Int64 { movedToTrash + removedByTools }
    }

    struct StorageSummary: Codable {
        let date: Date
        /// `StorageBucket.rawValue` → bytes.
        let totals: [String: Int64]
        let notMeasured: Int64

        var sortedBuckets: [(bucket: StorageBucket, bytes: Int64)] {
            totals.compactMap { key, bytes in StorageBucket(rawValue: key).map { ($0, bytes) } }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        }
    }

    struct Stats: Codable {
        var firstUse = Date()
        /// Moved to the Trash plus removed by Docker and Xcode, over all cleanups.
        var cleanedBytes: Int64 = 0
        var cleanups = 0
        var itemsRemoved = 0
        var lastScan: ScanSummary?
        var lastStorage: StorageSummary?
        /// Newest first, at most `historyLimit`.
        var history: [CleanupRecord] = []
    }

    static let historyLimit = 30
    private static let key = "usageStats"
    private let defaults: UserDefaults

    private(set) var stats: Stats

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = saved
        } else {
            stats = Stats()
            save()
        }
    }

    func recordScan(started: Date, results: [CategoryID: CategoryResult]) {
        let sizes = Dictionary(uniqueKeysWithValues: results.map { ($0.key.rawValue, $0.value.totalSize) })
        stats.lastScan = ScanSummary(
            date: Date(),
            seconds: Int(Date().timeIntervalSince(started)),
            found: sizes.values.reduce(0, +),
            categorySizes: sizes
        )
        save()
    }

    func recordStorage(_ report: StorageReport) {
        stats.lastStorage = StorageSummary(
            date: report.date,
            totals: Dictionary(uniqueKeysWithValues: report.totals.map { ($0.key.rawValue, $0.value) }),
            notMeasured: report.notMeasured
        )
        save()
    }

    func recordCleanup(movedToTrash: Int64, removedByTools: Int64, items: Int) {
        guard items > 0 else { return }
        let record = CleanupRecord(date: Date(), movedToTrash: movedToTrash, removedByTools: removedByTools, items: items)
        stats.cleanedBytes += record.bytes
        stats.cleanups += 1
        stats.itemsRemoved += items
        stats.history.insert(record, at: 0)
        if stats.history.count > Self.historyLimit { stats.history.removeLast(stats.history.count - Self.historyLimit) }
        save()
    }

    #if DEBUG
    /// Demo stats for website screenshots, saved only to the demo defaults suite.
    func loadDemo(_ demo: Stats) {
        stats = demo
        save()
    }
    #endif

    private func save() {
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: Self.key) }
    }
}
