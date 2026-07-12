import Foundation

enum Constants {
    static let appSupportDirName = "com.kuzen.task"
    static let tasksFileName = "tasks.json"
    static let saveDebounceInterval: TimeInterval = 0.3

    static let celebrationEmojis = ["🍕", "🌮", "🍔", "🍩", "🍜", "🍣", "🥐", "🥞"]

    static let statusBarPopoverWidth: CGFloat = 300
    static let statusBarPopoverHeight: CGFloat = 420

    enum Island {
        static let animationDuration: TimeInterval = 0.45
        static let hoverOutDelay: TimeInterval = 0.05

        static let collapsedWidth: CGFloat = 160
        static let collapsedHeight: CGFloat = 30
        static let collapsedCornerRadius: CGFloat = 4
        static let collapsedBottomCornerRadius: CGFloat = 10

        static let expandedWidth: CGFloat = 760
        static let expandedCornerRadius: CGFloat = 30

        static let expandedTopInset: CGFloat = 0

        static let headerHeight: CGFloat = 64
        static let newTaskAreaHeight: CGFloat = 72
        static let taskRowHeight: CGFloat = 48
        static let emptyStateHeight: CGFloat = 120
        static let maxListHeight: CGFloat = 260
        static let minExpandedHeight: CGFloat = 320

        enum Shadow {
            static let tightRadius: CGFloat = 8
            static let tightYOffset: CGFloat = 4
            static let tightOpacity: Double = 0.35

            static let ambientRadius: CGFloat = 32
            static let ambientYOffset: CGFloat = 16
            static let ambientOpacity: Double = 0.45
        }
    }
}
