import SwiftUI

struct IslandTaskRow: View {
    let task: TaskItem
    let isActive: Bool
    let onToggle: () -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(task.isCompleted ? .green : IslandStyles.secondaryText)
            }
            .buttonStyle(IslandIconButtonStyle(color: IslandStyles.secondaryText, size: 17))

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(IslandStyles.bodyFont(size: 13, weight: isActive ? .semibold : .medium))
                    .foregroundColor(task.isCompleted ? IslandStyles.secondaryText : .white)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if !task.isCompleted {
                    onActivate()
                }
            }

            HStack(spacing: 6) {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(IslandStyles.tertiaryText)
                }
                .buttonStyle(IslandIconButtonStyle(color: IslandStyles.tertiaryText, size: 13))
            }
            .opacity(isHovered || isActive ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.blue.opacity(0.10) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.blue.opacity(0.22) : Color.clear, lineWidth: 1)
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
}
