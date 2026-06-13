import Foundation
import Testing
@testable import Worktime

@Suite("Worktime")
struct WorktimeTests {
    @Test("whole-hour formatting drops minutes")
    func wholeHourFormatting() {
        #expect(WorktimeFormat.wholeHours(0) == "0h")
        #expect(WorktimeFormat.wholeHours(59 * 60) == "0h")
        #expect(WorktimeFormat.wholeHours(60 * 60) == "1h")
        #expect(WorktimeFormat.wholeHours(125 * 60) == "2h")
    }

    @Test("work session event matches lifedata shape")
    func workSessionEvent() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = Date(timeIntervalSince1970: 1_780_007_500)
        let session = WorkSession(id: "session-1", start: start, end: end)

        let event = LifedataClient.event(for: session)

        #expect(event.id == "session-1")
        #expect(event.type == "work_session")
        #expect(event.source == "worktime_macos")
        #expect(event.ts == 1_780_007_500_000)
        #expect(event.payload == [
            "start_ms": .integer(1_780_000_000_000),
            "end_ms": .integer(1_780_007_500_000),
            "duration_min": .integer(125)
        ])
    }

    @Test("sqlite store persists and returns pending sessions")
    func sqliteStorePersistsSession() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SQLiteStore(url: dir.appendingPathComponent("worktime.sqlite"))
        let session = WorkSession(
            id: "pending-1",
            start: Date(timeIntervalSince1970: 1_780_000_000),
            end: Date(timeIntervalSince1970: 1_780_003_600)
        )

        try store.insert(session)
        let pending = try store.pendingSyncSessions()

        #expect(pending.count == 1)
        #expect(pending.first?.id == "pending-1")

        try store.markSynced(sessionID: "pending-1", eventID: "event-1")
        #expect(try store.pendingSyncSessions().isEmpty)
    }

    @Test("sleep pauses a running timer and wake resumes it")
    @MainActor
    func sleepPausesAndWakeResumesRunningTimer() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let defaultsName = "WorktimeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)

        let store = try SQLiteStore(url: dir.appendingPathComponent("worktime.sqlite"))
        let tracker = TimeTracker(
            store: store,
            defaults: defaults,
            autoSyncEnabled: false
        )

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let sleep = start.addingTimeInterval(3_600)
        let wake = sleep.addingTimeInterval(7_200)
        let stop = wake.addingTimeInterval(3_600)

        tracker.start(at: start)
        tracker.handleSystemWillSleep(at: sleep)
        #expect(!tracker.isRunning)

        tracker.handleSystemDidWake(at: wake)
        #expect(tracker.isRunning)

        tracker.stop(at: stop)
        #expect(!tracker.isRunning)

        let sessions = try store.sessions(startingAtOrAfter: start.addingTimeInterval(-1))
        #expect(sessions.count == 2)
        #expect(sessions.map(\.durationSeconds).sorted() == [3_600, 3_600])

        let total = try store.totalSeconds(
            startingAtOrAfter: start.addingTimeInterval(-1),
            endingBefore: stop.addingTimeInterval(1)
        )
        #expect(total == 7_200)
    }

    @Test("client refuses production lifedata by default")
    func productionWritesAreDisabledByDefault() async throws {
        let defaults = try #require(UserDefaults(suiteName: "WorktimeTests.\(UUID().uuidString)"))
        defaults.set("http://\(LifedataClient.productionHost):8787", forKey: LifedataClient.serverURLDefaultsKey)
        defaults.set(false, forKey: LifedataClient.allowProductionDefaultsKey)

        let client = LifedataClient(defaults: defaults)
        let session = WorkSession(
            id: "prod-guard",
            start: Date(timeIntervalSince1970: 1_780_000_000),
            end: Date(timeIntervalSince1970: 1_780_000_060)
        )

        do {
            _ = try await client.postWorkSession(session)
            Issue.record("Expected production writes to be refused")
        } catch LifedataClient.ClientError.productionWritesDisabled(let host) {
            #expect(host == LifedataClient.productionHost)
        }
    }

    @Test("client reads launchd lifedata URL from environment")
    func clientReadsLaunchdURLFromEnvironment() async {
        let client = LifedataClient(environment: [
            LifedataClient.serverURLEnvironmentKey: LifedataClient.productionServerURL,
            LifedataClient.allowProductionEnvironmentKey: "1",
        ])

        let url = await client.serverURLString
        #expect(url == LifedataClient.productionServerURL)
    }

    @Test("production environment URL still requires explicit allow flag")
    func productionEnvironmentURLRequiresAllowFlag() async throws {
        let client = LifedataClient(environment: [
            LifedataClient.serverURLEnvironmentKey: LifedataClient.productionServerURL,
        ])
        let session = WorkSession(
            id: "prod-env-guard",
            start: Date(timeIntervalSince1970: 1_780_000_000),
            end: Date(timeIntervalSince1970: 1_780_000_060)
        )

        do {
            _ = try await client.postWorkSession(session)
            Issue.record("Expected production environment URL to be refused without allow flag")
        } catch LifedataClient.ClientError.productionWritesDisabled(let host) {
            #expect(host == LifedataClient.productionHost)
        }
    }
}
