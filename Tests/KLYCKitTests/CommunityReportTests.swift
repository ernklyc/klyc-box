import XCTest
@testable import KLYCKit

/// A canned network for CommunityReports: answers by URL, records every request.
final class StubNetwork: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [(match: String, status: Int, body: String)] = []
    nonisolated(unsafe) static var seen: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!.absoluteString
        Self.seen.append(request)
        if let body = request.httpBody ?? request.httpBodyStream.map({ s -> Data in
            s.open(); defer { s.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        }) { Self.bodies[url] = body }
        let hit = Self.answers.first { url.contains($0.match) } ?? (match: "", status: 404, body: "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: hit.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(hit.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class CommunityReportTests: XCTestCase {
    var home: URL!
    var reports: CommunityReports!

    override func setUp() {
        home = FileManager.default.temporaryDirectory.appending(path: "hb-community-\(UUID().uuidString)")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubNetwork.self]
        StubNetwork.answers = []; StubNetwork.seen = []; StubNetwork.bodies = [:]
        reports = CommunityReports(paths: KLYCPaths(home: home), session: URLSession(configuration: config), projectID: "test-proj", apiKey: "KEY")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    func vote(note: String = "ok") -> CommunityVote {
        CommunityVote(appid: 440, works: true, rating: 4, chip: "Apple M4", macos: "15.1", engine: "wine 10", renderer: "dxmt", note: note)
    }

    func testVoteClampsAndTrimsToTheRulesLimits() {
        let v = CommunityVote(appid: 1, works: false, rating: 9, chip: String(repeating: "x", count: 99), macos: String(repeating: "1", count: 50),
                              engine: String(repeating: "e", count: 99), renderer: String(repeating: "r", count: 99), note: "  " + String(repeating: "n", count: 300))
        XCTAssertEqual(v.rating, 5)
        XCTAssertEqual(CommunityVote(appid: 1, works: true, rating: -3, chip: "", macos: "", engine: "").rating, 1)
        XCTAssertEqual(v.chip.count, 40); XCTAssertEqual(v.macos.count, 20); XCTAssertEqual(v.engine.count, 60)
        XCTAssertEqual(v.renderer.count, 20); XCTAssertEqual(v.note.count, 200)
        XCTAssertFalse(v.note.hasPrefix(" "))
    }

    func testChipLosesTheApplePrefixAndInvalidIdsAreRefused() {
        XCTAssertEqual(vote().chip, "M4")
        XCTAssertFalse(CommunityVote(appid: 0, works: true, rating: 3, chip: "", macos: "", engine: "").isValid)
        XCTAssertFalse(CommunityVote(appid: 100_000_000, works: true, rating: 3, chip: "", macos: "", engine: "").isValid)
        XCTAssertTrue(vote().isValid)
    }

    func testDisclosureListsExactlyWhatIsSent() {
        let names = vote().disclosure.map(\.name)
        XCTAssertEqual(names, ["appid", "works", "rating", "chip", "macos", "engine", "renderer", "note"])
        let bare = CommunityVote(appid: 7, works: false, rating: 1, chip: "", macos: "", engine: "")
        XCTAssertEqual(bare.disclosure.map(\.name), ["appid", "works", "rating"])
    }

    func testCommitBodyMatchesTheFieldsTheRulesAllowAndUsesServerTime() throws {
        let body = reports.commitBody(for: vote(), uid: "U1")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let write = try XCTUnwrap((json["writes"] as? [[String: Any]])?.first)
        let update = try XCTUnwrap(write["update"] as? [String: Any])
        XCTAssertEqual(update["name"] as? String, "projects/test-proj/databases/(default)/documents/reports/440_U1")
        let fields = try XCTUnwrap(update["fields"] as? [String: Any])
        let allowed: Set<String> = ["appid", "works", "rating", "chip", "macos", "engine", "renderer", "note"]
        XCTAssertTrue(Set(fields.keys).isSubset(of: allowed))
        XCTAssertEqual((fields["appid"] as? [String: String])?["integerValue"], "440")
        XCTAssertEqual((fields["rating"] as? [String: String])?["integerValue"], "4")
        XCTAssertEqual((fields["works"] as? [String: Bool])?["booleanValue"], true)
        let transform = try XCTUnwrap((write["updateTransforms"] as? [[String: Any]])?.first)
        XCTAssertEqual(transform["fieldPath"] as? String, "updatedAt")
        XCTAssertEqual(transform["setToServerValue"] as? String, "REQUEST_TIME")
        XCTAssertNil(fields["updatedAt"], "the client never supplies the time")
    }

    func testEmptyOptionalFieldsAreNotSent() throws {
        let bare = CommunityVote(appid: 7, works: false, rating: 2, chip: "", macos: "", engine: "")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reports.commitBody(for: bare, uid: "U")) as? [String: Any])
        let fields = try XCTUnwrap((((json["writes"] as? [[String: Any]])?.first?["update"]) as? [String: Any])?["fields"] as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["appid", "works", "rating"])
    }

    /// The same bytes the emulator test (`reports/rest.test.mjs`) posts against the real rules.
    func testCommitBodyEqualsTheFixtureTheRulesTestUses() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "reports/fixtures/commit-body.json")
        let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
        let actual = try JSONSerialization.jsonObject(with: reports.commitBody(for: vote(), uid: "UID")) as? NSDictionary
        // The fixture is written for project "test-proj"; the node test swaps in the emulator's project.
        XCTAssertEqual(actual, expected)
    }

    func testFirstSendSignsInAnonymouslyThenWritesAndRemembersTheId() async throws {
        StubNetwork.answers = [
            ("accounts:signUp", 200, #"{"localId":"U1","refreshToken":"R1","idToken":"T1"}"#),
            ("documents:commit", 200, "{}"),
        ]
        try await reports.send(vote())
        XCTAssertEqual(reports.identity(), CommunityIdentity(uid: "U1", refreshToken: "R1"))
        let commit = try XCTUnwrap(StubNetwork.seen.last)
        XCTAssertEqual(commit.value(forHTTPHeaderField: "Authorization"), "Bearer T1")
        XCTAssertTrue(commit.url!.absoluteString.contains("projects/test-proj/"))
        let sent = try XCTUnwrap(StubNetwork.bodies.first { $0.key.contains("documents:commit") }?.value)
        let name = ((((try JSONSerialization.jsonObject(with: sent) as? [String: Any])?["writes"] as? [[String: Any]])?.first?["update"]) as? [String: Any])?["name"] as? String
        XCTAssertEqual(name, "projects/test-proj/databases/(default)/documents/reports/440_U1")
    }

    func testLaterSendsReuseTheIdThroughARefreshToken() async throws {
        StubNetwork.answers = [
            ("accounts:signUp", 200, #"{"localId":"U1","refreshToken":"R1","idToken":"T1"}"#),
            ("securetoken", 200, #"{"id_token":"T2"}"#),
            ("documents:commit", 200, "{}"),
        ]
        try await reports.send(vote())
        StubNetwork.seen = []
        try await reports.send(vote(note: "again"))
        XCTAssertFalse(StubNetwork.seen.contains { $0.url!.absoluteString.contains("signUp") }, "no second anonymous account")
        XCTAssertEqual(StubNetwork.seen.last?.value(forHTTPHeaderField: "Authorization"), "Bearer T2")
    }

    func testARefusedSavedIdIsReplacedByANewOne() async throws {
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        reports.save(CommunityIdentity(uid: "OLD", refreshToken: "ROLD"))
        StubNetwork.answers = [
            ("securetoken", 400, #"{"error":{"message":"INVALID_REFRESH_TOKEN"}}"#),
            ("accounts:signUp", 200, #"{"localId":"NEW","refreshToken":"RNEW","idToken":"TN"}"#),
            ("documents:commit", 200, "{}"),
        ]
        try await reports.send(vote())
        XCTAssertEqual(reports.identity()?.uid, "NEW")
    }

    func testWithdrawDeletesTheDocumentAndDoesNothingWithoutAnId() async throws {
        try await reports.withdraw(appid: 440)
        XCTAssertTrue(StubNetwork.seen.isEmpty, "never signed in: nothing to take back, nothing asked")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        reports.save(CommunityIdentity(uid: "U1", refreshToken: "R1"))
        StubNetwork.answers = [("securetoken", 200, #"{"id_token":"T2"}"#), ("documents:commit", 200, "{}")]
        try await reports.withdraw(appid: 440)
        let body = try XCTUnwrap(StubNetwork.bodies.first { $0.key.contains("documents:commit") }?.value)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("\"delete\""))
    }

    func testAProjectThatIsNotSetUpYetSaysSoInsteadOfPretendingToSend() async {
        StubNetwork.answers = [("accounts:signUp", 400, #"{"error":{"message":"OPERATION_NOT_ALLOWED"}}"#)]
        do { try await reports.send(vote()); XCTFail("must throw") }
        catch { XCTAssertEqual(error as? CommunityReportError, .unavailable) }
        XCTAssertNil(reports.identity())
    }

    func testRulesRefusalAndOffline() async {
        StubNetwork.answers = [("accounts:signUp", 200, #"{"localId":"U1","refreshToken":"R1","idToken":"T1"}"#), ("documents:commit", 403, #"{"error":{"status":"PERMISSION_DENIED"}}"#)]
        do { try await reports.send(vote()); XCTFail("must throw") }
        catch { XCTAssertEqual(error as? CommunityReportError, .rejected("403")) }
        XCTAssertEqual(CommunityReports.error(forStatus: 404, body: Data()), .unavailable)
    }

    func testSentVotesAreKeptPerGameAndCanBeForgotten() {
        let store = SentVoteStore(paths: KLYCPaths(home: home))
        XCTAssertTrue(store.all().isEmpty)
        store.set(SentVote(works: true, rating: 5, note: "great"), for: 440)
        store.set(SentVote(works: false, rating: 1, note: ""), for: 730)
        XCTAssertEqual(store.all()[440]?.rating, 5)
        XCTAssertEqual(store.all().count, 2)
        store.set(nil, for: 440)
        XCTAssertNil(store.all()[440])
        XCTAssertEqual(store.all()[730]?.works, false)
    }
}
