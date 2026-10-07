import XCTest
@testable import KLYCKit

final class PlaytimeTests: XCTestCase {
    private func store() throws -> (LibraryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (LibraryStore(paths: KLYCPaths(home: dir)), dir)
    }

    func testSessionsAddUpAndShortOnesDoNotCount() throws {
        let (s, dir) = try store(); defer { try? FileManager.default.removeItem(at: dir) }
        s.addPlaytime(id: "steam:1", seconds: 600); s.addPlaytime(id: "steam:1", seconds: 90); s.addPlaytime(id: "steam:1", seconds: 4)
        XCTAssertEqual(s.playtimes()["steam:1"], 690)
    }

    func testPlaytimeAndLaunchOptionsSurvivePruning() throws {
        let (s, dir) = try store(); defer { try? FileManager.default.removeItem(at: dir) }
        s.addPlaytime(id: "steam:1", seconds: 120); s.setLaunchArguments("-windowed -dx11", for: "steam:1")
        s.recordPlay(id: "steam:1", bottle: "Games"); s.recordPlay(id: "steam:gone", bottle: "Games")
        s.prune(validIDs: ["steam:1"])
        XCTAssertEqual(s.playtimes()["steam:1"], 120)
        XCTAssertEqual(s.launchArguments()["steam:1"], "-windowed -dx11")
        s.setLaunchArguments("  ", for: "steam:1")
        XCTAssertNil(s.launchArguments()["steam:1"])
    }

    func testArgumentSplittingKeepsQuotedParts() {
        XCTAssertEqual(PlaytimeText.arguments(from: "-windowed  -name \"My Game\" -x"), ["-windowed", "-name", "My Game", "-x"])
        XCTAssertEqual(PlaytimeText.arguments(from: ""), [])
    }

    func testReadableDurations() {
        XCTAssertEqual(PlaytimeText.format(seconds: 20), "less than a minute")
        XCTAssertEqual(PlaytimeText.format(seconds: 35 * 60), "35 min")
        XCTAssertEqual(PlaytimeText.format(seconds: 134 * 60), "2 h 14 min")
    }
}
