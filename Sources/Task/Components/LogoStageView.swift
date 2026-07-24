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
    /// 展开打招呼的歪头角度（与删除动画的摇头分开）。
    @State private var tiltAngle: Double = 0
    /// 点击随机反应里的「压扁眯眼」。
    @State private var squashed = false
    /// 点击反应的位移（上下跳/左右滑/抖动共用）。
    @State private var tapOffset = CGSize.zero
    /// 点击反应里的「缩水」。
    @State private var shrunk = false
    /// 点击反应里的 3D 翻转角度。
    @State private var flipAngle: Double = 0
    /// 抽卡不放回：一轮 10 种反应全出完才重置，保证每次点击都不一样。
    @State private var reactionBag: [Int] = []

    /// 用计数差分区分创建/删除（删除不触发创建动画）。
    @State private var lastTaskCount: Int = -1
    @State private var lastCompletedCount: Int = -1

    var body: some View {
        IslandLogo(size: 56, eyeStyle: eyeStyle, tint: tint)
            .scaleEffect(bouncing ? 1.12 : 1.0)
            .scaleEffect(x: squashed ? 1.1 : 1.0, y: squashed ? 0.72 : 1.0)
            .scaleEffect(shrunk ? 0.72 : 1.0)
            .offset(tapOffset)
            .rotationEffect(.degrees(shaking ? 6 : tiltAngle))
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
            .frame(width: 84, height: 84)
            .contentShape(Rectangle())
            .onTapGesture {
                reactTapped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 舞台底色两端渐隐、中间微亮，上下边缘都平滑融入周围，没有硬边。
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.white.opacity(0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                lastTaskCount = store.tasks.count
                lastCompletedCount = store.completedTasks.count
                // 舞台视图只在展开时插入层级：每次展开 = 一次 onAppear。
                // 等面板弹得差不多，从反应库里随机抽一种打招呼。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    reactTapped()
                }
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

    /// 点击白脸：抽卡不放回地随机一种纯动作反应。刻意不用眼睛表情——
    /// 眨眼=创建、笑眼=完成、晕眼=删除，那些是任务事件的语义。
    private func reactTapped() {
        if reactionBag.isEmpty {
            reactionBag = Array(0..<10).shuffled()
        }
        switch reactionBag.removeLast() {
        case 0:
            // 歪头：左 → 右 → 回正
            withAnimation(.easeInOut(duration: 0.14)) { tiltAngle = -8 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeInOut(duration: 0.18)) { tiltAngle = 8 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                withAnimation(.easeInOut(duration: 0.14)) { tiltAngle = 0 }
            }
        case 1:
            // 弹跳
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bouncing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { bouncing = false }
            }
        case 2:
            // 摇摆：左 → 右 → 左 → 回正
            withAnimation(.easeInOut(duration: 0.12)) { tiltAngle = -12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
                withAnimation(.easeInOut(duration: 0.16)) { tiltAngle = 12 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.16)) { tiltAngle = -6 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
                withAnimation(.easeInOut(duration: 0.12)) { tiltAngle = 0 }
            }
        case 3:
            // 转一圈（结束后瞬间归位，不反转回来）
            withAnimation(.easeInOut(duration: 0.55)) { tiltAngle = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { tiltAngle = 0 }
        case 4:
            // 压扁眯眼
            withAnimation(.easeInOut(duration: 0.14)) { squashed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeInOut(duration: 0.16)) { squashed = false }
            }
        case 5:
            // 上下跳：弹到空中再落回
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                tapOffset = CGSize(width: 0, height: -14)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                    tapOffset = .zero
                }
            }
        case 6:
            // 左右平移：右 → 左 → 回中
            withAnimation(.easeInOut(duration: 0.13)) {
                tapOffset = CGSize(width: 10, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.17)) {
                    tapOffset = CGSize(width: -10, height: 0)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                withAnimation(.easeInOut(duration: 0.13)) { tapOffset = .zero }
            }
        case 7:
            // 快速抖动
            withAnimation(.linear(duration: 0.06).repeatCount(6, autoreverses: true)) {
                tapOffset = CGSize(width: 3, height: 0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tapOffset = .zero }
        case 8:
            // 缩水一下再弹回
            withAnimation(.easeInOut(duration: 0.15)) { shrunk = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { shrunk = false }
            }
        default:
            // 3D 翻转一圈
            withAnimation(.easeInOut(duration: 0.6)) { flipAngle = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { flipAngle = 0 }
        }
    }

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
