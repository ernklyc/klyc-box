import XCTest
@testable import KLYCKit

final class AnticheatIndexTests: XCTestCase {
    private func index(_ games: [Int: [String]]) -> AnticheatIndex {
        AnticheatIndex(byAppID: games.mapValues { AnticheatIndex.Entry(names: $0, linuxStatus: nil) })
    }

    func testOnlyRiskyAntiCheatsCount() {
        let i = index([1: ["Easy Anti-Cheat", "VAC"], 2: ["VAC"], 3: ["PunkBuster"], 4: ["RICOCHET"]])
        XCTAssertEqual(i.riskyNames(appid: 1), ["Easy Anti-Cheat"])
        XCTAssertEqual(i.riskyNames(appid: 2), [], "VAC runs fine under Wine")
        XCTAssertEqual(i.riskyNames(appid: 3), [])
        XCTAssertEqual(i.riskyNames(appid: 4), ["RICOCHET"], "names compare without case")
        XCTAssertEqual(i.riskyNames(appid: 99), [])
    }

    func testReadsTheDatabaseFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ac-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"{"games":{"a":{"title":"A","anticheats":["BattlEye"],"linuxStatus":"Running","steam_appid":10},"b":{"title":"B","anticheats":["BattlEye"]},"c":{"title":"C","anticheats":[],"steam_appid":11}}}"#
        try json.write(to: url, atomically: true, encoding: .utf8)
        let i = AnticheatIndex(file: url)
        XCTAssertEqual(i.byAppID[10]?.names, ["BattlEye"])
        XCTAssertEqual(i.byAppID[10]?.linuxStatus, "Running")
        XCTAssertNil(i.byAppID[11], "a game with no anti-cheat names is not listed")
        XCTAssertEqual(i.byAppID.count, 1, "a game without a Steam id cannot be matched")
    }

    func testMissingOrBrokenFileGivesAnEmptyIndex() {
        XCTAssertTrue(AnticheatIndex(file: nil).byAppID.isEmpty)
        XCTAssertTrue(AnticheatIndex(file: URL(fileURLWithPath: "/nonexistent.json")).byAppID.isEmpty)
    }

    func testTheShippedDatabaseLoads() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "db/anticheat.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("db/anticheat.json not in this checkout") }
        let i = AnticheatIndex(file: url)
        XCTAssertGreaterThan(i.byAppID.count, 500)
        // Battlefield 2042 ships EA anticheat: the notice must exist for it.
        XCTAssertEqual(i.riskyNames(appid: 1517290), ["EA anticheat"])
    }

    func testNoticeIsKeptForGamesWithoutAnswerAndDroppedWhereTheDatabaseSpeaks() {
        func entry(_ status: String, anticheat: Bool) -> GameDBEntry {
            let ac = anticheat ? #","anticheat":{"names":["EA anticheat"],"macVerdict":"blocked"}"# : ""
            let json = #"{"id":"x","title":"X","steam_appid":5,"status":"\#(status)"\#(ac)}"#
            return try! JSONDecoder().decode(GameDBEntry.self, from: Data(json.utf8))
        }
        let ac = index([5: ["Easy Anti-Cheat"], 6: ["BattlEye"]])
        func db(_ e: GameDBEntry?) -> GameDB { GameDB(entries: e.map { [$0] } ?? [], anticheat: ac) }
        XCTAssertEqual(db(nil).anticheatNotice(appid: 6), ["BattlEye"])
        XCTAssertEqual(db(entry("community", anticheat: false)).anticheatNotice(appid: 5), ["Easy Anti-Cheat"])
        XCTAssertEqual(db(entry("blocked-anticheat", anticheat: true)).anticheatNotice(appid: 5), [], "blocked already says it")
        XCTAssertEqual(db(entry("community", anticheat: true)).anticheatNotice(appid: 5), [], "a row with its own note speaks for itself")
        XCTAssertEqual(db(entry("verified-local", anticheat: false)).anticheatNotice(appid: 5), [], "tested here: the result is the answer")
    }
}
