import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var notionService = NotionService.shared
    @State private var apiKey = ""
    @State private var databaseId = ""
    @State private var showingSetup = false
    @State private var showingFilters = false
    @State private var showingSortOptions = false
    
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
                
                Text("Connect your Notion database to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notion API Key")
                        .font(.headline)
                    
                    SecureField("Enter your Notion integration token", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Database ID")
                        .font(.headline)
                    
                    TextField("Enter your Notion database ID", text: $databaseId)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Button("Connect to Notion") {
                    connectToNotion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || databaseId.isEmpty)
            }
            
            Button("Use Demo Data") {
                useDemoData()
            }
            .font(.caption)
        }
        .padding(32)
    }
    
    // MARK: - Authenticated View
    
    private var authenticatedView: some View {
        VStack {
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
                    
                    Button("Show Debug Files") {
                        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            print("📁 Documents folder: \(documentsPath.path)")
                            print("📄 Schema file: \(documentsPath.appendingPathComponent("notion_schema.json").path)")
                            print("📄 Todos file: \(documentsPath.appendingPathComponent("notion_todos.json").path)")
                        }
                    }
                    
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
                    }
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
    
    private func connectToNotion() {
        notionService.configure(apiKey: apiKey, databaseId: databaseId)
        if notionService.isAuthenticated {
            notionService.fetchTodos()
        }
    }
    
    private func useDemoData() {
        notionService.configure(apiKey: "demo", databaseId: "demo")
        notionService.fetchTodos()
    }
}

// MARK: - Todo Row View

struct TodoRowView: View {
    let todo: TodoItem
    let onStatusUpdate: (TodoItem, TodoStatus) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                let newStatus: TodoStatus = todo.status.isCompleted ? .notStarted : .completed
                onStatusUpdate(todo, newStatus)
            } label: {
                Image(systemName: todo.status.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(todo.status.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .contextMenu {
                StatusContextMenu(currentStatus: todo.status) { newStatus in
                    onStatusUpdate(todo, newStatus)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(todo.title)
                    .font(.system(size: 17, weight: .medium))
                    .strikethrough(todo.status.isCompleted)
                    .foregroundColor(todo.status.isCompleted ? .secondary : .primary)
                    .lineLimit(nil)
                
                HStack {
                    // Status and Priority grouped together on left
                    HStack(spacing: 8) {
                        // Status badge
                        Text(todo.status.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(statusColor(for: todo.status))
                            .clipShape(Capsule())
                        
                        // Priority next to status
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
                    
                    // Due date on far right
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
    
    private func priorityIndicator(for priority: TodoPriority) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<priority.sortOrder, id: \.self) { _ in
                Circle()
                    .fill(priorityColor(for: priority))
                    .frame(width: 4, height: 4)
            }
        }
    }
    
    private func priorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
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
    
    // Updated priority colors matching the image
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

#Preview {
    ContentView()
}