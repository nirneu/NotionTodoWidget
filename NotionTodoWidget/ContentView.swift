import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var notionService = NotionService.shared
    @State private var apiKey = ""
    @State private var databaseId = ""
    @State private var databaseName = ""
    @State private var showingSetup = false
    @State private var showingFilters = false
    @State private var showingSortOptions = false
    @State private var showingDatabaseManager = false
    @State private var showingAddDatabase = false
    @State private var selectedTodo: TodoItem?
    @State private var showingTaskEditor = false
    @State private var selectedTaskId: String?
    @State private var showingTaskDetail = false
    
    var body: some View {
        NavigationView {
            Group {
                if notionService.isAuthenticated {
                    authenticatedView
                } else {
                    setupView
                }
            }
            .navigationTitle("Todo Widget")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemBackground))
        }
        .onAppear {
            if notionService.isAuthenticated {
                notionService.fetchDatabaseSchema()
            }
        }
        .onOpenURL { url in
            handleWidgetURL(url)
        }
        .alert("Error", isPresented: .constant(notionService.errorMessage != nil)) {
            Button("OK") {
                notionService.errorMessage = nil
            }
        } message: {
            Text(notionService.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let message = notionService.statusUpdateMessage {
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: notionService.statusUpdateMessage)
            }
        }
    }
    
    // MARK: - Setup View
    
    private var setupView: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "widget.large.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("Welcome to Todo Widget")
                    .font(.title)
                    .fontWeight(.semibold)
                
                if notionService.apiKey == nil {
                    Text("Enter your Notion API key to get started")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Add your first database to continue")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if notionService.apiKey == nil {
                apiKeySection
            } else {
                databaseManagementSection
            }
            
            Button("Use Demo Data") {
                useDemoData()
            }
            .font(.caption)
        }
        .padding(32)
        .sheet(isPresented: $showingAddDatabase) {
            addDatabaseSheet
        }
    }
    
    private var apiKeySection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notion API Key")
                    .font(.headline)
                
                SecureField("Enter your Notion integration token", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            
            Button("Save API Key") {
                notionService.configure(apiKey: apiKey)
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty)
        }
    }
    
    private var databaseManagementSection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Databases")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        showingAddDatabase = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                if notionService.databases.isEmpty {
                    Text("No databases added yet")
                        .foregroundColor(.secondary)
                        .font(.body)
                } else {
                    ForEach(notionService.databases) { database in
                        DatabaseRow(database: database, notionService: notionService)
                    }
                }
            }
        }
    }
    
    private var addDatabaseSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database Name")
                        .font(.headline)
                    
                    TextField("e.g., Personal Tasks", text: $databaseName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database ID")
                        .font(.headline)
                    
                    TextField("Enter your Notion database ID", text: $databaseId)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingAddDatabase = false
                        databaseName = ""
                        databaseId = ""
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        notionService.addDatabase(name: databaseName, databaseId: databaseId)
                        showingAddDatabase = false
                        databaseName = ""
                        databaseId = ""
                    }
                    .disabled(databaseName.isEmpty || databaseId.isEmpty)
                }
            }
        }
    }
}

struct DatabaseRow: View {
    let database: DatabaseConfiguration
    let notionService: NotionService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(database.name)
                    .font(.body)
                    .fontWeight(database.isActive ? .semibold : .regular)
                
                Text(database.databaseId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if database.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Select") {
                    notionService.setActiveDatabase(database)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(database.isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            Button("Delete", role: .destructive) {
                notionService.removeDatabase(database)
            }
        }
    }
}

extension ContentView {
    
    // MARK: - Authenticated View
    
    private var authenticatedView: some View {
        VStack(spacing: 0) {
            // Database picker at the top
            databasePicker
                .padding(.horizontal)
                .padding(.top, 8)
            
            Divider()
                .padding(.horizontal)
            
            if notionService.isLoading {
                ProgressView("Loading todos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                todoList
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingSortOptions = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(notionService.sortConfiguration.primaryOrder.symbol)
                            .font(.caption)
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingFilters = true
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Refresh", action: {
                        notionService.fetchDatabaseSchema()
                        // Force widget refresh
                        WidgetCenter.shared.reloadAllTimelines()
                    })
                    
                    Button("Sign Out", role: .destructive, action: {
                        notionService.signOut()
                    })
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            notionService.fetchDatabaseSchema()
            // Force widget refresh
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    private var todoList: some View {
        List {
            if notionService.filteredTodos.isEmpty {
                emptyState
            } else {
                ForEach(notionService.filteredTodos) { todo in
                    TodoRowView(todo: todo) { updatedTodo, newStatus in
                        notionService.updateTodoStatus(updatedTodo, status: newStatus)
                    } onTodoTap: { tappedTodo in
                        print("📱 Main List: Tapped todo: \(tappedTodo.title) (ID: \(tappedTodo.id))")
                        selectedTaskId = tappedTodo.id
                        showingTaskDetail = true
                        print("📱 Main List: Set showingTaskDetail = true")
                    }
                    .environmentObject(notionService)
                }
            }
        }
        .listStyle(.plain)
        .sheet(isPresented: $showingFilters) {
            FilterView()
                .environmentObject(notionService)
        }
        .sheet(isPresented: $showingSortOptions) {
            SortOptionsView()
                .environmentObject(notionService)
        }
        .sheet(isPresented: $showingDatabaseManager) {
            DatabaseManagerView()
                .environmentObject(notionService)
        }
        .sheet(isPresented: $showingTaskEditor) {
            if let selectedTodo = selectedTodo {
                IndividualTaskEditorView(todo: selectedTodo)
                    .environmentObject(notionService)
            }
        }
        .sheet(isPresented: $showingTaskDetail) {
            if let selectedTaskId = selectedTaskId {
                TaskDetailView(todoId: selectedTaskId)
                    .environmentObject(notionService)
                    .onAppear {
                        print("📋 Sheet: Presenting TaskDetailView for ID: \(selectedTaskId)")
                    }
            } else {
                Text("Error: No task selected")
                    .onAppear {
                        print("❌ Sheet: selectedTaskId is nil")
                    }
            }
        }
    }
    
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(isFiltered ? "No todos match filters" : "No todos found")
                .font(.headline)
            
            Text(isFiltered ? "Try adjusting your filters" : "Your todos will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if isFiltered {
                Button("Clear Filters") {
                    notionService.clearAllFilters()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
    }
    
    private var isFiltered: Bool {
        notionService.statusFilter.count < TodoStatus.allCases.count ||
        notionService.priorityFilter.count < TodoPriority.allCases.count
    }
    
    private var groupedTodos: [TodoPriority: [TodoItem]] {
        Dictionary(grouping: notionService.todos.filter { $0.priority != nil }) { $0.priority! }
    }
    
    // MARK: - Actions
    
    private func useDemoData() {
        notionService.configure(apiKey: "demo")
        notionService.addDatabase(name: "Demo Tasks", databaseId: "demo")
        notionService.fetchTodos()
    }
    
    // MARK: - URL Handling
    
    private func handleWidgetURL(_ url: URL) {
        print("🔗 URL Handler: Received URL: \(url)")
        print("🔗 URL Handler: Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")
        
        guard url.scheme == "notiontodowidget" else { 
            print("❌ URL Handler: Invalid scheme, expected 'notiontodowidget'")
            return 
        }
        
        switch url.host {
        case "change-database":
            // Open the database manager when user taps the widget button
            if notionService.isAuthenticated {
                showingDatabaseManager = true
            }
        case "open":
            // Widget tap - check if a specific database was requested
            handleWidgetOpen(url)
        case "edit":
            // Edit specific todo - extract todoId from path and handle database switching
            let todoId = String(url.path.dropFirst()) // Remove leading "/"
            print("🔗 URL Handler: Received edit request for todo ID: \(todoId)")
            
            // Check if a specific database was requested for this todo
            handleDatabaseSwitchIfNeeded(url)
            
            selectedTaskId = todoId
            showingTaskDetail = true
            print("🔗 URL Handler: Set showingTaskDetail = true")
        default:
            break
        }
    }
    
    private func handleWidgetOpen(_ url: URL) {
        print("🔗 Widget Open: Processing widget tap with URL: \(url)")
        handleDatabaseSwitchIfNeeded(url)
    }
    
    private func handleDatabaseSwitchIfNeeded(_ url: URL) {
        // Parse URL components to extract database parameter
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            print("🔗 Database Switch: No specific database requested, staying with current active database")
            return
        }
        
        // Look for database parameter in query items
        if let queryItems = components.queryItems,
           let databaseIdItem = queryItems.first(where: { $0.name == "database" }),
           let requestedDatabaseId = databaseIdItem.value {
            
            print("🔗 Database Switch: Requested database ID: \(requestedDatabaseId)")
            
            // Find the database configuration with this ID
            if let targetDatabase = notionService.databases.first(where: { $0.databaseId == requestedDatabaseId }) {
                print("🔗 Database Switch: Found database: \(targetDatabase.name)")
                
                // Switch to this database if it's not already active
                if targetDatabase.id != notionService.activeDatabaseId {
                    print("🔗 Database Switch: Switching from current active database to: \(targetDatabase.name)")
                    notionService.setActiveDatabase(targetDatabase)
                } else {
                    print("🔗 Database Switch: Database \(targetDatabase.name) is already active")
                }
            } else {
                print("❌ Database Switch: Requested database ID not found in configured databases")
            }
        } else {
            print("🔗 Database Switch: No database parameter found, staying with current active database")
        }
    }
    
    // MARK: - Database Picker
    
    private var databasePicker: some View {
        HStack {
            Image(systemName: "cylinder.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            Menu {
                ForEach(notionService.databases) { database in
                    Button(action: {
                        if database.id != notionService.activeDatabaseId {
                            notionService.setActiveDatabase(database)
                        }
                    }) {
                        HStack {
                            Text(database.name)
                            Spacer()
                            if database.isActive {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("Manage Databases...", action: {
                    showingDatabaseManager = true
                })
            } label: {
                HStack {
                    if let activeDatabase = notionService.databases.first(where: { $0.isActive }) {
                        Text(activeDatabase.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        Text("Select Database")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Show database count
            if notionService.databases.first(where: { $0.isActive }) != nil {
                Text("\(notionService.filteredTodos.count) tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Todo Row View

struct TodoRowView: View {
    let todo: TodoItem
    let onStatusUpdate: (TodoItem, TodoStatus) -> Void
    let onTodoTap: (TodoItem) -> Void
    @EnvironmentObject var notionService: NotionService
    
    var body: some View {
        Button(action: {
            onTodoTap(todo)
        }) {
            HStack(spacing: 12) {
                // Status toggle button (separate from main tap)
                Button {
                    let newStatus: TodoStatus = todo.status.isCompleted ? .notStarted : .completed
                    onStatusUpdate(todo, newStatus)
                } label: {
                    Image(systemName: todo.status.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(todo.status.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            
                VStack(alignment: .leading, spacing: 8) {
                    // Title (non-interactive, whole row is clickable)
                    Text(todo.title)
                        .font(.system(size: 17, weight: .medium))
                        .strikethrough(todo.status.isCompleted)
                        .foregroundColor(todo.status.isCompleted ? .secondary : .primary)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        // Status and Priority grouped together on left (display only)
                        HStack(spacing: 8) {
                            // Status badge (display only)
                            Text(todo.status.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(statusColor(for: todo.status))
                                .clipShape(Capsule())
                            
                            // Priority (display only)
                            if let priority = todo.priority {
                                HStack(spacing: 3) {
                                    Image(systemName: priorityIcon(for: priority))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(priority.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(updatedPriorityColor(for: priority))
                                .clipShape(Capsule())
                            }
                        }
                        
                        Spacer()
                        
                        // Due date (display only)
                        if let dueDate = todo.dueDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                Text(dueDateText(for: dueDate))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(smartDueDateColor(for: dueDate))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator))
                .opacity(0.3),
            alignment: .bottom
        )
        .buttonStyle(.plain)
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
    
    private func dueDateText(for date: Date) -> String {
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
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4) // Green
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2) // Yellow/Gold
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3) // Red
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark Red
        }
    }
    
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

// MARK: - Filter View

struct FilterView: View {
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Status Filters") {
                    ForEach(TodoStatus.allCases, id: \.self) { status in
                        FilterToggleRow(
                            title: status.displayName,
                            isEnabled: notionService.statusFilter.contains(status)
                        ) {
                            notionService.toggleStatusFilter(status)
                        }
                    }
                }
                
                Section("Priority Filters") {
                    ForEach(TodoPriority.allCases, id: \.self) { priority in
                        FilterToggleRow(
                            title: priority.displayName,
                            isEnabled: notionService.priorityFilter.contains(priority)
                        ) {
                            notionService.togglePriorityFilter(priority)
                        }
                    }
                }
                
                Section {
                    Button("Clear All Filters") {
                        notionService.clearAllFilters()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FilterToggleRow: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sort Options View

struct SortOptionsView: View {
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Primary Sort") {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if notionService.sortConfiguration.primary == option {
                                Button(action: {
                                    notionService.togglePrimarySortOrder()
                                }) {
                                    Text(notionService.sortConfiguration.primaryOrder.symbol)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if notionService.sortConfiguration.primary == option {
                                notionService.togglePrimarySortOrder()
                            } else {
                                notionService.setPrimarySort(option, order: .ascending)
                            }
                        }
                    }
                }
                
                Section("Secondary Sort (Optional)") {
                    HStack {
                        Text("None")
                        Spacer()
                        if notionService.sortConfiguration.secondary == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        notionService.setSecondarySort(nil, order: .ascending)
                    }
                    
                    ForEach(SortOption.allCases, id: \.self) { option in
                        if option != notionService.sortConfiguration.primary {
                            HStack {
                                Text(option.displayName)
                                Spacer()
                                if notionService.sortConfiguration.secondary == option {
                                    Button(action: {
                                        notionService.toggleSecondarySortOrder()
                                    }) {
                                        Text(notionService.sortConfiguration.secondaryOrder.symbol)
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if notionService.sortConfiguration.secondary == option {
                                    notionService.toggleSecondarySortOrder()
                                } else {
                                    notionService.setSecondarySort(option, order: .ascending)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Sort")
                            .font(.headline)
                        Text(notionService.sortConfiguration.displayName)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Sort Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Status Context Menu

struct StatusContextMenu: View {
    let currentStatus: TodoStatus
    let onStatusChange: (TodoStatus) -> Void
    
    var body: some View {
        ForEach(TodoStatus.allCases, id: \.self) { status in
            Button(action: {
                onStatusChange(status)
            }) {
                HStack {
                    Text(status.displayName)
                    if status == currentStatus {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

// MARK: - Status Picker View

struct StatusPickerView: View {
    let todo: TodoItem
    let onStatusUpdate: (TodoItem, TodoStatus) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(TodoStatus.allCases, id: \.self) { status in
                    Button(action: {
                        onStatusUpdate(todo, status)
                        dismiss()
                    }) {
                        HStack {
                            // Status badge preview
                            Text(status.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(statusColor(for: status))
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            if status == todo.status {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
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
}

// MARK: - Priority Picker View

struct PriorityPickerView: View {
    let todo: TodoItem
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(TodoPriority.allCases, id: \.self) { priority in
                    Button(action: {
                        notionService.updateTodoPriority(todo, priority: priority)
                        dismiss()
                    }) {
                        HStack {
                            // Priority badge preview
                            HStack(spacing: 3) {
                                Image(systemName: priorityIcon(for: priority))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                Text(priority.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(priorityColor(for: priority))
                            .clipShape(Capsule())
                            
                            Spacer()
                            
                            if priority == todo.priority {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Priority")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
    
    private func priorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4) // Green
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2) // Yellow/Gold
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3) // Red
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark Red
        }
    }
}

// MARK: - Date Picker View

struct DatePickerView: View {
    let todo: TodoItem
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDate: Date
    
    init(todo: TodoItem) {
        self.todo = todo
        self._selectedDate = State(initialValue: todo.dueDate ?? Date())
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current due date display
                if let currentDueDate = todo.dueDate {
                    VStack(spacing: 8) {
                        Text("Current Due Date")
                            .font(.headline)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text(dueDateText(for: currentDueDate))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(smartDueDateColor(for: currentDueDate))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 20)
                }
                
                // Date picker
                DatePicker(
                    "Select Due Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.wheel)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button("Update Due Date") {
                        notionService.updateTodoDueDate(todo, dueDate: selectedDate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    
                    if todo.dueDate != nil {
                        Button("Remove Due Date") {
                            notionService.updateTodoDueDate(todo, dueDate: nil)
                            dismiss()
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func dueDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
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

// MARK: - Title Editor View

struct TitleEditorView: View {
    let todo: TodoItem
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedTitle: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(todo: TodoItem) {
        self.todo = todo
        self._editedTitle = State(initialValue: todo.title)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current title display
                VStack(spacing: 8) {
                    Text("Current Title")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(todo.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 20)
                
                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Title")
                        .font(.headline)
                    
                    TextField("Enter task title", text: $editedTitle, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .onAppear {
                            // Focus the text field and select all text when view appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                isTextFieldFocused = true
                            }
                        }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button("Update Title") {
                        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTitle.isEmpty && trimmedTitle != todo.title {
                            notionService.updateTodoTitle(todo, title: trimmedTitle)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Revert to Original") {
                        editedTitle = todo.title
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Edit Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedTitle.isEmpty && trimmedTitle != todo.title {
                            notionService.updateTodoTitle(todo, title: trimmedTitle)
                        }
                        dismiss()
                    }
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct DatabaseManagerView: View {
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddDatabase = false
    @State private var databaseName = ""
    @State private var databaseId = ""
    @State private var editingDatabase: DatabaseConfiguration?
    @State private var showingEditDatabase = false
    @State private var isLoadingDatabaseInfo = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Your Databases")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            showingAddDatabase = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    if notionService.databases.isEmpty {
                        Text("No databases added yet")
                            .foregroundColor(.secondary)
                            .font(.body)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(notionService.databases) { database in
                                DatabaseManagerRow(
                                    database: database, 
                                    notionService: notionService,
                                    onEdit: {
                                        editingDatabase = database
                                        databaseName = database.name
                                        databaseId = database.databaseId
                                        isLoadingDatabaseInfo = false
                                        showingEditDatabase = true
                                    }
                                )
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Manage Databases")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddDatabase) {
                NavigationView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How to get your Notion database ID:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                        .fontWeight(.medium)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Go to your source database (not a filtered view)")
                                        Text("⚠️ Important: Must be the main database, not a view")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                    }
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                        .fontWeight(.medium)
                                    Text("Click the '•••' menu → 'Copy link to view'")
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                        .fontWeight(.medium)
                                    Text("Paste the URL below - we'll extract the ID and name automatically")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Notion Database URL")
                                    .font(.headline)
                                if isLoadingDatabaseInfo {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                if !databaseName.isEmpty {
                                    Text("(\(databaseName))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            TextField("Paste your Notion database URL here", text: $databaseId)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: databaseId) { oldValue, newValue in
                                    // Extract database ID from URL if it's a valid Notion URL
                                    if let extractedId = extractDatabaseId(from: newValue) {
                                        databaseId = extractedId
                                        // Auto-fetch database name
                                        fetchDatabaseName(for: extractedId)
                                    } else {
                                        // Reset database name if URL is invalid
                                        databaseName = ""
                                    }
                                }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Add Database")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAddDatabase = false
                                databaseName = ""
                                databaseId = ""
                                isLoadingDatabaseInfo = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Add") {
                                notionService.addDatabase(name: databaseName, databaseId: databaseId)
                                showingAddDatabase = false
                                databaseName = ""
                                databaseId = ""
                                isLoadingDatabaseInfo = false
                            }
                            .disabled(databaseName.isEmpty || databaseId.isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEditDatabase) {
                NavigationView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How to get your Notion database ID:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                        .fontWeight(.medium)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Go to your source database (not a filtered view)")
                                        Text("⚠️ Important: Must be the main database, not a view")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                    }
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                        .fontWeight(.medium)
                                    Text("Click the '•••' menu → 'Copy link to view'")
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                        .fontWeight(.medium)
                                    Text("Paste the URL below - we'll extract the ID and name automatically")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Notion Database URL")
                                    .font(.headline)
                                if isLoadingDatabaseInfo {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                if !databaseName.isEmpty {
                                    Text("(\(databaseName))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                }
                            }
                            
                            TextField("Paste your Notion database URL here", text: $databaseId)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: databaseId) { oldValue, newValue in
                                    // Extract database ID from URL if it's a valid Notion URL
                                    if let extractedId = extractDatabaseId(from: newValue) {
                                        databaseId = extractedId
                                        // Auto-fetch database name
                                        fetchDatabaseName(for: extractedId)
                                    } else {
                                        // Reset database name if URL is invalid
                                        databaseName = ""
                                    }
                                }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Edit Database")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingEditDatabase = false
                                editingDatabase = nil
                                databaseName = ""
                                databaseId = ""
                                isLoadingDatabaseInfo = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") {
                                if let editingDb = editingDatabase {
                                    // Update the database (we'll need to add this method to NotionService)
                                    notionService.updateDatabase(editingDb, name: databaseName, databaseId: databaseId)
                                }
                                showingEditDatabase = false
                                editingDatabase = nil
                                databaseName = ""
                                databaseId = ""
                                isLoadingDatabaseInfo = false
                            }
                            .disabled(databaseName.isEmpty || databaseId.isEmpty)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func fetchDatabaseName(for databaseId: String) {
        guard !databaseId.isEmpty else { return }
        
        isLoadingDatabaseInfo = true
        
        notionService.fetchDatabaseInfo(databaseId: databaseId) { result in
            self.isLoadingDatabaseInfo = false
            
            switch result {
            case .success(let name):
                self.databaseName = name
            case .failure(let error):
                print("Failed to fetch database name: \(error.localizedDescription)")
                // Don't change the name field if fetch fails
            }
        }
    }
    
    private func extractDatabaseId(from urlString: String) -> String? {
        // Remove whitespace and check if it's a valid URL
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it's already just a database ID (32 chars, alphanumeric), return it as-is
        if trimmedUrl.count == 32 && trimmedUrl.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return trimmedUrl
        }
        
        // Try to extract from Notion URL
        guard let url = URL(string: trimmedUrl),
              let host = url.host,
              host.contains("notion.so") else {
            return nil
        }
        
        let pathComponents = url.pathComponents
        
        // Look for the database ID in the URL
        // Database IDs are typically 32-character alphanumeric strings
        for component in pathComponents {
            // Remove query parameters if present
            let cleanComponent = component.components(separatedBy: "?").first ?? component
            
            // Check if this component looks like a database ID
            if cleanComponent.count == 32 && cleanComponent.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return cleanComponent
            }
            
            // Sometimes the database ID is at the end of a longer string like "DatabaseName-1b876dbaec29804cbb78c6077f9f5d37"
            if let range = cleanComponent.range(of: #"-[a-f0-9A-F]{32}$"#, options: .regularExpression) {
                let databaseId = String(cleanComponent[range].dropFirst()) // Remove the leading dash
                return databaseId
            }
        }
        
        return nil
    }
}

struct DatabaseManagerRow: View {
    let database: DatabaseConfiguration
    let notionService: NotionService
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(database.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(database.databaseId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Edit") {
                onEdit()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .contextMenu {
            Button("Edit") {
                onEdit()
            }
            
            Button("Delete", role: .destructive) {
                notionService.removeDatabase(database)
            }
        }
    }
}

// MARK: - Individual Task Editor View

struct IndividualTaskEditorView: View {
    let todo: TodoItem
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedStatus: TodoStatus = .notStarted
    @State private var selectedPriority: TodoPriority = .medium
    @State private var selectedDate: Date?
    @State private var titleText: String = ""
    
    init(todo: TodoItem) {
        self.todo = todo
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    HStack {
                        Text("Title")
                        Spacer()
                        TextField("Task title", text: $titleText)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Status") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(TodoStatus.allCases, id: \.self) { status in
                            Label(status.displayName, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Priority") {
                    Picker("Priority", selection: $selectedPriority) {
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Label(priority.displayName, systemImage: priority.systemImage)
                                .foregroundColor(priority.color)
                                .tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Due Date") {
                    HStack {
                        Text("Due Date")
                        Spacer()
                        if let selectedDate = selectedDate {
                            Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                        } else {
                            Text("No due date")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DatePicker("Select Date", selection: Binding(
                        get: { selectedDate ?? Date() },
                        set: { selectedDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    
                    if selectedDate != nil {
                        Button("Remove Due Date") {
                            selectedDate = nil
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedStatus = todo.status
            selectedPriority = todo.priority ?? .medium
            selectedDate = todo.dueDate
            titleText = todo.title
        }
    }
    
    private func saveChanges() {
        // Update status if changed
        if selectedStatus != todo.status {
            notionService.updateTodoStatus(todo, status: selectedStatus)
        }
        
        // Update priority if changed
        if selectedPriority != todo.priority {
            notionService.updateTodoPriority(todo, priority: selectedPriority)
        }
        
        // Update due date if changed
        if selectedDate != todo.dueDate {
            notionService.updateTodoDueDate(todo, dueDate: selectedDate)
        }
        
        // Update title if changed
        if titleText != todo.title {
            notionService.updateTodoTitle(todo, title: titleText)
        }
    }
}

#Preview {
    ContentView()
}