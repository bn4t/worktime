import Foundation

enum WorktimeFormat {
    static func wholeHours(_ seconds: Int) -> String {
        "\(max(0, seconds) / 3600)h"
    }

    static func shortTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}
