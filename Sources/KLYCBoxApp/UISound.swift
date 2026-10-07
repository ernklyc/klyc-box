import AVFoundation
import Foundation

/// Soft interface sounds, synthesized here (sine tones with a quick decay), so nothing is copied from anywhere.
/// Off with the "Interface sounds" switch in Settings.
@MainActor
enum UISound {
    enum Kind: CaseIterable { case move, select, back, start, error }

    static let defaultsKey = "uiSounds"
    static var enabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    private static var players: [Kind: AVAudioPlayer] = [:]

    static func play(_ kind: Kind) {
        guard enabled, let player = player(for: kind) else { return }
        player.currentTime = 0
        player.play()
    }

    private static func player(for kind: Kind) -> AVAudioPlayer? {
        if let p = players[kind] { return p }
        guard let p = try? AVAudioPlayer(data: wav(for: kind)) else { return nil }
        p.volume = 0.22
        p.prepareToPlay()
        players[kind] = p
        return p
    }

    /// (frequency Hz, start s, length s, gain)
    private static func notes(for kind: Kind) -> [(Double, Double, Double, Double)] {
        switch kind {
        case .move:   return [(523.3, 0, 0.09, 0.35)]
        case .select: return [(392.0, 0, 0.12, 0.38), (587.3, 0.07, 0.16, 0.34)]
        case .back:   return [(440.0, 0, 0.11, 0.34), (329.6, 0.07, 0.15, 0.3)]
        case .start:  return [(261.6, 0, 0.45, 0.28), (329.6, 0.10, 0.45, 0.28), (392.0, 0.20, 0.55, 0.26), (523.3, 0.30, 0.70, 0.22)]
        case .error:  return [(196.0, 0, 0.14, 0.4), (174.6, 0.12, 0.2, 0.36)]
        }
    }

    static func wav(for kind: Kind) -> Data {
        let rate = 44_100.0
        let list = notes(for: kind)
        let total = (list.map { $0.1 + $0.2 }.max() ?? 0.1) + 0.05
        var samples = [Float](repeating: 0, count: Int(total * rate))
        for (freq, start, length, gain) in list {
            let from = Int(start * rate), count = Int(length * rate)
            for i in 0..<count where from + i < samples.count {
                let t = Double(i) / rate
                let attack = min(1, t / 0.018)                       // 18 ms in: a soft swell, no click
                let decay = exp(-4.0 * t / length)                   // soft tail
                let tone = sin(2 * .pi * freq * t) + 0.05 * sin(4 * .pi * freq * t)   // nearly a pure tone: round, not sharp
                samples[from + i] += Float(tone * attack * decay * gain * 0.5)
            }
        }
        var pcm = Data()
        for s in samples {
            var v = Int16(max(-1, min(1, s)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ x: UInt32) { var v = x.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { var v = x.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
