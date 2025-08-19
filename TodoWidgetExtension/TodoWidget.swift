import WidgetKit
import SwiftUI
import AppIntents

// MARK: - App Intent Configuration

struct EditTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Edit Todo"
    static var description = IntentDescription("Edit a todo item")
    
    @Parameter(title: "Todo ID")
    var todoId: String
    
    @Parameter(title: "Database ID")
    var databaseId: String?
    
    init() {
        self.todoId = ""
        self.databaseId = nil
    }
    
    init(todoId: String, databaseId: String? = nil) {
        self.todoId = todoId
        self.databaseId = databaseId
    }
    
    func perform() async throws -> some IntentResult & OpensIntent {
        // Build URL with database information if available
        var urlString = "notiontodowidget://edit/\(todoId)"
        if let databaseId = databaseId {
            urlString += "?database=\(databaseId)"
        }
        
        let url = URL(string: urlString)!
        print("🎯 Widget Intent: Opening URL: \(url)")
        return .result(opensIntent: OpenURLIntent(url))
    }
}

struct DatabaseSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Database"
    static var description = IntentDescription("Choose which database to display in the widget")
    
    @Parameter(title: "Database", default: nil)
    var database: DatabaseEntity?
    
    init() {
        // Set default database for new widgets
        if let defaultDatabase = DatabaseEntity.createDefault() {
            self.database = defaultDatabase
            print("🔧 Widget Init: Setting default database to: \(defaultDatabase.name)")
        } else {
            print("🔧 Widget Init: No default database available")
        }
    }
    
    init(database: DatabaseEntity) {
        self.database = database
        print("🔧 Widget Init: Creating DatabaseSelectionIntent with database: \(database.name)")
    }
    
    func perform() async throws -> some IntentResult {
        print("Widget: Database selection changed to: \(database?.name ?? "none")")
        
        // If a specific database is selected, fetch its data
        if let selectedDatabase = database {
            print("Widget: Requesting data fetch for database: \(selectedDatabase.databaseId)")
            
            // Trigger data fetch for the selected database
            let notionService = NotionService.shared
            notionService.fetchAndCacheDataForDatabase(selectedDatabase.databaseId)
        }
        
        // Trigger widget timeline refresh
        WidgetCenter.shared.reloadAllTimelines()
        print("Widget: Triggered timeline refresh for database selection change")
        return .result()
    }
}

struct DatabaseEntity: AppEntity {
    let id: String
    let name: String
    let databaseId: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Database"
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static var defaultQuery = DatabaseEntityQuery()
    
    // Create a default database entity from the current active database
    static func createDefault() -> DatabaseEntity? {
        return DatabaseEntityQuery().getCurrentActiveDatabaseSync()
    }
}

struct DatabaseEntityQuery: EntityQuery {
    func entities(for identifiers: [DatabaseEntity.ID]) async throws -> [DatabaseEntity] {
        let databases = loadSavedDatabases()
        return databases.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [DatabaseEntity] {
        return loadSavedDatabases()
    }
    
    func defaultResult() async -> DatabaseEntity? {
        // Return the currently active database as the default for new widgets
        let result = getCurrentActiveDatabase()
        print("🔧 Widget Default Result: Returning default database: \(result?.name ?? "nil")")
        return result
    }
    
    private func loadSavedDatabases() -> [DatabaseEntity] {
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget"),
           let data = sharedDefaults.data(forKey: "savedDatabases"),
           let configurations = try? JSONDecoder().decode([DatabaseConfiguration].self, from: data) {
            return configurations.map { DatabaseEntity(id: $0.id, name: $0.name, databaseId: $0.databaseId) }
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "savedDatabases"),
           let configurations = try? JSONDecoder().decode([DatabaseConfiguration].self, from: data) {
            return configurations.map { DatabaseEntity(id: $0.id, name: $0.name, databaseId: $0.databaseId) }
        }
        
        return []
    }
    
    func getCurrentActiveDatabaseSync() -> DatabaseEntity? {
        let result = getCurrentActiveDatabase()
        print("🔧 Widget Default Sync: Found active database: \(result?.name ?? "nil")")
        return result
    }
    
    private func getCurrentActiveDatabase() -> DatabaseEntity? {
        // Get current active database ID
        let currentDatabaseId: String?
        
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            currentDatabaseId = sharedDefaults.string(forKey: "currentDatabaseId")
        } else {
            // Fallback to regular UserDefaults
            currentDatabaseId = UserDefaults.standard.string(forKey: "currentDatabaseId")
        }
        
        guard let activeDbId = currentDatabaseId else {
            print("🔍 Widget Default: No active database ID found")
            return nil
        }
        
        // Find the database configuration with this ID
        let allDatabases = loadSavedDatabases()
        if let activeDatabase = allDatabases.first(where: { $0.databaseId == activeDbId }) {
            print("✅ Widget Default: Setting default to active database: \(activeDatabase.name)")
            return activeDatabase
        } else {
            print("❌ Widget Default: Active database ID not found in saved databases")
            return nil
        }
    }
}

// DatabaseConfiguration is defined in the main app's TodoItem.swift

struct TodoWidget: Widget {
    let kind: String = "TodoWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DatabaseSelectionIntent.self, provider: TodoAppIntentTimelineProvider()) { entry in
            TodoWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Todo Widget")
        .description("Stay on top of your tasks with this elegant todo widget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let todos: [TodoItem]
    let currentDatabaseName: String?
    let configuration: DatabaseSelectionIntent
}

// MARK: - Timeline Provider

struct TodoAppIntentTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = TodoEntry
    typealias Intent = DatabaseSelectionIntent
    
    func placeholder(in context: TimelineProviderContext) -> TodoEntry {
        let defaultIntent = DatabaseSelectionIntent()
        return TodoEntry(date: Date(), todos: Array(TodoItem.sampleData.prefix(6)), currentDatabaseName: "Sample Database", configuration: defaultIntent)
    }
    
    func snapshot(for configuration: DatabaseSelectionIntent, in context: TimelineProviderContext) async -> TodoEntry {
        let (todos, databaseName) = getCachedTodosWithDatabase(for: configuration)
        return TodoEntry(date: Date(), todos: Array(todos.prefix(6)), currentDatabaseName: databaseName, configuration: configuration)
    }
    
    func timeline(for configuration: DatabaseSelectionIntent, in context: TimelineProviderContext) async -> Timeline<TodoEntry> {
        let currentDate = Date()
        
        print("=== Widget Timeline Debug ===")
        print("Configuration database name: \(configuration.database?.name ?? "None")")
        print("Configuration database ID: \(configuration.database?.databaseId ?? "None")")
        
        // Check authentication first to understand the state
        let notionService = NotionService.shared
        print("Is authenticated: \(notionService.isAuthenticated)")
        
        // Get cached data based on configuration
        let cachedResult = getCachedTodosWithDatabase(for: configuration)
        
        if !cachedResult.todos.isEmpty {
            // We have cached data, use it
            let todos = Array(cachedResult.todos.prefix(10))
            let entry = TodoEntry(date: currentDate, todos: todos, currentDatabaseName: cachedResult.databaseName, configuration: configuration)
            
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            
            print("✅ Using cached data with \(todos.count) todos for database: \(cachedResult.databaseName ?? "Unknown")")
            return timeline
        } else {
            print("❌ No cached data found")
            
            if notionService.isAuthenticated {
                // Authenticated but no cached data - show empty state with message to user
                let entry = TodoEntry(date: currentDate, todos: [], currentDatabaseName: cachedResult.databaseName ?? "No Data", configuration: configuration)
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                
                print("🔐 Authenticated but no cached data for \(cachedResult.databaseName ?? "Unknown"), showing empty state")
                return timeline
            } else {
                // Not authenticated - show demo data with clear indication
                let entry = TodoEntry(date: currentDate, todos: Array(TodoItem.sampleData.prefix(6)), currentDatabaseName: "Demo - Login Required", configuration: configuration)
                
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                
                print("🚫 Not authenticated, using sample data")
                return timeline
            }
        }
    }
    
    private func getCachedTodosWithDatabase(for configuration: DatabaseSelectionIntent) -> (todos: [TodoItem], databaseName: String?) {
        print("🔍 Widget: Starting data search...")
        print("🔍 Configuration database: \(configuration.database?.name ?? "nil")")
        print("🔍 Configuration database ID: \(configuration.database?.databaseId ?? "nil")")
        
        // PRIORITY 1: If specific database is configured in widget, use ONLY that
        if let configuredDatabase = configuration.database {
            let databaseKey = "cachedTodos_\(configuredDatabase.databaseId)"
            print("🎯 Widget configured for specific database: \(configuredDatabase.name)")
            print("🔍 Looking for key: \(databaseKey)")
            
            // Try App Groups first
            if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget"),
               let data = sharedDefaults.data(forKey: databaseKey),
               let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
                print("✅ Found \(cachedTodos.count) todos for configured database: \(configuredDatabase.name) (App Groups)")
                return (todos: cachedTodos, databaseName: configuredDatabase.name)
            }
            
            // Try regular UserDefaults as fallback
            if let data = UserDefaults.standard.data(forKey: databaseKey),
               let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
                print("✅ Found \(cachedTodos.count) todos for configured database: \(configuredDatabase.name) (UserDefaults)")
                return (todos: cachedTodos, databaseName: configuredDatabase.name)
            }
            
            print("❌ No data found for configured database: \(configuredDatabase.name)")
            print("💡 Widget will show empty state until data is fetched")
            return (todos: [], databaseName: configuredDatabase.name)
        }
        
        // PRIORITY 2: No specific database configured, use current active database
        print("🔍 No specific database configured (fallback), trying current active database...")
        
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            if let currentDatabaseId = getCurrentDatabaseId() {
                let databaseKey = "cachedTodos_\(currentDatabaseId)"
                print("🔍 Trying current database key: \(databaseKey)")
                
                if let data = sharedDefaults.data(forKey: databaseKey),
                   let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
                    let databaseName = getDatabaseName(for: currentDatabaseId) ?? "Current Database"
                    print("✅ Found \(cachedTodos.count) todos for current database: \(databaseName)")
                    return (todos: cachedTodos, databaseName: databaseName)
                }
            }
            
            // Fallback to general cached todos
            print("🔍 Trying general cached todos")
            if let data = sharedDefaults.data(forKey: "cachedTodos"),
               let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
                let databaseName = getCurrentDatabaseId().flatMap { getDatabaseName(for: $0) } ?? "Latest Data"
                print("✅ Found \(cachedTodos.count) general cached todos")
                return (todos: cachedTodos, databaseName: databaseName)
            }
        }
        
        // PRIORITY 3: Try regular UserDefaults as final fallback
        print("🔍 Trying regular UserDefaults as final fallback...")
        if let data = UserDefaults.standard.data(forKey: "cachedTodos"),
           let cachedTodos = try? JSONDecoder().decode([TodoItem].self, from: data) {
            print("✅ Found \(cachedTodos.count) general todos in UserDefaults")
            return (todos: cachedTodos, databaseName: "Available Data")
        }
        
        print("❌ No cached data found anywhere")
        return (todos: [], databaseName: nil)
    }
    
    private func getCurrentDatabaseId() -> String? {
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            return sharedDefaults.string(forKey: "currentDatabaseId")
        }
        
        // Fallback to regular UserDefaults
        return UserDefaults.standard.string(forKey: "currentDatabaseId")
    }
    
    private func getDatabaseName(for databaseId: String?) -> String? {
        guard let databaseId = databaseId else { return nil }
        
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget"),
           let data = sharedDefaults.data(forKey: "savedDatabases"),
           let databases = try? JSONDecoder().decode([DatabaseConfiguration].self, from: data) {
            if let database = databases.first(where: { $0.databaseId == databaseId }) {
                return database.name
            }
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "savedDatabases"),
           let databases = try? JSONDecoder().decode([DatabaseConfiguration].self, from: data) {
            if let database = databases.first(where: { $0.databaseId == databaseId }) {
                return database.name
            }
        }
        
        return nil
    }
}

struct TodoWidgetEntryView: View {
    var entry: TodoEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry) // fallback
        }
    }
    
    private func buildWidgetURL() -> URL? {
        // If widget has a specific database configured, include it in the URL
        if let database = entry.configuration.database {
            return URL(string: "notiontodowidget://open?database=\(database.databaseId)")
        } else {
            // Fallback to generic open URL
            return URL(string: "notiontodowidget://open")
        }
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Compact database indicator
            if let currentDatabaseName = entry.currentDatabaseName {
                HStack {
                    Image(systemName: "cylinder.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.secondary)
                    Text(currentDatabaseName)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 2)
            }
            
            // Content
            if entry.todos.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("All done!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 1) {
                    ForEach(entry.todos.prefix(3)) { todo in
                        Button(intent: EditTodoIntent(todoId: todo.id, databaseId: entry.configuration.database?.databaseId)) {
                            SmallTodoRowView(todo: todo)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if entry.todos.count > 3 {
                    Text("+ \(entry.todos.count - 3) more")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(buildWidgetURL(for: entry))
    }
}

struct SmallTodoRowView: View {
    let todo: TodoItem
    
    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(todo.status == .completed ? .green : .secondary)
                .font(.system(size: 10))
            
            VStack(alignment: .leading, spacing: 1) {
                // Title only - larger and clearer
                Text(todo.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(todo.status == .completed)
                    .foregroundColor(todo.status == .completed ? .secondary : .primary)
                
                // Only show the most important badge - priority or due date
                HStack(spacing: 4) {
                    if let priority = todo.priority, priority == .urgent || priority == .high {
                        HStack(spacing: 1) {
                            Image(systemName: priorityIcon(for: priority))
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white)
                            Text(priority.displayName)
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(updatedPriorityColor(for: priority))
                        .clipShape(Capsule())
                    } else if let dueDate = todo.dueDate, isUrgentDate(dueDate) {
                        HStack(spacing: 1) {
                            Image(systemName: "calendar")
                                .font(.system(size: 6))
                                .foregroundColor(.white)
                            Text(shortDateString(for: dueDate))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(smartDueDateColor(for: dueDate))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 0)
    }
    
    private func isUrgentDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        let daysDifference = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0
        return daysDifference <= 1 // Today or tomorrow or overdue
    }
    
    private func shortDateString(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        
        if dueDate < today {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        } else if dueDate == today {
            return "Today"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
    
    private func priorityIcon(for priority: TodoPriority) -> String {
        switch priority {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
    
    private func updatedPriorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4)
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3)
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2)
        }
    }
    
    private func smartDueDateColor(for date: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        
        if dueDate < today {
            return Color(red: 0.8, green: 0.3, blue: 0.3)
        } else if dueDate == today {
            return Color(red: 0.9, green: 0.5, blue: 0.1)
        } else {
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }
}

// MARK: - Medium Widget View (keeping existing layout)

struct MediumWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Database indicator at the top
            if let currentDatabaseName = entry.currentDatabaseName {
                HStack {
                    Image(systemName: "cylinder.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(currentDatabaseName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
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
                VStack(spacing: 4) {
                    ForEach(entry.todos.prefix(3)) { todo in
                        Button(intent: EditTodoIntent(todoId: todo.id, databaseId: entry.configuration.database?.databaseId)) {
                            TodoRowView(todo: todo)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
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
        .widgetURL(buildWidgetURL(for: entry))
    }
}

// MARK: - Large Widget View (using full space)

struct LargeWidgetView: View {
    let entry: TodoEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Database indicator at the top
            if let currentDatabaseName = entry.currentDatabaseName {
                HStack {
                    Image(systemName: "cylinder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(currentDatabaseName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.bottom, 4)
            }
            
            // Content using full height
            if entry.todos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("All done!")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(entry.todos.prefix(6)) { todo in
                        Button(intent: EditTodoIntent(todoId: todo.id, databaseId: entry.configuration.database?.databaseId)) {
                            LargeTodoRowView(todo: todo)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if todo.id != entry.todos.prefix(6).last?.id {
                            Divider()
                                .padding(.horizontal, 4)
                        }
                    }
                    
                    if entry.todos.count > 6 {
                        HStack {
                            Spacer()
                            Text("+ \(entry.todos.count - 6) more tasks")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                            Spacer()
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(buildWidgetURL(for: entry))
    }
}

struct LargeTodoRowView: View {
    let todo: TodoItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(todo.status == .completed ? .green : .secondary)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                // Title - larger for readability
                Text(todo.title)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .strikethrough(todo.status == .completed)
                    .foregroundColor(todo.status == .completed ? .secondary : .primary)
                
                // Status, Priority, and Due date row with more space
                HStack {
                    // Status and Priority grouped together on left
                    HStack(spacing: 8) {
                        // Status badge
                        Text(todo.status.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(for: todo.status))
                            .clipShape(Capsule())
                        
                        // Priority next to status
                        if let priority = todo.priority {
                            HStack(spacing: 3) {
                                Image(systemName: priorityIcon(for: priority))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                Text(priority.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(updatedPriorityColor(for: priority))
                            .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Due date on far right
                    if let dueDate = todo.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                            Text(relativeDateString(for: dueDate))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(smartDueDateColor(for: dueDate))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
    
    private func updatedPriorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4)
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3)
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2)
        }
    }
    
    private func smartDueDateColor(for date: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDate = calendar.startOfDay(for: date)
        
        if dueDate < today {
            return Color(red: 0.8, green: 0.3, blue: 0.3)
        } else if dueDate == today {
            return Color(red: 0.9, green: 0.5, blue: 0.1)
        } else {
            return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }
}

// Helper function for widget URL
private func buildWidgetURL(for entry: TodoEntry) -> URL? {
    if let database = entry.configuration.database {
        return URL(string: "notiontodowidget://open?database=\(database.databaseId)")
    } else {
        return URL(string: "notiontodowidget://open")
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