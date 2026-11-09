import AVFoundation
import Observation

@MainActor
@Observable
final class MetronomeModel {
    static let minBPM = 60
    static let maxBPM = 240
    static let presets = [160, 170, 180, 190]
    static let durationPresets = [5, 10, 15, 20, 30]

    // MARK: - 模式与参数持久化

    var mode: MetronomeMode {
        didSet {
            engine.setMode(mode)
            defaults.set(mode.rawValue, forKey: Keys.mode)
            if !isPlaying {
                resetProgress()
            }
        }
    }

    var bpm: Int {
        didSet {
            let clamped = min(max(bpm, Self.minBPM), Self.maxBPM)
            if clamped != bpm { bpm = clamped; return }
            engine.setFixedBPM(bpm)
            defaults.set(bpm, forKey: Keys.bpm)
            if mode == .fixed {
                displayBPM = bpm
            }
        }
    }

    var progStartBPM: Int {
        didSet {
            let clamped = min(max(progStartBPM, Self.minBPM), Self.maxBPM)
            if clamped != progStartBPM { progStartBPM = clamped; return }
            syncProgParams()
            defaults.set(progStartBPM, forKey: Keys.progStartBPM)
            if mode == .progressive && !isPlaying {
                resetProgress()
            }
        }
    }

    var progTargetBPM: Int {
        didSet {
            let clamped = min(max(progTargetBPM, Self.minBPM), Self.maxBPM)
            if clamped != progTargetBPM { progTargetBPM = clamped; return }
            syncProgParams()
            defaults.set(progTargetBPM, forKey: Keys.progTargetBPM)
            if mode == .progressive && !isPlaying {
                syncProgStatus()
            }
        }
    }

    var progDurationMinutes: Int {
        didSet {
            let clamped = min(max(progDurationMinutes, 1), 120)
            if clamped != progDurationMinutes { progDurationMinutes = clamped; return }
            syncProgParams()
            defaults.set(progDurationMinutes, forKey: Keys.progDuration)
            if mode == .progressive && !isPlaying {
                syncProgStatus()
            }
        }
    }

    var volume: Double {
        didSet {
            engine.setVolume(Float(volume))
            defaults.set(volume, forKey: Keys.volume)
        }
    }

    var sound: ClickSound {
        didSet {
            engine.setSound(sound)
            defaults.set(sound.rawValue, forKey: Keys.sound)
        }
    }

    var accentEnabled: Bool {
        didSet {
            engine.setAccentEnabled(accentEnabled)
            defaults.set(accentEnabled, forKey: Keys.accent)
        }
    }

    // MARK: - 实时状态

    private(set) var isPlaying = false
    private(set) var displayBPM: Int = 180
    private(set) var progElapsedSeconds: Double = 0
    private(set) var isProgCompleted = false
    var errorMessage: String?

    @ObservationIgnored private let engine = MetronomeEngine()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    private enum Keys {
        static let mode = "mode"
        static let bpm = "bpm"
        static let progStartBPM = "prog_start_bpm"
        static let progTargetBPM = "prog_target_bpm"
        static let progDuration = "prog_duration"
        static let volume = "volume"
        static let sound = "sound"
        static let accent = "accent"
    }

    init() {
        let d = UserDefaults.standard

        let savedModeStr = d.string(forKey: Keys.mode) ?? ""
        mode = MetronomeMode(rawValue: savedModeStr) ?? .fixed

        let savedBPM = d.object(forKey: Keys.bpm) as? Int ?? 180
        bpm = min(max(savedBPM, Self.minBPM), Self.maxBPM)

        let savedStart = d.object(forKey: Keys.progStartBPM) as? Int ?? 150
        progStartBPM = min(max(savedStart, Self.minBPM), Self.maxBPM)

        let savedTarget = d.object(forKey: Keys.progTargetBPM) as? Int ?? 180
        progTargetBPM = min(max(savedTarget, Self.minBPM), Self.maxBPM)

        let savedDuration = d.object(forKey: Keys.progDuration) as? Int ?? 10
        progDurationMinutes = min(max(savedDuration, 1), 120)

        volume = d.object(forKey: Keys.volume) as? Double ?? 0.8
        sound = ClickSound(rawValue: d.string(forKey: Keys.sound) ?? "") ?? .woodblock
        accentEnabled = d.bool(forKey: Keys.accent)

        // 配置底层引擎
        engine.setMode(mode)
        engine.setFixedBPM(bpm)
        engine.setProgressiveParams(start: progStartBPM, target: progTargetBPM, durationMinutes: progDurationMinutes)
        engine.setVolume(Float(volume))
        engine.setSound(sound)
        engine.setAccentEnabled(accentEnabled)

        displayBPM = (mode == .fixed) ? bpm : progStartBPM

        registerSessionObservers()
    }

    private func syncProgParams() {
        engine.setProgressiveParams(start: progStartBPM, target: progTargetBPM, durationMinutes: progDurationMinutes)
    }

    private func syncProgStatus() {
        let status = engine.currentStatus()
        displayBPM = Int(status.currentBPM.rounded())
        progElapsedSeconds = status.elapsedSeconds
        isProgCompleted = status.isCompleted
    }

    // MARK: - 播放控制

    func toggle() {
        isPlaying ? stop() : start()
    }

    func start() {
        guard !isPlaying else { return }
        do {
            try configureSession()
            try engine.start()
            isPlaying = true
            errorMessage = nil
            startUIMonitor()
        } catch {
            isPlaying = false
            errorMessage = "无法启动音频：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isPlaying else { return }
        monitorTask?.cancel()
        monitorTask = nil
        engine.stop()
        isPlaying = false
        syncProgStatus()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 重置渐进模式进度回起点
    func resetProgress() {
        engine.resetProgress()
        progElapsedSeconds = 0
        isProgCompleted = false
        displayBPM = (mode == .fixed) ? bpm : progStartBPM
    }

    // MARK: - UI 步进调节

    func adjustFixed(by delta: Int) {
        bpm = min(max(bpm + delta, Self.minBPM), Self.maxBPM)
    }

    func adjustProgStart(by delta: Int) {
        progStartBPM = min(max(progStartBPM + delta, Self.minBPM), Self.maxBPM)
    }

    func adjustProgTarget(by delta: Int) {
        progTargetBPM = min(max(progTargetBPM + delta, Self.minBPM), Self.maxBPM)
    }

    func adjustProgDuration(by deltaMinutes: Int) {
        progDurationMinutes = min(max(progDurationMinutes + deltaMinutes, 1), 120)
    }

    // MARK: - 界面高频状态监听

    private func startUIMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                let status = self.engine.currentStatus()
                if self.mode == .progressive {
                    self.displayBPM = Int(status.currentBPM.rounded())
                    self.progElapsedSeconds = status.elapsedSeconds
                    self.isProgCompleted = status.isCompleted
                } else {
                    self.displayBPM = self.bpm
                }
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms 刷新率
            }
        }
    }

    // MARK: - 音频会话

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func registerSessionObservers() {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: session, queue: .main) { [weak self] note in
            let info = note.userInfo
            let typeValue = info?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = info?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        })

        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                                        object: session, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        })

        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                        object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.stop()
                self.start()
            }
        })
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                stop()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) {
                start()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable, isPlaying {
            stop()
        }
    }
}
