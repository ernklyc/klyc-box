import XCTest
@testable import KLYCKit

/// Every recipe and db entry shipped from klyc-db must decode with the current
/// Recipe/GameDBEntry types — this is the drift tripwire between the two repos.
/// Skips cleanly when the sibling checkout isn't present (e.g. bare CI).
final class RecipeDBTests: XCTestCase {

    private var dbRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// upstream#195: Wine Mono writes the same NDP v4 Release value as Microsoft's .NET 4.8.1
    /// (0x82348), so a registry marker called .NET installed in every environment, the
    /// Dependencies panel offered no Install, and a mixed-mode launcher kept failing under Mono.
    /// The shipped recipe must look for the real runtime, clr.dll, which Mono never installs.
    func testDotNet48IsNotInstalledWhereOnlyWineMonoIs() throws {
        let f = dbRoot.appending(path: "recipes/tweaks/dotnet48.json")
        guard FileManager.default.fileExists(atPath: f.path) else { throw XCTSkip("klyc-db checkout not found next to the repo") }
        let recipe = try JSONDecoder.klycbox.decode(Recipe.self, from: Data(contentsOf: f))
        let dir = FileManager.default.temporaryDirectory.appending(path: "hb-dotnet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let framework = dir.appending(path: "drive_c/windows/Microsoft.NET/Framework/v4.0.30319")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try "WINE REGISTRY Version 2\n\n[Software\\\\Microsoft\\\\NET Framework Setup\\\\NDP\\\\v4\\\\Full] 1788462370\n\"Install\"=dword:00000001\n\"Release\"=dword:00082348\n"
            .write(to: dir.appending(path: "system.reg"), atomically: true, encoding: .utf8)
        try Data().write(to: framework.appending(path: "mscorlib.dll"))   // Mono leaves this one too
        let bottle = Bottle(url: dir, settings: BottleSettings(name: "mono", engineID: "e"))
        XCTAssertFalse(recipe.isInstalled(in: bottle), "THE BUG: Wine Mono alone must not count as .NET Framework 4.8")
        try Data().write(to: framework.appending(path: "clr.dll"))
        XCTAssertTrue(recipe.isInstalled(in: bottle), "the real runtime counts")
    }

    func testAllShippedRecipesDecode() throws {
        let recipes = dbRoot.appending(path: "recipes")
        guard FileManager.default.fileExists(atPath: recipes.path) else {
            throw XCTSkip("klyc-db checkout not found next to the repo")
        }
        var checked = 0
        for sub in ["launchers", "games", "tweaks"] {
            let dir = recipes.appending(path: sub)
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "json" {
                let r: Recipe
                do { r = try JSONDecoder.klycbox.decode(Recipe.self, from: Data(contentsOf: f)) }
                catch { XCTFail("\(f.lastPathComponent) failed to decode: \(error)"); continue }
                XCTAssertFalse(r.id.isEmpty, f.lastPathComponent)
                XCTAssertFalse(r.title.isEmpty, f.lastPathComponent)
                for step in r.steps {
                    if case let .installer(url, _, _, _, _, _) = step {
                        XCTAssertEqual(url.scheme, "https", "\(f.lastPathComponent): installer URLs must be https")
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 5, "expected to find shipped recipes; wrong path?")
    }

    func testAllShippedGameDBEntriesDecode() throws {
        let dir = dbRoot.appending(path: "db/games")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("klyc-db checkout not found next to the repo")
        }
        var checked = 0
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where f.pathExtension == "json" {
            do {
                let e = try JSONDecoder.klycbox.decode(GameDBEntry.self, from: Data(contentsOf: f))
                XCTAssertFalse(e.id.isEmpty, f.lastPathComponent)
                XCTAssertTrue(["verified-local", "reported-upstream", "community", "blocked-anticheat", "blocked-publisher"].contains(e.status),
                              "\(f.lastPathComponent): unknown status '\(e.status)'")
            } catch {
                XCTFail("\(f.lastPathComponent) failed to decode: \(error)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // A blocked recipe must refuse to run before touching the bottle — a launcher
    // installer would otherwise hang a user's install forever.
    func testBlockedRecipeRefusesToApply() async throws {
        let json = """
        {"id":"b","kind":"launcher","title":"Blocked Thing","steps":[{"type":"note","text":"x"}],
         "blocked":{"reason":"engine cannot run it","tracking":"https://example.com/1"}}
        """
        let r = try JSONDecoder.klycbox.decode(Recipe.self, from: Data(json.utf8))
        XCTAssertEqual(r.blocked?.reason, "engine cannot run it")
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "spike/engine-manifest.json")
        let engine = InstalledEngine(manifest: try EngineManifest.load(from: manifestURL),
                                     root: FileManager.default.temporaryDirectory.appending(path: "hb-blocked-\(UUID().uuidString)"))
        let bottle = Bottle(url: URL(fileURLWithPath: "/tmp/hb-blocked-bottle"),
                            settings: BottleSettings(name: "b", engineID: engine.id))
        var runner = RecipeRunner(engine: engine, bottle: bottle)
        do {
            _ = try await runner.apply(r)
            XCTFail("blocked recipe must throw")
        } catch {
            XCTAssertTrue("\(error)".contains("blocked"), "error should explain the block: \(error)")
        }
    }

    // Issue #36 tripwire: the VC++ installers must stay pinned to an immutable versioned URL
    // with a real sha256. The rolling aka.ms/vs/17/release/vc_redist.*.exe link is what breaks
    // winetricks every few months when Microsoft republishes behind it.
    func testVcrunInstallersArePinnedAndVerified() throws {
        let f = dbRoot.appending(path: "recipes/tweaks/vcrun2022.json")
        guard FileManager.default.fileExists(atPath: f.path) else {
            throw XCTSkip("klyc-db checkout not found next to the repo")
        }
        let r = try JSONDecoder.klycbox.decode(Recipe.self, from: Data(contentsOf: f))
        var installers = 0
        for step in r.steps {
            guard case let .installer(url, sha256, _, label, _, _) = step else { continue }
            installers += 1
            XCTAssertEqual(sha256?.count, 64, "\(label): pinned URLs must carry a sha256")
            XCTAssertFalse(url.absoluteString.hasSuffix("release/vc_redist.x64.exe"),
                           "\(label): rolling URL — pin the versioned one")
            XCTAssertFalse(url.absoluteString.hasSuffix("release/vc_redist.x86.exe"),
                           "\(label): rolling URL — pin the versioned one")
        }
        XCTAssertEqual(installers, 2, "expected the x64 and x86 redists")
    }
}
