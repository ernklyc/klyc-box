import XCTest
@testable import KLYCKit

final class HUDLogTests: XCTestCase {
    func hud(_ time: String, pid: Int, frames: Int) -> String {
        "\(time) AssettoCorsa.exe[\(pid):4025601] metal-HUD: \(frames),6.64,119.41,27.11,0.01,16.67"
    }

    func testTheFrameRateIsTheCounterChangePerSecond() throws {
        let text = [
            "wine: unrelated line",
            hud("2026-10-05 10:33:04.466", pid: 77, frames: 62), hud("2026-10-05 10:33:05.516", pid: 77, frames: 117),
            hud("2026-10-05 10:33:06.539", pid: 77, frames: 179), hud("2026-10-05 10:33:07.550", pid: 77, frames: 240),
            hud("2026-10-05 10:33:08.561", pid: 77, frames: 300),
        ].joined(separator: "\n")
        let s = try XCTUnwrap(HUDLog.summary(in: text))
        XCTAssertEqual(s.median, 60)
        XCTAssertEqual(s.seconds, 4)
        XCTAssertLessThanOrEqual(s.lowest, 60)
    }

    func testTheBusiestProcessIsTheGameAndAnotherRunOrWindowIsIgnored() throws {
        var lines = [hud("2026-10-05 10:00:00.000", pid: 5, frames: 10), hud("2026-10-05 10:00:01.000", pid: 5, frames: 70)]   // a launcher, 2 samples
        for i in 0..<6 { lines.append(hud("2026-10-05 10:00:\(String(format: "%02d", i)).000", pid: 9, frames: i * 30)) }
        let s = try XCTUnwrap(HUDLog.summary(in: lines.joined(separator: "\n")))
        XCTAssertEqual(s.median, 30)
    }

    func testNotEnoughSamplesGivesNothingAndTheWindowFiltersByTime() {
        let text = [hud("2026-10-05 10:00:00.000", pid: 1, frames: 0), hud("2026-10-05 10:00:01.000", pid: 1, frames: 60)].joined(separator: "\n")
        XCTAssertNil(HUDLog.summary(in: text))
        let f = HUDLog.formatter()
        let many = (0..<8).map { hud("2026-10-05 10:00:0\($0).000", pid: 1, frames: $0 * 60) }.joined(separator: "\n")
        XCTAssertNil(HUDLog.summary(in: many, from: f.date(from: "2026-10-05 10:00:06.000")!))   // only 2 samples inside the window
    }
}
