import SwiftUI

struct IslandTaskRow: View {
    let task: TaskItem
    let isActive: Bool
    let onToggle: () -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    @AppStorage("taskHighlightStyle") private var highlightStyle: TaskHighlightStyle = .leftBar
    @AppStorage("taskCheckboxStyle") private var checkboxStyle: TaskCheckboxStyle = .circle
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                leftIndicator

                Button(action: onToggle) {
                    Image(systemName: checkboxImageName)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(checkboxColor)
                }
                .buttonStyle(IslandIconButtonStyle(color: IslandStyles.secondaryText, size: 17))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(IslandStyles.bodyFont(size: 13, weight: .medium))
                    .foregroundColor(titleColor)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if !task.isCompleted {
                    onActivate()
                }
            }
            .help("双击开始/暂停此任务")

            HStack(spacing: 6) {
                if isActive {
                    ActiveIndicatorBars()
                }
                if isActive && highlightStyle == .rightTag {
                    Text("进行中")
                        .font(IslandStyles.bodyFont(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(IslandStyles.tertiaryText)
                }
                .buttonStyle(IslandIconButtonStyle(color: IslandStyles.tertiaryText, size: 13))
                .opacity(isHovered ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderStroke, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var leftIndicator: some View {
        switch highlightStyle {
        case .leftBar:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isActive ? Color.blue : Color.clear)
                .frame(width: 3, height: 16)
        case .leftDot:
            Circle()
                .fill(isActive ? Color.blue : Color.clear)
                .frame(width: 6, height: 6)
        default:
            EmptyView()
        }
    }

    private var checkboxImageName: String {
        if task.isCompleted {
            switch checkboxStyle {
            case .circle: return "checkmark.circle.fill"
            case .square: return "checkmark.square.fill"
            }
        } else {
            switch checkboxStyle {
            case .circle: return "circle"
            case .square: return "square"
            }
        }
    }

    private var checkboxColor: Color {
        task.isCompleted ? .green : IslandStyles.secondaryText
    }

    private var titleColor: Color {
        if task.isCompleted {
            return IslandStyles.secondaryText
        }
        if isActive && (highlightStyle == .blueText || highlightStyle == .blueTextBorder) {
            return .blue
        }
        return .white
    }

    private var backgroundFill: Color {
        if isActive && (highlightStyle == .border || highlightStyle == .blueTextBorder) {
            return Color.blue.opacity(0.10)
        }
        if isHovered {
            return Color.white.opacity(0.05)
        }
        return Color.clear
    }

    private var borderStroke: Color {
        if isActive && (highlightStyle == .border || highlightStyle == .blueTextBorder) {
            return Color.blue.opacity(0.22)
        }
        return Color.clear
    }
}
