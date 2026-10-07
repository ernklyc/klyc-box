import XCTest
@testable import KLYCKit

final class EpicDownloadProgressTests: XCTestCase {
    func testReadsTheProgressBlock() {
        var p = EpicDownloadProgress()
        XCTAssertTrue(p.apply(line: "[DLManager] INFO: = Progress: 3.56% (11/309), Running for 00:00:22, ETA: 00:10:07"))
        XCTAssertEqual(p.percent, 3.56)
        XCTAssertEqual(p.elapsedSeconds, 22)
        XCTAssertEqual(p.etaSeconds, 607)
        XCTAssertEqual(try XCTUnwrap(p.fraction), 0.0356, accuracy: 0.0001)

        p.apply(line: "[DLManager] INFO:  - Downloaded: 33.52 MiB, Written: 43.42 MiB")
        XCTAssertEqual(p.downloadedBytes, Int64(33.52 * 1024 * 1024))
        XCTAssertEqual(p.writtenBytes, Int64(43.42 * 1024 * 1024))

        p.apply(line: "[DLManager] INFO:  + Download\t- 1.51 MiB/s (raw) / 2.44 MiB/s (decompressed)")
        XCTAssertEqual(try XCTUnwrap(p.downloadSpeed), 1.51 * 1024 * 1024, accuracy: 10)
        p.apply(line: "[DLManager] INFO:  + Disk\t- 1.95 MiB/s (write) / 0.00 MiB/s (read)")
        XCTAssertEqual(try XCTUnwrap(p.diskSpeed), 1.95 * 1024 * 1024, accuracy: 10)
    }

    func testReadsTheSizesBeforeTheDownloadStarts() {
        var p = EpicDownloadProgress()
        p.apply(line: "[cli] INFO: Download size: 14.21 GiB (Compression savings: 12.3%)")
        p.apply(line: "[cli] INFO: Install size: 24.00 GiB")
        XCTAssertEqual(p.downloadSize, Int64(14.21 * 1024 * 1024 * 1024))
        XCTAssertEqual(p.installSize, 24 * 1024 * 1024 * 1024)
        XCTAssertNil(p.percent, "no progress yet")
        XCTAssertNil(p.fraction)
    }

    func testALineThatMeansNothingChangesNothing() {
        var p = EpicDownloadProgress()
        p.apply(line: "= Progress: 50.00% (5/10), Running for 00:01:00, ETA: 00:01:00")
        let before = p
        XCTAssertFalse(p.apply(line: "[cli] INFO: Verification finished successfully."))
        XCTAssertFalse(p.apply(line: "random text"))
        XCTAssertEqual(p, before, "the last known values stay")
    }

    func testClockAndSizeParsing() {
        XCTAssertEqual(EpicDownloadProgress.seconds(fromClock: "01:02:03"), 3723)
        XCTAssertEqual(EpicDownloadProgress.seconds(fromClock: "02:03"), 123)
        XCTAssertNil(EpicDownloadProgress.seconds(fromClock: "x"))
        XCTAssertEqual(EpicDownloadProgress.bytes(from: "512 B"), 512)
        XCTAssertEqual(EpicDownloadProgress.bytes(from: "1.5 KiB"), 1536)
        XCTAssertEqual(EpicDownloadProgress.bytes(from: "2 GiB"), 2 * 1024 * 1024 * 1024)
        XCTAssertNil(EpicDownloadProgress.bytes(from: "3 parsecs"))
    }

    func testFractionIsClamped() {
        var p = EpicDownloadProgress()
        p.percent = 140
        XCTAssertEqual(p.fraction, 1)
    }

    func testProgressLinesAreNoiseForTheActivityLogButOthersAreNot() {
        XCTAssertTrue(EpicDownloadProgress.isProgressNoise("[DLManager] INFO: = Progress: 3.56% (11/309), Running for 00:00:22, ETA: 00:10:07"))
        XCTAssertTrue(EpicDownloadProgress.isProgressNoise("[DLManager] INFO:  + Download\t- 1.51 MiB/s (raw) / 2.44 MiB/s (decompressed)"))
        XCTAssertFalse(EpicDownloadProgress.isProgressNoise("[cli] ERROR: Could not reach the server"))
    }
}
