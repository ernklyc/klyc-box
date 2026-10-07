import XCTest
@testable import KLYCKit

@MainActor
final class ToastTests: XCTestCase {
    private func center() -> ToastCenter {
        let c = ToastCenter()
        c.duration = .milliseconds(300)
        c.warningDuration = .milliseconds(1000)
        return c
    }

    func testShowsAndTakesItselfDown() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "timing-sensitive: shared CI VMs stall sleeps well past the toast durations")
        let c = center()
        c.show("Saved")
        XCTAssertEqual(c.current?.text, "Saved")
        XCTAssertEqual(c.current?.style, .success)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNil(c.current)
    }

    func testANewerOneReplacesTheOlderAndTheOldTimerDoesNotTakeItDown() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "timing-sensitive: shared CI VMs stall sleeps well past the toast durations")
        let c = center()
        c.show("First")
        try await Task.sleep(for: .milliseconds(200))
        c.show("Second")
        try await Task.sleep(for: .milliseconds(200))   // 400 ms after the first, 200 after the second
        XCTAssertEqual(c.current?.text, "Second", "the first one's timer must not end the second early")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(c.current)
    }

    func testRepeatingTheSameTextKeepsTheSameToastAndRestartsTheClock() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "timing-sensitive: shared CI VMs stall sleeps well past the toast durations")
        let c = center()
        c.show("Copied")
        let id = c.current?.id
        try await Task.sleep(for: .milliseconds(200))
        c.show("Copied")
        XCTAssertEqual(c.current?.id, id, "no flash for a repeated confirmation")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(c.current, "the clock restarted, so it is still up 400 ms after the first")
    }

    func testAWarningStaysLongerThanAConfirmation() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "timing-sensitive: shared CI VMs stall sleeps well past 100 ms")
        let c = center()
        c.show("Careful", style: .warning)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNotNil(c.current)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNil(c.current)
    }

    func testBlankTextShowsNothingAndDismissIgnoresAStaleId() {
        let c = center()
        c.show("   ")
        XCTAssertNil(c.current)
        c.show("Now")
        c.dismiss(UUID())
        XCTAssertEqual(c.current?.text, "Now", "an id that is not the current one dismisses nothing")
        c.dismiss()
        XCTAssertNil(c.current)
    }
}
