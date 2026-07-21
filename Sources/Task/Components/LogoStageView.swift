import SwiftUI

/// 左栏顶部 1/3 的动画舞台：大号 IslandLogo 对任务事件做出反应——
/// 创建任务 → 变蓝 + 眨两下眼 + 弹跳；完成任务 → 变绿 + 笑眼 + 弹跳。
/// 约 1.2 秒后恢复白方块圆眼。
struct LogoStageView: View {
    @ObservedObject var store: TaskStore

    @State private var eyeStyle: IslandLogo.EyeStyle = .open
    @State private var tint: Color = .white
    @State private var bouncing = false
    @State private var shaking = false

    /// 用计数差分区分创建/删除（删除不触发创建动画）。
    @State private var lastTaskCount: Int = -1
    @State private var lastCompletedCount: Int = -1

    var body: some View {
        IslandLogo(size: 56, eyeStyle: eyeStyle, tint: tint)
            .scaleEffect(bouncing ? 1.12 : 1.0)
            .rotationEffect(.degrees(shaking ? 6 : 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.03))
            .onAppear {
                lastTaskCount = store.tasks.count
                lastCompletedCount = store.completedTasks.count
            }
            .onChange(of: store.tasks.count) { newCount in
                if lastTaskCount >= 0 {
                    if newCount > lastTaskCount {
                        reactCreated()
                    } else if newCount < lastTaskCount {
                        reactDeleted()
                    }
                }
                lastTaskCount = newCount
            }
            .onChange(of: store.completedTasks.count) { newCount in
                if lastCompletedCount >= 0, newCount > lastCompletedCount {
                    reactCompleted()
                }
                lastCompletedCount = newCount
            }
    }

    // MARK: - Reactions

    private func reactCreated() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            bouncing = true
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            tint = Color(red: 0.45, green: 0.75, blue: 1.0)
        }
        blink(times: 2)
        scheduleReset()
    }

    private func reactCompleted() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bouncing = true
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            tint = Color(red: 0.55, green: 0.9, blue: 0.65)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            eyeStyle = .happy
        }
        scheduleReset()
    }

    /// 删除任务：变柔和红 + 晕眼 x x + 左右摇头。
    private func reactDeleted() {
        withAnimation(.easeInOut(duration: 0.25)) {
            tint = Color(red: 0.95, green: 0.6, blue: 0.6)
            eyeStyle = .dizzy
        }
        withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) {
            shaking = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeInOut(duration: 0.08)) {
                shaking = false
            }
        }
        scheduleReset()
    }

    private func blink(times: Int) {
        for index in 0..<times {
            let at = Double(index) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                withAnimation(.easeInOut(duration: 0.1)) { eyeStyle = .blink }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + 0.15) {
                withAnimation(.easeInOut(duration: 0.1)) { eyeStyle = .open }
            }
        }
    }

    private func scheduleReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                bouncing = false
            }
            withAnimation(.easeInOut(duration: 0.4)) {
                tint = .white
                eyeStyle = .open
            }
        }
    }
}
