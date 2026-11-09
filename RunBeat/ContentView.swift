import SwiftUI

struct ContentView: View {
    @Environment(MetronomeModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                Text("RunBeat")
                    .font(.headline)
                    .foregroundStyle(Color(white: 0.5))
                    .padding(.top, 8)

                Spacer(minLength: 0)

                // 超大 BPM 数字
                VStack(spacing: 0) {
                    Text("\(model.bpm)")
                        .font(.system(size: 150, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(model.isPlaying ? Color.accentColor : .white)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: model.bpm)
                    Text("步/分钟 BPM")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                }

                // 加减 + 滑条
                HStack(spacing: 28) {
                    RepeatButton(systemImage: "minus") { model.adjust(by: -1) }
                    RepeatButton(systemImage: "plus") { model.adjust(by: 1) }
                }

                // 预设胶囊
                HStack(spacing: 10) {
                    ForEach(MetronomeModel.presets, id: \.self) { p in
                        Button {
                            model.bpm = p
                        } label: {
                            Text("\(p)")
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
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

                // 设置面板
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

                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)

                // 底部超大播放/暂停按钮
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
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(model.isPlaying ? Color.accentColor : Color.black)
                            .offset(x: model.isPlaying ? 0 : 4)
                    }
                    .frame(width: 140, height: 140)
                    .scaleEffect(model.isPlaying ? 0.96 : 1.0)
                    .animation(.spring(duration: 0.25), value: model.isPlaying)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? "暂停" : "开始")
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView().environment(MetronomeModel())
}
