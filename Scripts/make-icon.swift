// Renders the KLYC-Box app icon to a PNG: the same cube as the website logo (K on the left face, B on the right, an apple on top),
// light and steel greys on a near-black plate, matching the app's own dark theme and the website's logo shape. Keep the shape in step with
// the site's Logo component (src/components/Logo.tsx in klyc-box-site).
// Usage: swift Scripts/make-icon.swift <output.png> [size]
import AppKit
import CoreGraphics

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let S = CGFloat(CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 1024 : 1024)

let image = NSImage(size: NSSize(width: S, height: S), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let u = S / 1024.0  // unit

    func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x * u, y: y * u, width: w * u, height: h * u),
               cornerWidth: r * u, cornerHeight: r * u, transform: nil)
    }
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }
    func gradient(_ path: CGPath, _ top: UInt32, _ bottom: UInt32, alpha: CGFloat = 1) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(top, alpha), color(bottom, alpha)] as CFArray, locations: [0, 1])!
        let box = path.boundingBox
        ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.maxY),
                               end: CGPoint(x: box.midX, y: box.minY), options: [])
        ctx.restoreGState()
    }

    func pt0(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
    // macOS squircle-ish canvas with standard margin
    let plate = rr(100, 100, 824, 824, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 24 * u, color: color(0x000000, 0.35))
    gradient(plate, 0x1C2332, 0x07090E)
    ctx.restoreGState()

    // isometric box
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
    func face(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath(); return path
    }
    let T = pt(512, 790), UR = pt(746, 655), LR = pt(746, 385), B = pt(512, 250), LL = pt(278, 385), UL = pt(278, 655), C = pt(512, 520)
    let top = face([T, UR, C, UL]), left = face([UL, C, B, LL]), right = face([C, UR, LR, B])
    gradient(top, 0x8D98AE, 0x7B869E)
    gradient(left, 0x2C3549, 0x1F2738)
    gradient(right, 0x4A566E, 0x3C475E)
    ctx.setLineJoin(.round)
    

    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xFFFFFF, 0.28))
    ctx.setLineWidth(5 * u)
    for f in [top, left, right] { ctx.addPath(f); ctx.strokePath() }

    // the K on the left face
    ctx.saveGState()
    ctx.concatenate(CGAffineTransform(a: 234 * u, b: -135 * u, c: 0, d: 270 * u, tx: 278 * u, ty: 385 * u))
    ctx.translateBy(x: 0.5, y: 0.5); ctx.scaleBy(x: 0.74, y: 0.74); ctx.translateBy(x: -0.5, y: -0.5)
    ctx.setStrokeColor(color(0xFFFFFF, 0.97))
    ctx.setLineWidth(0.15)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 0.28, y: 0.2)); ctx.addLine(to: CGPoint(x: 0.28, y: 0.8))
    ctx.move(to: CGPoint(x: 0.30, y: 0.5)); ctx.addLine(to: CGPoint(x: 0.72, y: 0.8))
    ctx.move(to: CGPoint(x: 0.42, y: 0.58)); ctx.addLine(to: CGPoint(x: 0.72, y: 0.2))
    ctx.strokePath()
    ctx.restoreGState()

    // the B on the right face
    ctx.saveGState()
    ctx.concatenate(CGAffineTransform(a: 234 * u, b: 135 * u, c: 0, d: 270 * u, tx: 512 * u, ty: 250 * u))
    ctx.translateBy(x: 0.5, y: 0.5); ctx.scaleBy(x: 0.74, y: 0.74); ctx.translateBy(x: -0.5, y: -0.5)
    ctx.setStrokeColor(color(0xFFFFFF, 0.97))
    ctx.setLineWidth(0.15)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 0.28, y: 0.2)); ctx.addLine(to: CGPoint(x: 0.28, y: 0.8))
    ctx.move(to: CGPoint(x: 0.28, y: 0.8)); ctx.addLine(to: CGPoint(x: 0.46, y: 0.8))
    ctx.addCurve(to: CGPoint(x: 0.46, y: 0.5), control1: CGPoint(x: 0.66, y: 0.8), control2: CGPoint(x: 0.66, y: 0.5))
    ctx.addLine(to: CGPoint(x: 0.28, y: 0.5))
    ctx.move(to: CGPoint(x: 0.28, y: 0.5)); ctx.addLine(to: CGPoint(x: 0.50, y: 0.5))
    ctx.addCurve(to: CGPoint(x: 0.50, y: 0.2), control1: CGPoint(x: 0.72, y: 0.5), control2: CGPoint(x: 0.72, y: 0.2))
    ctx.addLine(to: CGPoint(x: 0.28, y: 0.2))
    ctx.strokePath()
    ctx.restoreGState()

    // the apple on the top face (drawn upright, squashed to lie on the top plane)
    func A(_ x: CGFloat, _ y: CGFloat) -> CGPoint { pt(512 + (x - 12) * 13.5, 655 - (y - 12) * 13.5 * 0.58) }
    let apple = CGMutablePath()
    apple.move(to: A(12, 8.2))
    apple.addCurve(to: A(6.7, 8.4), control1: A(10.6, 7), control2: A(8.2, 6.8))
    apple.addCurve(to: A(7, 17.2), control1: A(4.9, 10.4), control2: A(5.2, 14))
    apple.addCurve(to: A(10.8, 20.4), control1: A(8, 19), control2: A(9.4, 20.6))
    apple.addCurve(to: A(12, 19.9), control1: A(11.6, 20.3), control2: A(11.8, 19.9))
    apple.addCurve(to: A(13.2, 20.4), control1: A(12.2, 19.9), control2: A(12.4, 20.3))
    apple.addCurve(to: A(17, 17.2), control1: A(14.6, 20.6), control2: A(16, 19))
    apple.addCurve(to: A(18.4, 14), control1: A(17.7, 15.9), control2: A(18.2, 14.8))
    apple.addCurve(to: A(17.9, 8.9), control1: A(16.4, 13.2), control2: A(15.8, 10.2))
    apple.addCurve(to: A(12, 8.2), control1: A(16.4, 6.9), control2: A(13.6, 6.9))
    apple.closeSubpath()
    apple.move(to: A(12.2, 6.6))
    apple.addCurve(to: A(14.6, 3.2), control1: A(12, 4.9), control2: A(13, 3.6))
    apple.addCurve(to: A(12.2, 6.6), control1: A(14.8, 4.8), control2: A(13.8, 6.2))
    apple.closeSubpath()
    ctx.setFillColor(color(0xFFFFFF, 0.97))
    ctx.addPath(apple); ctx.fillPath()

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(Int(S))px)")
