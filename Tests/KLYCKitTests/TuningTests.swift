import XCTest
@testable import KLYCKit

final class TuningTests: XCTestCase {
    func attempt(_ r: Renderer, _ v: VerifyOutcome.Verdict, _ s: Int) -> TuningResult.Attempt { .init(renderer: r, verdict: v, secondsAlive: s) }

    func testARenderingModeBeatsABlackScreenAndACrash() {
        let best = TuningResult.pick([attempt(.dxmt, .crashed, 12), attempt(.dxvk, .blackScreen, 60), attempt(.d3dmetal, .renders, 60)])
        XCTAssertEqual(best, .d3dmetal)
    }

    func testTiesGoToTheEarlierModeInTheEnginesOrder() {
        let best = TuningResult.pick([attempt(.dxmt, .renders, 60), attempt(.dxvk, .renders, 60)])
        XCTAssertEqual(best, .dxmt)
    }

    func testNothingIsSavedWhenNoModeRendered() {
        XCTAssertNil(TuningResult.pick([attempt(.dxmt, .blackScreen, 60), attempt(.dxvk, .crashed, 5), attempt(.wined3d, .neverStarted, 0)]))
        XCTAssertNil(TuningResult.pick([]))
    }

    func testResultsSurviveARoundTripThroughTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TuningStore(paths: KLYCPaths(home: dir))
        let result = TuningResult(best: .dxmt, attempts: [attempt(.dxmt, .renders, 60)], date: Date(timeIntervalSince1970: 1_700_000_000), engine: "e1")
        store.save(result, for: "steam:1")
        XCTAssertEqual(store.all()["steam:1"], result)
        store.remove("steam:1")
        XCTAssertTrue(store.all().isEmpty)
    }
}
