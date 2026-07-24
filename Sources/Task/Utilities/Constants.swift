import Foundation

enum Constants {
    static let appSupportDirName = "com.kuzen.task"
    static let tasksFileName = "tasks.json"
    static let saveDebounceInterval: TimeInterval = 0.3

    /// 音效开关（UserDefaults 键）。
    static let soundEffectsEnabledKey = "soundEffectsEnabled"

    /// 任务操作音效：用 macOS 系统自带音效，无需打包音频资源。
    enum Sounds {
        static let add = "Tink"
        static let complete = "Hero"
        static let delete = "Submarine"
    }

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
        /// 水滴吸附：飞行时长 + 过冲（潜入屏幕边缘）深度上限。
        static let snapFlightDuration: TimeInterval = 0.5
        static let snapMaxOvershoot: CGFloat = 14

        static let collapsedWidth: CGFloat = 160
        static let collapsedHeight: CGFloat = 30
        static let collapsedBottomCornerRadius: CGFloat = 10

        static let expandedWidth: CGFloat = 760
        static let expandedCornerRadius: CGFloat = 30

        /// 展开面板里内容的实际宽度：比面板窄一点并居中，内容不撑到面板边缘。
        static let expandedContentWidth: CGFloat = 736

        /// 持久化键：吸附边 + 胶囊中心坐标。
        static let dockEdgeDefaultsKey = "island.dockEdge"
        static let pillCenterXDefaultsKey = "island.pillCenterX"
        static let pillCenterYDefaultsKey = "island.pillCenterY"

        /// 顶部吸附时的默认水平停靠：center / left / right（刘海两侧，避让其他灵动岛软件）。
        static let topDockSideDefaultsKey = "islandTopDockSide"
        /// 自由移动（漂浮岛）开关；键不存在时视为开（默认可拖）。关闭后岛锁死不可拖拽。
        static let freeMoveEnabledDefaultsKey = "islandFreeMoveEnabled"
        /// 总是吸附边缘开关：拖拽松手后必吸到最近的一条边；关闭则维持靠近边缘才吸。
        static let alwaysSnapEnabledDefaultsKey = "islandAlwaysSnapEnabled"
        /// 日程临近时胶囊发光提醒开关。
        static let eventAlertEnabledDefaultsKey = "islandEventAlertEnabled"
        /// 日程开始前多久触发发光提醒。
        static let eventAlertLeadTime: TimeInterval = 300
        /// 日程开始后提醒继续保留多久。
        static let eventAlertGraceTime: TimeInterval = 180
        static let eventAlertCheckInterval: TimeInterval = 30
        /// 未展开时日历数据的兜底静默刷新（即时刷新由 EKEventStoreChanged 通知承担）。
        static let calendarIdleRefreshInterval: TimeInterval = 900

        static let headerHeight: CGFloat = 64
        static let fixedExpandedHeight: CGFloat = 420

        /// 岛体投影的透明边距：窗口比内容大这一圈，SwiftUI 投影画在里面，
        /// 不会被窗口边界裁掉（展开态内容尺寸 = 窗口尺寸 - 2×shadowPadding）。
        static let shadowPadding: CGFloat = 40

        enum Shadow {
            static let tightRadius: CGFloat = 8
            static let tightYOffset: CGFloat = 4
            static let tightOpacity: Double = 0.35

            static let ambientRadius: CGFloat = 32
            static let ambientYOffset: CGFloat = 16
            static let ambientOpacity: Double = 0.45

            /// 岛体本身的投影：接触影（小半径高浓度）给边缘提离感，
            /// 柔光层（大半径低浓度）给氛围；柔光太重会在角落积成黑雾。
            static let bodyAmbientRadius: CGFloat = 18
            static let bodyAmbientYOffset: CGFloat = 6
            static let bodyAmbientOpacity: Double = 0.26
            static let bodyTightRadius: CGFloat = 6
            static let bodyTightYOffset: CGFloat = 2
            static let bodyTightOpacity: Double = 0.32
        }
    }
}
