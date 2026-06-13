import Foundation

@MainActor
final class TimeTracker: ObservableObject {
    @Published private(set) var activeStart: Date?
    @Published private(set) var todaySeconds: Int = 0
    @Published private(set) var pendingSyncCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastCompletedSession: WorkSession?

    private let store: SQLiteStore
    private let client: LifedataClient
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let autoSyncEnabled: Bool
    private var ticker: Timer?

    private let activeStartDefaultsKey = "worktime.activeStartMS"
    private let resumeAfterWakeDefaultsKey = "worktime.resumeAfterWake"

    init(
        store: SQLiteStore? = nil,
        client: LifedataClient = LifedataClient(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        autoSyncEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.client = client
        self.calendar = calendar
        self.autoSyncEnabled = autoSyncEnabled
        do {
            self.store = try store ?? SQLiteStore()
            self.activeStart = Self.restoreActiveStart(from: defaults, key: activeStartDefaultsKey)
            if self.activeStart == nil && defaults.bool(forKey: resumeAfterWakeDefaultsKey) {
                start(at: Date())
            }
            refresh()
            startTicker()
            if autoSyncEnabled {
                Task { await syncPendingSessions() }
            }
        } catch {
            fatalError("Worktime store could not start: \(error.localizedDescription)")
        }
    }

    var isRunning: Bool {
        activeStart != nil
    }

    var elapsedActiveSeconds: Int {
        guard let activeStart else { return 0 }
        return max(0, Int(Date().timeIntervalSince(activeStart)))
    }

    var displaySeconds: Int {
        todaySeconds + elapsedActiveSeconds
    }

    var menuBarTitle: String {
        WorktimeFormat.wholeHours(displaySeconds)
    }

    var statusLine: String {
        isRunning ? "Tracking work" : "Stopped"
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        start(at: Date())
    }

    func stop() {
        stop(at: Date())
    }

    func handleSystemWillSleep(at date: Date = Date()) {
        guard activeStart != nil else {
            defaults.set(false, forKey: resumeAfterWakeDefaultsKey)
            return
        }
        defaults.set(true, forKey: resumeAfterWakeDefaultsKey)
        stop(at: date, shouldResumeAfterWake: true)
    }

    func handleSystemDidWake(at date: Date = Date()) {
        guard defaults.bool(forKey: resumeAfterWakeDefaultsKey) else { return }
        defaults.set(false, forKey: resumeAfterWakeDefaultsKey)
        start(at: date)
    }

    func start(at date: Date) {
        guard activeStart == nil else { return }
        activeStart = date
        defaults.set(Int64(date.timeIntervalSince1970 * 1000), forKey: activeStartDefaultsKey)
        lastError = nil
        refresh()
    }

    func stop(at date: Date) {
        stop(at: date, shouldResumeAfterWake: false)
    }

    private func stop(at date: Date, shouldResumeAfterWake: Bool) {
        guard let start = activeStart else { return }
        activeStart = nil
        defaults.removeObject(forKey: activeStartDefaultsKey)
        if !shouldResumeAfterWake {
            defaults.set(false, forKey: resumeAfterWakeDefaultsKey)
        }

        let session = WorkSession(start: start, end: date)
        do {
            try store.insert(session)
            lastCompletedSession = session
            refresh()
            if autoSyncEnabled {
                Task { await syncPendingSessions() }
            }
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
        }
    }

    func syncNow() {
        Task { await syncPendingSessions() }
    }

    func refresh() {
        do {
            let interval = todayInterval()
            todaySeconds = try store.totalSeconds(startingAtOrAfter: interval.start, endingBefore: interval.end)
            pendingSyncCount = try store.pendingSyncSessions().count
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncPendingSessions() async {
        do {
            let sessions = try store.pendingSyncSessions()
            pendingSyncCount = sessions.count
            for session in sessions {
                do {
                    let receipt = try await client.postWorkSession(session)
                    try store.markSynced(sessionID: session.id, eventID: receipt.id)
                    lastError = nil
                } catch {
                    try? store.markSyncFailed(sessionID: session.id, error: error.localizedDescription)
                    lastError = error.localizedDescription
                    break
                }
            }
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
                self?.refresh()
            }
        }
    }

    private func todayInterval() -> DateInterval {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date(timeInterval: 86_400, since: start)
        return DateInterval(start: start, end: end)
    }

    private static func restoreActiveStart(from defaults: UserDefaults, key: String) -> Date? {
        let value = defaults.object(forKey: key)
        let milliseconds: Int64?
        if let value = value as? Int64 {
            milliseconds = value
        } else if let value = value as? Int {
            milliseconds = Int64(value)
        } else {
            milliseconds = nil
        }
        guard let milliseconds else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}
