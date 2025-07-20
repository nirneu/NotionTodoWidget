import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var notionService = NotionService.shared
    @State private var apiKey = ""
    @State private var databaseId = ""
    @State private var showingSetup = false
    @State private var sortOption: SortOption = .createdDate
    
    enum SortOption: String, CaseIterable {
        case createdDate = "Created Date"
        case dueDate = "Due Date"
        case priority = "Priority"
        case status = "Status"
        case title = "Title"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
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
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                        }) {
                            HStack {
                                Text(option.displayName)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
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
            if notionService.todos.isEmpty {
                emptyState
            } else {
                ForEach(sortedTodos) { todo in
                    TodoRowView(todo: todo) { updatedTodo, newStatus in
                        notionService.updateTodoStatus(updatedTodo, status: newStatus)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var sortedTodos: [TodoItem] {
        switch sortOption {
        case .createdDate:
            return notionService.todos.sorted { $0.createdAt > $1.createdAt }
        case .dueDate:
            return notionService.todos.sorted { todo1, todo2 in
                // Sort by due date, putting items without due dates at the end
                switch (todo1.dueDate, todo2.dueDate) {
                case (nil, nil): return todo1.createdAt > todo2.createdAt
                case (nil, _): return false
                case (_, nil): return true
                case (let date1?, let date2?): return date1 < date2
                }
            }
        case .priority:
            return notionService.todos.sorted { todo1, todo2 in
                let priority1 = todo1.priority?.sortOrder ?? 0
                let priority2 = todo2.priority?.sortOrder ?? 0
                return priority1 > priority2
            }
        case .status:
            return notionService.todos.sorted { $0.status.rawValue < $1.status.rawValue }
        case .title:
            return notionService.todos.sorted { $0.title.lowercased() < $1.title.lowercased() }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No todos found")
                .font(.headline)
            
            Text("Your todos will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.body)
                    .strikethrough(todo.status.isCompleted)
                    .foregroundColor(todo.status.isCompleted ? .secondary : .primary)
                
                HStack(spacing: 8) {
                    Text(todo.status.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(for: todo.status))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    
                    if let priority = todo.priority {
                        Text(priority.displayName)
                            .font(.caption)
                            .foregroundColor(priority.color)
                    }
                    
                    Spacer()
                    
                    if let dueDate = todo.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(dueDateText(for: dueDate))
                                .font(.caption)
                        }
                        .foregroundColor(dueDateColor(for: dueDate))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(dueDateColor(for: dueDate).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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
    
    private func dueDateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
}

#Preview {
    ContentView()
}