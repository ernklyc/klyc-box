import XCTest
@testable import KLYCKit

final class BottleTests: XCTestCase {
    func testWindowsPathResolution() {
        let b = Bottle(url: URL(fileURLWithPath: "/tmp/b"), settings: BottleSettings(name: "b", engineID: "e"))
        XCTAssertEqual(b.resolve(windowsPath: "C:\\Program Files (x86)\\Steam\\steam.exe").path, "/tmp/b/drive_c/Program Files (x86)/Steam/steam.exe")
        XCTAssertEqual(b.resolve(windowsPath: "windows\\system32\\notepad.exe").path, "/tmp/b/drive_c/windows/system32/notepad.exe")
    }

    func testSettingsRoundTrip() throws {
        var s = BottleSettings(name: "play", engineID: "x64-test")
        s.pins = [Pin(name: "Steam", path: "Program Files (x86)/Steam/steam.exe", renderer: .dxmt)]
        s.environment["FOO"] = "bar"
        let data = try JSONEncoder.klycbox.encode(s)
        let back = try JSONDecoder.klycbox.decode(BottleSettings.self, from: data)
        XCTAssertEqual(back.pins.first?.name, "Steam")
        XCTAssertEqual(back.environment["FOO"], "bar")
        XCTAssertEqual(back.renderer, .dxmt)
    }

    func testRecipeDecodes() throws {
        let json = """
        {"id":"t","kind":"launcher","title":"T","steps":[
          {"type":"registry","key":"HKCU\\\\Software\\\\X","name":"Y","valueType":"REG_DWORD","data":"0"},
          {"type":"note","text":"hello"},
          {"type":"renderer","renderer":"d3dmetal"}]}
        """
        let r = try JSONDecoder.klycbox.decode(Recipe.self, from: Data(json.utf8))
        XCTAssertEqual(r.steps.count, 3)
        if case let .registry(key, _, _, _) = r.steps[0] { XCTAssertEqual(key, "HKCU\\Software\\X") } else { XCTFail() }
    }

    func testManifestDecodes() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "spike/engine-manifest.json")
        let m = try EngineManifest.load(from: url)
        XCTAssertEqual(m.arch, "x86_64")
        XCTAssertNotNil(m.licenses?["apple-gptk-license-2023-08-17"])
        XCTAssertEqual(EngineManifest.gatedRenderers["d3dmetal"], "apple-gptk-license-2023-08-17")
        XCTAssertEqual(m.orderedComponents.first?.name, "dxmt")
    }
}

final class SteamLibraryTests: XCTestCase {
    func testACFParse() throws {
        let acf = """
        "AppState"
        {
        \t"appid"\t\t"1902490"
        \t"name"\t\t"Aperture Desk Job"
        \t"StateFlags"\t\t"4"
        \t"installdir"\t\t"Aperture Desk Job"
        \t"SizeOnDisk"\t\t"3406000000"
        }
        """
        let dir = FileManager.default.temporaryDirectory.appending(path: "acf-\(UUID().uuidString)/steamapps")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: dir.appending(path: "common/Aperture Desk Job"), withIntermediateDirectories: true)
        let tmp = dir.appending(path: "appmanifest_1902490.acf")
        try acf.write(to: tmp, atomically: true, encoding: .utf8)
        let game = SteamLibrary.parseManifest(tmp)
        XCTAssertEqual(game?.appid, 1902490)
        XCTAssertEqual(game?.name, "Aperture Desk Job")
        XCTAssertTrue(game?.isReady == true)
        XCTAssertEqual(game?.sizeOnDisk, 3_406_000_000)
    }

    /// The files were deleted by hand but Steam's manifest is still there: that is not an installed game.
    func testAManifestWithoutItsFolderIsNotInstalled() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "acf-\(UUID().uuidString)/steamapps")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appending(path: "appmanifest_5.acf")
        try "\"AppState\"\n{\n\t\"appid\"\t\t\"5\"\n\t\"name\"\t\t\"Gone\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"installdir\"\t\t\"Gone\"\n\t\"SizeOnDisk\"\t\t\"100\"\n}".write(to: tmp, atomically: true, encoding: .utf8)
        let game = SteamLibrary.parseManifest(tmp)
        XCTAssertEqual(game?.isReady, false); XCTAssertEqual(game?.sizeOnDisk, 0)
    }
}
