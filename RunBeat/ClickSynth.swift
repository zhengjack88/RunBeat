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

    // MARK: - 木鱼（基于物理声学特征重调）
    //
    // 声学特征：
    // 1. 分音结构：主共鸣基频 900 Hz，非整数倍分音 2.7x (2430 Hz) 和 5.1x (4590 Hz)，
    //    分音增益分别为 0.5 和 0.2，衰减速度为基频的 2 倍（非整数谐波列，纯正木质声）。
    // 2. 衰减：整段时长 100 ms，包络采用 28 ms 陡峭指数衰减，尾部在 80-100 ms 平滑收住，无嗡嗡余音。
    // 3. 敲击起音：前 3-6 ms 叠加 3.2 kHz 带通滤波短噪声脉冲，提供短脆干的"笃"起音声。
    // 4. 起音滑音：前 10 ms 频率由 1.08x 滑落至基频，模拟木质腔体受击形变。
    // 5. 响度：相比原版提升约 3 dB，中频厚实干脆，能清晰穿透音乐。

    private static func woodblock(accent: Bool) -> [Float] {
        let duration = 0.100 // 100 ms
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)

        let f0: Double = 900.0
        let tau0: Double = 0.028 // 基频衰减时间常数 28 ms
        let tau1: Double = tau0 * 0.5 // 分音衰减快一倍 (14 ms)
        let tau2: Double = tau0 * 0.5

        let modes: [(ratio: Double, amp: Double, tau: Double)] = [
            (1.0, 1.0, tau0),
            (2.7, 0.5, tau1),
            (5.1, 0.2, tau2)
        ]

        // 3.2 kHz 带通双二阶滤波器 (Q=2.0)
        let fc = 3200.0
        let Q = 2.0
        let w0 = 2.0 * .pi * fc / sampleRate
        let alpha = sin(w0) / (2.0 * Q)
        let b0 = alpha / (1.0 + alpha)
        let b1 = 0.0
        let b2 = -alpha / (1.0 + alpha)
        let a1 = (-2.0 * cos(w0)) / (1.0 + alpha)
        let a2 = (1.0 - alpha) / (1.0 + alpha)

        var rng = LCG(seed: accent ? 87654321 : 12345678)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var filteredNoise = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let x0 = rng.nextSigned()
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            filteredNoise[i] = y0
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
        }

        var phi0: Double = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate

            // 起音前 10 ms 瞬态滑音 (1.08 -> 1.00)
            let pitchDrop = 0.08 * exp(-t / 0.003)
            let instF0 = f0 * (1.0 + pitchDrop)
            phi0 += 2.0 * .pi * instF0 / sampleRate

            // 非整数分音叠加
            var v = 0.0
            for m in modes {
                let phi = phi0 * m.ratio
                let decay = exp(-t / m.tau)
                v += m.amp * sin(phi) * decay
            }

            // 起音短噪声脉冲 (前 3-6 ms)
            let noiseEnvelope = t < 0.008 ? exp(-t / 0.0012) : 0.0
            let noiseVal = filteredNoise[i] * noiseEnvelope * 0.75
            v += noiseVal

            // 0.2 ms 极快渐入防爆音
            let attack = min(1.0, t / 0.0002)
            v *= attack

            // 80-100 ms 干净平滑收尾，消除余音
            if t > 0.075 {
                let fade = max(0.0, (duration - t) / (duration - 0.075))
                v *= (fade * fade)
            }

            out[i] = Float(v)
        }

        // 提高增益与响度（普通版 peak 0.82，重音版 0.98）
        return normalize(out, peak: accent ? 0.98 : 0.82)
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
        return normalize(out, peak: accent ? 0.98 : 0.82)
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
