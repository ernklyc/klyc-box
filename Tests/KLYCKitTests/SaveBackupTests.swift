import XCTest
@testable import KLYCKit

final class SaveBackupTests: XCTestCase {
    var work: URL!
    var drive: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appending(path: "sv-\(UUID().uuidString)")
        drive = work.appending(path: "drive_c")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: work) }

    func put(_ relative: String, _ text: String) throws {
        let url = drive.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testFindsSavesByGameNameAndSteamCloud() throws {
        try put("users/crossover/Documents/My Games/Assetto Corsa/cfg/a.ini", "x")
        try put("users/crossover/AppData/Local/Hades/Profile1.sav", "y")
        try put("users/crossover/AppData/Local/Unrelated/z.txt", "z")
        try put("Program Files (x86)/Steam/userdata/123/244210/remote/save.dat", "c")
        let ac = SaveLocator.candidates(driveC: drive, steamAppID: 244210, names: ["Assetto Corsa"])
        XCTAssertEqual(ac.count, 2)
        XCTAssertTrue(ac.contains { $0.url.path.hasSuffix("My Games/Assetto Corsa") })
        XCTAssertTrue(ac.contains { $0.url.path.hasSuffix("userdata/123/244210") })
        let hades = SaveLocator.candidates(driveC: drive, steamAppID: nil, names: ["Hades"])
        XCTAssertEqual(hades.map { $0.url.lastPathComponent }, ["Hades"])
        XCTAssertTrue(SaveLocator.candidates(driveC: drive, steamAppID: nil, names: ["ab"]).isEmpty)   // too short to match on
    }

    func testBackupThenRestoreBringsTheSavesBack() throws {
        try put("users/crossover/AppData/Local/Hades/Profile1.sav", "original")
        let folder = drive.appending(path: "users/crossover/AppData/Local/Hades")
        let backups = work.appending(path: "backups")
        let zip = try SaveBackup.create(folders: [folder], driveC: drive, into: backups)
        XCTAssertEqual(SaveBackup.list(in: backups).count, 1)
        try "changed".write(to: folder.appending(path: "Profile1.sav"), atomically: true, encoding: .utf8)
        try "extra".write(to: folder.appending(path: "Profile2.sav"), atomically: true, encoding: .utf8)
        try SaveBackup.restore(zip, driveC: drive, currentFolders: [folder], safetyDirectory: work.appending(path: "safety"))
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "Profile1.sav"), encoding: .utf8), "original")
        XCTAssertEqual(SaveBackup.list(in: work.appending(path: "safety")).count, 1)   // what was there before the restore is kept
    }

    func testNothingToBackUpIsAnError() {
        XCTAssertThrowsError(try SaveBackup.create(folders: [work.appending(path: "elsewhere")], driveC: drive, into: work.appending(path: "b"))) {
            XCTAssertEqual($0 as? SaveBackup.Failure, .nothingToBackUp)
        }
    }
}

final class ScreenshotFinderTests: XCTestCase {
    func testFindsNewestFirstAndIgnoresOtherFiles() throws {
        let drive = FileManager.default.temporaryDirectory.appending(path: "sh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: drive) }
        let dir = drive.appending(path: "Program Files (x86)/Steam/userdata/42/760/remote/620/screenshots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, age) in [("old.jpg", 300.0), ("new.png", 10.0), ("notes.txt", 5.0)] {
            let u = dir.appending(path: name)
            try Data([0]).write(to: u)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: u.path)
        }
        XCTAssertEqual(ScreenshotFinder.find(driveC: drive, steamAppID: 620).map(\.lastPathComponent), ["new.png", "old.jpg"])
        XCTAssertTrue(ScreenshotFinder.find(driveC: drive, steamAppID: 1).isEmpty)
    }
}
