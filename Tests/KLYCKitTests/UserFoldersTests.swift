import XCTest
@testable import KLYCKit

/// Discussion #157: game saves inside the environment instead of ~/Documents. The switch must
/// never lose a file in either direction, must be a no-op when the shape already matches, and
/// must restore what an earlier switch back set aside.
final class UserFoldersTests: XCTestCase {
    private var root: URL!
    private var driveC: URL!
    private var host: URL!
    private var user: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "userfolders-\(UUID().uuidString)")
        driveC = root.appending(path: "drive_c")
        host = root.appending(path: "host-Documents")
        user = driveC.appending(path: "users/tester")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: driveC.appending(path: "users/Public"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
        // What wineboot leaves: Documents is a link to the Mac's folder.
        try FileManager.default.createSymbolicLink(at: user.appending(path: "Documents"), withDestinationURL: host)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, in dir: URL) throws {
        try Data("x".utf8).write(to: dir.appending(path: name))
    }

    func testStartsLinkedAndOnlyRealUsersCount() {
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .linked(to: host.path))
        XCTAssertEqual(UserFolders.userDirectories(driveC: driveC).map(\.lastPathComponent), ["tester"], "Public is Wine's, never touched")
        XCTAssertFalse(UserFolders.hasFilesInside(driveC: driveC))
    }

    func testInsideReplacesTheLinkAndLeavesHostFilesWhereTheyAre() throws {
        try write("FromSoftware.txt", in: host)
        let notes = try UserFolders.set(inside: true, driveC: driveC, host: host)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .inside)
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: user.appending(path: "Documents").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: host.appending(path: "FromSoftware.txt").path), "the Mac's Documents is not moved")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: user.appending(path: "Documents").path), [], "starts empty inside")
        XCTAssertEqual(try UserFolders.set(inside: true, driveC: driveC, host: host), [], "already inside: nothing to do")
    }

    func testBackToLinkedKeepsTheInsideFolderWhenItHasFiles() throws {
        try UserFolders.set(inside: true, driveC: driveC, host: host)
        try write("save.es3", in: user.appending(path: "Documents"))
        XCTAssertTrue(UserFolders.hasFilesInside(driveC: driveC))
        let notes = try UserFolders.set(inside: false, driveC: driveC, host: host)
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .linked(to: host.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: user.appending(path: "Documents (environment)/save.es3").path), "nothing is deleted silently")
        XCTAssertFalse(UserFolders.hasFilesInside(driveC: driveC))
    }

    func testBackToLinkedDropsAnEmptyInsideFolder() throws {
        try UserFolders.set(inside: true, driveC: driveC, host: host)
        try UserFolders.set(inside: false, driveC: driveC, host: host)
        XCTAssertFalse(FileManager.default.fileExists(atPath: user.appending(path: "Documents (environment)").path))
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .linked(to: host.path))
        XCTAssertEqual(try UserFolders.set(inside: false, driveC: driveC, host: host), [], "already linked: nothing to do")
    }

    func testInsideAgainRestoresTheKeptFolder() throws {
        try UserFolders.set(inside: true, driveC: driveC, host: host)
        try write("save.es3", in: user.appending(path: "Documents"))
        try UserFolders.set(inside: false, driveC: driveC, host: host)
        let notes = try UserFolders.set(inside: true, driveC: driveC, host: host)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: user.appending(path: "Documents/save.es3").path), "the kept folder is Documents again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: user.appending(path: "Documents (environment)").path))
    }

    func testAMissingFolderIsCreatedOrLinkedAsAsked() throws {
        try FileManager.default.removeItem(at: user.appending(path: "Documents"))
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .missing)
        try UserFolders.set(inside: false, driveC: driveC, host: host)
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .linked(to: host.path))
        try FileManager.default.removeItem(at: user.appending(path: "Documents"))
        try UserFolders.set(inside: true, driveC: driveC, host: host)
        XCTAssertEqual(UserFolders.shape(userDirectory: user), .inside)
    }

    func testSettingDecodesWithoutTheKeyAndRoundTrips() throws {
        let json = #"{"name":"g","engineID":"e"}"#
        let s = try JSONDecoder().decode(BottleSettings.self, from: Data(json.utf8))
        XCTAssertFalse(s.keepFilesInside, "existing environments keep the link")
        var on = s; on.keepFilesInside = true
        let back = try JSONDecoder().decode(BottleSettings.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.keepFilesInside)
    }

    func testDesktopStaysInsideAndSteamShortcutsAreMovedNotDeleted() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "desk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let driveC = base.appending(path: "drive_c"), user = driveC.appending(path: "users/tester"), host = base.appending(path: "MacDesktop")
        try fm.createDirectory(at: user, withIntermediateDirectories: true); try fm.createDirectory(at: host, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: user.appending(path: "Desktop"), withDestinationURL: host)
        try "[InternetShortcut]\nURL=steam://rungameid/1145360\nICONFILE=C:\\Program Files (x86)\\Steam\\steam\\games\\x.ico\n".write(to: host.appending(path: "Hades.url"), atomically: true, encoding: .utf8)
        try "[InternetShortcut]\nURL=https://example.com\n".write(to: host.appending(path: "Mine.url"), atomically: true, encoding: .utf8)
        let notes = UserFolders.keepDesktopInside(driveC: driveC, hostDesktop: host)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: user.appending(path: "Desktop").path), "a real folder now")
        XCTAssertTrue(fm.fileExists(atPath: user.appending(path: "Desktop/Hades.url").path), "moved into the environment")
        XCTAssertFalse(fm.fileExists(atPath: host.appending(path: "Hades.url").path))
        XCTAssertTrue(fm.fileExists(atPath: host.appending(path: "Mine.url").path), "someone's own shortcut stays")
        XCTAssertTrue(UserFolders.keepDesktopInside(driveC: driveC, hostDesktop: host).isEmpty, "nothing to do the second time")
    }
}
