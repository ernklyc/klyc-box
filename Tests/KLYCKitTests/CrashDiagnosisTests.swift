import XCTest
@testable import KLYCKit

final class CrashDiagnosisTests: XCTestCase {
    private func diagnose(_ lines: String...) -> [CrashFinding] { CrashDiagnosis.diagnose(log: lines.joined(separator: "\n")) }

    func testWineChatterAloneIsNotAFinding() {
        XCTAssertTrue(diagnose("0128:err:sync:RtlLeaveCriticalSection section 0x1 is not acquired",
                               "0240:err:ole:CoGetContextToken apartment not initialised",
                               "0378:err:hid:handle_DeviceMatchingCallback failed").isEmpty)
    }

    func testStreamsOwnHelperMissingSDL2IsIgnored() {
        XCTAssertTrue(diagnose(#"0378:err:module:import_dll Library SDL2.dll (which is needed by L"C:\\Program Files (x86)\\Steam\\bin\\gldriverquery.exe") not found"#).isEmpty)
    }

    func testMissingVisualCRuntimeOffersVcrun() {
        let f = diagnose(#"0100:err:module:import_dll Library MSVCP140.dll (which is needed by L"C:\\Games\\x\\game.exe") not found"#)
        XCTAssertEqual(f.first?.kind, .missingRuntime)
        XCTAssertEqual(f.first?.detail, "MSVCP140.dll")
        XCTAssertEqual(f.first?.fix, .installRecipe("vcrun2022"))
    }

    func testMissingDotNetOffersDotnet48() {
        let f = diagnose(#"0100:err:module:import_dll Library mscoree.dll (which is needed by L"C:\\Games\\x\\game.exe") not found"#)
        XCTAssertEqual(f.first?.fix, .installRecipe("dotnet48"))
    }

    func testDirectXAndMediaFilesAreNamedWithoutAFalseFix() {
        XCTAssertEqual(diagnose(#"err:module:import_dll Library d3dx9_43.dll (which is needed by L"C:\\g\\a.exe") not found"#).first?.kind, .missingDirectXFiles)
        XCTAssertEqual(diagnose(#"err:module:import_dll Library mfplat.dll (which is needed by L"C:\\g\\a.exe") not found"#).first?.kind, .missingMedia)
        XCTAssertEqual(diagnose(#"err:module:import_dll Library foo.dll (which is needed by L"C:\\g\\a.exe") not found"#).first?.kind, .missingLibrary)
        XCTAssertEqual(diagnose(#"err:module:import_dll Library foo.dll (which is needed by L"C:\\g\\a.exe") not found"#).first?.fix, CrashFinding.Fix.none)
    }

    func testAntiCheatNeedsAFailureOnTheLine() {
        XCTAssertTrue(diagnose(#"loading C:\Program Files\EasyAntiCheat\eac_launcher.exe version 4"#).isEmpty)
        let f = diagnose("EasyAntiCheat: failed to start the service")
        XCTAssertEqual(f.first?.kind, .antiCheat)
        XCTAssertEqual(f.first?.detail, "Easy Anti-Cheat")
        XCTAssertEqual(f.first?.fix, CrashFinding.Fix.none)
    }

    func testGraphicsFailureOffersAnotherMode() {
        XCTAssertEqual(diagnose("vkQueueSubmit failed: VK_ERROR_DEVICE_LOST").first?.fix, .tryOtherRenderer)
    }

    func testMsyncMismatchOffersARestart() {
        XCTAssertEqual(diagnose("Failed to open msync shared memory file").first?.fix, .restartEnvironment)
    }

    func testNamedCauseOutranksTheGenericCrash() {
        let f = diagnose("wine: Unhandled page fault on read access to 0x0",
                         #"err:module:import_dll Library VCRUNTIME140.dll (which is needed by L"C:\\g\\a.exe") not found"#)
        XCTAssertEqual(f.map(\.kind), [.missingRuntime, .crash])
    }

    func testTheSameFindingIsReportedOnce() {
        let line = #"err:module:import_dll Library MSVCP140.dll (which is needed by L"C:\\g\\a.exe") not found"#
        XCTAssertEqual(diagnose(line, line, line).count, 1)
    }

    func testTailReadsOnlyTheEndOfALargeLog() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "crash-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try (String(repeating: "x", count: 5000) + "\nTHE END\n").write(to: url, atomically: true, encoding: .utf8)
        let t = CrashDiagnosis.tail(of: url, bytes: 100)
        XCTAssertTrue(t.hasSuffix("THE END\n"))
        XCTAssertLessThanOrEqual(t.utf8.count, 100)
    }
}
