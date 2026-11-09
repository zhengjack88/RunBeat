import AVFoundation

/// 节拍音色
enum ClickSound: String, CaseIterable, Identifiable {
    case woodblock
    case electronic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .woodblock: return "木鱼"
        case .electronic: return "电子"
        }
    }
}

/// 纯代码合成 PCM 音色，不依赖任何音频文件。
enum ClickSynth {
    static let sampleRate: Double = 44_100

    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: sampleRate,
                      channels: 1,
                      interleaved: false)!
    }

    /// 合成一个点击音的原始采样（不含拍间静音）。
    static func samples(for sound: ClickSound, accent: Bool) -> [Float] {
        switch sound {
        case .woodblock: return woodblock(accent: accent)
        case .electronic: return electronic(accent: accent)
        }
    }

    // MARK: - 木鱼

    /// 正弦衰减叠加（木质共振模态）+ 极短高频瞬态。
    private static func woodblock(accent: Bool) -> [Float] {
        let duration = 0.090
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        let pitch: Double = accent ? 1.35 : 1.0
        // (频率, 幅度, 衰减时间常数 秒)
        let modes: [(Double, Double, Double)] = [
            (860 * pitch, 1.00, 0.018),
            (1_720 * pitch, 0.55, 0.012),
            (2_650 * pitch, 0.30, 0.007),
            (3_900 * pitch, 0.12, 0.004)
        ]
        var rng = LCG(seed: accent ? 7 : 3)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var v = 0.0
            for (f, a, tau) in modes {
                v += a * sin(2 * .pi * f * t) * exp(-t / tau)
            }
            // 高频微瞬态：约 1.5ms 的噪声爆发
            let transient = rng.nextSigned() * exp(-t / 0.0006) * 0.35
            v += transient
            // 2ms 起音渐入，避免爆音
            let attack = min(1.0, t / 0.0005)
            out[i] = Float(v * attack)
        }
        return normalize(out, peak: accent ? 0.95 : 0.70)
    }

    // MARK: - 电子咔哒

    /// 双脉冲 + 白噪瞬态。
    private static func electronic(accent: Bool) -> [Float] {
        let duration = 0.045
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        let f1: Double = accent ? 2_600 : 1_900
        let f2: Double = accent ? 1_800 : 1_300
        let secondPulseStart = 0.008
        var rng = LCG(seed: accent ? 11 : 5)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var v = 0.0
            // 第一脉冲：高音 + 白噪
            v += sin(2 * .pi * f1 * t) * exp(-t / 0.0030)
            v += rng.nextSigned() * exp(-t / 0.0008) * 0.6
            // 第二脉冲：较低音，稍弱
            if t >= secondPulseStart {
                let u = t - secondPulseStart
                v += 0.7 * sin(2 * .pi * f2 * u) * exp(-u / 0.0040)
                v += rng.nextSigned() * exp(-u / 0.0006) * 0.3
            }
            let attack = min(1.0, t / 0.0002)
            out[i] = Float(v * attack)
        }
        return normalize(out, peak: accent ? 0.95 : 0.70)
    }

    // MARK: - 工具

    private static func normalize(_ x: [Float], peak: Float) -> [Float] {
        let m = x.map { abs($0) }.max() ?? 1
        guard m > 0 else { return x }
        let g = peak / m
        return x.map { $0 * g }
    }

    /// 确定性伪随机数，保证每次合成结果一致。
    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func nextSigned() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = Double((state >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
            return v * 2 - 1
        }
    }
}
