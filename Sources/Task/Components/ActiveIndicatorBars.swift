import SwiftUI

/// 进行中任务的运行动画（模仿 Vibe Island 的工作律动条）。
struct ActiveIndicatorBars: View {
    var color: Color = .green
    var maxHeight: CGFloat = 10

    @State private var animating = false

    private let phases: [(low: CGFloat, high: CGFloat, delay: Double)] = [
        (0.35, 1.0, 0.0),
        (0.50, 0.75, 0.18),
        (0.30, 0.90, 0.36)
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<phases.count, id: \.self) { index in
                let phase = phases[index]
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color)
                    .frame(width: 2.5, height: maxHeight * (animating ? phase.high : phase.low))
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(phase.delay),
                        value: animating
                    )
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
    }
}
