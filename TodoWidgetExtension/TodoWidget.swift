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
        
        // Try to get fresh data from NotionService
        let notionService = NotionService.shared
        
        if notionService.isAuthenticated {
            // Use cached data
            let cachedTodos = getCachedTodos()
            let todos = Array(cachedTodos.prefix(3))
            let entry = TodoEntry(date: currentDate, todos: todos)
            
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        } else {
            // Not authenticated, use sample data
            let entry = TodoEntry(date: currentDate, todos: Array(TodoItem.sampleData.prefix(3)))
            
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            completion(timeline)
        }
    }
    
    private func getCachedTodos() -> [TodoItem] {
        // Try App Groups first - this is the primary shared storage
        if let sharedDefaults = UserDefaults(suiteName: "group.com.notiontodowidget.app"),
           let data = sharedDefaults.data(forKey: "cachedTodos"),
           let todos = try? JSONDecoder().decode([TodoItem].self, from: data),
           !todos.isEmpty {
            print("Widget: Successfully loaded \(todos.count) todos from App Groups")
            return todos
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "cachedTodos"),
           let todos = try? JSONDecoder().decode([TodoItem].self, from: data),
           !todos.isEmpty {
            print("Widget: Loaded \(todos.count) todos from regular UserDefaults")
            return todos
        }
        
        print("Widget: No cached todos found, using empty array")
        return []
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Todo")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entry.todos.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            
            if entry.todos.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text("All done!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(entry.todos.prefix(3)) { todo in
                    TodoRowView(todo: todo)
                }
                
                if entry.todos.count > 3 {
                    Text("+ \(entry.todos.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(todo.status == .completed ? .green : .secondary)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.caption)
                    .lineLimit(1)
                    .strikethrough(todo.status == .completed)
                    .foregroundColor(todo.status == .completed ? .secondary : .primary)
                
                if let dueDate = todo.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if todo.priority != .low {
                Circle()
                    .fill(todo.priority.color)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

@main
struct TodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
    }
}