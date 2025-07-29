import SwiftUI

struct TaskDetailView: View {
    let todoId: String
    @EnvironmentObject var notionService: NotionService
    @Environment(\.dismiss) private var dismiss
    
    @State private var todo: TodoItem?
    @State private var editedTitle: String = ""
    @State private var selectedStatus: TodoStatus = .notStarted
    @State private var selectedPriority: TodoPriority = .medium
    @State private var selectedDate: Date?
    @State private var showingDatePicker = false
    
    var body: some View {
        NavigationView {
            Group {
                if let todo = todo {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Title Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Task Title")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                TextField("Enter task title", text: $editedTitle, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...6)
                                    .font(.title2)
                            }
                            
                            // Status Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Status")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(TodoStatus.allCases, id: \.self) { status in
                                        Button(action: {
                                            selectedStatus = status
                                        }) {
                                            HStack {
                                                Text(status.displayName)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                if selectedStatus == status {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.white)
                                                        .font(.system(size: 12, weight: .bold))
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(statusColor(for: status))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedStatus == status ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // Priority Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Priority")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(TodoPriority.allCases, id: \.self) { priority in
                                        Button(action: {
                                            selectedPriority = priority
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: priorityIcon(for: priority))
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                                Text(priority.displayName)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                if selectedPriority == priority {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.white)
                                                        .font(.system(size: 12, weight: .bold))
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(priorityColor(for: priority))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedPriority == priority ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // Due Date Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Due Date")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    showingDatePicker = true
                                }) {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.accentColor)
                                        
                                        if let selectedDate = selectedDate {
                                            Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text("No due date set")
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                
                                if selectedDate != nil {
                                    Button("Remove Due Date") {
                                        selectedDate = nil
                                    }
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                                }
                            }
                            
                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                } else {
                    ProgressView("Loading task...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.large)
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
                    .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            loadTodo()
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate)
        }
    }
    
    private func loadTodo() {
        print("🔍 TaskDetailView: Loading todo with ID: \(todoId)")
        print("🔍 Available todos: \(notionService.todos.map { $0.id })")
        
        if let foundTodo = notionService.todos.first(where: { $0.id == todoId }) {
            print("✅ Found todo: \(foundTodo.title)")
            todo = foundTodo
            editedTitle = foundTodo.title
            selectedStatus = foundTodo.status
            selectedPriority = foundTodo.priority ?? .medium
            selectedDate = foundTodo.dueDate
        } else {
            print("❌ Todo not found with ID: \(todoId)")
        }
    }
    
    private func saveChanges() {
        guard let todo = todo else { return }
        
        // Update title if changed
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty && trimmedTitle != todo.title {
            notionService.updateTodoTitle(todo, title: trimmedTitle)
        }
        
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
    
    private func priorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return Color(red: 0.0, green: 0.6, blue: 0.4) // Green
        case .medium: return Color(red: 0.8, green: 0.6, blue: 0.2) // Yellow/Gold
        case .high: return Color(red: 0.8, green: 0.3, blue: 0.3) // Red
        case .urgent: return Color(red: 0.7, green: 0.2, blue: 0.2) // Dark Red
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
}

struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var tempDate = Date()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker(
                    "Select Date",
                    selection: $tempDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.wheel)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedDate = tempDate
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            tempDate = selectedDate ?? Date()
        }
    }
}

#Preview {
    TaskDetailView(todoId: "sample-id")
        .environmentObject(NotionService.shared)
}