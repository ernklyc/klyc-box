import XCTest
@testable import KLYCKit

final class SteamBrowserArgumentsTests: XCTestCase {
    private let steam = "/x/drive_c/Program Files (x86)/Steam/steam.exe"

    func testWine11EnginesGetSoftwareRenderingForSteam() {
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: steam, engineID: "x64-crossover26.3-r17", arguments: []), ["-cef-disable-gpu"])
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: steam, engineID: "x64-crossover26.3-r17", arguments: ["-silent"]), ["-silent", "-cef-disable-gpu"])
    }

    func testOtherEnginesAndProgramsAreLeftAlone() {
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: steam, engineID: "x64-sikarugir10.0_6-r19", arguments: []), [])
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: "/x/Game/game.exe", engineID: "x64-crossover26.3-r17", arguments: ["-w"]), ["-w"])
    }

    func testThePersonsOwnBrowserFlagsOrALinkDecide() {
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: steam, engineID: "x64-crossover26.3-r17", arguments: ["-cef-force-gpu"]), ["-cef-force-gpu"])
        XCTAssertEqual(WineRunner.steamBrowserArguments(executable: steam, engineID: "x64-crossover26.3-r17", arguments: ["steam://open/main"]), ["steam://open/main"])
    }
}
