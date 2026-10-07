import XCTest
@testable import KLYCKit

final class LocalVerdictTests: XCTestCase {
    func testAVerdictIsKeptPerGameAndCanBeRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalVerdictStore(paths: KLYCPaths(home: dir))
        let v = LocalVerdict(works: true, fps: 60, renderer: "dxmt", engine: "e1", chip: "Apple M4", macos: "27.0.1", minutes: 40,
                             date: Date(timeIntervalSince1970: 1_700_000_000))
        store.set(v, for: "steam:244210")
        XCTAssertEqual(store.all()["steam:244210"], v)
        XCTAssertEqual(v.machine, "M4, macOS 27.0.1")
        store.set(nil, for: "steam:244210")
        XCTAssertTrue(store.all().isEmpty)
    }

    func testTheExportCarriesTheMachineAndTheFramesThePlayerSaw() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lv2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalVerdictStore(paths: KLYCPaths(home: dir))
        store.set(LocalVerdict(works: true, fps: 45, engine: "e", chip: "Apple M4", macos: "27.0.1"), for: "steam:1")
        let text = String(decoding: try XCTUnwrap(store.exportJSON()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"fps\" : 45") && text.contains("Apple M4") && text.contains("steam:1"))
    }

    func testALongNormalSessionIsEnoughAndAShortOrCrashedOneIsNot() {
        XCTAssertTrue(AutoVerdict.works(reason: "ended", seconds: 600))
        XCTAssertTrue(AutoVerdict.works(reason: "ended", seconds: 4_000))
        XCTAssertFalse(AutoVerdict.works(reason: "ended", seconds: 599))
        XCTAssertFalse(AutoVerdict.works(reason: "stopped", seconds: 4_000))   // KLYC-Box ended it: not proof
    }

    func testAnAutomaticResultNeverReplacesTheirOwnAnswer() {
        let own = LocalVerdict(works: false, engine: "e", chip: "Apple M4", macos: "27")
        let auto = LocalVerdict(works: true, engine: "e", chip: "Apple M4", macos: "27", auto: true)
        XCTAssertTrue(AutoVerdict.mayReplace(existing: nil))
        XCTAssertTrue(AutoVerdict.mayReplace(existing: auto))
        XCTAssertFalse(AutoVerdict.mayReplace(existing: own))
    }
}
