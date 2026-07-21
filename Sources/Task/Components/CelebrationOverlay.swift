import AppKit
import QuartzCore

@MainActor
final class CelebrationOverlay {
    private var window: NSWindow?

    /// 在灵动岛位置爆出庆祝动画：动画窗口与岛顶部对齐并完全盖住它，层级也高于岛。
    func show(covering islandFrame: NSRect) {
        window?.orderOut(nil)
        window = nil

        // 左右和下方留出粒子散布/飘落的空间，窗口顶部与岛顶部对齐（岛贴着屏幕顶边，上方没有空间）。
        let sideMargin: CGFloat = 100
        let fallMargin: CGFloat = 320
        let size = NSSize(
            width: islandFrame.width + sideMargin * 2,
            height: islandFrame.height + fallMargin
        )
        let origin = NSPoint(
            x: islandFrame.midX - size.width / 2,
            y: islandFrame.maxY - size.height
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // 灵动岛是 .popUpMenu(101)，动画必须比它高才能盖在岛前面。
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window.ignoresMouseEvents = true

        // 发射点 = 岛的中心（转换为动画 view 内部坐标）。
        let emitterPoint = NSPoint(
            x: size.width / 2,
            y: size.height - islandFrame.height / 2
        )
        let view = CelebrationView(frame: NSRect(origin: .zero, size: size), emitterPoint: emitterPoint)
        window.contentView = view

        self.window = window
        window.orderFrontRegardless()

        // 粒子全部淡出后关闭（最后一批在 0.25s 时生成，alpha 2.0s 归零）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
    }
}

private final class CelebrationView: NSView {
    private let emitterLayer = CAEmitterLayer()
    private let emitterPoint: NSPoint

    init(frame frameRect: NSRect, emitterPoint: NSPoint) {
        self.emitterPoint = emitterPoint
        super.init(frame: frameRect)
        wantsLayer = true
        setupEmitter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        emitterLayer.emitterPosition = emitterPoint
    }

    private func setupEmitter() {
        guard let layer = self.layer else { return }

        // 注意：macOS 未翻转的 layer 坐标系 y 轴向上（与 iOS 相反），
        // 所以向上发射是 π/2，向下的重力是负的 yAcceleration。
        emitterLayer.emitterPosition = emitterPoint
        emitterLayer.emitterShape = .point

        var cells: [CAEmitterCell] = []

        // 第一层：快速闪点——小而亮，一闪而过，制造“绽开”的瞬间感。
        for color in [NSColor.white, Self.palette[0]] {
            guard let image = renderCircle(color: color, diameter: 3) else { continue }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 8
            cell.lifetime = 0.7
            cell.lifetimeRange = 0.2
            cell.scale = 1.0
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.5
            cell.velocity = 300
            cell.velocityRange = 100
            cell.yAcceleration = -500
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi
            cell.alphaSpeed = -1.4
            cells.append(cell)
        }

        // 第二层：彩色圆点——主体礼花，抛起后缓缓落下。
        for color in Self.palette {
            guard let image = renderCircle(color: color, diameter: 6) else { continue }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 4
            cell.lifetime = 1.6
            cell.lifetimeRange = 0.5
            cell.scale = 1.0
            cell.scaleRange = 0.4
            cell.scaleSpeed = -0.35
            cell.velocity = 200
            cell.velocityRange = 90
            cell.yAcceleration = -420
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi
            cell.alphaSpeed = -0.6
            cells.append(cell)
        }

        // 第三层：小纸屑——带旋转的长条，增加质感，落得最慢。
        for color in [Self.palette[0], Self.palette[2], Self.palette[3]] {
            guard let image = renderConfetti(color: color) else { continue }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 3
            cell.lifetime = 1.8
            cell.lifetimeRange = 0.4
            cell.scale = 1.0
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.3
            cell.velocity = 130
            cell.velocityRange = 60
            cell.yAcceleration = -180
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi
            cell.spin = 3
            cell.spinRange = 3
            cell.alphaSpeed = -0.5
            cells.append(cell)
        }

        emitterLayer.emitterCells = cells
        layer.addSublayer(emitterLayer)

        // 0.2 秒后停止生成新粒子，形成一次性"爆出"效果；已生成的继续抛落直到淡出。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.emitterLayer.birthRate = 0
        }
    }

    /// 克制的礼花配色：金 / 橙 / 淡蓝 / 粉 / 紫 / 白。
    private static let palette: [NSColor] = [
        NSColor(red: 1.00, green: 0.84, blue: 0.04, alpha: 1),
        NSColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1),
        NSColor(red: 0.39, green: 0.82, blue: 1.00, alpha: 1),
        NSColor(red: 1.00, green: 0.39, blue: 0.51, alpha: 1),
        NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1),
        .white
    ]

    private func renderCircle(color: NSColor, diameter: CGFloat) -> CGImage? {
        let size = NSSize(width: diameter, height: diameter)
        let nsImage = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        var rect = NSRect(origin: .zero, size: size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func renderConfetti(color: NSColor) -> CGImage? {
        let size = NSSize(width: 4, height: 7)
        let nsImage = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            return true
        }
        var rect = NSRect(origin: .zero, size: size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
