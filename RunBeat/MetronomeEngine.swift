import AVFoundation

/// 节拍器模式
enum MetronomeMode: String, CaseIterable, Identifiable {
    case fixed
    case progressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "固定节拍"
        case .progressive: return "渐进模式"
        }
    }
}

/// 基于 AVAudioEngine + AVAudioPlayerNode 的采样级前瞻排程节拍引擎。
///
/// 特性：
/// 1. 零 Timer 调度：每一拍按当前时刻应有的瞬时 BPM 计算精确采样数，由音频硬件时钟无缝消费。
/// 2. 渐进模式线性爬升：每拍间隔按发声时刻应有的 BPM 逐拍计算，BPM 是已播放采样时间的连续函数。
/// 3. 暂停/继续保护：基于实际已消费采样数（consumedFrames）记录进度，暂停时爬升计时随之停止，杜绝按墙钟偷跑。
final class MetronomeEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = ClickSynth.format
    private let sampleRate = ClickSynth.sampleRate

    /// 所有可变状态都在该串行队列上访问。
    private let queue = DispatchQueue(label: "com.jackzheng.runbeat.scheduler", qos: .userInteractive)

    // 以下状态受 queue 保护
    private var generation = 0
    private var running = false
    private var mode: MetronomeMode = .fixed
    private var fixedBPM: Double = 180
    private var progStartBPM: Double = 150
    private var progTargetBPM: Double = 180
    private var progDurationSec: Double = 600.0

    private var sound: ClickSound = .woodblock
    private var accentEnabled = false
    private var beatIndex = 0

    // 采样排程与时间轴
    private var framesExact: Double = 0        // 精确累计采样点（下一拍发声点）
    private var framesScheduled: Int64 = 0     // 已排程的整数采样点
    private var consumedFrames: Int64 = 0      // 硬件已实际消费播放的采样点
    private var queuedBuffers = 0
    private var queuedFrames: Int64 = 0

    // 节拍回调与发声队列（由硬件 dataConsumed 回调严格驱动）
    var onBeat: ((_ sequence: Int, _ beatInBar: Int, _ isAccent: Bool) -> Void)?
    private var beatSequence: Int = 0
    private var queuedBeats: [(sequence: Int, beatInBar: Int, isAccent: Bool)] = []

    private var clicks: [ClickSound: [Bool: [Float]]] = [:]
    private var configObserver: NSObjectProtocol?

    /// 前瞻窗口：至少排入 3 个 buffer 且不少于 0.8 秒音频
    private let minQueuedBuffers = 3
    private var minQueuedFrames: Int64 { Int64(sampleRate * 0.8) }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        reloadSounds()
        player.volume = 0.8

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    func reloadSounds() {
        for s in ClickSound.allCases {
            clicks[s] = [
                false: ClickSynth.samples(for: s, accent: false),
                true: ClickSynth.samples(for: s, accent: true)
            ]
        }
    }

    // MARK: - 控制与参数配置

    func setVolume(_ v: Float) {
        player.volume = min(max(v, 0), 1)
    }

    func setSound(_ s: ClickSound) {
        queue.async { self.sound = s }
    }

    func setAccentEnabled(_ on: Bool) {
        queue.async { self.accentEnabled = on }
    }

    func setMode(_ m: MetronomeMode) {
        queue.async {
            self.mode = m
        }
    }

    func setFixedBPM(_ value: Int) {
        queue.async {
            self.fixedBPM = Double(min(max(value, 60), 240))
        }
    }

    func setProgressiveParams(start: Int, target: Int, durationMinutes: Int) {
        queue.async {
            self.progStartBPM = Double(min(max(start, 60), 240))
            self.progTargetBPM = Double(min(max(target, 60), 240))
            self.progDurationSec = Double(max(durationMinutes, 1) * 60)
        }
    }

    /// 重置渐进模式进度至起点
    func resetProgress() {
        queue.sync {
            consumedFrames = 0
            framesScheduled = 0
            framesExact = 0
            beatIndex = 0
            beatSequence = 0
            queuedBeats.removeAll()
        }
    }

    /// 获取当前发声刻度的实际 BPM 与已播放秒数
    func currentStatus() -> (currentBPM: Double, elapsedSeconds: Double, isCompleted: Bool) {
        queue.sync {
            let tSec = Double(consumedFrames) / sampleRate
            switch mode {
            case .fixed:
                return (fixedBPM, tSec, false)
            case .progressive:
                if progDurationSec <= 0 {
                    return (progTargetBPM, 0, true)
                }
                let ratio = min(max(tSec / progDurationSec, 0.0), 1.0)
                let cur = progStartBPM + (progTargetBPM - progStartBPM) * ratio
                return (cur, tSec, ratio >= 1.0)
            }
        }
    }

    // MARK: - 播放与停止

    func start() throws {
        try engine.start()
        queue.sync {
            generation += 1
            running = true
            // 从暂停时记录的 consumedFrames 精确继续，不偷跑
            framesScheduled = consumedFrames
            framesExact = Double(consumedFrames)
            queuedBuffers = 0
            queuedFrames = 0
            queuedBeats.removeAll()
            player.stop()
            player.play()
            fill()

            // 派发首拍事件（首拍随 player.play() 立即在硬件发声）
            if let first = queuedBeats.first {
                DispatchQueue.main.async {
                    self.onBeat?(first.sequence, first.beatInBar, first.isAccent)
                }
            }
        }
    }

    func stop() {
        queue.sync {
            running = false
            generation += 1
            queuedBuffers = 0
            queuedFrames = 0
            queuedBeats.removeAll()
            player.stop()
            // 将调度游标回退对齐到用户实际耳朵听到的已消费采样点
            framesScheduled = consumedFrames
            framesExact = Double(consumedFrames)
        }
        engine.pause()
    }

    // MARK: - 排程逻辑

    private func fill() {
        while running && (queuedBuffers < minQueuedBuffers || queuedFrames < minQueuedFrames) {
            scheduleNextBeat()
        }
    }

    private func scheduleNextBeat() {
        let beatStart = framesScheduled
        let tSec = Double(beatStart) / sampleRate

        // 逐拍计算当前拍发声时刻应有的 BPM
        let instBPM: Double
        switch mode {
        case .fixed:
            instBPM = fixedBPM
        case .progressive:
            if progDurationSec <= 0 {
                instBPM = progTargetBPM
            } else {
                let ratio = min(max(tSec / progDurationSec, 0.0), 1.0)
                instBPM = progStartBPM + (progTargetBPM - progStartBPM) * ratio
            }
        }

        let periodExact = 60.0 * sampleRate / instBPM
        framesExact += periodExact
        let nextStart = Int64(framesExact.rounded())
        let length = max(Int(nextStart - beatStart), 1)
        framesScheduled = nextStart

        let isAccent = accentEnabled && (beatIndex % 4 == 0)
        let beatInBar = beatIndex % 4
        beatIndex = (beatIndex + 1) % 4
        beatSequence += 1
        let seq = beatSequence

        queuedBeats.append((sequence: seq, beatInBar: beatInBar, isAccent: isAccent))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
              let dest = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(length)
        dest.update(repeating: 0, count: length)

        if let src = clicks[sound]?[isAccent] {
            let n = min(src.count, length)
            src.withUnsafeBufferPointer { p in
                dest.update(from: p.baseAddress!, count: n)
            }
            if src.count > length {
                let fade = min(64, length)
                for i in 0..<fade {
                    dest[length - fade + i] *= Float(fade - 1 - i) / Float(fade)
                }
            }
        }

        let gen = generation
        queuedBuffers += 1
        queuedFrames += Int64(length)

        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard gen == self.generation else { return }
                self.consumedFrames += Int64(length)
                self.queuedBuffers -= 1
                self.queuedFrames -= Int64(length)

                // 当前拍 buffer 消费完毕，下一拍紧接着在硬件发声
                if !self.queuedBeats.isEmpty {
                    self.queuedBeats.removeFirst()
                }
                if let nextBeat = self.queuedBeats.first {
                    DispatchQueue.main.async {
                        self.onBeat?(nextBeat.sequence, nextBeat.beatInBar, nextBeat.isAccent)
                    }
                }

                self.fill()
            }
        }
    }

    private func handleConfigurationChange() {
        queue.async {
            guard self.running else { return }
            self.generation += 1
            self.queuedBuffers = 0
            self.queuedFrames = 0
            self.framesScheduled = self.consumedFrames
            self.framesExact = Double(self.consumedFrames)
            do {
                try self.engine.start()
                self.player.stop()
                self.player.play()
                self.fill()
            } catch {
                self.running = false
            }
        }
    }
}
