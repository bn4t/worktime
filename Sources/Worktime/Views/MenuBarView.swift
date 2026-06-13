import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var tracker: TimeTracker

    var body: some View {
        Text(tracker.statusLine)
        Text("Today \(WorktimeFormat.wholeHours(tracker.displaySeconds))")

        if tracker.isRunning {
            Text("Current \(WorktimeFormat.wholeHours(tracker.elapsedActiveSeconds))")
        }

        if tracker.pendingSyncCount > 0 {
            Text("Queued \(tracker.pendingSyncCount)")
        }

        if let last = tracker.lastCompletedSession {
            Text("Last \(WorktimeFormat.shortTimeRange(start: last.start, end: last.end))")
        }

        if let error = tracker.lastError {
            Divider()
            Text(shortError(error))
        }

        Divider()

        Button(tracker.isRunning ? "Stop" : "Start") {
            tracker.toggle()
        }
        .keyboardShortcut(tracker.isRunning ? "s" : "r")

        Button("Sync") {
            tracker.syncNow()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func shortError(_ error: String) -> String {
        if error.count <= 30 {
            return error
        }
        return String(error.prefix(27)) + "..."
    }
}
