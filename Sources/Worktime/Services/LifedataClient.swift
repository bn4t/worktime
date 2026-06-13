import Foundation

actor LifedataClient {
    enum ClientError: LocalizedError {
        case noServerURL
        case productionWritesDisabled(String)
        case badResponse(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .noServerURL:
                return "No lifedata server URL configured."
            case .productionWritesDisabled(let host):
                return "Refusing to write to production lifedata host \(host)."
            case .badResponse(let code, let body):
                return "HTTP \(code): \(body)"
            case .decode(let message):
                return "Response decode failed: \(message)"
            }
        }
    }

    static let serverURLDefaultsKey = "lifedata.url"
    static let allowProductionDefaultsKey = "lifedata.allowProductionWrites"
    static let serverURLEnvironmentKey = "WORKTIME_LIFEDATA_URL"
    static let allowProductionEnvironmentKey = "WORKTIME_ALLOW_PROD_LIFEDATA"
    static let defaultServerURL = "http://127.0.0.1:8787"
    static let productionHost = "100.94.53.42"
    static let productionServerURL = "http://100.94.53.42:8787"
    static let sourceName = "worktime_macos"
    static let sourceVersion = "1.0.0"

    private let session: URLSession
    private let defaults: UserDefaults
    private let environment: [String: String]

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.session = session
        self.defaults = defaults
        self.environment = environment
        defaults.register(defaults: [
            Self.serverURLDefaultsKey: Self.defaultServerURL,
            Self.allowProductionDefaultsKey: false
        ])
    }

    var serverURLString: String {
        if let value = environment[Self.serverURLEnvironmentKey], !value.isEmpty {
            return value
        }
        return defaults.string(forKey: Self.serverURLDefaultsKey) ?? Self.defaultServerURL
    }

    func postWorkSession(_ workSession: WorkSession) async throws -> LifedataReceipt {
        let event = Self.event(for: workSession)
        let receipts = try await postEvents([event])
        guard let first = receipts.first else {
            throw ClientError.decode("Empty receipt list")
        }
        return first
    }

    func postEvents(_ events: [LifedataEvent]) async throws -> [LifedataReceipt] {
        guard !events.isEmpty else { return [] }
        guard let base = URL(string: serverURLString) else {
            throw ClientError.noServerURL
        }
        try validateDevelopmentTarget(base)

        var request = URLRequest(url: base.appendingPathComponent("events"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(events)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.badResponse(code, String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try JSONDecoder().decode([LifedataReceipt].self, from: data)
        } catch {
            if let single = try? JSONDecoder().decode(LifedataReceipt.self, from: data) {
                return [single]
            }
            throw ClientError.decode(error.localizedDescription)
        }
    }

    private func validateDevelopmentTarget(_ url: URL) throws {
        let allowProduction = defaults.bool(forKey: Self.allowProductionDefaultsKey)
            || environment[Self.allowProductionEnvironmentKey] == "1"
        if url.host == Self.productionHost && !allowProduction {
            throw ClientError.productionWritesDisabled(Self.productionHost)
        }
    }

    static func event(for session: WorkSession) -> LifedataEvent {
        let startMS = Int64(session.start.timeIntervalSince1970 * 1000)
        let endMS = Int64(session.end.timeIntervalSince1970 * 1000)
        return LifedataEvent(
            id: session.id,
            ts: endMS,
            type: "work_session",
            source: sourceName,
            sourceVersion: sourceVersion,
            payload: [
                "start_ms": .integer(startMS),
                "end_ms": .integer(endMS),
                "duration_min": .integer(Int64(session.durationMinutes))
            ],
            attrs: [
                "app": "Worktime",
                "session_id": .string(session.id)
            ]
        )
    }
}
