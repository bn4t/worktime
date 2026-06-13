import Foundation
import SQLite3

final class SQLiteStore {
    enum StoreError: LocalizedError {
        case applicationSupportUnavailable
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case bindFailed(String)

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                return "Application Support directory unavailable."
            case .openFailed(let message):
                return "Open SQLite failed: \(message)"
            case .prepareFailed(let message):
                return "Prepare SQLite statement failed: \(message)"
            case .stepFailed(let message):
                return "SQLite step failed: \(message)"
            case .bindFailed(let message):
                return "SQLite bind failed: \(message)"
            }
        }
    }

    private var db: OpaquePointer?
    let dbURL: URL

    static func defaultDatabaseURL() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.applicationSupportUnavailable
        }
        let dir = base.appendingPathComponent("Worktime", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("worktime.sqlite")
    }

    init(url: URL? = nil) throws {
        dbURL = try url ?? Self.defaultDatabaseURL()
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK else {
            throw StoreError.openFailed(Self.message(db))
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA busy_timeout=5000")
        try execute("""
        CREATE TABLE IF NOT EXISTS work_sessions (
          id TEXT PRIMARY KEY,
          start_ms INTEGER NOT NULL,
          end_ms INTEGER NOT NULL,
          duration_seconds INTEGER NOT NULL,
          synced_event_id TEXT,
          synced_at_ms INTEGER,
          sync_error TEXT,
          created_at_ms INTEGER NOT NULL
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_work_sessions_start ON work_sessions(start_ms)")
        try execute("CREATE INDEX IF NOT EXISTS idx_work_sessions_sync ON work_sessions(synced_at_ms)")
    }

    deinit {
        sqlite3_close(db)
    }

    func insert(_ session: WorkSession) throws {
        let sql = """
        INSERT OR REPLACE INTO work_sessions
          (id, start_ms, end_ms, duration_seconds, synced_event_id, synced_at_ms, sync_error, created_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withStatement(sql) { statement in
            try bind(session.id, to: statement, at: 1)
            try bind(milliseconds(session.start), to: statement, at: 2)
            try bind(milliseconds(session.end), to: statement, at: 3)
            try bind(Int64(session.durationSeconds), to: statement, at: 4)
            try bind(session.syncedEventID, to: statement, at: 5)
            try bind(session.syncedAt.map(milliseconds), to: statement, at: 6)
            try bind(session.syncError, to: statement, at: 7)
            try bind(milliseconds(Date()), to: statement, at: 8)
            try stepDone(statement)
        }
    }

    func markSynced(sessionID: String, eventID: String, at date: Date = Date()) throws {
        try withStatement("UPDATE work_sessions SET synced_event_id = ?, synced_at_ms = ?, sync_error = NULL WHERE id = ?") { statement in
            try bind(eventID, to: statement, at: 1)
            try bind(milliseconds(date), to: statement, at: 2)
            try bind(sessionID, to: statement, at: 3)
            try stepDone(statement)
        }
    }

    func markSyncFailed(sessionID: String, error: String) throws {
        try withStatement("UPDATE work_sessions SET sync_error = ? WHERE id = ?") { statement in
            try bind(error, to: statement, at: 1)
            try bind(sessionID, to: statement, at: 2)
            try stepDone(statement)
        }
    }

    func pendingSyncSessions(limit: Int = 50) throws -> [WorkSession] {
        try fetch("""
        SELECT id, start_ms, end_ms, duration_seconds, synced_event_id, synced_at_ms, sync_error
        FROM work_sessions
        WHERE synced_at_ms IS NULL
        ORDER BY start_ms ASC
        LIMIT ?
        """, bind: { statement in
            try bind(Int64(limit), to: statement, at: 1)
        })
    }

    func sessions(startingAtOrAfter lowerBound: Date) throws -> [WorkSession] {
        try fetch("""
        SELECT id, start_ms, end_ms, duration_seconds, synced_event_id, synced_at_ms, sync_error
        FROM work_sessions
        WHERE start_ms >= ?
        ORDER BY start_ms DESC
        """, bind: { statement in
            try bind(milliseconds(lowerBound), to: statement, at: 1)
        })
    }

    func totalSeconds(startingAtOrAfter lowerBound: Date, endingBefore upperBound: Date) throws -> Int {
        var total: Int64 = 0
        try withStatement("""
        SELECT COALESCE(SUM(duration_seconds), 0)
        FROM work_sessions
        WHERE start_ms >= ? AND start_ms < ?
        """) { statement in
            try bind(milliseconds(lowerBound), to: statement, at: 1)
            try bind(milliseconds(upperBound), to: statement, at: 2)
            if sqlite3_step(statement) == SQLITE_ROW {
                total = sqlite3_column_int64(statement, 0)
            }
        }
        return Int(total)
    }

    private func fetch(_ sql: String, bind binder: (OpaquePointer?) throws -> Void) throws -> [WorkSession] {
        var sessions: [WorkSession] = []
        try withStatement(sql) { statement in
            try binder(statement)
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE {
                    break
                }
                guard result == SQLITE_ROW else {
                    throw StoreError.stepFailed(Self.message(db))
                }
                sessions.append(Self.session(from: statement))
            }
        }
        return sessions
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.stepFailed(Self.message(db))
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(Self.message(db))
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.stepFailed(Self.message(db))
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw StoreError.bindFailed(Self.message(db))
            }
            return
        }
        guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw StoreError.bindFailed(Self.message(db))
        }
    }

    private func bind(_ value: Int64?, to statement: OpaquePointer?, at index: Int32) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw StoreError.bindFailed(Self.message(db))
            }
            return
        }
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw StoreError.bindFailed(Self.message(db))
        }
    }

    private static func session(from statement: OpaquePointer?) -> WorkSession {
        let id = String(cString: sqlite3_column_text(statement, 0))
        let start = date(milliseconds: sqlite3_column_int64(statement, 1))
        let end = date(milliseconds: sqlite3_column_int64(statement, 2))
        let syncedEventID = text(statement, column: 4)
        let syncedAtMS = optionalInt64(statement, column: 5)
        return WorkSession(
            id: id,
            start: start,
            end: end,
            syncedEventID: syncedEventID,
            syncedAt: syncedAtMS.map(date(milliseconds:)),
            syncError: text(statement, column: 6)
        )
    }

    private static func text(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: cString)
    }

    private static func optionalInt64(_ statement: OpaquePointer?, column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
    }

    private static func message(_ db: OpaquePointer?) -> String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "unknown sqlite error"
    }
}

private func milliseconds(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1000)
}

private func date(milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
