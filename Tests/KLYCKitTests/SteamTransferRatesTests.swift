import XCTest
@testable import KLYCKit

final class SteamTransferRatesTests: XCTestCase {
    private func transfer(_ appid: Int = 1, downloaded: Int64, total: Int64 = 1_000_000_000, flags: Int = 1024) -> SteamTransfer {
        SteamTransfer(appid: appid, name: "G", flags: flags, downloaded: downloaded, toDownload: total, staged: 0, toStage: 0, sizeOnDisk: 0)
    }
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testSpeedIsTheChangeBetweenTwoLooks() {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        XCTAssertNil(r.speed[1], "one look says nothing about speed")
        r.update([transfer(downloaded: 30_000_000)], at: t0.addingTimeInterval(3))
        XCTAssertEqual(try XCTUnwrap(r.speed[1]), 10_000_000, accuracy: 1)
    }

    func testEtaIsWhatIsLeftOverTheSpeed() throws {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        let later = transfer(downloaded: 100_000_000)
        r.update([later], at: t0.addingTimeInterval(10))   // 10 MB/s
        XCTAssertEqual(try XCTUnwrap(r.etaSeconds(for: later)), 90)   // 900 MB left
    }

    func testSpeedIsSmoothedNotJumpy() {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        r.update([transfer(downloaded: 10_000_000)], at: t0.addingTimeInterval(1))      // 10 MB/s
        r.update([transfer(downloaded: 10_000_000)], at: t0.addingTimeInterval(2))      // stalled for a second
        let s = r.speed[1] ?? 0
        XCTAssertGreaterThan(s, 0)
        XCTAssertLessThan(s, 10_000_000, "a stall pulls it down")
        XCTAssertGreaterThan(s, 3_000_000, "but only part of the way")
    }

    func testPausedOrFinishedTransfersHaveNoSpeedAndNoEta() {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        r.update([transfer(downloaded: 50_000_000)], at: t0.addingTimeInterval(5))
        let paused = transfer(downloaded: 50_000_000, flags: 512)
        r.update([paused], at: t0.addingTimeInterval(10))
        XCTAssertNil(r.speed[1])
        XCTAssertNil(r.etaSeconds(for: paused))
    }

    func testTooSlowOrCompleteGivesNoEstimate() {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        let slow = transfer(downloaded: 1000)
        r.update([slow], at: t0.addingTimeInterval(10))
        XCTAssertNil(r.etaSeconds(for: slow), "100 bytes per second is not an estimate worth showing")
        let done = transfer(downloaded: 1_000_000_000)
        r.update([done], at: t0.addingTimeInterval(20))
        XCTAssertNil(r.etaSeconds(for: done))
    }

    func testLooksCloserThanHalfASecondAreIgnored() {
        var r = SteamTransferRates()
        r.update([transfer(downloaded: 0)], at: t0)
        r.update([transfer(downloaded: 5_000_000)], at: t0.addingTimeInterval(0.1))
        XCTAssertNil(r.speed[1])
        r.update([transfer(downloaded: 20_000_000)], at: t0.addingTimeInterval(2))
        XCTAssertEqual(try XCTUnwrap(r.speed[1]), 10_000_000, accuracy: 1, "measured from the last accepted look")
    }
}
