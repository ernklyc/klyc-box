import XCTest
@testable import KLYCKit

/// A program's imports say which graphics API it needs, and a Direct3D 12-only one must not be
/// launched on a mode without Direct3D 12 (upstream#139, upstream#105).
final class PEImportsTests: XCTestCase {
    /// A minimal 64-bit PE with one section holding an import table naming `imports` and a
    /// delay-load table naming `delayImports`, laid out the way the parser reads them.
    static func makePE(imports: [String], delayImports: [String] = [], oldStyleDelay: Bool = false) -> Data {
        let imageBase = 0x400000, sectionVA = 0x1000, sectionRaw = 0x200   // a base that fits the old-style delay descriptors' 32-bit addresses
        var section = Data()
        func put32(_ v: UInt32) { for i in 0..<4 { section.append(UInt8((v >> (8 * i)) & 0xFF)) } }
        // Names first, so their RVAs are known when the descriptors are written.
        var nameRVA: [String: UInt32] = [:]
        for n in imports + delayImports where nameRVA[n] == nil {
            nameRVA[n] = UInt32(sectionVA + section.count)
            section.append(contentsOf: Array(n.utf8) + [0])
        }
        while section.count % 4 != 0 { section.append(0) }
        let importOff = section.count
        for n in imports { put32(0); put32(0); put32(0); put32(nameRVA[n]!); put32(UInt32(sectionVA)) }   // FirstThunk non-zero
        put32(0); put32(0); put32(0); put32(0); put32(0)
        let delayOff = section.count
        for n in delayImports {
            put32(oldStyleDelay ? 0 : 1)
            put32(oldStyleDelay ? UInt32(imageBase + Int(nameRVA[n]!)) : nameRVA[n]!)
            for _ in 0..<6 { put32(0) }
        }
        for _ in 0..<8 { put32(0) }

        var d = Data(count: sectionRaw)
        func w16(_ v: UInt16, _ o: Int) { d[o] = UInt8(v & 0xFF); d[o + 1] = UInt8(v >> 8) }
        func w32(_ v: UInt32, _ o: Int) { for i in 0..<4 { d[o + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        d[0] = 0x4D; d[1] = 0x5A; w32(0x40, 0x3C)
        let pe = 0x40
        w32(0x4550, pe); w16(0x8664, pe + 4); w16(1, pe + 6); w16(240, pe + 20)
        let opt = pe + 24
        w16(0x20B, opt)
        w32(UInt32(imageBase & 0xFFFFFFFF), opt + 24); w32(UInt32(imageBase >> 32), opt + 28)
        w32(16, opt + 108)
        let dd = opt + 112
        w32(UInt32(sectionVA + importOff), dd + 8); w32(UInt32(section.count - importOff), dd + 12)
        if !delayImports.isEmpty { w32(UInt32(sectionVA + delayOff), dd + 8 * 13); w32(UInt32(section.count - delayOff), dd + 8 * 13 + 4) }
        let table = opt + 240
        d.replaceSubrange(table..<table + 8, with: Array(".idata\0\0".utf8))
        w32(UInt32(section.count), table + 8); w32(UInt32(sectionVA), table + 12)
        w32(UInt32(section.count), table + 16); w32(UInt32(sectionRaw), table + 20)
        d.append(section)
        return d
    }

    func testReadsImportAndDelayLoadTables() {
        let pe = Self.makePE(imports: ["KERNEL32.dll", "d3d11.dll"], delayImports: ["d3d12.dll", "dxgi.dll"])
        XCTAssertEqual(PEImports.dllNames(fromPE: pe), ["KERNEL32.dll", "d3d11.dll", "d3d12.dll", "dxgi.dll"])
        XCTAssertEqual(PEImports.dllNames(fromPE: Self.makePE(imports: ["USER32.dll"])), ["USER32.dll"])
    }

    func testOldStyleDelayLoadUsesVirtualAddresses() {
        let pe = Self.makePE(imports: ["KERNEL32.dll"], delayImports: ["d3d12.dll"], oldStyleDelay: true)
        XCTAssertEqual(PEImports.dllNames(fromPE: pe), ["KERNEL32.dll", "d3d12.dll"])
    }

    func testRejectsWhatItDoesNotUnderstand() {
        XCTAssertEqual(PEImports.dllNames(fromPE: Data("not a program".utf8)), [])
        XCTAssertEqual(PEImports.dllNames(fromPE: Data(count: 0x100)), [])
        XCTAssertEqual(PEImports.dllNames(fromPE: Self.makePE(imports: []).prefix(0x150)), [], "a truncated section table is not a list")
    }

    func testDirect3D12OnlyLooksAtTheProgramAndItsOwnDLLs() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "hb-needs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appending(path: "Game.exe")
        // The executable links only its engine DLL and Direct3D 12 (delay-loaded, as Path of Exile 2 does).
        try Self.makePE(imports: ["KERNEL32.dll", "Engine.dll"], delayImports: ["d3d12.dll"]).write(to: exe)
        XCTAssertTrue(ProgramNeeds.direct3D12Only(program: exe))
        // Its engine DLL beside it has a Direct3D 11 path too: the environment's choice stands.
        try Self.makePE(imports: ["d3d11.dll", "dxgi.dll"]).write(to: dir.appending(path: "Engine.dll"))
        XCTAssertFalse(ProgramNeeds.direct3D12Only(program: exe))
        // A Unity build: the executable names only the player, the player draws with Direct3D 11 or OpenGL.
        try Self.makePE(imports: ["UnityPlayer.dll", "KERNEL32.dll"]).write(to: exe)
        try Self.makePE(imports: ["d3d11.dll", "OPENGL32.dll"]).write(to: dir.appending(path: "UnityPlayer.dll"))
        XCTAssertFalse(ProgramNeeds.direct3D12Only(program: exe))
        // No graphics import at all (a launcher, a .NET stub): nothing to say.
        try Self.makePE(imports: ["KERNEL32.dll"]).write(to: exe)
        XCTAssertFalse(ProgramNeeds.direct3D12Only(program: exe))
        XCTAssertFalse(ProgramNeeds.direct3D12Only(program: dir.appending(path: "missing.exe")))
    }

    func testUnreal5LayoutCountsAsDirect3D12() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hb-ue5-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let exe = root.appending(path: "Voyage/Binaries/Win64/VoyageSteam-Win64-Shipping.exe")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Unreal's executable names dxgi and opengl32 only; d3d12.dll is loaded at run time.
        try Self.makePE(imports: ["KERNEL32.dll", "dxgi.dll", "OPENGL32.dll"]).write(to: exe)
        XCTAssertFalse(ProgramNeeds.direct3D12Only(program: exe), "imports alone say nothing")
        XCTAssertFalse(ProgramNeeds.isUnreal5Build(program: exe), "no engine tree yet")
        try fm.createDirectory(at: root.appending(path: "Engine/Binaries/Win64"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Voyage/Content/Paks"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "Voyage/Content/Paks/pakchunk0-Windows.pak"))
        XCTAssertFalse(ProgramNeeds.isUnreal5Build(program: exe), "a pak without IoStore is Unreal 4's layout, Direct3D 11 by default")
        try Data().write(to: root.appending(path: "Voyage/Content/Paks/pakchunk0-Windows.utoc"))
        XCTAssertTrue(ProgramNeeds.isUnreal5Build(program: exe))
        XCTAssertTrue(ProgramNeeds.wantsDirect3D12(program: exe))
        // A Unity build in a similar-looking folder is not Unreal.
        let unity = root.appending(path: "Other/Binaries/Win64/Game.exe")
        try fm.createDirectory(at: unity.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.makePE(imports: ["UnityPlayer.dll"]).write(to: unity)
        XCTAssertFalse(ProgramNeeds.isUnreal5Build(program: unity), "no Paks with IoStore under it")
    }

    func testRealBinariesOnThisMac() throws {
        // GameOverlayRenderer64.dll delay-loads KERNEL32; UnityPlayer.dll (PEAK) links Direct3D 11 and OpenGL.
        let steam = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support/KLYC-Box/bottles/Gaming/drive_c/Program Files (x86)/Steam")
        let overlay = steam.appending(path: "GameOverlayRenderer64.dll")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: overlay.path), "no Gaming bottle with Steam here")
        let names = PEImports.dllNames(of: overlay).map { $0.lowercased() }
        XCTAssertTrue(names.contains("kernel32.dll"), "\(names)")
        let peak = steam.appending(path: "steamapps/common/PEAK/PEAK.exe")
        if FileManager.default.fileExists(atPath: peak.path) {
            XCTAssertFalse(ProgramNeeds.direct3D12Only(program: peak))
            XCTAssertFalse(ProgramNeeds.wantsDirect3D12(program: peak), "Unity with a Direct3D 11 player")
            XCTAssertTrue(PEImports.dllNames(of: peak).contains("UnityPlayer.dll"))
        }
        // The Last Caretaker demo (Unreal 5, upstream#138): imports say dxgi and opengl32 only, the layout says Unreal 5.
        let caretaker = steam.appending(path: "steamapps/common/TheLastCaretakerDemo/Voyage/Binaries/Win64/VoyageSteam-Win64-Shipping.exe")
        if FileManager.default.fileExists(atPath: caretaker.path) {
            XCTAssertFalse(ProgramNeeds.direct3D12Only(program: caretaker))
            XCTAssertTrue(ProgramNeeds.isUnreal5Build(program: caretaker))
            XCTAssertTrue(ProgramNeeds.wantsDirect3D12(program: caretaker))
        }
    }
}

final class ProgramProfileTests: XCTestCase {
    private func write(_ data: Data, named name: String = "game.exe", in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try data.write(to: url)
        return url
    }
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func testReadsBitnessFromTheMachineField() throws {
        let dir = try tempDir()
        var pe = PEImportsTests.makePE(imports: ["d3d11.dll"])
        XCTAssertEqual(PEImports.is64Bit(of: try write(pe, in: dir)), true)
        pe[0x44] = 0x4C; pe[0x45] = 0x01   // IMAGE_FILE_MACHINE_I386
        XCTAssertEqual(PEImports.is64Bit(of: try write(pe, named: "old.exe", in: dir)), false)
        XCTAssertNil(PEImports.is64Bit(of: try write(Data("not a program".utf8), named: "x.exe", in: dir)))
    }

    func testListsTheGraphicsAPIsNewestFirst() throws {
        let dir = try tempDir()
        let exe = try write(PEImportsTests.makePE(imports: ["kernel32.dll", "d3d9.dll", "D3D11.dll", "opengl32.dll"]), in: dir)
        let profile = ProgramProfile.read(program: exe)
        XCTAssertEqual(profile.apis, [.direct3D11, .direct3D9, .openGL])
        XCTAssertEqual(profile.is64Bit, true)
        XCTAssertFalse(profile.needsDirect3D12)
    }

    func testDirect3D12OnlyNeedsIt() throws {
        let dir = try tempDir()
        let only = try write(PEImportsTests.makePE(imports: ["d3d12.dll", "dxgi.dll"]), in: dir)
        XCTAssertTrue(ProgramProfile.read(program: only).needsDirect3D12)
        let both = try write(PEImportsTests.makePE(imports: ["d3d12.dll", "d3d11.dll"]), named: "both.exe", in: dir)
        XCTAssertFalse(ProgramProfile.read(program: both).needsDirect3D12)
    }

    func testAnEmptyProfileSaysNothing() throws {
        let dir = try tempDir()
        let p = ProgramProfile.read(program: try write(Data("MZ".utf8), in: dir))
        XCTAssertTrue(p.isEmpty)
    }

    func testProfileAgreesWithTheLaunchRule() throws {
        let dir = try tempDir()
        for imports in [["d3d12.dll"], ["d3d12.dll", "d3d9.dll"], ["d3d11.dll"], ["vulkan-1.dll"]] {
            let exe = try write(PEImportsTests.makePE(imports: imports), named: "\(imports.joined()).exe", in: dir)
            XCTAssertEqual(ProgramProfile.read(program: exe).needsDirect3D12, ProgramNeeds.direct3D12Only(program: exe), "\(imports)")
        }
    }
}

final class WindowsComponentsTests: XCTestCase {
    func testManagedProgramNeedsDotNet() {
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: ["mscoree.dll", "kernel32.dll"], shipsBeside: { _ in false }), ["dotnet48"])
    }

    func testVisualCRuntimeIsNeededOnlyWhenTheGameDoesNotShipIt() {
        let imports: Set<String> = ["vcruntime140.dll", "msvcp140.dll", "kernel32.dll"]
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: imports, shipsBeside: { _ in false }), ["vcrun2022"])
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: imports, shipsBeside: { $0 == "vcruntime140.dll" }), [])
    }

    func testOtherRuntimesAreNotTheOneTheRecipeInstalls() {
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: ["msvcp120.dll", "msvcr120.dll", "msvcr100.dll"], shipsBeside: { _ in false }), [])
    }

    func testAProgramThatImportsNothingSpecialNeedsNothing() {
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: ["kernel32.dll", "d3d11.dll"], shipsBeside: { _ in false }), [])
    }

    func testBothCanBeNeeded() {
        XCTAssertEqual(ProgramNeeds.windowsComponents(importing: ["mscoree.dll", "vcruntime140.dll"], shipsBeside: { _ in false }), ["dotnet48", "vcrun2022"])
    }
}
