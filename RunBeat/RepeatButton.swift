import SwiftUI

/// 点按触发一次，按住后持续加速重复触发的按钮。
/// 重复由 Task.sleep 驱动，仅用于 UI 数值调整，与节拍发声无关。
struct RepeatButton: View {
    let systemImage: String
    var size: CGFloat = 64
    var fontSize: CGFloat = 26
    let action: () -> Void

    @State private var pressed = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(pressed ? Color(white: 0.28) : Color(white: 0.13)))
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(pressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        begin()
                    }
                    .onEnded { _ in
                        pressed = false
                        task?.cancel()
                        task = nil
                    }
            )
            .onDisappear {
                task?.cancel()
                task = nil
                pressed = false
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(systemImage == "plus" ? "增加" : "减少")
            .accessibilityAction { action() }
    }

    private func begin() {
        action()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            var interval: UInt64 = 120_000_000
            var ticks = 0
            while !Task.isCancelled {
                action()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                ticks += 1
                if ticks == 6 { interval = 70_000_000 }
                if ticks == 20 { interval = 40_000_000 }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}
