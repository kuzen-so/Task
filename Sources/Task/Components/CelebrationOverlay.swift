import AppKit
import QuartzCore

@MainActor
final class CelebrationOverlay {
    private var window: NSWindow?

    func show(near sourceFrame: NSRect) {
        window?.orderOut(nil)
        window = nil

        let size = NSSize(width: 240, height: 240)
        let origin = NSPoint(
            x: sourceFrame.midX - size.width / 2,
            y: sourceFrame.minY - size.height + 20
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
        window.level = .statusBar
        window.ignoresMouseEvents = true

        let view = CelebrationView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view

        self.window = window
        window.orderFrontRegardless()

        // 1.5 秒后关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
    }
}

private final class CelebrationView: NSView {
    private let emitterLayer = CAEmitterLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupEmitter()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupEmitter()
    }

    override func layout() {
        super.layout()
        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY - 20)
    }

    private func setupEmitter() {
        guard let layer = self.layer else { return }

        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY - 20)
        emitterLayer.emitterSize = CGSize(width: 40, height: 10)
        emitterLayer.emitterMode = .outline
        emitterLayer.emitterShape = .line

        let cells = Constants.celebrationEmojis.compactMap { emoji -> CAEmitterCell? in
            guard let image = renderEmoji(emoji, size: 28) else { return nil }
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 3
            cell.lifetime = 1.4
            cell.lifetimeRange = 0.3
            cell.scale = 1.0
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.2
            cell.velocity = 120
            cell.velocityRange = 60
            cell.yAcceleration = 300
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 2
            cell.spinRange = 4
            cell.alphaSpeed = -0.8
            return cell
        }

        emitterLayer.emitterCells = cells
        layer.addSublayer(emitterLayer)

        // 0.5 秒后停止生成新粒子，已生成的继续下落直到 lifetime 结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
