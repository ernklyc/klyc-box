import XCTest
@testable import KLYCKit

final class PlayLinkTests: XCTestCase {
    func testPlayLinksStillParseAndRoundTrip() {
        let steam = PlayLink.parse(URL(string: "klycbox://play/steam/620?t=abc")!)
        XCTAssertEqual(steam, PlayLink.Request(target: .steam(appid: 620), token: "abc"))
        XCTAssertEqual(PlayLink.url(for: .steam(appid: 620), token: "abc").absoluteString, "klycbox://play/steam/620?t=abc")
        XCTAssertNil(PlayLink.parse(URL(string: "klycbox://play/steam/0")!))
    }

    /// Issue #53: a Mac app for a launcher opens it through `klycbox://open/launcher/<id>`.
    func testLauncherLinkParsesAndRoundTrips() {
        let url = PlayLink.url(for: .launcher(id: "steam"), token: "tok")
        XCTAssertEqual(url.absoluteString, "klycbox://open/launcher/steam?t=tok")
        XCTAssertEqual(PlayLink.parse(url), PlayLink.Request(target: .launcher(id: "steam"), token: "tok"))
        XCTAssertEqual(PlayLink.Target.launcher(id: "epic").libraryID, "launcher:epic")
        XCTAssertNil(PlayLink.parse(URL(string: "klycbox://open/steam")!))
        XCTAssertNil(PlayLink.parse(URL(string: "klycbox://open/launcher/../x")!))
        XCTAssertNil(PlayLink.parse(URL(string: "klycbox://open/launcher/Steam%20Client")!))
    }

    /// A stub must not drag KLYC-Box in front of the game it starts (issue #53).
    func testStubOpensTheLinkInTheBackground() {
        let script = MacAppStub.launchScript(url: URL(string: "klycbox://play/steam/620?t=x")!)
        XCTAssertTrue(script.contains("/usr/bin/open -g \"klycbox://play/steam/620?t=x\""))
    }
}
