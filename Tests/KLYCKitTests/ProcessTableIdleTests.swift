import XCTest
@testable import KLYCKit

final class ProcessTableIdleTests: XCTestCase {
    private let prefix = "/Users/me/Library/Application Support/KLYC-Box/bottles/games"
    private let server = "/private/tmp/.wine-501/server-100000f-1db1d89"

    func testWinePlumbingAndServicesAreIdle() {
        // services.exe, winedevice, plugplay, rpcss, svchost work in drive_c/windows, explorer in
        // system32, a Windows service (ExampleGamesService.exe) in drive_c/windows too (measured).
        let cwds = [server, prefix + "/drive_c/windows", prefix + "/drive_c/windows",
                    prefix + "/drive_c/windows/system32", prefix + "/drive_c/windows"]
        XCTAssertTrue(ProcessTable.isIdle(workingDirectories: cwds, prefix: prefix, serverDirectory: server))
    }

    func testNoProcessesIsIdle() {
        XCTAssertTrue(ProcessTable.isIdle(workingDirectories: [], prefix: prefix, serverDirectory: server))
    }

    func testAProgramInItsOwnFolderIsNotIdle() {
        let cwds = [server, prefix + "/drive_c/windows", prefix + "/drive_c/Program Files/ExampleGames Games/Launcher"]
        XCTAssertFalse(ProcessTable.isIdle(workingDirectories: cwds, prefix: prefix, serverDirectory: server))
    }

    func testASteamClientIsNotIdle() {
        let cwds = [server, prefix + "/drive_c/windows", prefix + "/drive_c/Program Files (x86)/Steam"]
        XCTAssertFalse(ProcessTable.isIdle(workingDirectories: cwds, prefix: prefix, serverDirectory: server))
    }

    func testAFolderNamedLikeWindowsOutsideItIsNotIdle() {
        // "drive_c/windowsgame" must not pass as "drive_c/windows".
        let cwds = [prefix + "/drive_c/windowsgame"]
        XCTAssertFalse(ProcessTable.isIdle(workingDirectories: cwds, prefix: prefix, serverDirectory: server))
    }

    func testServerWithoutDirectoryStillClassifies() {
        XCTAssertTrue(ProcessTable.isIdle(workingDirectories: [prefix + "/drive_c/windows"], prefix: prefix, serverDirectory: nil))
        XCTAssertFalse(ProcessTable.isIdle(workingDirectories: [server], prefix: prefix, serverDirectory: nil))
    }
}

final class ProcessTablePlumbingTests: XCTestCase {
    private let prefix = "/Users/me/Library/Application Support/KLYC-Box/bottles/games"

    func testWindowsSystemProcessesArePlumbing() {
        XCTAssertTrue(ProcessTable.isPlumbing(executable: "C:\\windows\\system32\\services.exe", workingDirectory: prefix + "/drive_c/windows", prefix: prefix))
        XCTAssertTrue(ProcessTable.isPlumbing(executable: "C:\\windows\\system32\\explorer.exe", workingDirectory: prefix + "/drive_c/windows/system32", prefix: prefix))
    }

    func testTheServerIsPlumbingWhereverItWorks() {
        XCTAssertTrue(ProcessTable.isPlumbing(executable: "/e/engine/bin/wineserver", workingDirectory: "/private/tmp/.wine-501/server-1-2", prefix: prefix))
    }

    func testAWindowsServiceCountsAsPlumbingByItsWorkingDirectory() {
        // ExampleGames's service is started by services.exe in drive_c/windows (measured 2026-09-18).
        XCTAssertTrue(ProcessTable.isPlumbing(executable: "C:\\Program Files\\ExampleGames Games\\Launcher\\ExampleGamesService.exe", workingDirectory: prefix + "/drive_c/windows", prefix: prefix))
    }

    func testAProgramInItsOwnFolderIsNotPlumbing() {
        XCTAssertFalse(ProcessTable.isPlumbing(executable: "C:\\Program Files (x86)\\Steam\\steam.exe", workingDirectory: prefix + "/drive_c/Program Files (x86)/Steam", prefix: prefix))
        XCTAssertFalse(ProcessTable.isPlumbing(executable: "C:/ProgramData/ExampleNet/Agent/Agent.exe", workingDirectory: prefix + "/drive_c/ProgramData/ExampleNet/Agent", prefix: prefix))
    }
}

final class PinOwnershipTests: XCTestCase {
    private let steam = Pin(name: "Steam", path: "Program Files (x86)/Steam/steam.exe", arguments: [], environment: ["WINEMSYNC": "0", "WINEESYNC": "0"], renderer: nil)
    private let examplegames = Pin(name: "ExampleGames Launcher", path: "Program Files/ExampleGames Games/Launcher/Launcher.exe", arguments: [], environment: [:], renderer: .dxvk)

    func testAHelperUnderThePinnedFolderBelongsToThePin() {
        XCTAssertEqual(Bottle.pin(owning: "C:\\Program Files (x86)\\Steam\\bin\\cef\\cef.win7x64\\steamwebhelper.exe", in: [steam, examplegames])?.name, "Steam")
        XCTAssertEqual(Bottle.pin(owning: "C:\\Program Files (x86)\\Steam\\steam.exe", in: [steam, examplegames])?.name, "Steam")
    }

    func testAProgramElsewhereBelongsToNoPin() {
        XCTAssertNil(Bottle.pin(owning: "C:\\Program Files\\ExampleGames Games\\Social Club\\SocialClubHelper.exe", in: [steam]))
        XCTAssertNil(Bottle.pin(owning: "C:\\windows\\system32\\services.exe", in: [steam, examplegames]))
    }

    func testForwardSlashesAndCaseDoNotMatter() {
        XCTAssertEqual(Bottle.pin(owning: "c:/program files/examplegames games/launcher/ExampleGamesService.exe", in: [steam, examplegames])?.name, "ExampleGames Launcher")
    }
}
