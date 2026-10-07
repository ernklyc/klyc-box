import XCTest
@testable import KLYCKit

final class SteamStoreTests: XCTestCase {
    func testPresenceFromTheCommunityXML() {
        XCTAssertEqual(SteamPresence.parse(xml: "<profile><onlineState>online</onlineState><stateMessage><![CDATA[Online]]></stateMessage></profile>").state, .online)
        let off = SteamPresence.parse(xml: "<profile><onlineState>offline</onlineState><stateMessage><![CDATA[Last Online 3 hrs, 5 mins ago]]></stateMessage></profile>")
        XCTAssertEqual(off.state, .offline); XCTAssertEqual(off.message, "Last Online 3 hrs, 5 mins ago")
        let game = SteamPresence.parse(xml: "<profile><onlineState>in-game</onlineState><stateMessage><![CDATA[In-Game<br/>Counter-Strike 2]]></stateMessage><inGameInfo><gameName><![CDATA[Counter-Strike 2]]></gameName><gameLink><![CDATA[https://steamcommunity.com/app/730]]></gameLink></inGameInfo></profile>")
        XCTAssertEqual(game.state, .inGame); XCTAssertEqual(game.appid, 730); XCTAssertEqual(game.gameName, "Counter-Strike 2")
        XCTAssertEqual(SteamPresence.parse(xml: "<profile><privacyState>private</privacyState></profile>").state, .unknown)
        // A friends-only profile reads "offline" to a stranger: that is not knowledge.
        XCTAssertEqual(SteamPresence.parse(xml: "<profile><onlineState>offline</onlineState><privacyState>friendsonly</privacyState></profile>").state, .unknown)
    }

    func testStoreDetailsWithRequirementsAndWithout() throws {
        let json = """
        {"244210":{"success":true,"data":{"name":"Assetto Corsa","short_description":"Racing &amp; simulation","genres":[{"description":"Yarış"}],
        "platforms":{"windows":true,"mac":false,"linux":false},"release_date":{"date":"19 Ara 2014"},"metacritic":{"score":87},"developers":["Kunos"],
        "pc_requirements":{"minimum":"<strong>Minimum:</strong><br><ul class=\\"bb_ul\\"><li><strong>Bellek:</strong> 2 GB RAM<br></li><li><strong>Depolama:</strong> 15 GB available space<br></li></ul>","recommended":"<ul><li>Memory: 8 GB RAM</li></ul>"},
        "mac_requirements":[]}}}
        """.data(using: .utf8)!
        let info = try XCTUnwrap(SteamStoreInfo.parse(appid: 244210, json: json))
        XCTAssertEqual(info.name, "Assetto Corsa"); XCTAssertEqual(info.shortDescription, "Racing & simulation")
        XCTAssertTrue(info.windows); XCTAssertFalse(info.mac); XCTAssertEqual(info.metacritic, 87)
        XCTAssertTrue(info.macRequirements.isEmpty)
        XCTAssertEqual(info.pc.minimum, "Minimum:\n• Bellek: 2 GB RAM\n• Depolama: 15 GB available space")
        XCTAssertNil(SteamStoreInfo.parse(appid: 1, json: "{\"1\":{\"success\":false}}".data(using: .utf8)!))
    }

    func testSpecCheckComparesMemoryAndDisk() {
        let text = "Minimum:\n• Bellek: 16 GB RAM\n• Depolama: 80 GB available space\n• Graphics: GTX 970"
        XCTAssertEqual(SpecCheck.needs(text).ram, 16); XCTAssertEqual(SpecCheck.needs(text).disk, 80)
        let checks = SpecCheck.compare(text, ramBytes: 24 << 30, freeDiskBytes: 50 << 30, labels: ("RAM", "Disk"))
        XCTAssertEqual(checks.map(\.ok), [true, false])
        XCTAssertEqual(SpecCheck.needs("• Memory: 512 MB RAM").ram, 0.5)
        XCTAssertEqual(SpecCheck.needs("• Storage: 1 TB available space").disk, 1024)
    }
}
