import AppKit
import QuartzCore
import SwiftUI

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// The calm background of every screen that has no game art behind it: near-black, a cool blue glow, and faint particles drifting up.
struct BottleBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.062, green: 0.072, blue: 0.100), Color(red: 0.026, green: 0.031, blue: 0.046)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [HB.amber.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 760)
            RadialGradient(colors: [HB.amberDeep.opacity(0.34), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 980)
            ParticleField()
        }
        .ignoresSafeArea()
    }
}

/// Specks of light that rise slowly and fade. Drawn by Core Animation's particle emitter, which runs on the graphics chip: a canvas redrawn
/// 20 times a second cost a fifth of a processor core, this costs next to nothing. Frozen while the window is not in front, and a still
/// picture with Reduce Motion.
struct ParticleField: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ParticleLayer(running: scenePhase == .active && !reduceMotion)
    }
}

private struct ParticleLayer: NSViewRepresentable {
    let running: Bool

    func makeNSView(context: Context) -> EmitterView { EmitterView() }
    func updateNSView(_ view: EmitterView, context: Context) { view.setRunning(running) }

    final class EmitterView: NSView {
        private let emitter = CAEmitterLayer()
        private var running = true

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(emitter)
            emitter.emitterShape = .rectangle
            emitter.renderMode = .additive
            emitter.emitterCells = [cell()]
            // Start as if it had been running for a while, so the screen opens with particles already spread out.
            emitter.beginTime = CACurrentMediaTime() - 40
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layout() {
            super.layout()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitter.emitterSize = bounds.size
        }

        func setRunning(_ on: Bool) {
            guard on != running else { return }
            running = on
            if on {
                let paused = emitter.timeOffset
                emitter.speed = 1; emitter.timeOffset = 0
                emitter.beginTime = emitter.convertTime(CACurrentMediaTime(), from: nil) - paused
            } else {
                emitter.timeOffset = emitter.convertTime(CACurrentMediaTime(), from: nil)
                emitter.speed = 0
            }
        }

        private func cell() -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = Self.dot
            cell.birthRate = 2.4              // a speck every ~0.4 s over the whole screen
            cell.lifetime = 40
            cell.lifetimeRange = 12
            cell.velocity = 9
            cell.velocityRange = 5
            cell.emissionLongitude = .pi / 2  // up (the layer's y axis points up)
            cell.emissionRange = .pi / 10     // a little sideways
            cell.scale = 0.34
            cell.scaleRange = 0.2
            cell.alphaRange = 0.18
            cell.color = NSColor(white: 1, alpha: 0.22).cgColor
            cell.alphaSpeed = -0.004          // fades as it goes: nothing pops out at the top
            return cell
        }

        private static let dot: CGImage? = {
            let size = 8
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
            return ctx.makeImage()
        }()
    }
}
