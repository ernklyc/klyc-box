import XCTest
@testable import KLYCKit

final class ModInstallerTests: XCTestCase {
    var root: URL!
    var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appending(path: "mods-\(UUID().uuidString)")
        root = work.appending(path: "game")
        try FileManager.default.createDirectory(at: root.appending(path: "content"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: work) }

    func make(_ relative: String, _ text: String, under base: URL? = nil) throws -> URL {
        let url = (base ?? work).appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func read(_ relative: String) -> String? { try? String(contentsOf: root.appending(path: relative), encoding: .utf8) }

    func testAFolderKeepsItsNameAndItsContents() throws {
        _ = try make("incoming/MyCar/data.ini", "a"); _ = try make("incoming/MyCar/skin/s.dds", "b")
        let plan = try ModInstaller.plan(sources: [work.appending(path: "incoming/MyCar")], into: root, subfolder: "content/cars")
        XCTAssertEqual(Set(plan.files.map(\.relative)), ["content/cars/MyCar/data.ini", "content/cars/MyCar/skin/s.dds"])
        let result = try ModInstaller.install(plan, into: root, overwrite: false)
        XCTAssertEqual(result.added.count, 2)
        XCTAssertEqual(read("content/cars/MyCar/skin/s.dds"), "b")
    }

    func testExistingFilesAreSkippedUnlessOverwritingAndOverwrittenOnesAreBackedUp() throws {
        _ = try make("content/a.txt", "old", under: root)
        let source = try make("in/a.txt", "new")
        let plan = try ModInstaller.plan(sources: [source], into: root, subfolder: "content")
        XCTAssertEqual(plan.conflicts, ["content/a.txt"])
        let skipped = try ModInstaller.install(plan, into: root, overwrite: false)
        XCTAssertEqual(skipped.skipped, ["content/a.txt"]); XCTAssertEqual(read("content/a.txt"), "old")
        let replaced = try ModInstaller.install(plan, into: root, overwrite: true)
        XCTAssertEqual(replaced.replaced, ["content/a.txt"]); XCTAssertEqual(read("content/a.txt"), "new")
    }

    func testUndoRestoresReplacedFilesAndRemovesAddedOnesAndEmptyFolders() throws {
        _ = try make("content/a.txt", "old", under: root)
        let one = try make("in/a.txt", "new"), two = try make("in/MyMod/b.txt", "b")
        let plan = try ModInstaller.plan(sources: [one, work.appending(path: "in/MyMod")], into: root, subfolder: "content")
        try ModInstaller.install(plan, into: root, overwrite: true)
        XCTAssertNotNil(ModInstaller.lastRecord(in: root))
        XCTAssertEqual(try ModInstaller.undoLast(in: root), 2)
        XCTAssertEqual(read("content/a.txt"), "old")
        XCTAssertNil(read("content/MyMod/b.txt"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "content/MyMod").path))
        XCTAssertNil(ModInstaller.lastRecord(in: root))
        _ = two
    }

    func testHistoryListsEveryInstallNewestFirst() throws {
        let one = try make("in/a.txt", "1"), two = try make("in/b.txt", "2")
        try ModInstaller.install(try ModInstaller.plan(sources: [one], into: root), into: root, overwrite: false, now: Date(timeIntervalSince1970: 1_000))
        try ModInstaller.install(try ModInstaller.plan(sources: [two], into: root), into: root, overwrite: false, now: Date(timeIntervalSince1970: 2_000))
        let history = ModInstaller.records(in: root)
        XCTAssertEqual(history.map(\.added), [["b.txt"], ["a.txt"]])
        _ = try ModInstaller.undoLast(in: root)
        XCTAssertEqual(ModInstaller.records(in: root).map(\.added), [["a.txt"]])
    }

    func testASubfolderCannotLeaveTheGameFolder() throws {
        let source = try make("in/x.txt", "x")
        XCTAssertThrowsError(try ModInstaller.plan(sources: [source], into: root, subfolder: "../outside")) {
            XCTAssertEqual($0 as? ModInstaller.Failure, .outsideGameFolder)
        }
    }

    func testNothingToInstallIsAnError() {
        XCTAssertThrowsError(try ModInstaller.plan(sources: [work.appending(path: "missing")], into: root)) {
            XCTAssertEqual($0 as? ModInstaller.Failure, .nothingToInstall)
        }
    }

    func testWindowsPaths() {
        let drive = URL(fileURLWithPath: "/data/bottles/Games/drive_c")
        XCTAssertEqual(WindowsPath.string(for: drive.appending(path: "Program Files (x86)/Steam/steamapps/common/Hades"), driveC: drive),
                       "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Hades")
        XCTAssertEqual(WindowsPath.string(for: URL(fileURLWithPath: "/Volumes/SSD/Games/X"), driveC: drive), "Z:\\Volumes\\SSD\\Games\\X")
    }

    func testDLLOverridesAreOneAppendEntry() {
        var env: [String: String] = [:]
        env = ModDLLOverrides.adding("dwrite", to: env)
        env = ModDLLOverrides.adding("Version.dll", to: env)
        XCTAssertEqual(env["WINEDLLOVERRIDES+"], "dwrite,version=n,b")
        XCTAssertEqual(ModDLLOverrides.names(in: env), ["dwrite", "version"])
        env = ModDLLOverrides.removing("dwrite", from: env)
        XCTAssertEqual(env["WINEDLLOVERRIDES+"], "version=n,b")
        env = ModDLLOverrides.removing("version", from: env)
        XCTAssertNil(env["WINEDLLOVERRIDES+"])
    }
}

final class ModCatalogTests: XCTestCase {
    func testTheShippedCatalogDecodesAndKnowsAssettoCorsa() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "db/mods.json")
        let catalog = try JSONDecoder().decode(ModCatalog.self, from: Data(contentsOf: url))
        let ac = try XCTUnwrap(catalog.entry(for: "steam:244210"))
        XCTAssertTrue(ac.folders?.contains { $0.path == "content/cars" } == true)
        XCTAssertNil(catalog.entry(for: "steam:0"))
    }
}
