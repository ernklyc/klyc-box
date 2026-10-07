import Foundation

/// What a program says about itself in its own file: its bitness and the graphics APIs it
/// imports. Read from the executable's headers (and its own DLLs beside it), so it is a fact
/// about the file, never a guess from the game's name. A program that loads its renderer at
/// run time (Unreal) shows few imports; the profile says so instead of claiming more.
public struct ProgramProfile: Equatable, Sendable {
    public enum API: String, CaseIterable, Sendable {
        case direct3D12, direct3D11, direct3D10, direct3D9, direct3D8, directDraw, openGL, vulkan

        /// The import that names it.
        static let dlls: [(api: API, names: Set<String>)] = [
            (.direct3D12, ["d3d12.dll"]),
            (.direct3D11, ["d3d11.dll"]),
            (.direct3D10, ["d3d10.dll", "d3d10_1.dll", "d3d10core.dll"]),
            (.direct3D9, ["d3d9.dll"]),
            (.direct3D8, ["d3d8.dll"]),
            (.directDraw, ["ddraw.dll"]),
            (.openGL, ["opengl32.dll"]),
            (.vulkan, ["vulkan-1.dll"]),
        ]
    }

    /// Nil when the file's machine type is not one the parser knows.
    public var is64Bit: Bool?
    /// Newest first (the order of `API.allCases`).
    public var apis: [API]
    public var isUnreal5: Bool

    public init(is64Bit: Bool?, apis: [API], isUnreal5: Bool) {
        self.is64Bit = is64Bit; self.apis = apis; self.isUnreal5 = isUnreal5
    }

    /// The APIs the imported DLL names stand for. Pure.
    public static func apis(importing dlls: Set<String>) -> [API] {
        API.dlls.filter { !$0.names.isDisjoint(with: dlls) }.map(\.api)
    }

    /// The same rule `ProgramNeeds.wantsDirect3D12` applies, stated on the profile: only
    /// Direct3D 12, or an Unreal 5 build that loads it at run time.
    public var needsDirect3D12: Bool {
        isUnreal5 || (apis == [.direct3D12])
    }

    /// Whether the headers say anything at all (a launcher stub or a packed executable may not).
    public var isEmpty: Bool { is64Bit == nil && apis.isEmpty && !isUnreal5 }

    public static func read(program exe: URL) -> ProgramProfile {
        ProgramProfile(is64Bit: PEImports.is64Bit(of: exe),
                       apis: apis(importing: ProgramNeeds.importedDLLs(program: exe)),
                       isUnreal5: ProgramNeeds.isUnreal5Build(program: exe))
    }
}

/// Windows components a program's own file asks for, as the ids of the dependency recipes that
/// install them (`vcrun2022`, `dotnet48`). Read from imports, so it names what the file links
/// against; whether the program actually fails without it is for the crash diagnosis to say.
public extension ProgramNeeds {
    /// Pure. `shipsBeside` says whether a DLL sits in the program's own folder: a game that ships
    /// its Visual C++ runtime needs nothing installed, and most do.
    static func windowsComponents(importing dlls: Set<String>, shipsBeside: (String) -> Bool) -> [String] {
        var ids: [String] = []
        // A .NET Framework program (not .NET 5 and later, which bring their own runtime) imports mscoree.
        if dlls.contains("mscoree.dll") { ids.append("dotnet48") }
        // The 2015-2022 family only: msvcp120 or msvcr100 are other runtimes the recipe does not install.
        let family = ["vcruntime140", "msvcp140", "concrt140", "vccorlib140"]
        let wanted = dlls.filter { name in family.contains { name.hasPrefix($0) } }
        if !wanted.isEmpty, !wanted.contains(where: shipsBeside) { ids.append("vcrun2022") }
        return ids
    }

    static func windowsComponents(program exe: URL) -> [String] {
        let dir = exe.deletingLastPathComponent()
        return windowsComponents(importing: importedDLLs(program: exe)) {
            FileManager.default.fileExists(atPath: dir.appending(path: $0).path)
        }
    }
}
