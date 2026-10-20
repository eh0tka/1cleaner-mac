import Foundation

extension Int64 {
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false  // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: self)
    }
}

extension Date {
    /// "3 months ago".
    var relativeDescription: String {
        if abs(timeIntervalSinceNow) < 60 {
            return String(localized: "just now", comment: "Relative time under a minute, used mid-sentence like \"3 months ago\"")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

enum PathDisplay {
    static let home = NSHomeDirectory()

    /// `~/www/app` instead of `/Users/name/www/app`.
    static func abbreviated(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
