import SwiftUI

struct ContentView: View {
    @Environment(MetronomeModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // 1. 顶部小号字距拉宽标题
                    Text("RUNBEAT")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(4.5)
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.top, 4)

                    // 模式选择器
                    Picker("模式", selection: $model.mode) {
                        ForEach(MetronomeMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 28)
                    .onChange(of: model.mode) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    // 2. 核心 BPM 行（左右两侧 64pt 按钮，中间大数字居中）
                    HStack(alignment: .center, spacing: 8) {
                        RepeatButton(systemImage: "minus", size: 64, fontSize: 26) {
                            if model.mode == .fixed {
                                model.adjustFixed(by: -1)
                            } else {
                                model.adjustProgStart(by: -1)
                            }
                        }

                        Spacer(minLength: 4)

                        VStack(spacing: 0) {
                            Text("\(model.displayBPM)")
                                .font(.system(size: 118, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                                .foregroundStyle(model.isPlaying ? Color.accentColor : .white)
                                .shadow(color: (model.isPlaying ? Color.accentColor : Color.white).opacity(0.18), radius: 10, x: 0, y: 0)
                                .shadow(color: (model.isPlaying ? Color.accentColor : Color.clear).opacity(0.12), radius: 24, x: 0, y: 0)
                                .contentTransition(.numericText())
                                .animation(.snappy(duration: 0.15), value: model.displayBPM)

                            if model.mode == .fixed {
                                Text("步/分钟 BPM")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(white: 0.45))
                            } else {
                                HStack(spacing: 6) {
                                    Text("起始 \(model.progStartBPM)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(white: 0.65))
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                    Text("目标 \(model.progTargetBPM)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(white: 0.65))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 4)

                        RepeatButton(systemImage: "plus", size: 64, fontSize: 26) {
                            if model.mode == .fixed {
                                model.adjustFixed(by: 1)
                            } else {
                                model.adjustProgStart(by: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(minHeight: 140)

                    // 3. 数字下方预设胶囊 / 渐进重置
                    if model.mode == .fixed {
                        HStack(spacing: 10) {
                            ForEach(MetronomeModel.presets, id: \.self) { p in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    model.bpm = p
                                } label: {
                                    Text("\(p)")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(model.bpm == p ? Color.black : Color.white)
                                        .background(
                                            Capsule().fill(model.bpm == p ? Color.accentColor : Color(white: 0.14))
                                        )
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(model.bpm == p ? 0 : 0.08), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    } else if model.progElapsedSeconds > 0 && !model.isPlaying {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.resetProgress()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重置进度为起点")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(white: 0.12)))
                            .overlay(Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    // 4. 渐进模式参数精修卡
                    if model.mode == .progressive {
                        progressiveSettingsCard(model: model)
                    }

                    // 5. 通用设置卡（深灰分层 + 1px 白色描边，圆角 24，细分隔线）
                    generalSettingsCard(model: model)

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    // 6. 底部大圆播放按钮（含实际发声脉冲光圈与发光阴影）
                    VStack(spacing: 10) {
                        ZStack {
                            // 实际音频发声驱动的节拍脉冲光圈
                            PulseHaloView(
                                pulseCount: model.beatPulseCount,
                                isAccent: model.isCurrentBeatAccent,
                                isPlaying: model.isPlaying
                            )
                            .frame(width: 136, height: 136)

                            // 主播放/暂停圆钮
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                model.toggle()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(model.isPlaying ? Color(white: 0.16) : Color.accentColor)
                                    Circle()
                                        .strokeBorder(Color.accentColor, lineWidth: model.isPlaying ? 4 : 0)
                                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 52, weight: .bold))
                                        .foregroundStyle(model.isPlaying ? Color.accentColor : Color.black)
                                        .offset(x: model.isPlaying ? 0 : 3)
                                }
                                .frame(width: 136, height: 136)
                                .shadow(color: Color.accentColor.opacity(model.isPlaying ? 0.42 : 0.22), radius: model.isPlaying ? 26 : 14, x: 0, y: 6)
                                .scaleEffect(model.isPlaying ? 0.96 : 1.0)
                                .animation(.spring(duration: 0.22), value: model.isPlaying)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(model.isPlaying ? "暂停" : "开始")
                        }
                        .padding(.top, 6)

                        // 7. 播放状态与时长信息
                        VStack(spacing: 4) {
                            if model.isPlaying || model.totalPlaybackSeconds > 0 {
                                Text(formatTime(model.totalPlaybackSeconds))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(white: 0.85))

                                if model.mode == .progressive {
                                    let remainingSec = max(0, Double(model.progDurationMinutes * 60) - model.progElapsedSeconds)
                                    Text(model.isProgCompleted ?
                                         "渐进已完成 · 保持 \(model.progTargetBPM) BPM" :
                                         "渐进 \(model.displayBPM) → \(model.progTargetBPM) · 还剩 \(formatTime(remainingSec))")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(model.isProgCompleted ? Color.accentColor : Color(white: 0.55))
                                }
                            } else {
                                Text("轻点开始")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(white: 0.4))
                            }
                        }
                        .frame(minHeight: 36)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 渐进设置卡精修

    @ViewBuilder
    private func progressiveSettingsCard(model: MetronomeModel) -> some View {
        VStack(spacing: 0) {
            // 起始 BPM
            HStack {
                Text("起始 BPM")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                HStack(spacing: 12) {
                    miniStepButton(icon: "minus") { model.adjustProgStart(by: -1) }
                    Text("\(model.progStartBPM)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 40)
                        .foregroundStyle(.white)
                    miniStepButton(icon: "plus") { model.adjustProgStart(by: 1) }
                }
            }
            .padding(.vertical, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // 目标 BPM
            HStack {
                Text("目标 BPM")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                HStack(spacing: 12) {
                    miniStepButton(icon: "minus") { model.adjustProgTarget(by: -1) }
                    Text("\(model.progTargetBPM)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 40)
                        .foregroundStyle(.white)
                    miniStepButton(icon: "plus") { model.adjustProgTarget(by: 1) }
                }
            }
            .padding(.vertical, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // 爬升时长
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("爬升时长")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.75))
                    Spacer()
                    HStack(spacing: 12) {
                        miniStepButton(icon: "minus") { model.adjustProgDuration(by: -1) }
                        Text("\(model.progDurationMinutes) 分钟")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(minWidth: 64)
                            .foregroundStyle(.white)
                        miniStepButton(icon: "plus") { model.adjustProgDuration(by: 1) }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(MetronomeModel.durationPresets, id: \.self) { min in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.progDurationMinutes = min
                        } label: {
                            Text("\(min)m")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundStyle(model.progDurationMinutes == min ? Color.black : Color.white)
                                .background(
                                    Capsule().fill(model.progDurationMinutes == min ? Color.accentColor : Color(white: 0.16))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - 通用设置卡精修（深灰分层 + 1px 白色描边，圆角 24，内部细分隔线）

    @ViewBuilder
    private func generalSettingsCard(model: MetronomeModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // 1. 音量滑杆（保留两端图标）
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.5))
                Slider(value: $model.volume, in: 0...1)
                    .tint(Color.accentColor)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // 2. 音色分段
            HStack {
                Text("音色")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.75))
                Spacer()
                Picker("音色", selection: $model.sound) {
                    ForEach(ClickSound.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .onChange(of: model.sound) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // 3. 4拍重音开关
            Toggle("每 4 拍重音", isOn: $model.accentEnabled)
                .font(.subheadline)
                .tint(Color.accentColor)
                .foregroundStyle(Color(white: 0.9))
                .padding(.vertical, 14)
                .onChange(of: model.accentEnabled) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func miniStepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(white: 0.20)))
                .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
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

// MARK: - 实际发声时间驱动的节拍脉冲光圈组件

private struct PulseHaloView: View {
    let pulseCount: Int
    let isAccent: Bool
    let isPlaying: Bool

    @State private var animating = false

    var body: some View {
        Circle()
            .stroke(
                Color.accentColor.opacity(animating ? 0.0 : (isAccent ? 0.75 : 0.50)),
                lineWidth: isAccent ? 3.5 : 2.0
            )
            .scaleEffect(animating ? (isAccent ? 1.42 : 1.32) : 1.0)
            .opacity(isPlaying ? 1.0 : 0.0)
            .onChange(of: pulseCount) { _, _ in
                guard isPlaying else { return }
                animating = false
                withAnimation(.easeOut(duration: 0.26)) {
                    animating = true
                }
            }
            .animation(.easeOut(duration: 0.26), value: animating)
    }
}
