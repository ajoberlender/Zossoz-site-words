import Foundation

struct NCBError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

/// Dates in NCB DATETIME columns: "yyyy-MM-dd HH:mm:ss" (UTC). Reads can come back ISO-8601 or date-only.
enum NCBDate {
    private static let out: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func string(_ d: Date) -> String { out.string(from: d) }

    static func parse(_ any: Any?) -> Date? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return isoFrac.date(from: s) ?? iso.date(from: s) ?? out.date(from: s) ?? dateOnly.date(from: s)
    }
}

/// MySQL-backed columns come back with loose types (DECIMAL as "0.85", BOOLEAN as 0/1).
extension Dictionary where Key == String, Value == Any {
    func int(_ k: String) -> Int? {
        if let v = self[k] as? Int { return v }
        if let v = self[k] as? Double { return Int(v) }
        if let v = self[k] as? String { return Int(v) ?? Double(v).map(Int.init) }
        return nil
    }
    func double(_ k: String) -> Double? {
        if let v = self[k] as? Double { return v }
        if let v = self[k] as? Int { return Double(v) }
        if let v = self[k] as? String { return Double(v) }
        return nil
    }
    func string(_ k: String) -> String? {
        if let v = self[k] as? String { return v }
        return nil
    }
    func bool(_ k: String) -> Bool {
        if let v = self[k] as? Bool { return v }
        if let v = self[k] as? Int { return v != 0 }
        if let v = self[k] as? String { return v == "1" || v.lowercased() == "true" }
        return false
    }
    func date(_ k: String) -> Date? { NCBDate.parse(self[k]) }
}

/// Thin async client for NoCodeBackend auth + data APIs. Uses the user's session token as a Bearer.
final class NCBClient {
    static let shared = NCBClient()
    private static let tokenKey = "ncb.session.token"

    private let session: URLSession
    /// Called on any 401 so the UI can drop back to sign-in.
    var onUnauthorized: (() -> Void)?

    var token: String? {
        get { Keychain.get(Self.tokenKey) }
        set { Keychain.set(newValue, for: Self.tokenKey) }
    }

    private init() {
        let cfg = URLSessionConfiguration.ephemeral // never touch shared cookie storage; we use Bearer
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    // MARK: Core request

    @discardableResult
    func request(_ base: URL, _ path: String, method: String = "GET", query: [String: String] = [:],
                 body: Any? = nil, authenticated: Bool = true) async throws -> Any {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "instance", value: NCBConfig.instance)]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(NCBConfig.instance, forHTTPHeaderField: "X-Database-Instance")
        req.setValue(NCBConfig.origin, forHTTPHeaderField: "Origin")
        if authenticated, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if status == 401, authenticated { onUnauthorized?() }
        guard (200..<300).contains(status) else {
            let dict = json as? [String: Any]
            let msg = (dict?["message"] as? String) ?? (dict?["error"] as? String) ?? "Request failed (\(status))"
            throw NCBError(status: status, message: msg)
        }
        if let dict = json as? [String: Any], (dict["status"] as? String) == "failed" {
            throw NCBError(status: status, message: (dict["error"] as? String) ?? "Request failed")
        }
        return json
    }

    // MARK: Data API helpers

    /// Reads every row, following pagination.
    func readAll(_ table: String, query: [String: String] = [:]) async throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var page = 1
        while true {
            var q = query
            q["limit"] = "500"
            q["page"] = String(page)
            let json = try await request(NCBConfig.dataBase, "read/\(table)", query: q) as? [String: Any]
            rows += (json?["data"] as? [[String: Any]]) ?? []
            let hasMore = ((json?["metadata"] as? [String: Any])?["hasMore"] as? Bool) ?? false
            if !hasMore { break }
            page += 1
        }
        return rows
    }

    func create(_ table: String, _ body: [String: Any]) async throws -> Int {
        let json = try await request(NCBConfig.dataBase, "create/\(table)", method: "POST", body: body) as? [String: Any]
        guard let id = json?.int("id") else { throw NCBError(status: 0, message: "No id returned from create/\(table)") }
        return id
    }

    func update(_ table: String, id: Int, _ body: [String: Any]) async throws {
        try await request(NCBConfig.dataBase, "update/\(table)/\(id)", method: "PUT", body: body)
    }

    func delete(_ table: String, id: Int) async throws {
        try await request(NCBConfig.dataBase, "delete/\(table)/\(id)", method: "DELETE")
    }

    func bulkCreate(_ table: String, records: [[String: Any]]) async throws {
        guard !records.isEmpty else { return }
        try await request(NCBConfig.dataBase, "bulk/create/\(table)", method: "POST", body: ["records": records])
    }
}
