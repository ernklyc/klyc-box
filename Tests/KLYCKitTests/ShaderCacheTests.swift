import XCTest
@testable import KLYCKit

final class ShaderCacheTests: XCTestCase {
    private func library() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "sc-\(UUID().uuidString)/steamapps", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d.deletingLastPathComponent()) }
        return d
    }
    private func game(_ steamapps: URL, appid: Int, bytes: Int) throws -> URL {
        try Data().write(to: steamapps.appending(path: "appmanifest_\(appid).acf"))
        let cache = steamapps.appending(path: "shadercache/\(appid)/DXVK_state_cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: cache.appending(path: "game.dxvk-cache"))
        return steamapps.appending(path: "shadercache/\(appid)", directoryHint: .isDirectory)
    }

    func testFindsTheCacheOfAnInstalledGameOnly() throws {
        let lib = try library()
        let cache = try game(lib, appid: 10, bytes: 100)
        // A cache with no manifest beside it belongs to a game this library no longer holds.
        try FileManager.default.createDirectory(at: lib.appending(path: "shadercache/99"), withIntermediateDirectories: true)
        XCTAssertEqual(ShaderCache.folders(appid: 10, steamapps: [lib]).map(\.path), [cache.path])
        XCTAssertTrue(ShaderCache.folders(appid: 99, steamapps: [lib]).isEmpty)
        XCTAssertTrue(ShaderCache.folders(appid: 11, steamapps: [lib]).isEmpty)
    }

    func testSizeCountsFilesRecursively() throws {
        let lib = try library()
        let cache = try game(lib, appid: 10, bytes: 1234)
        XCTAssertEqual(ShaderCache.size(of: [cache]), 1234)
        XCTAssertEqual(ShaderCache.size(of: []), 0)
    }

    func testClearEmptiesTheFolderButKeepsIt() throws {
        let lib = try library()
        let cache = try game(lib, appid: 10, bytes: 500)
        XCTAssertEqual(ShaderCache.clear([cache]), 500)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path), "Steam expects the folder to stay")
        XCTAssertEqual(ShaderCache.size(of: [cache]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.appending(path: "appmanifest_10.acf").path), "the manifest is not the cache")
    }

    func testClearRefusesAnythingThatIsNotAShaderCacheFolder() throws {
        let lib = try library()
        _ = try game(lib, appid: 10, bytes: 500)
        let notCache = lib.appending(path: "common/Game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: notCache, withIntermediateDirectories: true)
        try Data(count: 10).write(to: notCache.appending(path: "keep.dat"))
        XCTAssertEqual(ShaderCache.clear([notCache, lib]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: notCache.appending(path: "keep.dat").path))
        // A numeric folder that is not under shadercache is refused too.
        let numeric = lib.appending(path: "common/12345", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: numeric, withIntermediateDirectories: true)
        try Data(count: 10).write(to: numeric.appending(path: "keep.dat"))
        XCTAssertEqual(ShaderCache.clear([numeric]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: numeric.appending(path: "keep.dat").path))
    }
}

final class DesktopCopyTests: XCTestCase {
    private func scratch() throws -> (app: URL, desktop: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "dcopy-\(UUID().uuidString)", directoryHint: .isDirectory)
        let app = root.appending(path: "Applications/Buckshot Roulette.app", directoryHint: .isDirectory)
        let desktop = root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
        try "<plist/>".write(to: app.appending(path: "Contents/Info.plist"), atomically: true, encoding: .utf8)
        try MacAppStub.launchScript(url: URL(string: "klycbox://play/steam/1")!).write(to: app.appending(path: "Contents/MacOS/launch"), atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: app.appending(path: "Contents/Resources/icon.icns"))
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (app, desktop)
    }

    func testTheCopyCarriesTheIconAndIsFoundByTitle() throws {
        let (app, desktop) = try scratch()
        let copy = try MacAppStub.copyToDesktop(app, in: desktop)
        XCTAssertEqual(copy.lastPathComponent, "Buckshot Roulette.app")
        XCTAssertEqual(try Data(contentsOf: copy.appending(path: "Contents/Resources/icon.icns")), Data([1, 2, 3]), "the icon travels inside the bundle")
        XCTAssertEqual(MacAppStub.existingDesktopCopy(for: "Buckshot Roulette", in: desktop)?.path, copy.path)
        XCTAssertNil(MacAppStub.existingDesktopCopy(for: "Something Else", in: desktop))
    }

    func testRunningItAgainReplacesTheOldCopy() throws {
        let (app, desktop) = try scratch()
        try MacAppStub.copyToDesktop(app, in: desktop)
        try MacAppStub.copyToDesktop(app, in: desktop)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: desktop.path), ["Buckshot Roulette.app"])
    }

    func testTheAliasTheFirstVersionMadeIsCleanedUp() throws {
        let (app, desktop) = try scratch()
        let data = try app.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: desktop.appending(path: "Buckshot Roulette"))
        try MacAppStub.copyToDesktop(app, in: desktop)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: desktop.path), ["Buckshot Roulette.app"])
    }

    func testSomeoneElsesAppOfTheSameNameIsNotTreatedAsOurs() throws {
        let (_, desktop) = try scratch()
        let other = desktop.appending(path: "Buckshot Roulette.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other.appending(path: "MacOS"), withIntermediateDirectories: true)
        try "<plist/>".write(to: other.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho hi\n".write(to: other.appending(path: "MacOS/launch"), atomically: true, encoding: .utf8)
        XCTAssertNil(MacAppStub.existingDesktopCopy(for: "Buckshot Roulette", in: desktop), "without our play link it is not ours, and removing it is not ours to do")
    }
}
