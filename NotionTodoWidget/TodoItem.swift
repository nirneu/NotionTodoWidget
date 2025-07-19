import Foundation
import SwiftUI

struct TodoItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: TodoStatus
    let dueDate: Date?
    let priority: TodoPriority
    let createdAt: Date
    let updatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        title: String,
        status: TodoStatus = .notStarted,
        dueDate: Date? = nil,
        priority: TodoPriority = .medium,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.dueDate = dueDate
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum TodoStatus: String, Codable, CaseIterable {
    case notStarted = "Not started"
    case inProgress = "In progress"
    case completed = "Done"
    case cancelled = "Cancelled"
    
    var displayName: String {
        return self.rawValue
    }
    
    var isCompleted: Bool {
        return self == .completed
    }
}

enum TodoPriority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"
    
    var displayName: String {
        return self.rawValue
    }
    
    var sortOrder: Int {
        switch self {
        case .urgent: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
    
    var color: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }
}

// MARK: - Sample Data

extension TodoItem {
    static let sampleData: [TodoItem] = [
        TodoItem(
            title: "Review quarterly reports",
            status: .inProgress,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
            priority: .high
        ),
        TodoItem(
            title: "Prepare presentation slides",
            status: .notStarted,
            dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
            priority: .medium
        ),
        TodoItem(
            title: "Team meeting notes",
            status: .completed,
            priority: .low
        ),
        TodoItem(
            title: "Update project documentation",
            status: .notStarted,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            priority: .urgent
        ),
        TodoItem(
            title: "Fix critical bug in API",
            status: .inProgress,
            dueDate: Date(),
            priority: .urgent
        )
    ]
}