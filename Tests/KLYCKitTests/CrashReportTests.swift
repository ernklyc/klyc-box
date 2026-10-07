import XCTest
@testable import KLYCKit

final class CrashReportTests: XCTestCase {
    /// A trimmed report in the shape macOS writes: a one-line JSON header, then the JSON body.
    private func ips(bundle: String = "com.klyc.klycbox", frames: String? = nil) -> String {
        let f = frames ?? """
        {"imageOffset":1,"symbol":"_assertionFailure(_:_:file:line:flags:)","symbolLocation":216,"imageIndex":5},
        {"imageOffset":2,"symbol":"NavigationPath.removeLast(_:)","symbolLocation":128,"imageIndex":7},
        {"imageOffset":3,"sourceLine":116,"sourceFile":"/Volumes/Somebody/private/project/Sources/Shell.swift","symbol":"closure in TopBar.body.getter","imageIndex":0}
        """
        return """
        {"app_name":"KLYC-Box","app_version":"1.0.2","bundleID":"\(bundle)","os_version":"macOS 27.0.1 (26A434)","timestamp":"2026-10-07 14:02:15.00 +0300"}
        {"bundleInfo":{"CFBundleShortVersionString":"1.0.2","CFBundleIdentifier":"\(bundle)"},"osVersion":{"train":"macOS 27.0.1"},"modelCode":"Mac16,10","captureTime":"2026-10-07 14:01:50.0579 +0300","exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"faultingThread":0,"threads":[{"triggered":true,"frames":[\(f)]},{"frames":[{"symbol":"other"}]}]}
        """
    }

    func testSummaryHasTypeVersionsAndFunctionNamesButNoPaths() throws {
        let s = try XCTUnwrap(CrashReport.summary(ips: ips()))
        XCTAssertEqual(s.appVersion, "1.0.2")
        XCTAssertEqual(s.exception, "EXC_BREAKPOINT (SIGTRAP)")
        XCTAssertEqual(s.frames.first, "_assertionFailure(_:_:file:line:flags:)")
        XCTAssertTrue(s.frames.contains("closure in TopBar.body.getter (Shell.swift:116)"))
        XCTAssertFalse(s.text.contains("/Volumes"), "a source path must never reach the report")
        XCTAssertFalse(s.text.contains("other"), "only the crashing thread is reported")
    }

    func testOtherAppsAndGarbageAreIgnored() {
        XCTAssertNil(CrashReport.summary(ips: ips(bundle: "com.example.other")))
        XCTAssertNil(CrashReport.summary(ips: "not a report"))
        XCTAssertNil(CrashReport.summary(ips: ips(frames: "")), "no frames, nothing useful to send")
    }

    func testTheIssueLinkTargetsTheBugTemplateAndStaysShort() throws {
        let s = try XCTUnwrap(CrashReport.summary(ips: ips()))
        let url = CrashReport.issueURL(s, chip: "M4", macos: "27.0.1").absoluteString
        XCTAssertTrue(url.hasPrefix("https://github.com/ernklyc/klyc-box/issues/new?"))
        XCTAssertTrue(url.contains("template=bug.yml"))
        XCTAssertTrue(url.contains("version=1.0.2"))
        XCTAssertLessThan(url.count, 5000)
    }

    func testNewestReportOnlyAfterTheGivenDate() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "crash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ips().write(to: dir.appending(path: "KLYC-Box-2026-10-07-140150.ips"), atomically: true, encoding: .utf8)
        try ips().write(to: dir.appending(path: "Other-2026-10-07.ips"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(CrashReport.newest(after: Date().addingTimeInterval(-60), in: dir))
        XCTAssertNil(CrashReport.newest(after: Date().addingTimeInterval(60), in: dir), "an older crash must not be offered again")
    }

    /// Optional: point KLYC_CRASH_FIXTURE at a real .ips to check that the reader copes with what macOS actually writes.
    func testARealReportWhenOneIsProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["KLYC_CRASH_FIXTURE"] else { throw XCTSkip("set KLYC_CRASH_FIXTURE to an .ips file") }
        let s = try XCTUnwrap(CrashReport.summary(ips: String(contentsOfFile: path, encoding: .utf8)))
        print(s.text)
        XCTAssertFalse(s.frames.isEmpty)
    }
}
