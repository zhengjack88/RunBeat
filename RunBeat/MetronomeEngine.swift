import AVFoundation

/// 基于 AVAudioEngine + AVAudioPlayerNode 的采样级前瞻排程节拍引擎。
///
/// 原理：每一拍是一个长度恰为「到下一拍的采样数」的 PCM buffer（点击音 + 静音补齐），
/// 连续 scheduleBuffer 到 player 节点，由音频硬件时钟按采样点无缝衔接播放。
/// 拍起点的采样位置由累计的精确浮点值取整得到（framesExact），
/// 因此舍入误差不会累积，长时间无时钟漂移。
/// 补充排程由 buffer 的播放完成回调驱动，不使用 Timer / asyncAfter 触发声音。
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
    private var bpm: Double = 180
    private var sound: ClickSound = .woodblock
    private var accentEnabled = false
    private var beatIndex = 0
    private var framesExact: Double = 0      // 精确累计采样位置（下一拍起点）
    private var framesScheduled: Int64 = 0   // 已排程的整数采样位置
    private var queuedBuffers = 0
    private var queuedFrames: Int64 = 0

    private var clicks: [ClickSound: [Bool: [Float]]] = [:]
    private var configObserver: NSObjectProtocol?

    /// 前瞻窗口：至少排入 3 个 buffer 且不少于 0.8 秒音频
    private let minQueuedBuffers = 3
    private var minQueuedFrames: Int64 { Int64(sampleRate * 0.8) }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for s in ClickSound.allCases {
            clicks[s] = [
                false: ClickSynth.samples(for: s, accent: false),
                true: ClickSynth.samples(for: s, accent: true)
            ]
        }
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

    // MARK: - 控制接口

    func setVolume(_ v: Float) {
        // 只控制节拍节点自身音量，不影响系统音量
        player.volume = min(max(v, 0), 1)
    }

    func setBPM(_ value: Int) {
        queue.async { self.bpm = Double(min(max(value, 60), 240)) }
    }

    func setSound(_ s: ClickSound) {
        queue.async { self.sound = s }
    }

    func setAccentEnabled(_ on: Bool) {
        queue.async { self.accentEnabled = on }
    }

    /// 启动引擎并开始排程。需先激活 AVAudioSession。
    func start() throws {
        try engine.start()
        queue.sync {
            generation += 1
            running = true
            beatIndex = 0
            framesExact = 0
            framesScheduled = 0
            queuedBuffers = 0
            queuedFrames = 0
            player.stop()
            player.play()
            fill()
        }
    }

    func stop() {
        queue.sync {
            running = false
            generation += 1
            queuedBuffers = 0
            queuedFrames = 0
            player.stop()
        }
        engine.pause()
    }

    // MARK: - 排程（queue 上执行）

    private func fill() {
        while running && (queuedBuffers < minQueuedBuffers || queuedFrames < minQueuedFrames) {
            scheduleNextBeat()
        }
    }

    private func scheduleNextBeat() {
        let periodExact = 60.0 * sampleRate / bpm
        let beatStart = framesScheduled
        framesExact += periodExact
        let nextStart = Int64(framesExact.rounded())
        let length = max(Int(nextStart - beatStart), 1)
        framesScheduled = nextStart

        let isAccent = accentEnabled && beatIndex % 4 == 0
        beatIndex = (beatIndex + 1) % 4

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
              let dest = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(length)
        // 整个 buffer 先置零（拍间静音），再拷入点击音
        dest.update(repeating: 0, count: length)
        if let src = clicks[sound]?[isAccent] {
            let n = min(src.count, length)
            src.withUnsafeBufferPointer { p in
                dest.update(from: p.baseAddress!, count: n)
            }
            // 点击音比拍间隔长时（极端情况），对尾部做短淡出避免截断爆音
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
                self.queuedBuffers -= 1
                self.queuedFrames -= Int64(length)
                self.fill()
            }
        }
    }

    // MARK: - 配置变化（如路由/采样率改变导致引擎停止）

    private func handleConfigurationChange() {
        queue.async {
            guard self.running else { return }
            self.generation += 1
            self.queuedBuffers = 0
            self.queuedFrames = 0
            self.framesExact = 0
            self.framesScheduled = 0
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
