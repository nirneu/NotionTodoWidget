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
        // Load todos from cache
        var todos: [TodoItem] = []
        
        // Try App Groups first - this is the primary shared storage
        if let sharedDefaults = UserDefaults(suiteName: "group.com.notiontodowidget.app"),
           let data = sharedDefaults.data(forKey: "cachedTodos"),
           let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data),
           !cachedTodos.isEmpty {
            print("Widget: Successfully loaded \(cachedTodos.count) todos from App Groups")
            todos = cachedTodos
        } else if let data = UserDefaults.standard.data(forKey: "cachedTodos"),
                  let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data),
                  !cachedTodos.isEmpty {
            print("Widget: Loaded \(cachedTodos.count) todos from regular UserDefaults")
            todos = cachedTodos
        } else {
            print("Widget: No cached todos found, using empty array")
            return []
        }
        
        // Apply the same filters and sorting as the main app
        let filteredAndSortedTodos = applyFiltersAndSorting(to: todos)
        print("Widget: After filtering and sorting: \(filteredAndSortedTodos.count) todos")
        
        return filteredAndSortedTodos
    }
    
    private func applyFiltersAndSorting(to todos: [TodoItem]) -> [TodoItem] {
        // Load persistent preferences
        let sortConfig = PreferencesManager.shared.loadSortConfiguration()
        let statusFilter = PreferencesManager.shared.loadStatusFilter()
        let priorityFilter = PreferencesManager.shared.loadPriorityFilter()
        
        // Apply filters
        let filteredTodos = todos.filter { todo in
            let statusMatch = statusFilter.contains(todo.status)
            let priorityMatch = todo.priority == nil || priorityFilter.contains(todo.priority!)
            return statusMatch && priorityMatch
        }
        
        // Apply sorting
        return filteredTodos.sorted { todo1, todo2 in
            // Primary sort
            let primaryResult = compareTodos(todo1, todo2, by: sortConfig.primary)
            
            if primaryResult != .orderedSame {
                let ascending = sortConfig.primaryOrder == .ascending
                return ascending ? primaryResult == .orderedAscending : primaryResult == .orderedDescending
            }
            
            // Secondary sort (if primary is equal and secondary exists)
            if let secondary = sortConfig.secondary {
                let secondaryResult = compareTodos(todo1, todo2, by: secondary)
                let ascending = sortConfig.secondaryOrder == .ascending
                return ascending ? secondaryResult == .orderedAscending : secondaryResult == .orderedDescending
            }
            
            return false
        }
    }
    
    private func compareTodos(_ todo1: TodoItem, _ todo2: TodoItem, by option: SortOption) -> ComparisonResult {
        switch option {
        case .title:
            return todo1.title.localizedCaseInsensitiveCompare(todo2.title)
        case .status:
            return todo1.status.rawValue.localizedCaseInsensitiveCompare(todo2.status.rawValue)
        case .priority:
            let priority1 = todo1.priority?.sortOrder ?? 0
            let priority2 = todo2.priority?.sortOrder ?? 0
            if priority1 < priority2 { return .orderedAscending }
            if priority1 > priority2 { return .orderedDescending }
            return .orderedSame
        case .dueDate:
            let date1 = todo1.dueDate ?? Date.distantFuture
            let date2 = todo2.dueDate ?? Date.distantFuture
            return date1.compare(date2)
        case .createdAt:
            return todo1.createdAt.compare(todo2.createdAt)
        case .updatedAt:
            return todo1.updatedAt.compare(todo2.updatedAt)
        }
    }
    
    
    private func saveTodosToCache(_ todos: [TodoItem]) {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: "cachedTodos")
            UserDefaults(suiteName: "group.com.notiontodowidget.app")?.set(data, forKey: "cachedTodos")
        }
    }
}

struct TodoWidgetEntryView: View {
    var entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                    
                    Text("Todo Widget")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("\(entry.todos.count)")
                        .font(.system(size: 12, weight: .bold))
                    Text("tasks")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
            }
            
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
                VStack(spacing: 8) {
                    ForEach(entry.todos.prefix(3)) { todo in
                        TodoRowView(todo: todo)
                        
                        if todo.id != entry.todos.prefix(3).last?.id {
                            Divider()
                                .padding(.horizontal, 4)
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
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(todo.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(todo.status == .completed)
                    .foregroundColor(todo.status == .completed ? .secondary : .primary)
                
                // Status and due date row
                HStack(spacing: 8) {
                    // Status badge
                    Text(todo.status.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(for: todo.status))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    
                    // Due date
                    if let dueDate = todo.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8))
                            Text(relativeDateString(for: dueDate))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(dueDateColor(for: dueDate))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(dueDateColor(for: dueDate).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                }
            }
            
            // Priority indicator
            if let priority = todo.priority {
                VStack(spacing: 1) {
                    ForEach(0..<min(priority.sortOrder, 3), id: \.self) { _ in
                        Circle()
                            .fill(priority.color)
                            .frame(width: 3, height: 3)
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
}

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}