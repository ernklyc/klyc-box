import XCTest
@testable import KLYCKit

final class SteamProfileTests: XCTestCase {
    func testVDFBlocksPairsAndEscapes() {
        let root = TextVDF.parse("""
        "users"
        {
            "76561198060265729"
            {
                "PersonaName"\t\t"Te\\"ster"
                "Timestamp"\t\t"1791184087"
            }
        }
        // a comment
        "tail" "x"
        """)
        let user = root["users"]?.children.first
        XCTAssertEqual(user?.key, "76561198060265729")
        XCTAssertEqual(user?.string("PersonaName"), "Te\"ster")
        XCTAssertEqual(user?.int("Timestamp"), 1791184087)
        XCTAssertEqual(root.string("tail"), "x")
    }

    func testATruncatedFileGivesWhatWasReadAndNeverCrashes() {
        let root = TextVDF.parse("\"a\" { \"b\" \"1\" \"c\" { \"d\" ")
        XCTAssertEqual(root["a"]?.string("b"), "1")
    }

    func testProfileReadsHoursFriendsAndTheLastSignedInAccount() throws {
        let drive = FileManager.default.temporaryDirectory.appending(path: "sp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: drive) }
        let steam = drive.appending(path: "Program Files (x86)/Steam")
        try FileManager.default.createDirectory(at: steam.appending(path: "config"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steam.appending(path: "userdata/100000001/config"), withIntermediateDirectories: true)
        try """
        "users" { "76561198060265729" { "AccountName" "testuser" "PersonaName" "Tester" "Timestamp" "200" }
                  "76561197960265729" { "PersonaName" "Old" "Timestamp" "100" } }
        """.write(to: steam.appending(path: "config/loginusers.vdf"), atomically: true, encoding: .utf8)
        try """
        "UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" {
            "730" { "LastPlayed" "1789210715" "Playtime" "7335" "Playtime2wks" "120" }
            "480" { "LastPlayed" "1713302061" "Playtime" "65" }
            "760" { "cloud" { "used_bytes" "0" } }
        } } } }
        "WebStorage" { "FriendStoreLocalPrefs_100000001" "{\\"ePersonaState\\":7,\\"strNonFriendsAllowedToMsg\\":\\"\\"}" }
        "friends" { "100000001" { "name" "Me" } "200000002" { "name" "Friend" "avatar" "420d" } } }
        """.write(to: steam.appending(path: "userdata/100000001/config/localconfig.vdf"), atomically: true, encoding: .utf8)
        let p = try XCTUnwrap(SteamProfile.load(driveC: drive))
        XCTAssertEqual(p.personaName, "Tester")
        XCTAssertEqual(p.accountID, 100000001)
        XCTAssertEqual(p.totalMinutes, 7400)
        XCTAssertEqual(p.gamesPlayed, 2)
        XCTAssertEqual(p.lastTwoWeeksMinutes, 120)
        XCTAssertEqual(p.top(1).first?.appid, 730)
        XCTAssertEqual(p.persona, .invisible)
        XCTAssertEqual(p.friends.map(\.name), ["Friend"])           // the account itself is not its own friend
        XCTAssertEqual(p.friends.first?.steamID64, 76561197960265728 + 200000002)
    }

    func testNoSteamMeansNoProfile() { XCTAssertNil(SteamProfile.load(driveC: URL(fileURLWithPath: "/nonexistent"))) }
}
