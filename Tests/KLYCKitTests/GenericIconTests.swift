import XCTest
import CoreGraphics
import ImageIO
@testable import KLYCKit

final class GenericIconTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Fixtures/icons/\(name).png")
        return try Data(contentsOf: url)
    }

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Data {
        let n = 64
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255 }
        let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testTheStockWindowsIconIsRecognised() throws {
        XCTAssertTrue(GenericIcon.isGenericWindowsIcon(pngData: try fixture("generic-windows")))
    }

    func testRealGameIconsAreNot() throws {
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: try fixture("real-megabonk")))
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: try fixture("real-hades")))
    }

    func testPlainPicturesAreNot() {
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: solid(255, 255, 255)), "an all-white square has no blue frame")
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: solid(20, 60, 200)), "an all-blue square has no white body")
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: solid(200, 30, 30)))
        XCTAssertFalse(GenericIcon.isGenericWindowsIcon(pngData: Data("not an image".utf8)))
    }
}

final class IconFitTests: XCTestCase {
    func testTheShortSideBecomesTheSquare() {
        let tall = MacAppStub.coverFitSize(width: 600, height: 900, side: 1024)
        XCTAssertEqual(tall?.width, 1024)
        XCTAssertEqual(tall?.height, 1536)
        let wide = MacAppStub.coverFitSize(width: 920, height: 430, side: 1024)
        XCTAssertEqual(wide?.height, 1024)
        XCTAssertEqual(wide?.width, 2191)
        let square = MacAppStub.coverFitSize(width: 256, height: 256, side: 1024)
        XCTAssertEqual(square?.width, 1024)
        XCTAssertEqual(square?.height, 1024)
        XCTAssertNil(MacAppStub.coverFitSize(width: 0, height: 10, side: 1024))
    }

    func testReadsSipsOutput() {
        let out = "/tmp/x.png\n  pixelWidth: 600\n  pixelHeight: 900\n"
        XCTAssertEqual(MacAppStub.pixelSize(fromSips: out)?.width, 600)
        XCTAssertEqual(MacAppStub.pixelSize(fromSips: out)?.height, 900)
        XCTAssertNil(MacAppStub.pixelSize(fromSips: "garbage"))
    }

    /// The real thing: a tall picture of one colour must come out of makeIcon with that colour at
    /// the left and right edges, not black bars.
    func testATallCoverFillsTheWholeIcon() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = 300, h = 450
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4] = 220; px[i * 4 + 1] = 40; px[i * 4 + 2] = 40; px[i * 4 + 3] = 255 }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let png = dir.appending(path: "tall.png")
        let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)

        let icns = dir.appending(path: "icon.icns")
        try MacAppStub.makeIcon(from: png, to: icns)
        let back = dir.appending(path: "back.png")
        try Shell.run("/usr/bin/sips", ["-s", "format", "png", icns.path, "--out", back.path])
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(back as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let octx = CGContext(data: &out, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        octx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func red(_ x: Int, _ y: Int) -> Int { Int(out[(y * image.width + x) * 4]) }
        let mid = image.height / 2
        for x in [2, image.width / 2, image.width - 3] {
            XCTAssertGreaterThan(red(x, mid), 150, "column \(x) is not black")
        }
    }
}
