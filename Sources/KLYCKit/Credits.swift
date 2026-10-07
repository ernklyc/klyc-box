import Foundation

/// Who made what KLYC-Box stands on. Shown in the About window and mirrored in NOTICE.md; a test
/// keeps this list and the engine manifest in step, so a component added to the engine cannot go
/// without its credit.
public struct CreditEntry: Equatable, Sendable {
    public let name: String
    /// What it is to KLYC-Box, in a few words (English, translated where shown).
    public let role: String
    public let license: String
    public let url: URL
    /// Names that appear in the engine manifest for this project, to check coverage.
    public let manifestNames: [String]

    public init(name: String, role: String, license: String, url: String, manifestNames: [String] = []) {
        self.name = name; self.role = role; self.license = license
        self.url = URL(string: url)!; self.manifestNames = manifestNames
    }
}

public enum Credits {
    /// The project KLYC-Box is derived from comes first: it is the one that matters most.
    public static let entries: [CreditEntry] = [
        CreditEntry(name: "Highball", role: "The app KLYC-Box is built on, by Gauthier Piarrette and its contributors",
                    license: "GPL-3.0", url: "https://github.com/gauthierpiarrette/highball"),
        CreditEntry(name: "Highball engine components", role: "The DXMT build, the D3DMetal timestamp shim, the audio buffer fix and the Wine patches in KLYC-Box's engine, made for Highball",
                    license: "MIT and LGPL-2.1+", url: "https://github.com/gauthierpiarrette/highball-engine",
                    manifestNames: ["d3dmetal-tsshim", "audiobuf"]),
        CreditEntry(name: "Wine", role: "Runs Windows programs",
                    license: "LGPL-2.1+", url: "https://www.winehq.org", manifestNames: ["wine", "winemac", "wineserver", "ntdll-unix"]),
        CreditEntry(name: "Sikarugir", role: "Wine builds and the runtime KLYC-Box's engine starts from",
                    license: "LGPL-2.1 and others", url: "https://github.com/Sikarugir-App", manifestNames: ["runtime"]),
        CreditEntry(name: "DXMT", role: "Direct3D 10/11 to Metal, by 3Shain",
                    license: "MIT", url: "https://github.com/3Shain/dxmt", manifestNames: ["dxmt"]),
        CreditEntry(name: "DXVK", role: "Direct3D 9 to Vulkan",
                    license: "zlib", url: "https://github.com/doitsujin/dxvk", manifestNames: ["d9vk-modern"]),
        CreditEntry(name: "MoltenVK", role: "Vulkan on Metal, by Khronos and Brenwill Workshop",
                    license: "Apache-2.0", url: "https://github.com/KhronosGroup/MoltenVK", manifestNames: ["moltenvk"]),
        CreditEntry(name: "Winetricks", role: "Installs Windows components",
                    license: "LGPL-2.1", url: "https://github.com/Winetricks/winetricks", manifestNames: ["winetricks"]),
        CreditEntry(name: "Legendary", role: "Installs and starts Epic Games titles",
                    license: "GPL-3.0", url: "https://github.com/legendary-gl/legendary"),
        CreditEntry(name: "Sparkle", role: "Updates the app",
                    license: "MIT", url: "https://sparkle-project.org"),
        CreditEntry(name: "cabextract", role: "Unpacks Microsoft cabinet files",
                    license: "GPL-3.0+", url: "https://www.cabextract.org.uk"),
        CreditEntry(name: "Are We Anti-Cheat Yet?", role: "The list of games and their anti-cheat",
                    license: "MIT", url: "https://areweanticheatyet.com"),
        CreditEntry(name: "Apple Game Porting Toolkit (D3DMetal)", role: "DirectX 12 on Metal. Not part of KLYC-Box: you accept Apple's license yourself, inside the app",
                    license: "Apple's license", url: "https://developer.apple.com/games/game-porting-toolkit/"),
    ]

    /// The author's own site, with the links to everything else they make.
    public static let authorSite = URL(string: "https://ernklyc.dev")!
    /// The project's own game guide and compatibility data, and its source code.
    public static let guideSite = URL(string: "https://klycbox.ernklyc.dev")!
    public static let sourceSite = URL(string: "https://github.com/ernklyc/klyc-box")!

    /// The line about what KLYC-Box itself is.
    public static let ownership = "KLYC-Box is made by Eren Kalaycı. It started as a fork of Highball by Gauthier Piarrette and is developed further on top of it. It is free, open source (GPL-3.0) and not for sale: it takes no money for any feature."
    public static let affiliation = "KLYC-Box is not affiliated with or approved by Valve, Epic Games or Apple. Steam, Epic Games and Apple are their owners' trademarks."
}
