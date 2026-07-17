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

        /// 鼠标按下后移动超过该距离判定为拖拽。
        static let dragThreshold: CGFloat = 4
        /// 松手后胶囊中心距屏幕边缘小于该距离时吸附（顶部除外）。
        static let snapThreshold: CGFloat = 48
        static let snapAnimationDuration: TimeInterval = 0.32

        static let collapsedWidth: CGFloat = 160
        static let collapsedHeight: CGFloat = 30
        static let collapsedCornerRadius: CGFloat = 4
        static let collapsedBottomCornerRadius: CGFloat = 10

        static let expandedWidth: CGFloat = 760
        static let expandedCornerRadius: CGFloat = 30

        static let expandedTopInset: CGFloat = 0

        /// 持久化键：吸附边 + 胶囊中心坐标。
        static let dockEdgeDefaultsKey = "island.dockEdge"
        static let pillCenterXDefaultsKey = "island.pillCenterX"
        static let pillCenterYDefaultsKey = "island.pillCenterY"

        static let headerHeight: CGFloat = 64
        static let newTaskAreaHeight: CGFloat = 72
        static let taskRowHeight: CGFloat = 48
        static let emptyStateHeight: CGFloat = 120
        static let maxListHeight: CGFloat = 260
        static let minExpandedHeight: CGFloat = 320
        static let fixedExpandedHeight: CGFloat = 420

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
