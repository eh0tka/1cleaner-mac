import Foundation
import os

/// Everything a scanner needs, fixed for one scan.
struct ScanContext: Sendable {
    static let largeFileThreshold: Int64 = 200_000_000
    static let oldDownloadDays = 90
    /// Cache and log entries smaller than this are noise in the list.
    static let minimumItemSize: Int64 = 1_000_000

    let home: String
    /// Folders searched for project builds and large files.
    let roots: [String]
    let progress: ScanProgress
    let now: Date
    let fullDiskAccess: Bool
    /// Safe List folders: never entered by the walk, and nothing inside them is shown.
    var safeFolders: Set<String> = []

    func homePath(_ relative: String) -> String { home + "/" + relative }
}

/// Scan counters shared by all scanners; the UI reads a snapshot a few times a second.
final class ScanProgress: Sendable {
    struct Snapshot: Sendable {
        var entries = 0
        var currentFolder = ""
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot())

    func reset() { state.withLock { $0 = Snapshot() } }
    func add(entries: Int) { state.withLock { $0.entries += entries } }
    func setFolder(_ path: String) { state.withLock { $0.currentFolder = path } }
    var snapshot: Snapshot { state.withLock { $0 } }
}

protocol Scanner: Sendable {
    var categories: [CategoryID] { get }
    func scan(_ context: ScanContext) async -> [CategoryID: ScanOutput]
}

enum Concurrency {
    /// Maps with at most `limit` transforms in flight; keeps the input order.
    static func map<T: Sendable, R: Sendable>(
        _ input: [T], limit: Int = 4, _ transform: @escaping @Sendable (T) async -> R
    ) async -> [R] {
        guard !input.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, R).self) { group in
            var results = [R?](repeating: nil, count: input.count)
            var next = 0
            for _ in 0..<min(limit, input.count) {
                let index = next
                group.addTask { (index, await transform(input[index])) }
                next += 1
            }
            for await (index, value) in group {
                results[index] = value
                if next < input.count, !Task.isCancelled {
                    let index = next
                    group.addTask { (index, await transform(input[index])) }
                    next += 1
                }
            }
            return results.compactMap { $0 }
        }
    }
}
