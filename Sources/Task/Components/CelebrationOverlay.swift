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

        let cells = Constants.celebrationEmojis.compactMap { emoji -> CAEmitterCell? in
            guard let image = renderEmoji(emoji, size: 28) else { return nil }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 10
            cell.lifetime = 2.0
            cell.lifetimeRange = 0.4
            cell.scale = 1.0
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.2
            cell.velocity = 170
            cell.velocityRange = 90
            cell.yAcceleration = -360
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi
            cell.spin = 2
            cell.spinRange = 4
            cell.alphaSpeed = -0.5
            return cell
        }

        emitterLayer.emitterCells = cells
        layer.addSublayer(emitterLayer)

        // 0.25 秒后停止生成新粒子，形成一次性"爆出"效果；已生成的继续抛落直到淡出。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.emitterLayer.birthRate = 0
        }
    }

    private func renderEmoji(_ emoji: String, size: CGFloat) -> CGImage? {
        let nsImage = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let attributedString = NSAttributedString(
                string: emoji,
                attributes: [
                    .font: NSFont.systemFont(ofSize: size * 0.8),
                    .foregroundColor: NSColor.white
                ]
            )
            let textSize = attributedString.size()
            let point = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2
            )
            attributedString.draw(at: point)
            return true
        }

        var rect = NSRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
