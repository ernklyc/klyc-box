import XCTest
@testable import KLYCKit

/// The launch environment is where most field bugs lived (Steam's CEF hang, DLL
/// overrides, renderer overlays). These tests pin its composition rules.
final class EnvironmentTests: XCTestCase {

    private func fixtures() throws -> (engine: InstalledEngine, bottle: Bottle) {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "spike/engine-manifest.json")
        let manifest = try EngineManifest.load(from: manifestURL)
        let root = FileManager.default.temporaryDirectory.appending(path: "hb-test-engine-\(UUID().uuidString)")
        let engine = InstalledEngine(manifest: manifest, root: root)
        let bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-test-bottle"),
                            settings: BottleSettings(name: "t", engineID: manifest.id))
        return (engine, bottle)
    }

    // Steam's CEF webhelper hangs under msync/esync on Wine 10. sync=none must write
    // explicit zeros, not merely omit the variables.
    func testSyncNoneWritesExplicitZeros() throws {
        var (engine, bottle) = try fixtures()
        bottle.settings.sync = .none
        let env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEMSYNC"], "0")
        XCTAssertEqual(env["WINEESYNC"], "0")
    }

    func testSyncModes() throws {
        var (engine, bottle) = try fixtures()
        bottle.settings.sync = .msync
        var env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertEqual(env["WINEESYNC"], "0")
        bottle.settings.sync = .esync
        env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEESYNC"], "1")
        XCTAssertEqual(env["WINEMSYNC"], "0")
    }

    // Wine's menu builder must never run: it writes shortcuts onto the macOS Desktop for every
    // installer (three of them appeared during the CrossOver-tree engine's first tests). The
    // user's own overrides still append after it.
    func testMenuBuilderDisabledOnEveryRenderer() throws {
        let (engine, bottle) = try fixtures()
        let env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "winemenubuilder.exe=d", "present with no bottle overrides at all")
        var b2 = bottle; b2.settings.dllOverrides = "winemenubuilder.exe=b"
        XCTAssertEqual(try b2.environment(engine: engine, renderer: .wined3d)["WINEDLLOVERRIDES"], "winemenubuilder.exe=d;winemenubuilder.exe=b", "a user's own entry comes last and therefore wins")
    }

    func testPrefixAndDebugAlwaysSet() throws {
        let (engine, bottle) = try fixtures()
        let env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEPREFIX"], "/tmp/hb-test-bottle")
        XCTAssertEqual(env["WINEDEBUG"], "fixme-all")
    }

    // Bottle-level DLL overrides (the #17 feature) reach WINEDLLOVERRIDES, and compose
    // with an override the user also set via the env editor, joined by ";".
    func testDllOverridesCompose() throws {
        var (engine, bottle) = try fixtures()
        bottle.settings.dllOverrides = "version=n,b"
        var env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "winemenubuilder.exe=d;version=n,b", "KLYC-Box's default first, the bottle's overrides after it: Wine's last entry wins, so the user can re-enable anything")

        bottle.settings.environment["WINEDLLOVERRIDES+"] = "libglesv2=d"
        env = try bottle.environment(engine: engine, renderer: .wined3d)
        let v = env["WINEDLLOVERRIDES"] ?? ""
        XCTAssertTrue(v.contains("version=n,b") && v.contains("libglesv2=d"), "got \(v)")
        XCTAssertTrue(v.contains(";"), "WINEDLLOVERRIDES parts must be ';'-joined, got \(v)")
    }

    // The registry mirror (issues #22/#25) parses only real override syntax: multi-name
    // entries fan out, ".dll" is stripped, and pasted Proton launch options never leak
    // garbage value names into HKCU\Software\Wine\DllOverrides.
    func testDllOverridesRegistryParse() {
        func flat(_ s: String) -> [String] { WineRunner.parseDllOverrides(s).map { "\($0.name)=\($0.order)" } }
        XCTAssertEqual(flat("version=n,b"), ["version=n,b"])
        XCTAssertEqual(flat("dxgi,D3D9.dll=n"), ["dxgi=n", "d3d9=n"])
        XCTAssertEqual(flat("winmm="), ["winmm="])              // empty = disabled
        XCTAssertEqual(flat("libglesv2=d"), ["libglesv2=d"])    // explicit disable
        XCTAssertEqual(flat("version=native,builtin;winmm=b"), ["version=native,builtin", "winmm=b"])
        XCTAssertEqual(flat(#"WINEDLLOVERRIDES="version=n,b" %command%"#), [])
        XCTAssertEqual(flat("just some words"), [])
        XCTAssertEqual(flat(""), [])
    }

    // The generated dxvk.conf: global line follows the bottle toggle, and the [csgo.exe]
    // section (issue #21: legacy CS:GO map-load freeze) must come AFTER it — later lines
    // win in DXVK's parser — carrying async off, the 32-bit memory cap, and the device id.
    func testDxvkConfigContent() {
        let on = Bottle.dxvkConfig(async: true)
        XCTAssertTrue(on.contains("dxvk.enableAsync = True"))
        let section = on.range(of: "[csgo.exe]")
        let global = on.range(of: "dxvk.enableAsync = True")
        XCTAssertNotNil(section); XCTAssertNotNil(global)
        XCTAssertTrue(global!.lowerBound < section!.lowerBound, "global line must precede the per-app section")
        let tail = String(on[section!.lowerBound...])
        XCTAssertTrue(tail.contains("dxvk.enableAsync = False"))
        XCTAssertTrue(tail.contains("d3d9.maxAvailableMemory = 2048"))
        XCTAssertTrue(tail.contains("d3d9.customDeviceId = 73BF"))

        let off = Bottle.dxvkConfig(async: false)
        XCTAssertTrue(off.contains("dxvk.enableAsync = False"))
        XCTAssertFalse(off.contains("dxvk.enableAsync = True"))
    }

    // The launch header quotes the conf without its comments and without the CS:GO fallback,
    // which is the same in every environment, while a section a recipe set stays (Discord, 2026-10-01).
    func testDxvkConfigHeaderLinesDropTheConstantParts() {
        XCTAssertEqual(Bottle.dxvkConfigHeaderLines(Bottle.dxvkConfig(async: false)), ["dxvk.enableAsync = False"])
        let tuned = Bottle.dxvkConfig(async: true, appConfig: ["csgo.exe": ["d3d9.maxAvailableMemory": "4096"],
                                                                "hl2.exe": ["dxvk.enableAsync": "False"]])
        XCTAssertEqual(Bottle.dxvkConfigHeaderLines(tuned),
                       ["dxvk.enableAsync = True", "[csgo.exe]", "d3d9.customDeviceId = 73BF", "d3d9.maxAvailableMemory = 4096",
                        "dxvk.enableAsync = False", "[hl2.exe]", "dxvk.enableAsync = False"])
    }

    // extra (per-pin environment from the program settings sheet) wins over bottle env.
    func testExtraEnvironmentWins() throws {
        var (engine, bottle) = try fixtures()
        bottle.settings.environment["MY_FLAG"] = "bottle"
        let env = try bottle.environment(engine: engine, renderer: .wined3d, extra: ["MY_FLAG": "pin"])
        XCTAssertEqual(env["MY_FLAG"], "pin")
    }

    func testAGamesOwnFpsCapBeatsTheEnvironmentsAndStaysVisibleToTheRestartRule() throws {
        var (engine, bottle) = try fixtures()
        let dxvkWine = engine.renderersDir.appending(path: "dxvk/wine"), d9vkWine = engine.renderersDir.appending(path: "d9vk/wine")
        try FileManager.default.createDirectory(at: dxvkWine, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: d9vkWine, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: engine.root) }
        bottle.settings.fpsCap = 60
        // The game asks for 30: it wins.
        var env = try bottle.environment(engine: engine, renderer: .dxvk, extra: [BottleSettings.gameFpsCapKey: "30"])
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "30")
        XCTAssertEqual(env[BottleSettings.gameFpsCapKey], "30", "kept, so Steam's restart rule can tell a capped client from an uncapped launch")
        // 0 means uncapped for this game, even where the environment caps.
        env = try bottle.environment(engine: engine, renderer: .dxvk, extra: [BottleSettings.gameFpsCapKey: "0"])
        XCTAssertNil(env["DXVK_FRAME_RATE"])
        // No game setting: the environment's cap stands. Nonsense is ignored the same way.
        env = try bottle.environment(engine: engine, renderer: .dxvk)
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "60")
        env = try bottle.environment(engine: engine, renderer: .dxvk, extra: [BottleSettings.gameFpsCapKey: "fast"])
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "60")
    }

    func testACappedClientIsNotReusedForAnUncappedGame() {
        // The rule the restart check applies to a game's scoped variable.
        let capped = ["KLYC_FPS_CAP": "30"]
        XCTAssertNotNil(SteamRestart.reason(live: capped, wanted: [:], wantedRenderer: "dxmt", custom: ["KLYC_FPS_CAP"]))
        XCTAssertNil(SteamRestart.reason(live: capped, wanted: capped, wantedRenderer: "dxmt", custom: ["KLYC_FPS_CAP"]))
    }

    func testCapChoicesIncludeTheDisplaysOwnRefreshRate() {
        let base = BottleSettings.fpsCapChoices(displayHz: nil, current: nil)
        XCTAssertEqual(base.first, 0)
        XCTAssertTrue(base.contains(180) && base.contains(144) && base.contains(60))
        XCTAssertEqual(BottleSettings.fpsCapChoices(displayHz: 175, current: nil).filter { $0 == 175 }.count, 1)
        XCTAssertTrue(BottleSettings.fpsCapChoices(displayHz: 100, current: nil).contains(100))
        XCTAssertEqual(BottleSettings.fpsCapChoices(displayHz: 180, current: 180).filter { $0 == 180 }.count, 1, "no duplicate")
        XCTAssertTrue(BottleSettings.fpsCapChoices(displayHz: nil, current: 77).contains(77), "a saved cap stays selectable")
        XCTAssertFalse(BottleSettings.fpsCapChoices(displayHz: 5, current: nil).contains(5), "nonsense refresh rates are ignored")
    }

    func testGameFpsCapParsing() {
        XCTAssertEqual(BottleSettings.gameFpsCap(in: ["KLYC_FPS_CAP": "45"]), 45)
        XCTAssertEqual(BottleSettings.gameFpsCap(in: ["KLYC_FPS_CAP": "0"]), 0)
        XCTAssertNil(BottleSettings.gameFpsCap(in: [:]))
        XCTAssertNil(BottleSettings.gameFpsCap(in: ["KLYC_FPS_CAP": "-5"]))
        XCTAssertNil(BottleSettings.gameFpsCap(in: ["KLYC_FPS_CAP": "99999"]))
    }

    func testTogglesAndFpsCap() throws {
        var (engine, bottle) = try fixtures()
        bottle.settings.metalHUD = true
        bottle.settings.advertiseAVX = true
        bottle.settings.fpsCap = 60
        var env = try bottle.environment(engine: engine, renderer: .wined3d)
        XCTAssertEqual(env["MTL_HUD_ENABLED"], "1")
        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertNil(env["DXVK_FRAME_RATE"], "wined3d has no fps cap channel")

        // DXVK renderer needs BOTH overlay dirs on disk: d9vk (D3D9) and dxvk (D3D10/11).
        let d9vkWine = engine.renderersDir.appending(path: "d9vk/wine")
        let dxvkWine = engine.renderersDir.appending(path: "dxvk/wine")
        try FileManager.default.createDirectory(at: d9vkWine, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dxvkWine, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: engine.root) }
        env = try bottle.environment(engine: engine, renderer: .dxvk)
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "60")
        // The async toggle travels via the generated conf, never DXVK_ASYNC: the async fork
        // reads `env == "1" || config.enableAsync`, so an env 1 would defeat the per-game
        // [csgo.exe] override that issue #21 requires.
        XCTAssertNil(env["DXVK_ASYNC"], "async must ride the conf, not the env")
        XCTAssertEqual(env["DXVK_CONFIG_FILE"], #"C:\klycbox\dxvk.conf"#)
        // d9vk must come first so DXVK's d3d9 wins the builtin search over wined3d (#21 CSM gate).
        XCTAssertEqual(env["WINEDLLPATH_PREPEND"], "\(d9vkWine.path):\(dxvkWine.path)")
    }

    // check frame generation setup and fallback
    func testFrameGenEnvironment() throws {
        var (engine, bottle) = try fixtures()
        let root = FileManager.default.temporaryDirectory.appending(path: "hb-test-fg-\(UUID().uuidString)")
        bottle = Bottle(url: root, settings: bottle.settings)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: engine.root) }
        for dir in ["d9vk/wine", "dxvk/wine", "dxmt/wine"] {
            try FileManager.default.createDirectory(at: engine.renderersDir.appending(path: dir), withIntermediateDirectories: true)
        }
        bottle.settings.frameGen = 2

        // missing shim
        XCTAssertEqual(bottle.frameGenStatus(engine: engine), .unavailable("This engine has no usable frame generation component. Build or install the component for this engine."))
        var env = try bottle.environment(engine: engine, renderer: .dxvk)
        XCTAssertNil(env["LSFGM_ENV"])

        // missing shaders
        let shim = engine.renderersDir.appending(path: "lsfg")
        try FileManager.default.createDirectory(at: shim, withIntermediateDirectories: true)
        try Data().write(to: shim.appending(path: "libMoltenVK.dylib"))
        XCTAssertNil(engine.resolveLsfgShimDir(), "a shim without a real driver cannot work")
        try FileManager.default.createDirectory(at: engine.frameworksDir, withIntermediateDirectories: true)
        try Data().write(to: engine.frameworksDir.appending(path: "libMoltenVK.dylib"))
        XCTAssertNotNil(engine.resolveLsfgShimDir())
        if case .unavailable(let why) = bottle.frameGenStatus(engine: engine) {
            XCTAssertTrue(why.contains("Lossless Scaling"), why)
        } else { XCTFail("expected unavailable without the DLL") }

        // add the shader fixture
        let steam = bottle.driveC.appending(path: "Program Files (x86)/Steam")
        let ls = steam.appending(path: "steamapps/common/Lossless Scaling")
        try FileManager.default.createDirectory(at: ls, withIntermediateDirectories: true)
        try Data().write(to: steam.appending(path: "steam.exe"))
        try Data().write(to: ls.appending(path: "lsfg-vk.dll"))
        XCTAssertEqual(bottle.frameGenStatus(engine: engine), .active(multiplier: 2))
        env = try bottle.environment(engine: engine, renderer: .dxvk)
        XCTAssertEqual(env["LSFGM_ENV"], "1")
        XCTAssertEqual(env["LSFGM_MULTIPLIER"], "2")
        XCTAssertEqual(env["LSFGM_DLL_PATH"], ls.appending(path: "lsfg-vk.dll").path)
        // check driver link repair
        XCTAssertEqual(env["LSFGM_MOLTENVK"], shim.appending(path: "libMoltenVK.real.dylib").path)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: shim.appending(path: "libMoltenVK.real.dylib").path), "../../frameworks/libMoltenVK.dylib")
        // the shim must take priority over the driver
        XCTAssertEqual(env["DYLD_LIBRARY_PATH"], shim.path)
        XCTAssertTrue(env["DYLD_FALLBACK_LIBRARY_PATH"]!.contains(engine.frameworksDir.path), "the runtime's fallback path is untouched")

        // a Metal renderer generates through the Metal hook instead of the Vulkan one
        XCTAssertEqual(bottle.frameGenStatus(engine: engine), .active(multiplier: 2))
        env = try bottle.environment(engine: engine, renderer: .dxmt)
        XCTAssertEqual(env["LSFGM_ENV"], "1")
        XCTAssertEqual(env["LSFGM_METAL"], "1")
        XCTAssertTrue(env["DYLD_INSERT_LIBRARIES"]!.contains(shim.appending(path: "libMoltenVK.dylib").path),
                      "the Metal hook must be injected")

        // off overrides installed components
        bottle.settings.frameGen = 1
        XCTAssertEqual(bottle.frameGenStatus(engine: engine), .off)
        XCTAssertNil(try bottle.environment(engine: engine, renderer: .dxvk)["LSFGM_ENV"])
    }

    // A renderer whose overlay is missing must throw, not silently fall back.
    func testMissingRendererThrows() throws {
        let (engine, bottle) = try fixtures()
        XCTAssertThrowsError(try bottle.environment(engine: engine, renderer: .dxmt))
    }

    // .dxvk with the dxvk overlay present but d9vk (its D3D9) missing must throw — never
    // silently regress D3D9 to builtin wined3d, which is exactly the #21 CSM-gate failure.
    func testDxvkRequiresD9vkOverlay() throws {
        let (engine, bottle) = try fixtures()
        try FileManager.default.createDirectory(at: engine.renderersDir.appending(path: "dxvk/wine"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: engine.root) }
        XCTAssertThrowsError(try bottle.environment(engine: engine, renderer: .dxvk),
                             "dxvk present but d9vk missing must throw, not fall back to wined3d")
    }

    /// OpenGL games asking for a 3.2+ core context without the forward-compatible bit crash on
    /// macOS unless Wine adds it; the engine's Mac driver reads this switch.
    func testForwardCompatibleGLContextsAreOnForEveryLaunch() throws {
        let (engine, bottle) = try fixtures()
        // The fixture engine has no renderer overlays on disk, so wined3d is the mode that resolves.
        XCTAssertEqual(try bottle.environment(engine: engine, renderer: .wined3d)["CX_FWD_COMPAT_GL_CTX"], "1")
    }

    // an engine with the d3dmetal licence accepted and its overlay plus d9vk on disk
    private func d3dmetalEngine() throws -> InstalledEngine {
        var manifest = EngineManifest(id: "d3dmetal-test", displayName: "D3DMetal test",
                                      arch: "x86_64", minMacOS: "14.0", components: [:])
        manifest.acceptedLicenses = Array(EngineManifest.gatedRenderers.values)
        let engine = InstalledEngine(manifest: manifest,
                                     root: FileManager.default.temporaryDirectory.appending(path: "hb-test-d3dmetal-\(UUID().uuidString)"))
        for r in ["d3dmetal", "d9vk"] {
            try FileManager.default.createDirectory(at: engine.frameworksDir.appending(path: "renderer/\(r)/wine"),
                                                    withIntermediateDirectories: true)
        }
        return engine
    }

    /// upstream#127: an engine that ships the audio buffer library gets it inserted into Wine's
    /// processes, a library the player set keeps its place after it, and HB_AUDIOBUF=0 leaves it out.
    func testTheAudioBufferLibraryIsInsertedOnlyWhenTheEngineShipsIt() throws {
        let engine = try d3dmetalEngine()
        defer { try? FileManager.default.removeItem(at: engine.root) }
        var bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-test-bottle"), settings: BottleSettings(name: "t", engineID: engine.id))
        XCTAssertNil(try bottle.environment(engine: engine)["DYLD_INSERT_LIBRARIES"], "an engine without the library inserts nothing")
        let lib = engine.frameworksDir.appending(path: "libhbaudiobuf.dylib")
        try Data().write(to: lib)
        XCTAssertEqual(try bottle.environment(engine: engine)["DYLD_INSERT_LIBRARIES"], lib.path)
        bottle.settings.environment["DYLD_INSERT_LIBRARIES"] = "/x/own.dylib"
        XCTAssertEqual(try bottle.environment(engine: engine)["DYLD_INSERT_LIBRARIES"], "\(lib.path):/x/own.dylib",
                       "a library the player inserts stays, after ours")
        bottle.settings.environment["HB_AUDIOBUF"] = "0"
        XCTAssertEqual(try bottle.environment(engine: engine)["DYLD_INSERT_LIBRARIES"], "/x/own.dylib", "HB_AUDIOBUF=0 leaves ours out")
    }

    /// upstream#248: a winetricks step runs under /bin/bash and Apple's arm64e tools, which
    /// cannot load the audio buffer library, so the variables it adds keep the library out even
    /// on an engine that ships it.
    func testAWinetricksStepNeverInsertsTheAudioBufferLibrary() throws {
        let engine = try d3dmetalEngine()
        defer { try? FileManager.default.removeItem(at: engine.root) }
        try Data().write(to: engine.frameworksDir.appending(path: "libhbaudiobuf.dylib"))
        let bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-test-bottle"), settings: BottleSettings(name: "t", engineID: engine.id))
        XCTAssertNotNil(try bottle.environment(engine: engine)["DYLD_INSERT_LIBRARIES"], "a game launch on this engine gets the library")
        let env = try bottle.environment(engine: engine, renderer: .wined3d, extra: RecipeRunner.winetricksExtras(engine: engine))
        XCTAssertNil(env["DYLD_INSERT_LIBRARIES"])
        XCTAssertEqual(env["WINE_BINDIR"], engine.wineBinary.deletingLastPathComponent().path, "winetricks' own overrides stay")
    }

    // d3dmetal ships 64-bit only, so 32-bit direct3d 10/11 goes to dxmt after it, not to wined3d
    func testD3DMetalFallsBackToDXMTFor32BitGames() throws {
        let engine = try d3dmetalEngine()
        defer { try? FileManager.default.removeItem(at: engine.root) }
        let d3dmetal = engine.frameworksDir.appending(path: "renderer/d3dmetal/wine").path
        let d9vk = engine.frameworksDir.appending(path: "renderer/d9vk/wine").path
        XCTAssertEqual(try Renderer.d3dmetal.environment(engine: engine)["WINEDLLPATH_PREPEND"], "\(d3dmetal):\(d9vk)",
                       "an engine without dxmt keeps the search path as it was")
        let dxmt = engine.frameworksDir.appending(path: "renderer/dxmt/wine")
        try FileManager.default.createDirectory(at: dxmt, withIntermediateDirectories: true)
        XCTAssertEqual(try Renderer.d3dmetal.environment(engine: engine)["WINEDLLPATH_PREPEND"], "\(d3dmetal):\(dxmt.path):\(d9vk)",
                       "dxmt comes after d3dmetal, so d3dmetal still serves everything it ships")
    }

    // the fps cap reaches the 32-bit games dxmt serves on a d3dmetal environment
    func testD3DMetalPassesTheFpsCapToDXMT() throws {
        let engine = try d3dmetalEngine()
        defer { try? FileManager.default.removeItem(at: engine.root) }
        var bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-test-bottle"),
                            settings: BottleSettings(name: "t", engineID: engine.id))
        XCTAssertNil(try bottle.environment(engine: engine, renderer: .d3dmetal)["DXMT_CONFIG"], "uncapped sets nothing")
        bottle.settings.fpsCap = 45
        let env = try bottle.environment(engine: engine, renderer: .d3dmetal)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=45;")
        XCTAssertEqual(env["D3DM_MAX_FPS"], "45", "the 64-bit games D3DMetal serves get its own cap")
        XCTAssertNil(env["DXVK_FRAME_RATE"], "d3dmetal has no dxvk cap channel")
    }
}
