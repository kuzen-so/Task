import SwiftUI
import AppKit

/// Boring Notch 风格的玻璃材质背景。
/// 在 `NSVisualEffectView` 上叠加一层暗色渐变遮罩，保证文字可读性。
struct IslandMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> IslandMaterialView {
        IslandMaterialView()
    }

    func updateNSView(_ nsView: IslandMaterialView, context: Context) {
        // 尺寸由外层 frame 决定，无需额外更新。
    }
}

final class IslandMaterialView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let overlayView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        overlayView.wantsLayer = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(visualEffectView)
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        super.layout()
        updateOverlay()
    }

    private func updateOverlay() {
        let gradient = CAGradientLayer()
        gradient.frame = overlayView.bounds
        gradient.colors = [
            NSColor.black.withAlphaComponent(0.35).cgColor,
            NSColor.black.withAlphaComponent(0.15).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        overlayView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        overlayView.layer?.addSublayer(gradient)
    }
}
