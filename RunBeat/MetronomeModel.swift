import AVFoundation
import Observation

@MainActor
@Observable
final class MetronomeModel {
    static let minBPM = 60
    static let maxBPM = 240
    static let presets = [160, 170, 180, 190]

    var bpm: Int {
        didSet {
            let clamped = min(max(bpm, Self.minBPM), Self.maxBPM)
            if clamped != bpm { bpm = clamped; return }
            engine.setBPM(bpm)
            defaults.set(bpm, forKey: Keys.bpm)
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

    private(set) var isPlaying = false
    var errorMessage: String?

    @ObservationIgnored private let engine = MetronomeEngine()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let bpm = "bpm"
        static let volume = "volume"
        static let sound = "sound"
        static let accent = "accent"
    }

    init() {
        let d = UserDefaults.standard
        let savedBPM = d.object(forKey: Keys.bpm) as? Int ?? 180
        bpm = min(max(savedBPM, Self.minBPM), Self.maxBPM)
        volume = d.object(forKey: Keys.volume) as? Double ?? 0.8
        sound = ClickSound(rawValue: d.string(forKey: Keys.sound) ?? "") ?? .woodblock
        accentEnabled = d.bool(forKey: Keys.accent)

        engine.setBPM(bpm)
        engine.setVolume(Float(volume))
        engine.setSound(sound)
        engine.setAccentEnabled(accentEnabled)

        registerSessionObservers()
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
        } catch {
            isPlaying = false
            errorMessage = "无法启动音频：\(error.localizedDescription)"
        }
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        isPlaying = false
        // 释放会话并通知其他 App（不影响正在播放的音乐）
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func adjust(by delta: Int) {
        bpm = min(max(bpm + delta, Self.minBPM), Self.maxBPM)
    }

    // MARK: - 音频会话

    /// category=.playback, mode=.default, options=[.mixWithOthers]（不含 duckOthers）
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
                self.engine.stop()
                self.isPlaying = false
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
                engine.stop()
                isPlaying = false
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
        // 耳机拔出 / 蓝牙断开：自动暂停
        if reason == .oldDeviceUnavailable, isPlaying {
            stop()
        }
    }
}
