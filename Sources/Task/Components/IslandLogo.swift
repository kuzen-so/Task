import SwiftUI

/// 品牌图标：白色圆角方块 + 两个黑色眼睛（和状态栏图标同一造型，比例来自
/// Assets/generate_icons.swift 的 72px 规格：圆角 16、眼睛 10px、眼心距 ±16）。
/// 用 SwiftUI 绘制而不是图片/SF Symbol，眼睛支持 圆眼/眨眼/笑眼 三种形态，
/// 方块可变色，供舞台区做创建/完成动画。
struct IslandLogo: View {
    enum EyeStyle {
        case open   /// 圆眼（默认）
        case blink  /// 眨眼（压扁）
        case happy  /// 笑眼 ^ ^
        case dizzy  /// 晕眼 x x（删除任务）
    }

    var size: CGFloat = 14
    var eyeStyle: EyeStyle = .open
    var tint: Color = .white
    var eyeColor: Color = .black

    private var cornerRadius: CGFloat { size * 16 / 72 }
    private var eyeSize: CGFloat { size * 10 / 72 }
    /// 两眼边缘间距（72px 规格下眼心距 32，减去眼睛直径 10）。
    private var eyeSpacing: CGFloat { size * 22 / 72 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)

            HStack(spacing: eyeSpacing) {
                eye
                eye
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var eye: some View {
        switch eyeStyle {
        case .open:
            Circle()
                .fill(eyeColor)
                .frame(width: eyeSize, height: eyeSize)
        case .blink:
            Capsule()
                .fill(eyeColor)
                .frame(width: eyeSize, height: max(1.5, eyeSize * 0.25))
        case .happy:
            // 上半圆弧 = ^ 形笑眼
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(eyeColor, style: StrokeStyle(lineWidth: max(1.5, eyeSize * 0.3), lineCap: .round))
                .frame(width: eyeSize * 1.15, height: eyeSize * 1.15)
        case .dizzy:
            XEyeShape()
                .stroke(eyeColor, style: StrokeStyle(lineWidth: max(1.5, eyeSize * 0.3), lineCap: .round))
                .frame(width: eyeSize, height: eyeSize)
        }
    }
}

/// x 形眼睛（删除任务的晕眼）。
private struct XEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
