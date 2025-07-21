import WidgetKit
import SwiftUI

struct TodoWidget: Widget {
    let kind: String = "TodoWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                TodoWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                TodoWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(.systemGray6))
            }
        }
        .configurationDisplayName("Todo Widget")
        .description("Stay on top of your tasks with this elegant todo widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let todos: [TodoItem]
}

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: Date(), todos: Array(TodoItem.sampleData.prefix(3)))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        // For snapshot, use cached data or sample data
        let todos = getCachedTodos()
        let entry = TodoEntry(date: Date(), todos: Array(todos.prefix(3)))
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let currentDate = Date()
        
        // Always try to get cached data first, regardless of authentication state
        let cachedTodos = getCachedTodos()
        
        if !cachedTodos.isEmpty {
            // We have cached data, use it
            let todos = Array(cachedTodos.prefix(3))
            let entry = TodoEntry(date: currentDate, todos: todos)
            
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            print("Widget: Using cached data with \(todos.count) todos")
            completion(timeline)
        } else {
            // No cached data available, check authentication
            let notionService = NotionService.shared
            
            if notionService.isAuthenticated {
                // Authenticated but no cached data - show empty state
                let entry = TodoEntry(date: currentDate, todos: [])
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                
                print("Widget: Authenticated but no cached data, showing empty state")
                completion(timeline)
            } else {
                // Not authenticated, use sample data
                let entry = TodoEntry(date: currentDate, todos: Array(TodoItem.sampleData.prefix(3)))
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                
                print("Widget: Not authenticated, using sample data")
                completion(timeline)
            }
        }
    }
    
    private func getCachedTodos() -> [TodoItem] {
        // Load todos from cache - the main app already applies filters and sorting before saving
        var todos: [TodoItem] = []
        
        // Try App Groups first - this is the primary shared storage
        print("Widget: Attempting to load from App Groups...")
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            print("Widget: Successfully created shared UserDefaults")
            if let data = sharedDefaults.data(forKey: "cachedTodos") {
                print("Widget: Found cached data (\(data.count) bytes)")
                if let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data), !cachedTodos.isEmpty {
                    print("Widget: Successfully decoded \(cachedTodos.count) todos from App Groups")
                    print("Widget: First todo: '\(cachedTodos.first?.title ?? "unknown")'")
                    todos = cachedTodos
                } else {
                    print("Widget: Failed to decode todos from App Groups data")
                }
            } else {
                print("Widget: No data found in App Groups for key 'cachedTodos'")
            }
        } else {
            print("Widget: Failed to create shared UserDefaults with suite name")
        }
        
        // If App Groups failed, try regular UserDefaults as fallback
        if todos.isEmpty {
            print("Widget: Trying regular UserDefaults as fallback...")
            if let data = UserDefaults.standard.data(forKey: "cachedTodos") {
                print("Widget: Found fallback data (\(data.count) bytes)")
                if let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data), !cachedTodos.isEmpty {
                    print("Widget: Successfully loaded \(cachedTodos.count) todos from regular UserDefaults")
                    todos = cachedTodos
                } else {
                    print("Widget: Failed to decode todos from regular UserDefaults")
                }
            } else {
                print("Widget: No fallback data found in regular UserDefaults")
            }
        }
        
        if todos.isEmpty {
            print("Widget: No cached todos found anywhere, returning empty array")
            return []
        }
        
        print("Widget: Returning \(todos.count) todos (already filtered and sorted by main app)")
        return todos
    }
    
}

struct TodoWidgetEntryView: View {
    var entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Content
            if entry.todos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    Text("All done!")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    ForEach(entry.todos.prefix(3)) { todo in
                        TodoRowView(todo: todo)
                        
                        if todo.id != entry.todos.prefix(3).last?.id {
                            Divider()
                                .padding(.horizontal, 2)
                        }
                    }
                }
                
                if entry.todos.count > 3 {
                    HStack {
                        Spacer()
                        Text("+ \(entry.todos.count - 3) more tasks")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        Spacer()
                    }
                }
            }
            
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    
    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(todo.status == .completed ? .green : .secondary)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 1) {
                // Title - even larger text
                Text(todo.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(todo.status == .completed)
                    .foregroundColor(todo.status == .completed ? .secondary : .primary)
                
                // Status, Priority, and Due date row
                HStack {
                    // Status and Priority grouped together on left
                    HStack(spacing: 6) {
                        // Status badge
                        Text(todo.status.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(statusColor(for: todo.status))
                            .clipShape(Capsule())
                        
                        // Priority next to status
                        if let priority = todo.priority {
                            HStack(spacing: 2) {
                                Image(systemName: priorityIcon(for: priority))
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white)
                                Text(priority.displayName)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(updatedPriorityColor(for: priority))
                            .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Due date on far right
                    if let dueDate = todo.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white)
                            Text(relativeDateString(for: dueDate))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(smartDueDateColor(for: dueDate))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func statusColor(for status: TodoStatus) -> Color {
        switch status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .red
        case .blocked: return .red
        case .research: return .orange
        }
    }
    
    private func dueDateColor(for date: Date) -> Color {
        let daysDifference = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        
        if daysDifference < 0 {
            return .red
        } else if daysDifference == 0 {
            return .orange
        } else if daysDifference <= 3 {
            return .yellow
        } else {
            return .secondary
        }
    }
    
    private func relativeDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    private func priorityIcon(for priority: TodoPriority) -> String {
        switch priority {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
    
    // Updated priority colors matching the main app
    private func updatedPriorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4) // Green
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2) // Yellow/Gold
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3) // Red
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark Red
        }
    }
    
    // Updated due date color to match high priority red
    private func updatedDueDateColor(for date: Date) -> Color {
        return Color(red: 0.8, green: 0.3, blue: 0.3) // Same red as high priority
    }
    
    // Smart due date color based on date status
    private func smartDueDateColor(for date: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        
        if dueDate < today {
            // Overdue - Red
            return Color(red: 0.8, green: 0.3, blue: 0.3)
        } else if dueDate == today {
            // Today - Orange
            return Color(red: 0.9, green: 0.5, blue: 0.1)
        } else {
            // Future - Gray
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }
}

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}