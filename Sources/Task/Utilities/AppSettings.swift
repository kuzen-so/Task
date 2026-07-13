import Foundation

enum TaskHighlightStyle: String, CaseIterable, Identifiable {
    case leftBar = "leftBar"
    case leftDot = "leftDot"
    case blueText = "blueText"
    case blueTextBorder = "blueTextBorder"
    case rightTag = "rightTag"
    case border = "border"
    case none = "none"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftBar: return "左侧小蓝条"
        case .leftDot: return "左侧圆点"
        case .blueText: return "文字变蓝"
        case .blueTextBorder: return "文字变蓝+边框"
        case .rightTag: return "右侧标签"
        case .border: return "边框高亮"
        case .none: return "无高亮"
        }
    }
}

enum TaskCheckboxStyle: String, CaseIterable, Identifiable {
    case circle = "circle"
    case square = "square"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "圆形"
        case .square: return "方形"
        }
    }
}
