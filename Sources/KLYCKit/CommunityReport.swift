import Foundation

/// A player's report for one Steam game, sent to KLYC-Box's own reports project (never anywhere
/// else): works yes/no, 1 to 5, this Mac's chip and macOS, the engine and renderer, a short note.
/// Opt-in, one report per game and per anonymous id, and the player sees every field before it goes.
/// The fields and their limits mirror `reports/firestore.rules`, which is what enforces them.
public struct CommunityVote: Equatable, Sendable {
    public static let noteLimit = 200

    public var appid: Int
    public var works: Bool
    public var rating: Int
    public var chip: String
    public var macos: String
    public var engine: String
    public var renderer: String
    public var note: String

    public init(appid: Int, works: Bool, rating: Int, chip: String, macos: String, engine: String, renderer: String = "", note: String = "") {
        self.appid = appid
        self.works = works
        self.rating = min(5, max(1, rating))
        self.chip = Self.clip(GamePageCopy.shortChip(chip), 40)
        self.macos = Self.clip(macos, 20)
        self.engine = Self.clip(engine, 60)
        self.renderer = Self.clip(renderer, 20)
        self.note = Self.clip(note, Self.noteLimit)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    /// Only Steam games can be reported: the report is filed under the Steam id.
    public var isValid: Bool { appid > 0 && appid < 100_000_000 }

    /// The fields exactly as they will be sent, in the order the player reads them. Empty optional
    /// fields are left out, so what the preview lists is what the server receives.
    public var disclosure: [(name: String, value: String)] {
        var rows: [(String, String)] = [("appid", String(appid)), ("works", works ? "yes" : "no"), ("rating", "\(rating)/5")]
        for (name, value) in [("chip", chip), ("macos", macos), ("engine", engine), ("renderer", renderer), ("note", note)] where !value.isEmpty {
            rows.append((name, value))
        }
        return rows
    }
}

/// What was last sent for a game, kept on this Mac so the form can show it and a report can be taken back.
public struct SentVote: Codable, Equatable, Sendable {
    public var works: Bool
    public var rating: Int
    public var note: String
    public var date: Date
    public init(works: Bool, rating: Int, note: String, date: Date = Date()) {
        self.works = works; self.rating = rating; self.note = note; self.date = date
    }
}

public struct SentVoteStore: Sendable {
    public let paths: KLYCPaths
    public init(paths: KLYCPaths = KLYCPaths()) { self.paths = paths }
    var file: URL { paths.home.appending(path: "sent-reports.json", directoryHint: .notDirectory) }

    public func all() -> [Int: SentVote] {
        guard let data = try? Data(contentsOf: file),
              let map = try? JSONDecoder.klycbox.decode([String: SentVote].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    public func set(_ vote: SentVote?, for appid: Int) {
        var map = all().reduce(into: [String: SentVote]()) { $0[String($1.key)] = $1.value }
        map[String(appid)] = vote
        try? paths.ensure()
        if let data = try? JSONEncoder.klycbox.encode(map) { try? data.write(to: file, options: .atomic) }
    }
}

/// The anonymous id Firebase gave this install, and the token that renews it. It carries no name,
/// no email and nothing about the Mac. Deleting the file simply makes the next report a new person.
public struct CommunityIdentity: Codable, Equatable, Sendable {
    public var uid: String
    public var refreshToken: String
    public init(uid: String, refreshToken: String) { self.uid = uid; self.refreshToken = refreshToken }
}

public enum CommunityReportError: Error, Equatable, LocalizedError {
    /// The reports project is not switched on yet (anonymous sign-in off, or the database not created).
    case unavailable
    case offline
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return L("Player reports are not switched on yet. Nothing was sent.")
        case .offline: return L("No connection. Nothing was sent.")
        case .rejected(let why): return String(format: L("The report was not accepted (%@). Nothing was kept."), why)
        }
    }
}

/// Talks to Firebase over its public REST endpoints: anonymous sign-in, then one write (or delete)
/// of the player's own document. No Firebase SDK, no analytics, no other request.
public struct CommunityReports: Sendable {
    /// The project's web key. It is public by design (every Firebase web app ships one); what protects
    /// the data are the Firestore rules, which let a signed-in player write only their own valid report.
    public static let projectID = "klyc-box-reports"
    public static let apiKey = "AIzaSyAZzt5mtKnp2APHS9sqKIuLrBnouGIoHwE"
    /// The privacy page, on the same GitHub Pages site as the Atlas.
    public static var privacyURL: URL { AtlasSite.privacyPage() ?? URL(string: "https://klycbox.ernklyc.dev/privacy/")! }

    public let paths: KLYCPaths
    public let session: URLSession
    public let projectID: String
    public let apiKey: String

    public init(paths: KLYCPaths = KLYCPaths(), session: URLSession = .shared,
                projectID: String = CommunityReports.projectID, apiKey: String = CommunityReports.apiKey) {
        self.paths = paths; self.session = session; self.projectID = projectID; self.apiKey = apiKey
    }

    var identityFile: URL { paths.home.appending(path: "community-identity.json", directoryHint: .notDirectory) }

    public func identity() -> CommunityIdentity? {
        guard let data = try? Data(contentsOf: identityFile) else { return nil }
        return try? JSONDecoder().decode(CommunityIdentity.self, from: data)
    }

    func save(_ identity: CommunityIdentity) {
        try? paths.ensure()
        if let data = try? JSONEncoder().encode(identity) {
            try? data.write(to: identityFile, options: .atomic)
            // Holds a renewal token: readable by this user only.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identityFile.path)
        }
    }

    // MARK: Request bodies (pure, tested)

    public func documentName(appid: Int, uid: String) -> String {
        "projects/\(projectID)/databases/(default)/documents/reports/\(appid)_\(uid)"
    }

    /// The write: the document replaced as a whole, its `updatedAt` filled in by the server (the
    /// rules require it to be the server's time, so a player cannot back-date a report).
    public func commitBody(for vote: CommunityVote, uid: String) -> Data {
        var fields: [String: Any] = [
            "appid": ["integerValue": String(vote.appid)],
            "works": ["booleanValue": vote.works],
            "rating": ["integerValue": String(vote.rating)],
        ]
        for (key, value) in [("chip", vote.chip), ("macos", vote.macos), ("engine", vote.engine), ("renderer", vote.renderer), ("note", vote.note)] where !value.isEmpty {
            fields[key] = ["stringValue": value]
        }
        let write: [String: Any] = [
            "update": ["name": documentName(appid: vote.appid, uid: uid), "fields": fields],
            "updateTransforms": [["fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: ["writes": [write]], options: [.sortedKeys])) ?? Data()
    }

    public func deleteBody(appid: Int, uid: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["writes": [["delete": documentName(appid: appid, uid: uid)]]], options: [.sortedKeys])) ?? Data()
    }

    // MARK: Network

    /// Sends (or replaces) this install's report for the game.
    public func send(_ vote: CommunityVote) async throws {
        guard vote.isValid else { throw CommunityReportError.rejected("game id") }
        let auth = try await authorise()
        try await commit(commitBody(for: vote, uid: auth.uid), token: auth.token)
    }

    /// Takes this install's report for the game back.
    public func withdraw(appid: Int) async throws {
        guard let known = identity() else { return }
        let auth = try await authorise(known: known)
        try await commit(deleteBody(appid: appid, uid: auth.uid), token: auth.token)
    }

    private func authorise(known: CommunityIdentity? = nil) async throws -> (uid: String, token: String) {
        if let id = known ?? identity() {
            if let token = try await refresh(id) { return (id.uid, token) }
            // The saved id was refused (account removed): a fresh one is made below.
        }
        let object = try await post("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)", json: ["returnSecureToken": true], token: nil)
        guard let uid = object["localId"] as? String, let refresh = object["refreshToken"] as? String, let token = object["idToken"] as? String else {
            throw CommunityReportError.rejected("sign-in")
        }
        save(CommunityIdentity(uid: uid, refreshToken: refresh))
        return (uid, token)
    }

    /// A fresh access token for a saved id; nil when Firebase no longer knows the id.
    private func refresh(_ id: CommunityIdentity) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let token = id.refreshToken.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id.refreshToken
        request.httpBody = Data("grant_type=refresh_token&refresh_token=\(token)".utf8)
        request.timeoutInterval = 20
        let (data, status) = try await perform(request)
        if status == 400 { return nil }
        guard (200..<300).contains(status), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["id_token"] as? String else { throw CommunityReportError.rejected("HTTP \(status)") }
        return access
    }

    private func commit(_ body: Data, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents:commit")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 20
        let (data, status) = try await perform(request)
        if (200..<300).contains(status) { return }
        throw Self.error(forStatus: status, body: data)
    }

    private func post(_ url: String, json: [String: Any], token: String?) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        request.timeoutInterval = 20
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else { throw Self.error(forStatus: status, body: data) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw CommunityReportError.offline
        }
    }

    /// Maps Firebase's answer to something a player can read. A project that is not set up yet
    /// answers 400/403/404 with a reason like OPERATION_NOT_ALLOWED or "database does not exist".
    static func error(forStatus status: Int, body: Data) -> CommunityReportError {
        let text = String(data: body, encoding: .utf8) ?? ""
        let notSetUp = ["OPERATION_NOT_ALLOWED", "CONFIGURATION_NOT_FOUND", "has not been used", "does not exist", "SERVICE_DISABLED"]
        if notSetUp.contains(where: text.contains) || status == 404 { return .unavailable }
        if status == 403 { return .rejected("403") }
        return .rejected("HTTP \(status)")
    }
}

extension CommunityVote: Identifiable {
    public var id: Int { appid }
}
