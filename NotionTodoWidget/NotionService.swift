import Foundation
import Combine
import WidgetKit

class NotionService: ObservableObject {
    static let shared = NotionService()
    
    @Published var isAuthenticated = false
    @Published var todos: [TodoItem] = []
    @Published var filteredTodos: [TodoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var databaseProperties: [String: Any] = [:]
    
    // Sorting and filtering options (loaded from persistent storage)
    @Published var sortConfiguration: SortConfiguration
    @Published var statusFilter: Set<TodoStatus>
    @Published var priorityFilter: Set<TodoPriority>
    @Published var statusUpdateMessage: String?
    
    private var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: "NotionAPIKey")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "NotionAPIKey")
        }
    }
    
    private var databaseId: String? {
        get {
            UserDefaults.standard.string(forKey: "NotionDatabaseId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "NotionDatabaseId")
        }
    }
    
    
    private init() {
        // Load persistent preferences first
        self.sortConfiguration = PreferencesManager.shared.loadSortConfiguration()
        self.statusFilter = PreferencesManager.shared.loadStatusFilter()
        self.priorityFilter = PreferencesManager.shared.loadPriorityFilter()
        
        checkAuthenticationStatus()
        // Apply initial filtering and sorting
        applyFiltersAndSorting()
    }
    
    // MARK: - Authentication
    
    func configure(apiKey: String, databaseId: String) {
        self.apiKey = apiKey
        self.databaseId = databaseId
        checkAuthenticationStatus()
        
        // If we become authenticated, immediately fetch schema then data
        if isAuthenticated {
            fetchDatabaseSchema()
        }
    }
    
    private func checkAuthenticationStatus() {
        isAuthenticated = apiKey != nil && databaseId != nil
    }
    
    func signOut() {
        apiKey = nil
        databaseId = nil
        isAuthenticated = false
        todos = []
    }
    
    // MARK: - Data Operations
    
    func fetchDatabaseSchema() {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            errorMessage = "API key or database ID not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let url = URL(string: "https://api.notion.com/v1/databases/\(databaseId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    self.isLoading = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorData["message"] as? String {
                            self.errorMessage = "Notion API error: \(message)"
                        } else {
                            self.errorMessage = "HTTP error: \(httpResponse.statusCode)"
                        }
                        self.isLoading = false
                        return
                    }
                }
                
                do {
                    // Save the raw schema response to Documents for debugging
                    if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let schemaFile = documentsPath.appendingPathComponent("notion_schema.json")
                        try data.write(to: schemaFile)
                        print("📝 Schema saved to: \(schemaFile.path)")
                    }
                    
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let properties = json?["properties"] as? [String: Any] {
                        self.databaseProperties = properties
                        print("Database properties found: \(properties.keys.joined(separator: ", "))")
                        
                        // Log the actual property structures for debugging
                        for (key, value) in properties {
                            if let propertyDict = value as? [String: Any],
                               let type = propertyDict["type"] as? String {
                                print("Property '\(key)' is of type '\(type)'")
                                
                                // If it's a select property, log the options
                                if type == "select",
                                   let selectDict = propertyDict["select"] as? [String: Any],
                                   let options = selectDict["options"] as? [[String: Any]] {
                                    let optionNames = options.compactMap { $0["name"] as? String }
                                    print("  Select options: \(optionNames.joined(separator: ", "))")
                                }
                            }
                        }
                    }
                    
                    // After getting schema, fetch the actual todos
                    self.fetchTodos()
                } catch {
                    self.errorMessage = "Failed to parse database schema: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }.resume()
    }
    
    func fetchTodos() {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            errorMessage = "API key or database ID not configured"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let url = URL(string: "https://api.notion.com/v1/databases/\(databaseId)/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "sorts": [
                [
                    "timestamp": "created_time",
                    "direction": "descending"
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create request: \(error.localizedDescription)"
                self.isLoading = false
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorData["message"] as? String {
                            self.errorMessage = "Notion API error: \(message)"
                        } else {
                            self.errorMessage = "HTTP error: \(httpResponse.statusCode)"
                        }
                        return
                    }
                }
                
                do {
                    // Save the raw todos response to Documents for debugging
                    if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let todosFile = documentsPath.appendingPathComponent("notion_todos.json")
                        try data.write(to: todosFile)
                        print("📝 Todos response saved to: \(todosFile.path)")
                    }
                    
                    self.todos = try self.parseNotionResponse(data)
                    // Apply filtering and sorting
                    self.applyFiltersAndSorting()
                    // Cache the data for the widget
                    self.saveTodosToSharedCache(self.filteredTodos)
                    // Refresh all widgets
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    self.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func parseNotionResponse(_ data: Data) throws -> [TodoItem] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            throw NSError(domain: "NotionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        print("📊 Parsing \(results.count) todo items from Notion...")
        
        var todos: [TodoItem] = []
        
        for (index, result) in results.enumerated() {
            guard let id = result["id"] as? String,
                  let properties = result["properties"] as? [String: Any] else {
                print("❌ Item \(index): Missing id or properties")
                continue
            }
            
            print("\n🔍 Item \(index) (\(id)):")
            print("📝 Available properties: \(properties.keys.joined(separator: ", "))")
            
            // Log the full properties structure for debugging
            for (key, value) in properties {
                if let propertyDict = value as? [String: Any] {
                    print("   \(key): \(propertyDict)")
                } else {
                    print("   \(key): \(value)")
                }
            }
            
            // Extract title - try common property names
            let title = extractTitle(from: properties)
            print("📋 Title: '\(title)'")
            
            // Extract status
            let status = extractStatus(from: properties)
            print("🏷️ Status: '\(status.rawValue)'")
            
            // Extract priority
            let priority = extractPriority(from: properties)
            print("⚡ Priority: \(priority?.rawValue ?? "none")")
            
            // Extract due date
            let dueDate = extractDueDate(from: properties)
            print("📅 Due date: \(dueDate?.description ?? "none")")
            
            // Extract created/updated dates
            let createdAt = extractDate(from: result["created_time"] as? String) ?? Date()
            let updatedAt = extractDate(from: result["last_edited_time"] as? String) ?? Date()
            
            let todo = TodoItem(
                id: id,
                title: title,
                status: status,
                dueDate: dueDate,
                priority: priority,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            
            todos.append(todo)
        }
        
        print("\n✅ Successfully parsed \(todos.count) todos")
        return todos
    }
    
    private func extractTitle(from properties: [String: Any]) -> String {
        // Try common title property names, including "Task name"
        let titleKeys = ["Task name", "Name", "Title", "Task", "name", "title", "task"]
        
        for key in titleKeys {
            if let titleProperty = properties[key] as? [String: Any],
               let titleContent = titleProperty["title"] as? [[String: Any]] {
                if let firstTitle = titleContent.first,
                   let plainText = firstTitle["plain_text"] as? String {
                    return plainText
                }
            }
        }
        
        return "Untitled"
    }
    
    private func extractStatus(from properties: [String: Any]) -> TodoStatus {
        // Try common status property names
        let statusKeys = ["Status", "status", "Done", "done", "Completed", "completed"]
        
        print("🔍 Looking for status in properties: \(properties.keys.joined(separator: ", "))")
        
        for key in statusKeys {
            print("   Checking key: '\(key)'")
            if let statusProperty = properties[key] as? [String: Any] {
                print("   Found property '\(key)': \(statusProperty)")
                
                // Handle the new Notion "status" property type (different from select)
                if let status = statusProperty["status"] as? [String: Any] {
                    print("   Status property found: \(status)")
                    if let name = status["name"] as? String {
                        print("   ✅ Found status value: '\(name)'")
                        return mapToTodoStatus(name)
                    }
                }
                
                // Handle select property (fallback)
                if let select = statusProperty["select"] as? [String: Any] {
                    print("   Select property found: \(select)")
                    if let name = select["name"] as? String {
                        print("   ✅ Found status value: '\(name)'")
                        return mapToTodoStatus(name)
                    }
                }
                
                // Handle checkbox property
                if let checkbox = statusProperty["checkbox"] as? Bool {
                    print("   ✅ Found checkbox status: \(checkbox)")
                    return checkbox ? .completed : .notStarted
                }
            } else {
                print("   ❌ Property '\(key)' not found or not a dictionary")
            }
        }
        
        print("   ⚠️ No status property found, defaulting to 'Not started'")
        return .notStarted
    }
    
    private func mapToTodoStatus(_ statusName: String) -> TodoStatus {
        // Map actual Notion status values to our enum cases
        switch statusName {
        case "In progress":
            return .inProgress
        case "Blocked":
            return .blocked
        case "Not started":
            return .notStarted
        case "Research":
            return .research
        case "Done", "Completed":
            return .completed
        case "Cancelled", "Canceled":
            return .cancelled
        default:
            // For any other status, try to match the raw value
            if let status = TodoStatus(rawValue: statusName) {
                print("   ✅ Matched to enum: \(status.rawValue)")
                return status
            }
            print("   ⚠️ Unknown status: '\(statusName)', defaulting to 'Not started'")
            return .notStarted
        }
    }
    
    private func extractPriority(from properties: [String: Any]) -> TodoPriority? {
        // Try common priority property names
        let priorityKeys = ["Priority", "priority", "Importance", "importance"]
        
        for key in priorityKeys {
            if let priorityProperty = properties[key] as? [String: Any],
               let select = priorityProperty["select"] as? [String: Any],
               let name = select["name"] as? String {
                
                // First try exact match with our enum cases
                if let priority = TodoPriority(rawValue: name) {
                    return priority
                }
                
                // Fallback to fuzzy matching
                switch name.lowercased() {
                case "urgent", "critical":
                    return .urgent
                case "high":
                    return .high
                case "medium", "normal":
                    return .medium
                case "low":
                    return .low
                default:
                    print("Unknown priority: \(name), setting to nil")
                    break
                }
            }
        }
        
        // Return nil if no priority is set
        return nil
    }
    
    private func extractDueDate(from properties: [String: Any]) -> Date? {
        // Try common due date property names
        let dueDateKeys = ["Due date", "Due Date", "Due", "due_date", "due", "Deadline", "deadline"]
        
        print("🔍 Looking for due date in properties: \(properties.keys.joined(separator: ", "))")
        
        for key in dueDateKeys {
            print("   Checking key: '\(key)'")
            if let dateProperty = properties[key] as? [String: Any] {
                print("   Found property '\(key)': \(dateProperty)")
                
                // Handle both null dates and date objects
                if let date = dateProperty["date"] as? [String: Any] {
                    print("   Date object found: \(date)")
                    if let start = date["start"] as? String {
                        print("   ✅ Found due date string: '\(start)'")
                        let parsedDate = extractDate(from: start)
                        print("   📅 Parsed date: \(parsedDate?.description ?? "failed to parse")")
                        return parsedDate
                    } else {
                        print("   ❌ Date object has no 'start' field")
                    }
                } else if dateProperty["date"] == nil || (dateProperty["date"] as? NSNull) != nil {
                    print("   ⚪ Property '\(key)' has null date - no due date set")
                    return nil
                } else {
                    print("   ❌ Property '\(key)' has unexpected date format: \(dateProperty["date"] ?? "nil")")
                }
            } else {
                print("   ❌ Property '\(key)' not found or not a dictionary")
            }
        }
        
        print("   ⚠️ No due date property found")
        return nil
    }
    
    private func extractDate(from dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        // Try ISO8601 first (for date-time formats)
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try date-only format (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }
        
        print("⚠️ Failed to parse date string: '\(dateString)'")
        return nil
    }
    
    private func saveTodosToSharedCache(_ todos: [TodoItem]) {
        if let data = try? JSONEncoder().encode(todos) {
            // Primary storage: App Groups (this is what the widget should read)
            if let sharedDefaults = UserDefaults(suiteName: "group.com.notiontodowidget.app") {
                sharedDefaults.set(data, forKey: "cachedTodos")
                print("App: Saved \(todos.count) todos to App Groups")
            } else {
                print("App: Failed to access App Groups UserDefaults")
            }
            
            // Fallback storage: Regular UserDefaults
            UserDefaults.standard.set(data, forKey: "cachedTodos")
            print("App: Saved \(todos.count) todos to regular UserDefaults")
        }
    }
    
    func updateTodoStatus(_ todo: TodoItem, status: TodoStatus) {
        // Update local copy immediately for responsive UI
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            let updatedTodo = TodoItem(
                id: todo.id,
                title: todo.title,
                status: status,
                dueDate: todo.dueDate,
                priority: todo.priority,
                createdAt: todo.createdAt,
                updatedAt: Date()
            )
            todos[index] = updatedTodo
            applyFiltersAndSorting()
            saveTodosToSharedCache(filteredTodos)
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        // Update in Notion asynchronously
        updateNotionTaskStatus(pageId: todo.id, status: status)
    }
    
    private func updateNotionTaskStatus(pageId: String, status: TodoStatus) {
        guard let apiKey = apiKey else {
            print("❌ No API key available for updating task")
            return
        }
        
        guard let url = URL(string: "https://api.notion.com/v1/pages/\(pageId)") else {
            print("❌ Invalid URL for page update")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use the actual property name from your database
        let updateBody: [String: Any] = [
            "properties": [
                "Status": [
                    "status": [
                        "name": status.rawValue
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateBody)
        } catch {
            print("❌ Failed to serialize update request: \(error)")
            return
        }
        
        print("🔄 Updating task \(pageId) to status: \(status.rawValue)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error updating task: \(error.localizedDescription)")
                    self.errorMessage = "Failed to update task: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ Successfully updated task \(pageId) to \(status.rawValue)")
                        self.statusUpdateMessage = "Task updated to \(status.rawValue)"
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.statusUpdateMessage = nil
                        }
                    } else {
                        print("❌ Failed to update task. Status code: \(httpResponse.statusCode)")
                        if let data = data,
                           let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorResponse["message"] as? String {
                            print("❌ Notion API error: \(message)")
                            self.errorMessage = "Failed to update task: \(message)"
                        } else {
                            self.errorMessage = "Failed to update task: HTTP \(httpResponse.statusCode)"
                        }
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Filtering and Sorting
    
    func applyFiltersAndSorting() {
        // First apply filters
        filteredTodos = todos.filter { todo in
            let statusMatch = statusFilter.contains(todo.status)
            let priorityMatch = todo.priority == nil || priorityFilter.contains(todo.priority!)
            return statusMatch && priorityMatch
        }
        
        // Then apply sorting
        filteredTodos.sort { todo1, todo2 in
            // Primary sort
            let primaryResult = compareTodos(todo1, todo2, by: sortConfiguration.primary)
            
            if primaryResult != .orderedSame {
                let ascending = sortConfiguration.primaryOrder == .ascending
                return ascending ? primaryResult == .orderedAscending : primaryResult == .orderedDescending
            }
            
            // Secondary sort (if primary is equal and secondary exists)
            if let secondary = sortConfiguration.secondary {
                let secondaryResult = compareTodos(todo1, todo2, by: secondary)
                let ascending = sortConfiguration.secondaryOrder == .ascending
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
    
    // MARK: - Filter Management
    
    func toggleStatusFilter(_ status: TodoStatus) {
        if statusFilter.contains(status) {
            statusFilter.remove(status)
        } else {
            statusFilter.insert(status)
        }
        PreferencesManager.shared.saveStatusFilter(statusFilter)
        applyFiltersAndSorting()
    }
    
    func togglePriorityFilter(_ priority: TodoPriority) {
        if priorityFilter.contains(priority) {
            priorityFilter.remove(priority)
        } else {
            priorityFilter.insert(priority)
        }
        PreferencesManager.shared.savePriorityFilter(priorityFilter)
        applyFiltersAndSorting()
    }
    
    func clearAllFilters() {
        statusFilter = Set(TodoStatus.allCases)
        priorityFilter = Set(TodoPriority.allCases)
        PreferencesManager.shared.saveStatusFilter(statusFilter)
        PreferencesManager.shared.savePriorityFilter(priorityFilter)
        applyFiltersAndSorting()
    }
    
    func setSortConfiguration(_ config: SortConfiguration) {
        sortConfiguration = config
        PreferencesManager.shared.saveSortConfiguration(config)
        applyFiltersAndSorting()
    }
    
    func setPrimarySort(_ option: SortOption, order: SortOrder) {
        sortConfiguration = SortConfiguration(
            primary: option,
            secondary: sortConfiguration.secondary,
            primaryOrder: order,
            secondaryOrder: sortConfiguration.secondaryOrder
        )
        PreferencesManager.shared.saveSortConfiguration(sortConfiguration)
        applyFiltersAndSorting()
    }
    
    func setSecondarySort(_ option: SortOption?, order: SortOrder) {
        sortConfiguration = SortConfiguration(
            primary: sortConfiguration.primary,
            secondary: option,
            primaryOrder: sortConfiguration.primaryOrder,
            secondaryOrder: order
        )
        PreferencesManager.shared.saveSortConfiguration(sortConfiguration)
        applyFiltersAndSorting()
    }
    
    func togglePrimarySortOrder() {
        let newOrder: SortOrder = sortConfiguration.primaryOrder == .ascending ? .descending : .ascending
        setPrimarySort(sortConfiguration.primary, order: newOrder)
    }
    
    func toggleSecondarySortOrder() {
        let newOrder: SortOrder = sortConfiguration.secondaryOrder == .ascending ? .descending : .ascending
        setSecondarySort(sortConfiguration.secondary, order: newOrder)
    }
}