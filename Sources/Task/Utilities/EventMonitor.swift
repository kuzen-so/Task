import AppKit

/// 用于把 `NSEvent` 全局监听句柄标记为可在 deinit 中传递的 token。
private final class MonitorHandle: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}

@MainActor
final class EventMonitor {
    private var handle: MonitorHandle?
    private let mask: NSEvent.EventTypeMask
    private let handler: @MainActor (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        if let handle = handle {
            Task { @MainActor in
                NSEvent.removeMonitor(handle.value)
            }
        }
    }

    func start() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            handle = MonitorHandle(monitor)
        }
    }

    func stop() {
        if let handle = handle {
            NSEvent.removeMonitor(handle.value)
            self.handle = nil
        }
    }
}
