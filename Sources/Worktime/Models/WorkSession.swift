import Foundation

struct WorkSession: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let durationSeconds: Int
    var syncedEventID: String?
    var syncedAt: Date?
    var syncError: String?

    init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        syncedEventID: String? = nil,
        syncedAt: Date? = nil,
        syncError: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.durationSeconds = max(0, Int(end.timeIntervalSince(start)))
        self.syncedEventID = syncedEventID
        self.syncedAt = syncedAt
        self.syncError = syncError
    }

    var durationMinutes: Int {
        durationSeconds / 60
    }

    var durationHours: Int {
        durationSeconds / 3600
    }
}
