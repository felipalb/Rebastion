import AVFoundation
import QuartzCore

/// Procedural sound effects: every sound is synthesized at launch, so the game ships with no audio assets.
@MainActor
final class SoundEngine {
    enum Sound: CaseIterable {
        case launch, bounce, hit, crit, kill, eliteKill, gem, levelUp, pulse, hurt
        case explosion, zap, shield, freeze, enemyShot, waveStart, waveClear
        case bossAlarm, bossDown, fusion, combo, heal, select, gameOver

        var minInterval: CFTimeInterval {
            switch self {
            case .hit, .gem: 0.035
            case .bounce, .launch: 0.06
            case .explosion, .zap, .enemyShot, .shield: 0.07
            default: 0.05
            }
        }
    }

    var isEnabled = true

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: [AVAudioPCMBuffer]] = [:]
    private var lastPlayed: [Sound: CFTimeInterval] = [:]
    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private var configurationObserver: NSObjectProtocol?

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.8
        buildBuffers()
        startEngine()

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startEngine() }
        }
    }

    func play(_ sound: Sound, variant: Int = 0, volume: Float = 1) {
        guard isEnabled, let variants = buffers[sound], !variants.isEmpty else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[sound], now - last < sound.minInterval { return }
        lastPlayed[sound] = now
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }

        let buffer = variants[min(max(variant, 0), variants.count - 1)]
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            players.forEach { $0.play() }
        } catch {
            // Audio is optional; the game keeps running silently.
        }
    }

    // MARK: Synthesis

    private func buildBuffers() {
        buffers[.launch] = [tone(0.05, from: 900, to: 1400, wave: .sine, gain: 0.16)]
        buffers[.bounce] = [tone(0.04, from: 560, to: 520, wave: .triangle, gain: 0.12)]
        buffers[.hit] = (0..<12).map { i in
            let f = 330 * pow(2, Double(i) / 12)
            return mix([tone(0.07, from: f, to: f * 0.8, wave: .triangle, gain: 0.32), noise(0.03, gain: 0.12, cutoff: 0.5)])
        }
        buffers[.crit] = [mix([tone(0.12, from: 880, to: 1500, wave: .square, gain: 0.16), noise(0.06, gain: 0.2, cutoff: 0.7)])]
        buffers[.kill] = [mix([tone(0.16, from: 620, to: 180, wave: .sine, gain: 0.35), noise(0.12, gain: 0.25, cutoff: 0.25)])]
        buffers[.eliteKill] = [mix([tone(0.38, from: 320, to: 60, wave: .sine, gain: 0.5), noise(0.3, gain: 0.35, cutoff: 0.15)])]
        buffers[.gem] = (0..<12).map { i in
            let f = 1100 * pow(2, Double(i) / 12)
            return tone(0.08, from: f, to: f, wave: .sine, gain: 0.14)
        }
        buffers[.levelUp] = [arpeggio([523, 659, 784, 1046, 1318], step: 0.07, tail: 0.25, wave: .square, gain: 0.13)]
        buffers[.pulse] = [mix([tone(0.6, from: 110, to: 900, wave: .sine, gain: 0.4), noise(0.5, gain: 0.3, cutoff: 0.12)])]
        buffers[.hurt] = [mix([tone(0.28, from: 240, to: 90, wave: .square, gain: 0.25), noise(0.15, gain: 0.25, cutoff: 0.3)])]
        buffers[.explosion] = [mix([noise(0.42, gain: 0.5, cutoff: 0.08), tone(0.35, from: 100, to: 40, wave: .sine, gain: 0.5)])]
        buffers[.zap] = [zap(0.14, gain: 0.2)]
        buffers[.shield] = [mix([tone(0.12, from: 1500, to: 1450, wave: .sine, gain: 0.15), tone(0.12, from: 1830, to: 1790, wave: .sine, gain: 0.12)])]
        buffers[.freeze] = [tremolo(tone(0.3, from: 2000, to: 2700, wave: .sine, gain: 0.12), rate: 28)]
        buffers[.enemyShot] = [tone(0.09, from: 720, to: 380, wave: .square, gain: 0.08)]
        buffers[.waveStart] = [arpeggio([440, 660], step: 0.12, tail: 0.2, wave: .triangle, gain: 0.25)]
        buffers[.waveClear] = [arpeggio([660, 880, 1100, 1320], step: 0.08, tail: 0.3, wave: .triangle, gain: 0.25)]
        buffers[.bossAlarm] = [arpeggio([440, 330, 440, 330, 440, 330], step: 0.16, tail: 0.15, wave: .square, gain: 0.14)]
        buffers[.bossDown] = [mix([noise(1.2, gain: 0.5, cutoff: 0.06), tone(1.2, from: 400, to: 35, wave: .sine, gain: 0.5)])]
        buffers[.fusion] = [mix([
            tone(0.9, from: 262, to: 524, wave: .triangle, gain: 0.2),
            tone(0.9, from: 330, to: 660, wave: .triangle, gain: 0.18),
            tone(0.9, from: 392, to: 784, wave: .triangle, gain: 0.18),
            noise(0.9, gain: 0.08, cutoff: 0.4),
        ])]
        buffers[.combo] = (0..<5).map { i in
            let base = 523 * pow(2, Double(i * 2) / 12)
            return arpeggio([base, base * 1.26, base * 1.5], step: 0.05, tail: 0.15, wave: .square, gain: 0.12)
        }
        buffers[.heal] = [tone(0.28, from: 660, to: 990, wave: .sine, gain: 0.25)]
        buffers[.select] = [tone(0.035, from: 1000, to: 1000, wave: .square, gain: 0.08)]
        buffers[.gameOver] = [arpeggio([440, 349, 262, 196], step: 0.2, tail: 0.5, wave: .triangle, gain: 0.28)]
    }

    private enum Wave { case sine, square, triangle }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData![0]
        for (i, s) in samples.enumerated() { channel[i] = s }
        return buffer
    }

    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let channel = buffer.floatChannelData![0]
        return (0..<Int(buffer.frameLength)).map { channel[$0] }
    }

    /// Percussive envelope: 4 ms attack then exponential decay.
    private func envelope(_ t: Double, _ duration: Double) -> Double {
        let attack = 0.004
        if t < attack { return t / attack }
        return exp(-4.5 * (t - attack) / duration)
    }

    private func oscillator(_ wave: Wave, _ phase: Double) -> Double {
        switch wave {
        case .sine: return sin(phase)
        case .square: return sin(phase) >= 0 ? 1 : -1
        case .triangle: return 2 / .pi * asin(sin(phase))
        }
    }

    private func toneSamples(_ duration: Double, from f0: Double, to f1: Double, wave: Wave, gain: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var phase = 0.0
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let f = f0 * pow(f1 / f0, progress)
            phase += 2 * .pi * f / sampleRate
            out[i] = Float(oscillator(wave, phase) * envelope(t, duration) * gain)
        }
        return out
    }

    private func tone(_ duration: Double, from f0: Double, to f1: Double, wave: Wave, gain: Double) -> AVAudioPCMBuffer {
        makeBuffer(toneSamples(duration, from: f0, to: f1, wave: wave, gain: gain))
    }

    private func noise(_ duration: Double, gain: Double, cutoff: Double) -> AVAudioPCMBuffer {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var last = 0.0
        var seed: UInt32 = 0x1234_5678
        for i in 0..<count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed) / Double(UInt32.max) * 2 - 1
            last += cutoff * (white - last)
            let t = Double(i) / sampleRate
            out[i] = Float(last * envelope(t, duration) * gain * (1 / max(0.3, sqrt(cutoff))))
        }
        return makeBuffer(out)
    }

    private func zap(_ duration: Double, gain: Double) -> AVAudioPCMBuffer {
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        var freq = 900.0
        var seed: UInt32 = 0xBEEF
        for i in 0..<count {
            if i % 400 == 0 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                freq = 600 + Double(seed % 1800)
            }
            phase += 2 * .pi * freq / sampleRate
            let t = Double(i) / sampleRate
            out[i] = Float((sin(phase) >= 0 ? 1 : -1) * envelope(t, duration) * gain)
        }
        return makeBuffer(out)
    }

    private func arpeggio(_ notes: [Double], step: Double, tail: Double, wave: Wave, gain: Double) -> AVAudioPCMBuffer {
        let total = step * Double(notes.count - 1) + tail
        var out = [Float](repeating: 0, count: Int(total * sampleRate))
        for (index, note) in notes.enumerated() {
            let offset = Int(Double(index) * step * sampleRate)
            let part = toneSamples(tail + step, from: note, to: note, wave: wave, gain: gain)
            for (i, s) in part.enumerated() where offset + i < out.count {
                out[offset + i] += s
            }
        }
        return makeBuffer(out)
    }

    private func mix(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
        let all = parts.map(samples)
        let length = all.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: length)
        for part in all {
            for (i, s) in part.enumerated() { out[i] += s }
        }
        return makeBuffer(out.map { max(-1, min(1, $0)) })
    }

    private func tremolo(_ buffer: AVAudioPCMBuffer, rate: Double) -> AVAudioPCMBuffer {
        let input = samples(buffer)
        let out = input.enumerated().map { i, s in
            s * Float(0.6 + 0.4 * sin(2 * .pi * rate * Double(i) / sampleRate))
        }
        return makeBuffer(out)
    }
}
