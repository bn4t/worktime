import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let tracker: TimeTracker
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(tracker: TimeTracker) {
        self.tracker = tracker
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        observeTracker()
        updateButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.toolTip = "Worktime"
    }

    private func observeTracker() {
        tracker.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.title = " \(tracker.menuBarTitle)"
        button.image = NSImage(
            systemSymbolName: tracker.isRunning ? "briefcase.fill" : "briefcase",
            accessibilityDescription: tracker.isRunning ? "Tracking work" : "Work stopped"
        )
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        tracker.toggle()
        updateButton()
    }

    @objc private func toggleFromMenu() {
        tracker.toggle()
        updateButton()
    }

    @objc private func syncFromMenu() {
        tracker.syncNow()
        updateButton()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(disabledItem(tracker.statusLine))
        menu.addItem(disabledItem("Today \(tracker.menuBarTitle)"))

        if tracker.isRunning {
            menu.addItem(disabledItem("Current \(WorktimeFormat.wholeHours(tracker.elapsedActiveSeconds))"))
        }

        if tracker.pendingSyncCount > 0 {
            menu.addItem(disabledItem("Queued \(tracker.pendingSyncCount)"))
        }

        if let last = tracker.lastCompletedSession {
            menu.addItem(disabledItem("Last \(WorktimeFormat.shortTimeRange(start: last.start, end: last.end))"))
        }

        if let error = tracker.lastError {
            menu.addItem(.separator())
            menu.addItem(disabledItem(shortError(error)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(tracker.isRunning ? "Stop" : "Start", action: #selector(toggleFromMenu)))
        menu.addItem(actionItem("Sync", action: #selector(syncFromMenu)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit", action: #selector(quit)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func shortError(_ error: String) -> String {
        if error.count <= 30 {
            return error
        }
        return String(error.prefix(27)) + "..."
    }
}
