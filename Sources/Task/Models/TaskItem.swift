import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var elapsedTime: TimeInterval
    var reminderID: String?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        elapsedTime: TimeInterval = 0,
        reminderID: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.elapsedTime = elapsedTime
        self.reminderID = reminderID
        self.isActive = isActive
    }
}
