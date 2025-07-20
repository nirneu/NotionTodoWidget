import Foundation
import Combine
import WidgetKit

class NotionService: ObservableObject {
    static let shared = NotionService()
    
    @Published var isAuthenticated = false
    @Published var todos: [TodoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var databaseProperties: [String: Any] = [:]
    
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
        checkAuthenticationStatus()
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
                    self.todos = try self.parseNotionResponse(data)
                    // Cache the data for the widget
                    self.saveTodosToSharedCache(self.todos)
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
        
        var todos: [TodoItem] = []
        
        for result in results {
            guard let id = result["id"] as? String,
                  let properties = result["properties"] as? [String: Any] else {
                continue
            }
            
            // Extract title - try common property names
            let title = extractTitle(from: properties)
            
            // Extract status
            let status = extractStatus(from: properties)
            
            // Extract priority
            let priority = extractPriority(from: properties)
            
            // Extract due date
            let dueDate = extractDueDate(from: properties)
            
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
        
        for key in statusKeys {
            if let statusProperty = properties[key] as? [String: Any] {
                // Handle select property
                if let select = statusProperty["select"] as? [String: Any],
                   let name = select["name"] as? String {
                    
                    // First try exact match with our enum cases
                    if let status = TodoStatus(rawValue: name) {
                        return status
                    }
                    
                    // Fallback to fuzzy matching for common variations
                    switch name.lowercased() {
                    case "done", "completed", "complete":
                        return .completed
                    case "in progress", "doing", "started":
                        return .inProgress
                    case "not started", "todo", "to do":
                        return .notStarted
                    case "cancelled", "canceled":
                        return .cancelled
                    case "blocked":
                        return .blocked
                    case "research":
                        return .research
                    default:
                        // For any unknown status, default to not started
                        print("Unknown status: \(name), defaulting to 'Not started'")
                        return .notStarted
                    }
                }
                
                // Handle checkbox property
                if let checkbox = statusProperty["checkbox"] as? Bool {
                    return checkbox ? .completed : .notStarted
                }
            }
        }
        
        return .notStarted
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
        let dueDateKeys = ["Due Date", "Due", "due_date", "due", "Deadline", "deadline"]
        
        for key in dueDateKeys {
            if let dateProperty = properties[key] as? [String: Any],
               let date = dateProperty["date"] as? [String: Any],
               let start = date["start"] as? String {
                return extractDate(from: start)
            }
        }
        
        return nil
    }
    
    private func extractDate(from dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
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
        }
    }
}