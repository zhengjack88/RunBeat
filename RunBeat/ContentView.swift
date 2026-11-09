import SwiftUI

struct ContentView: View {
    @Environment(MetronomeModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 顶栏模式切换
                    Picker("模式", selection: $model.mode) {
                        ForEach(MetronomeMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

                    // 核心 BPM 大字展示区
                    VStack(spacing: 6) {
                        Text("\(model.displayBPM)")
                            .font(.system(size: 140, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .foregroundStyle(model.isPlaying ? Color.accentColor : .white)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.15), value: model.displayBPM)

                        if model.mode == .fixed {
                            Text("步/分钟 BPM")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.5))
                        } else {
                            // 渐进模式小字标注起始和目标
                            VStack(spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("起始 \(model.progStartBPM)")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(white: 0.7))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                    Text("目标 \(model.progTargetBPM)")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(white: 0.7))
                                }

                                if model.isPlaying || model.progElapsedSeconds > 0 {
                                    let currentSec = model.progElapsedSeconds
                                    let totalSec = Double(model.progDurationMinutes * 60)
                                    HStack(spacing: 6) {
                                        Text("\(formatTime(currentSec)) / \(formatTime(totalSec))")
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(model.isProgCompleted ? Color.accentColor : Color(white: 0.5))
                                        if model.isProgCompleted {
                                            Text("(已达标)")
                                                .font(.caption2)
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                } else {
                                    Text("爬升时长 \(model.progDurationMinutes) 分钟")
                                        .font(.caption)
                                        .foregroundStyle(Color(white: 0.5))
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180)

                    // 模式专属调节区
                    if model.mode == .fixed {
                        fixedControls(model: model)
                    } else {
                        progressiveControls(model: model)
                    }

                    // 通用设置面板（音量、音色、重音）
                    generalSettings(model: model)

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    // 底部超大播放/暂停圆钮
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        model.toggle()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(model.isPlaying ? Color(white: 0.16) : Color.accentColor)
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: model.isPlaying ? 5 : 0)
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 54, weight: .bold))
                                .foregroundStyle(model.isPlaying ? Color.accentColor : Color.black)
                                .offset(x: model.isPlaying ? 0 : 4)
                        }
                        .frame(width: 136, height: 136)
                        .scaleEffect(model.isPlaying ? 0.96 : 1.0)
                        .animation(.spring(duration: 0.25), value: model.isPlaying)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.isPlaying ? "暂停" : "开始")
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 固定模式组件

    @ViewBuilder
    private func fixedControls(model: MetronomeModel) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                RepeatButton(systemImage: "minus") { model.adjustFixed(by: -1) }
                RepeatButton(systemImage: "plus") { model.adjustFixed(by: 1) }
            }

            HStack(spacing: 10) {
                ForEach(MetronomeModel.presets, id: \.self) { p in
                    Button {
                        model.bpm = p
                    } label: {
                        Text("\(p)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(model.bpm == p ? Color.black : Color.white)
                            .background(
                                Capsule().fill(model.bpm == p ? Color.accentColor : Color(white: 0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - 渐进模式组件

    @ViewBuilder
    private func progressiveControls(model: MetronomeModel) -> some View {
        VStack(spacing: 14) {
            // 起始 BPM 调节
            HStack {
                Text("起始 BPM")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.7))
                Spacer()
                HStack(spacing: 14) {
                    stepButton(icon: "minus") { model.adjustProgStart(by: -1) }
                    Text("\(model.progStartBPM)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 44)
                        .foregroundStyle(.white)
                    stepButton(icon: "plus") { model.adjustProgStart(by: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.11)))

            // 目标 BPM 调节
            HStack {
                Text("目标 BPM")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.7))
                Spacer()
                HStack(spacing: 14) {
                    stepButton(icon: "minus") { model.adjustProgTarget(by: -1) }
                    Text("\(model.progTargetBPM)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 44)
                        .foregroundStyle(.white)
                    stepButton(icon: "plus") { model.adjustProgTarget(by: 1) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.11)))

            // 爬升时长调节
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("爬升时长")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.7))
                    Spacer()
                    HStack(spacing: 14) {
                        stepButton(icon: "minus") { model.adjustProgDuration(by: -1) }
                        Text("\(model.progDurationMinutes) 分钟")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(minWidth: 70)
                            .foregroundStyle(.white)
                        stepButton(icon: "plus") { model.adjustProgDuration(by: 1) }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(MetronomeModel.durationPresets, id: \.self) { min in
                        Button {
                            model.progDurationMinutes = min
                        } label: {
                            Text("\(min)m")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .foregroundStyle(model.progDurationMinutes == min ? Color.black : Color.white)
                                .background(
                                    Capsule().fill(model.progDurationMinutes == min ? Color.accentColor : Color(white: 0.18))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.11)))

            // 重置进度按钮（若有已播放进度且暂停中）
            if model.progElapsedSeconds > 0 && !model.isPlaying {
                Button {
                    model.resetProgress()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("重置为起点")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 通用设置面板

    @ViewBuilder
    private func generalSettings(model: MetronomeModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(Color(white: 0.5))
                Slider(value: $model.volume, in: 0...1)
                    .tint(Color.accentColor)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(Color(white: 0.5))
            }

            Picker("音色", selection: $model.sound) {
                ForEach(ClickSound.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Toggle("每 4 拍重音", isOn: $model.accentEnabled)
                .tint(Color.accentColor)
                .foregroundStyle(.white)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.09)))
        .padding(.horizontal, 20)
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.22)))
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
