# RunBeat

iOS 跑步节拍器。SwiftUI，iOS 17+，Bundle ID `com.jackzheng.runbeat`。无账号、无联网、无广告、无统计。

## 架构

    RunBeat/
      RunBeatApp.swift      App 入口
      ContentView.swift     深色极简 UI（大号 BPM、预设胶囊、音量、音色、重音、播放按钮）
      RepeatButton.swift    长按连续加减按钮
      MetronomeModel.swift  @Observable 状态；AVAudioSession 配置、中断/路由变化处理、设置持久化
      MetronomeEngine.swift AVAudioEngine + AVAudioPlayerNode 采样级前瞻排程
      ClickSynth.swift      运行时合成 PCM 音色（木鱼 / 电子咔哒，含重音版本）
      Info.plist            UIBackgroundModes = audio
      Assets.xcassets       AppIcon、AccentColor
    project.yml             XcodeGen 工程描述（不提交 pbxproj）
    .github/workflows/build.yml

关键设计：

- 排程：每拍是一个长度 = 到下一拍采样数的 PCM buffer（点击音 + 静音），连续 `scheduleBuffer` 给 player 节点，由音频硬件时钟无缝播放。拍位置取自累计的精确浮点采样位置再取整，舍入误差不累积，无时钟漂移。buffer 消费回调负责补充后续排程（始终保持至少 3 拍、0.8 秒前瞻）。声音触发不使用 `Timer` 或 `asyncAfter`。BPM 改动在已排程的前瞻窗口之后生效（约 1 秒内）。
- 混音：`AVAudioSession` category `.playback`、mode `.default`、options `[.mixWithOthers]`，不含 `.duckOthers`，可叠加在 Apple Music / Spotify / 播客之上，不会打断或压低它们。
- 音量：滑杆只设置 `AVAudioPlayerNode.volume`，不改系统音量。
- 后台：`UIBackgroundModes` 含 `audio`，锁屏/切后台持续播放。
- 中断：来电等中断开始时暂停，结束且系统建议恢复时自动继续；耳机/蓝牙断开（`oldDeviceUnavailable`）时自动暂停；引擎配置变化时自动重启并重排程。

## 本地生成工程（需 macOS + Xcode 15+）

    brew install xcodegen
    xcodegen generate
    open RunBeat.xcodeproj

## GitHub Actions 构建

1. 将项目推送到 GitHub。
2. 推送到 `main`/`master` 会自动构建；也可在 Actions 页选择 "Build unsigned IPA" → Run workflow 手动触发。
3. 构建完成后，在该次运行页面底部 Artifacts 下载 `RunBeat-unsigned.ipa`（下载得到的是 zip，解压后即为 IPA）。

## 安装未签名 IPA

IPA 未签名，需要自行签名安装：

- TrollStore：支持的系统版本上可直接安装，永久有效，无需重签。
- AltStore：用你的 Apple ID 签名，免费账号每 7 天需刷新，同时最多 3 个 App。
- Sideloadly：电脑端用 Apple ID 签名安装，同样有 7 天有效期限制（付费开发者账号为 1 年）。

注意：签名工具可能改写 Bundle ID（免费账号常见）；`UIBackgroundModes` 在重签后会保留，后台音频不受影响。

## 验证清单

1. `mixWithOthers`：`MetronomeModel.configureSession()` 中设置。
2. `UIBackgroundModes` 含 `audio`：见 `RunBeat/Info.plist`。
3. 排程不含 Timer：`MetronomeEngine.swift` 仅用 `scheduleBuffer` + 完成回调（`RepeatButton` 的 `Task.sleep` 只用于长按调节数值）。
4. 先开节拍再切音乐 App 不会打断：因 `.mixWithOthers` 且未使用 `.duckOthers`，需在真机上确认。
