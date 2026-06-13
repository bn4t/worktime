import AppKit

@MainActor
final class WorktimeApp: NSObject, NSApplicationDelegate {
    private var tracker: TimeTracker?
    private var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let tracker = TimeTracker()
        self.tracker = tracker
        self.statusItemController = StatusItemController(tracker: tracker)
        registerSleepWakeNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        statusItemController = nil
        tracker = nil
    }

    private func registerSleepWakeNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        tracker?.handleSystemWillSleep()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        tracker?.handleSystemDidWake()
    }
}
