import XCTest
@testable import KLYCKit

final class GameFolderScanTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ url: URL, _ size: Int = 10) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
    }

    func testFindsPlainGameFoldersAndPicksTheGameProgram() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try write(root.appending(path: "DeadCells/deadcells.exe"), 500)
        try write(root.appending(path: "DeadCells/UnityCrashHandler64.exe"), 9000)
        try write(root.appending(path: "AlanWakeRemastered/Game_f_x64_EOS.exe"), 800)
        try write(root.appending(path: "AlanWakeRemastered/vc_redist.x64.exe"), 99999)
        try write(root.appending(path: "Sifu/Binaries/Sifu.exe"), 300)          // one level down
        try write(root.appending(path: "logs/notagame.exe"))
        try write(root.appending(path: "Empty/readme.txt"))
        let scan = GameFolderScan.scan(root)
        XCTAssertEqual(scan.programs.map(\.name), ["Alan Wake Remastered", "Dead Cells", "Sifu"])
        XCTAssertEqual(scan.programs[1].executable.lastPathComponent, "deadcells.exe")
        XCTAssertEqual(scan.programs[0].executable.lastPathComponent, "Game_f_x64_EOS.exe", "the redistributable is plumbing, not the game")
        XCTAssertNil(scan.steamLibrary)
    }

    func testRecognisesASteamLibraryFolder() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "steamapps"), withIntermediateDirectories: true)
        try """
        "AppState"
        {
        \t"appid"\t\t"292030"
        \t"name"\t\t"The Witcher 3"
        }
        """.write(to: root.appending(path: "steamapps/appmanifest_292030.acf"), atomically: true, encoding: .utf8)
        try write(root.appending(path: "steamapps/common/The Witcher 3/witcher3.exe"))
        let scan = GameFolderScan.scan(root)
        XCTAssertEqual(scan.steamLibrary, root); XCTAssertEqual(scan.steamGames, ["The Witcher 3"])
        XCTAssertTrue(scan.programs.isEmpty, "steamapps is a library, not a game folder")
    }

    func testHumanName() {
        XCTAssertEqual(GameFolderScan.humanName("DiscoElysium"), "Disco Elysium")
        XCTAssertEqual(GameFolderScan.humanName("Sifu"), "Sifu")
        XCTAssertEqual(GameFolderScan.humanName("Left_4_Dead"), "Left 4 Dead")
    }
}

final class SteamLibraryFoldersTests: XCTestCase {
    let vdf = "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"C:\\\\Program Files (x86)\\\\Steam\"\n\t\t\"apps\"\n\t\t{\n\t\t\t\"244210\"\t\t\"1\"\n\t\t}\n\t}\n}\n"

    func testWindowsPathAndBack() {
        XCTAssertEqual(SteamLibraryFolders.windowsPath(forHost: "/Volumes/SSD/GameHub"), "Z:\\Volumes\\SSD\\GameHub")
        let driveC = URL(fileURLWithPath: "/b/drive_c"), dos = URL(fileURLWithPath: "/b/dosdevices")
        XCTAssertEqual(SteamLibraryFolders.hostPath(forWindows: "Z:\\\\Volumes\\\\SSD\\\\GameHub", driveC: driveC, dosdevices: dos)?.path, "/Volumes/SSD/GameHub")
        XCTAssertEqual(SteamLibraryFolders.hostPath(forWindows: "C:\\\\Games", driveC: driveC, dosdevices: dos)?.path, "/b/drive_c/Games")
        XCTAssertNil(SteamLibraryFolders.hostPath(forWindows: "nonsense", driveC: driveC, dosdevices: dos))
    }

    func testAddingNumbersTheNewFolderAndIsIdempotent() throws {
        let folder = URL(fileURLWithPath: "/Volumes/SSD/GameHub")
        let added = try XCTUnwrap(SteamLibraryFolders.adding(folder: folder, games: [("292030", 70)], to: vdf))
        XCTAssertTrue(added.contains("\t\"1\"\n\t{"), "the next number after 0")
        XCTAssertTrue(added.contains("Z:\\\\Volumes\\\\SSD\\\\GameHub"))
        XCTAssertTrue(added.contains("\"292030\"\t\t\"70\""))
        XCTAssertTrue(added.contains("C:\\\\Program Files (x86)\\\\Steam"), "the existing library is untouched")
        XCTAssertNil(SteamLibraryFolders.adding(folder: folder, games: [], to: added), "already listed")
        let driveC = URL(fileURLWithPath: "/b/drive_c"), dos = URL(fileURLWithPath: "/b/dosdevices")
        XCTAssertEqual(SteamLibraryFolders.extraFolders(vdf: added, driveC: driveC, dosdevices: dos).map(\.path), ["/Volumes/SSD/GameHub"])
    }

    func testASharedFolderIsFoundAndRemovedAndTheOwnOneStays() throws {
        var text = vdf
        text = try XCTUnwrap(SteamLibraryFolders.adding(folder: URL(fileURLWithPath: "/Volumes/SSD/Steam"), games: [("1", 1)], to: text))
        text = try XCTUnwrap(SteamLibraryFolders.adding(folder: URL(fileURLWithPath: "/Volumes/SSD/Mine"), games: [("2", 2)], to: text))
        let driveC = URL(fileURLWithPath: "/b/drive_c"), dos = URL(fileURLWithPath: "/b/dosdevices")
        let macSteam = [URL(fileURLWithPath: "/Volumes/SSD/Steam")]
        XCTAssertEqual(SteamLibraryFolders.shared(vdf: text, driveC: driveC, dosdevices: dos, with: macSteam).map(\.path), ["/Volumes/SSD/Steam"])
        let cleaned = try XCTUnwrap(SteamLibraryFolders.removing(folders: macSteam, from: text, driveC: driveC, dosdevices: dos))
        XCTAssertFalse(cleaned.contains("SSD\\\\Steam"), "the shared folder is gone")
        XCTAssertTrue(cleaned.contains("SSD\\\\Mine"), "a folder only this Steam uses stays")
        XCTAssertTrue(cleaned.contains("C:\\\\Program Files (x86)\\\\Steam"), "Steam's own folder always stays")
        XCTAssertTrue(SteamLibraryFolders.shared(vdf: cleaned, driveC: driveC, dosdevices: dos, with: macSteam).isEmpty)
        XCTAssertNil(SteamLibraryFolders.removing(folders: macSteam, from: cleaned, driveC: driveC, dosdevices: dos))
    }
}
