import Foundation
import ImageIO
import CoreGraphics

/// Tells Windows' stock application icon (a white window with a blue frame, what the shell shows
/// for a program with no icon of its own and what some programs embed anyway) from a real one.
/// Used so a game's Mac app gets its cover art instead of that placeholder. A heuristic on the
/// picture: the window's body is almost white and its title bar blue; real game icons are neither.
public enum GenericIcon {
    public static func isGenericWindowsIcon(pngData: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let n = 32
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        func px(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * n + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
        }
        // The body: the middle of the picture, below the title bar.
        var body = 0, bodyWhite = 0
        for y in 12..<26 { for x in 8..<24 {
            let p = px(x, y); body += 1
            if p.a > 200, p.r > 225, p.g > 225, p.b > 225 { bodyWhite += 1 }
        } }
        // The frame: the top rows, clearly blue.
        var top = 0, topBlue = 0
        for y in 1..<8 { for x in 4..<28 {
            let p = px(x, y); top += 1
            if p.a > 200, p.b > p.r + 40, p.b > p.g + 10 { topBlue += 1 }
        } }
        return Double(bodyWhite) / Double(body) > 0.7 && Double(topBlue) / Double(top) > 0.4
    }
}
