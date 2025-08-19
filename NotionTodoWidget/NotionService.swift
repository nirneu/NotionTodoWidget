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
    @Published var databases: [DatabaseConfiguration] = []
    @Published var activeDatabaseId: String?
    @Published var widgetDatabaseId: String?
    
    var apiKey: String? {
        get {
            UserDefaults.standard.string(forKey: "NotionAPIKey")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "NotionAPIKey")
        }
    }
    
    private var savedDatabases: [DatabaseConfiguration] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "NotionDatabases"),
                  let databases = try? JSONDecoder().decode([DatabaseConfiguration].self, from: data) else {
                return []
            }
            return databases
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "NotionDatabases")
            }
        }
    }
    
    private var activeDatabase: DatabaseConfiguration? {
        return databases.first { $0.isActive }
    }
    
    private var currentDatabaseId: String? {
        return activeDatabase?.databaseId
    }
    
    
    private init() {
        // Load persistent preferences first
        self.sortConfiguration = PreferencesManager.shared.loadSortConfiguration()
        self.statusFilter = PreferencesManager.shared.loadStatusFilter()
        self.priorityFilter = PreferencesManager.shared.loadPriorityFilter()
        
        // Load saved databases
        self.databases = savedDatabases
        self.activeDatabaseId = databases.first { $0.isActive }?.id
        self.widgetDatabaseId = PreferencesManager.shared.loadWidgetDatabaseId()
        
        checkAuthenticationStatus()
        // Apply initial filtering and sorting
        applyFiltersAndSorting()
    }
    
    // MARK: - Authentication
    
    func configure(apiKey: String) {
        self.apiKey = apiKey
        checkAuthenticationStatus()
        
        // If we become authenticated, immediately fetch schema then data
        if isAuthenticated {
            fetchDatabaseSchema()
            // Also cache data for all databases for widget usage
            cacheDataForAllDatabases()
        }
    }
    
    func checkAuthenticationStatus() {
        isAuthenticated = apiKey != nil && !databases.isEmpty && activeDatabase != nil
    }
    
    func signOut() {
        // Store database IDs before clearing for cleanup
        let databaseIds = databases.map { $0.databaseId }
        
        // Clear in-memory data
        apiKey = nil
        databases = []
        savedDatabases = []
        activeDatabaseId = nil
        isAuthenticated = false
        todos = []
        filteredTodos = []
        errorMessage = nil
        statusUpdateMessage = nil
        databaseProperties = [:]
        widgetDatabaseId = nil
        
        // COMPLETE PRIVACY CLEANUP - Clear ALL UserDefaults keys
        
        // 1. Clear API Key and Core Data
        UserDefaults.standard.removeObject(forKey: "NotionAPIKey")
        UserDefaults.standard.removeObject(forKey: "NotionDatabases")
        
        // 2. Clear User Preferences (sort, filters)
        UserDefaults.standard.removeObject(forKey: "sortConfiguration")
        UserDefaults.standard.removeObject(forKey: "statusFilter")
        UserDefaults.standard.removeObject(forKey: "priorityFilter")
        UserDefaults.standard.removeObject(forKey: "widgetDatabaseId")
        
        // 3. Clear Database Metadata
        UserDefaults.standard.removeObject(forKey: "currentDatabaseId")
        UserDefaults.standard.removeObject(forKey: "currentDatabaseName")
        UserDefaults.standard.removeObject(forKey: "savedDatabases")
        
        // 4. Clear All Cached Todos (general and database-specific)
        UserDefaults.standard.removeObject(forKey: "cachedTodos")
        for databaseId in databaseIds {
            let databaseSpecificKey = "cachedTodos_\(databaseId)"
            UserDefaults.standard.removeObject(forKey: databaseSpecificKey)
        }
        
        // 5. Clear ALL App Groups Data (used by widget)
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            // Clear user preferences
            sharedDefaults.removeObject(forKey: "sortConfiguration")
            sharedDefaults.removeObject(forKey: "statusFilter")
            sharedDefaults.removeObject(forKey: "priorityFilter")
            sharedDefaults.removeObject(forKey: "widgetDatabaseId")
            
            // Clear database metadata
            sharedDefaults.removeObject(forKey: "currentDatabaseId")
            sharedDefaults.removeObject(forKey: "currentDatabaseName")
            sharedDefaults.removeObject(forKey: "savedDatabases")
            
            // Clear all cached todos
            sharedDefaults.removeObject(forKey: "cachedTodos")
            for databaseId in databaseIds {
                let databaseSpecificKey = "cachedTodos_\(databaseId)"
                sharedDefaults.removeObject(forKey: databaseSpecificKey)
            }
            
            print("🔒 Privacy: Cleared ALL App Groups data")
        }
        
        // 6. Clear debug files from Documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let schemaFile = documentsPath.appendingPathComponent("notion_schema.json")
            let todosFile = documentsPath.appendingPathComponent("notion_todos.json")
            
            try? FileManager.default.removeItem(at: schemaFile)
            try? FileManager.default.removeItem(at: todosFile)
            print("🔒 Privacy: Cleared debug files from Documents directory")
        }
        
        // 7. Reset user preferences to defaults
        sortConfiguration = SortConfiguration(primary: .dueDate)
        statusFilter = Set(TodoStatus.allCases)
        priorityFilter = Set(TodoPriority.allCases)
        
        // 8. Force widget refresh to clear widget display
        WidgetCenter.shared.reloadAllTimelines()
        print("🔒 Privacy: Complete sign out - ALL user data cleared")
    }
    
    // MARK: - Database Management
    
    func fetchDatabaseInfo(databaseId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey = apiKey else {
            completion(.failure(NSError(domain: "NotionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No API key"])))
            return
        }
        
        guard let url = URL(string: "https://api.notion.com/v1/databases/\(databaseId)") else {
            completion(.failure(NSError(domain: "NotionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "NotionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? [[String: Any]] {
                    
                    // Extract the database name from the title array
                    var databaseName = "Untitled Database"
                    if let firstTitle = title.first,
                       let plainText = firstTitle["plain_text"] as? String,
                       !plainText.isEmpty {
                        databaseName = plainText
                    }
                    
                    DispatchQueue.main.async {
                        completion(.success(databaseName))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "NotionService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func fetchAvailableDatabases(completion: @escaping (Result<[(id: String, name: String)], Error>) -> Void) {
        guard let apiKey = apiKey else {
            completion(.failure(NSError(domain: "NotionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No API key"])))
            return
        }
        
        guard let url = URL(string: "https://api.notion.com/v1/search") else {
            completion(.failure(NSError(domain: "NotionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Search for databases only
        let searchBody: [String: Any] = [
            "query": "",
            "filter": [
                "value": "database",
                "property": "object"
            ] as [String: Any]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: searchBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "NotionService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]] {
                    
                    var allDatabases: [(id: String, name: String)] = []
                    
                    // First, collect all database IDs and names
                    for result in results {
                        if let id = result["id"] as? String,
                           let title = result["title"] as? [[String: Any]],
                           let firstTitle = title.first,
                           let plainText = firstTitle["plain_text"] as? String {
                            allDatabases.append((id: id, name: plainText.isEmpty ? "Untitled Database" : plainText))
                        }
                    }
                    
                    // Now filter databases by checking their properties for task-related fields
                    self.filterTaskDatabases(databases: allDatabases, completion: completion)
                    
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "NotionService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func filterTaskDatabases(databases: [(id: String, name: String)], completion: @escaping (Result<[(id: String, name: String)], Error>) -> Void) {
        let group = DispatchGroup()
        var taskDatabases: [(id: String, name: String)] = []
        let queue = DispatchQueue(label: "database-filter", attributes: .concurrent)
        
        for database in databases {
            group.enter()
            queue.async {
                self.checkIfTaskDatabase(databaseId: database.id) { isTaskDB in
                    if isTaskDB {
                        taskDatabases.append(database)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: DispatchQueue.main) {
            completion(.success(taskDatabases))
        }
    }
    
    private func checkIfTaskDatabase(databaseId: String, completion: @escaping (Bool) -> Void) {
        guard let apiKey = apiKey else {
            completion(false)
            return
        }
        
        guard let url = URL(string: "https://api.notion.com/v1/databases/\(databaseId)") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let properties = json["properties"] as? [String: Any] else {
                completion(false)
                return
            }
            
            // Check for task-related properties
            let isTaskDatabase = self.containsTaskProperties(properties: properties)
            completion(isTaskDatabase)
        }.resume()
    }
    
    private func containsTaskProperties(properties: [String: Any]) -> Bool {
        // Define task-related property names and types
        let taskPropertyNames = [
            "status", "state", "done", "complete", "progress", "task", "todo", "priority", 
            "due", "deadline", "date", "finish", "start", "end", "assignee", "assigned"
        ]
        
        let taskPropertyTypes = ["status", "select", "date", "people", "checkbox"]
        
        var foundTaskProperties = 0
        
        for (propertyName, propertyData) in properties {
            guard let propertyInfo = propertyData as? [String: Any],
                  let propertyType = propertyInfo["type"] as? String else {
                continue
            }
            
            let lowercaseName = propertyName.lowercased()
            
            // Check if property name suggests it's task-related
            let hasTaskName = taskPropertyNames.contains { taskName in
                lowercaseName.contains(taskName)
            }
            
            // Check if property type is commonly used in task databases
            let hasTaskType = taskPropertyTypes.contains(propertyType)
            
            if hasTaskName && hasTaskType {
                foundTaskProperties += 1
            }
            
            // Special case: Status property with task-like options
            if propertyType == "status" || (propertyType == "select" && lowercaseName.contains("status")) {
                foundTaskProperties += 2 // Status is a strong indicator
            }
        }
        
        // Consider it a task database if it has at least 2 task-related properties
        return foundTaskProperties >= 2
    }
    
    func addDatabase(name: String, databaseId: String) {
        let newDatabase = DatabaseConfiguration(
            name: name, 
            databaseId: databaseId, 
            isActive: databases.isEmpty
        )
        databases.append(newDatabase)
        savedDatabases = databases
        
        if databases.count == 1 {
            activeDatabaseId = newDatabase.id
        }
        
        checkAuthenticationStatus()
        
        if isAuthenticated {
            fetchDatabaseSchema()
            // Also cache data for all databases for widget usage
            cacheDataForAllDatabases()
        }
    }
    
    func removeDatabase(_ database: DatabaseConfiguration) {
        databases.removeAll { $0.id == database.id }
        
        // Clean up cached data for the removed database
        let databaseSpecificKey = "cachedTodos_\(database.databaseId)"
        if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
            sharedDefaults.removeObject(forKey: databaseSpecificKey)
        }
        UserDefaults.standard.removeObject(forKey: databaseSpecificKey)
        print("🗑️ Cleaned up cached data for removed database: \(database.name)")
        
        // If we removed the active database, set the first one as active
        if database.isActive && !databases.isEmpty {
            databases[0] = DatabaseConfiguration(
                id: databases[0].id,
                name: databases[0].name,
                databaseId: databases[0].databaseId,
                isActive: true,
                createdAt: databases[0].createdAt
            )
            activeDatabaseId = databases[0].id
        } else if database.isActive {
            activeDatabaseId = nil
        }
        
        savedDatabases = databases
        checkAuthenticationStatus()
        
        if isAuthenticated {
            fetchDatabaseSchema()
            // Also cache data for all remaining databases for widget usage
            cacheDataForAllDatabases()
        }
    }
    
    func updateDatabase(_ database: DatabaseConfiguration, name: String, databaseId: String) {
        // Clean up old cached data if database ID changed
        if database.databaseId != databaseId {
            let oldDatabaseSpecificKey = "cachedTodos_\(database.databaseId)"
            if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
                sharedDefaults.removeObject(forKey: oldDatabaseSpecificKey)
            }
            UserDefaults.standard.removeObject(forKey: oldDatabaseSpecificKey)
            print("🗑️ Cleaned up old cached data for database: \(database.name)")
        }
        
        // Update the database in the array
        if let index = databases.firstIndex(where: { $0.id == database.id }) {
            databases[index] = DatabaseConfiguration(
                id: database.id,
                name: name,
                databaseId: databaseId,
                isActive: database.isActive,
                createdAt: database.createdAt
            )
            
            // Update activeDatabaseId if this was the active database
            if database.isActive {
                activeDatabaseId = database.id
            }
            
            savedDatabases = databases
            print("✏️ Updated database: \(database.name) -> \(name)")
            
            // If authenticated and this is the active database, refresh data
            if isAuthenticated {
                if database.isActive {
                    fetchDatabaseSchema()
                }
                // Also cache data for all databases for widget usage
                cacheDataForAllDatabases()
            }
        }
    }
    
    func setActiveDatabase(_ database: DatabaseConfiguration) {
        // Deactivate all databases
        databases = databases.map { db in
            DatabaseConfiguration(
                id: db.id,
                name: db.name,
                databaseId: db.databaseId,
                isActive: db.id == database.id,
                createdAt: db.createdAt
            )
        }
        
        activeDatabaseId = database.id
        savedDatabases = databases
        
        // Immediately save current database info for widget access
        saveCurrentDatabaseInfo()
        
        checkAuthenticationStatus()
        
        if isAuthenticated {
            fetchDatabaseSchema()
            // Also ensure all databases have cached data for widget usage
            cacheDataForAllDatabases()
        }
    }
    
    private func saveCurrentDatabaseInfo() {
        // Save current database info to both App Groups and regular UserDefaults
        if let currentDb = activeDatabase {
            // App Groups UserDefaults for widget access
            if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
                sharedDefaults.set(currentDb.databaseId, forKey: "currentDatabaseId")
                sharedDefaults.set(currentDb.name, forKey: "currentDatabaseName")
                
                // Also save all databases for widget database selection
                if let data = try? JSONEncoder().encode(databases) {
                    sharedDefaults.set(data, forKey: "savedDatabases")
                }
                
                print("App: Saved current database info to App Groups: \(currentDb.name)")
            }
            
            // Regular UserDefaults as fallback
            UserDefaults.standard.set(currentDb.databaseId, forKey: "currentDatabaseId")
            UserDefaults.standard.set(currentDb.name, forKey: "currentDatabaseName")
            
            // Also save all databases for widget database selection
            if let data = try? JSONEncoder().encode(databases) {
                UserDefaults.standard.set(data, forKey: "savedDatabases")
            }
            
            print("App: Saved current database info to regular UserDefaults: \(currentDb.name)")
        }
        
        // Force widget refresh
        WidgetCenter.shared.reloadAllTimelines()
        print("App: Forced widget timeline refresh after database change")
    }
    
    func setWidgetDatabase(_ database: DatabaseConfiguration?) {
        widgetDatabaseId = database?.databaseId
        PreferencesManager.shared.saveWidgetDatabaseId(database?.databaseId)
        
        // Force widget refresh to reflect the change
        WidgetCenter.shared.reloadAllTimelines()
        print("App: Widget database changed to: \(database?.name ?? "none"), forced widget refresh")
    }
    
    // MARK: - Data Operations
    
    func fetchAndCacheDataForDatabase(_ databaseId: String) {
        guard let apiKey = apiKey else {
            print("❌ No API key available for fetching database data")
            return
        }
        
        print("🔄 Fetching data for database: \(databaseId)")
        
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
            print("❌ Failed to create request: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error fetching database data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("❌ No data received for database")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    print("❌ HTTP error fetching database data: \(httpResponse.statusCode)")
                    return
                }
            }
            
            do {
                let fetchedTodos = try self.parseNotionResponse(data)
                
                // Apply current user's filters and sorting to the fetched data
                let filteredAndSortedTodos = self.applyFiltersAndSorting(to: fetchedTodos)
                
                // Cache the filtered and sorted data with database-specific key
                if let encodedData = try? JSONEncoder().encode(filteredAndSortedTodos) {
                    let databaseSpecificKey = "cachedTodos_\(databaseId)"
                    
                    // Save to App Groups
                    if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
                        sharedDefaults.set(encodedData, forKey: databaseSpecificKey)
                        print("✅ Cached \(filteredAndSortedTodos.count) filtered/sorted todos for database \(databaseId) in App Groups (from \(fetchedTodos.count) raw todos)")
                    }
                    
                    // Save to regular UserDefaults as fallback
                    UserDefaults.standard.set(encodedData, forKey: databaseSpecificKey)
                    print("✅ Cached \(filteredAndSortedTodos.count) filtered/sorted todos for database \(databaseId) in UserDefaults")
                    
                    // Trigger widget refresh
                    DispatchQueue.main.async {
                        WidgetCenter.shared.reloadAllTimelines()
                        print("🔄 Triggered widget refresh for database change")
                    }
                }
            } catch {
                print("❌ Failed to parse database response: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func cacheDataForAllDatabases() {
        print("🔄 Caching data for all configured databases...")
        for database in databases {
            // Don't fetch for the active database since it's already being fetched
            if database.id != activeDatabaseId {
                print("🔄 Fetching data for database: \(database.name)")
                fetchAndCacheDataForDatabase(database.databaseId)
            }
        }
    }
    
    // Method to refresh cached data for all databases with current filter/sort preferences
    private func refreshCachedDataForAllDatabases() {
        print("🔄 Refreshing cached data for all databases with current preferences...")
        for database in databases {
            print("🔄 Re-fetching data for database: \(database.name)")
            fetchAndCacheDataForDatabase(database.databaseId)
        }
    }
    
    func fetchDatabaseSchema() {
        guard let apiKey = apiKey, let databaseId = currentDatabaseId else {
            errorMessage = "API key or active database not configured"
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
        guard let apiKey = apiKey, let databaseId = currentDatabaseId else {
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
            if let sharedDefaults = UserDefaults(suiteName: "group.com.nirneu.notiontodowidget") {
                // Save to general cache for backward compatibility
                sharedDefaults.set(data, forKey: "cachedTodos")
                
                // Save to database-specific cache for widget configuration support
                if let currentDb = activeDatabase {
                    let databaseSpecificKey = "cachedTodos_\(currentDb.databaseId)"
                    sharedDefaults.set(data, forKey: databaseSpecificKey)
                    sharedDefaults.set(currentDb.databaseId, forKey: "currentDatabaseId")
                    sharedDefaults.set(currentDb.name, forKey: "currentDatabaseName")
                    print("App: Saved \(todos.count) todos to App Groups with key: \(databaseSpecificKey)")
                }
                
                print("App: Saved \(todos.count) todos to App Groups from \(activeDatabase?.name ?? "unknown") database")
            } else {
                print("App: Failed to access App Groups UserDefaults")
            }
            
            // Fallback storage: Regular UserDefaults
            UserDefaults.standard.set(data, forKey: "cachedTodos")
            if let currentDb = activeDatabase {
                let databaseSpecificKey = "cachedTodos_\(currentDb.databaseId)"
                UserDefaults.standard.set(data, forKey: databaseSpecificKey)
                UserDefaults.standard.set(currentDb.databaseId, forKey: "currentDatabaseId")
                UserDefaults.standard.set(currentDb.name, forKey: "currentDatabaseName")
            }
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
        updateNotionTask(pageId: todo.id, status: status, priority: todo.priority)
    }
    
    func updateTodoPriority(_ todo: TodoItem, priority: TodoPriority) {
        // Update local copy immediately for responsive UI
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            let updatedTodo = TodoItem(
                id: todo.id,
                title: todo.title,
                status: todo.status,
                dueDate: todo.dueDate,
                priority: priority,
                createdAt: todo.createdAt,
                updatedAt: Date()
            )
            todos[index] = updatedTodo
            applyFiltersAndSorting()
            saveTodosToSharedCache(filteredTodos)
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        // Update in Notion asynchronously
        updateNotionTask(pageId: todo.id, status: todo.status, priority: priority)
    }
    
    func updateTodoDueDate(_ todo: TodoItem, dueDate: Date?) {
        // Update local copy immediately for responsive UI
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            let updatedTodo = TodoItem(
                id: todo.id,
                title: todo.title,
                status: todo.status,
                dueDate: dueDate,
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
        updateNotionTaskDueDate(pageId: todo.id, dueDate: dueDate)
    }
    
    func updateTodoTitle(_ todo: TodoItem, title: String) {
        // Update local copy immediately for responsive UI
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            let updatedTodo = TodoItem(
                id: todo.id,
                title: title,
                status: todo.status,
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
        updateNotionTaskTitle(pageId: todo.id, title: title)
    }
    
    private func updateNotionTask(pageId: String, status: TodoStatus, priority: TodoPriority?) {
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
        
        // Build properties to update
        var properties: [String: Any] = [
            "Status": [
                "status": [
                    "name": status.rawValue
                ]
            ]
        ]
        
        // Add priority if provided
        if let priority = priority {
            properties["Priority"] = [
                "select": [
                    "name": priority.rawValue
                ]
            ]
        }
        
        let updateBody: [String: Any] = [
            "properties": properties
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
    
    private func updateNotionTaskDueDate(pageId: String, dueDate: Date?) {
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
        
        // Build due date property
        let dueDateProperty: Any
        if let dueDate = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dueDateProperty = [
                "date": [
                    "start": formatter.string(from: dueDate)
                ]
            ]
        } else {
            dueDateProperty = NSNull()
        }
        
        let updateBody: [String: Any] = [
            "properties": [
                "Due date": dueDateProperty
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateBody)
        } catch {
            print("❌ Failed to serialize due date update request: \(error)")
            return
        }
        
        print("🔄 Updating task \(pageId) due date to: \(dueDate?.description ?? "nil")")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error updating due date: \(error.localizedDescription)")
                    self.errorMessage = "Failed to update due date: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ Successfully updated due date for task \(pageId)")
                        self.statusUpdateMessage = "Due date updated"
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.statusUpdateMessage = nil
                        }
                    } else {
                        print("❌ Failed to update due date. Status code: \(httpResponse.statusCode)")
                        if let data = data,
                           let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorResponse["message"] as? String {
                            print("❌ Notion API error: \(message)")
                            self.errorMessage = "Failed to update due date: \(message)"
                        } else {
                            self.errorMessage = "Failed to update due date: HTTP \(httpResponse.statusCode)"
                        }
                    }
                }
            }
        }.resume()
    }
    
    private func updateNotionTaskTitle(pageId: String, title: String) {
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
        
        // Build title property - try different possible title property names
        let updateBody: [String: Any] = [
            "properties": [
                "Task name": [
                    "title": [
                        [
                            "text": [
                                "content": title
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateBody)
        } catch {
            print("❌ Failed to serialize title update request: \(error)")
            return
        }
        
        print("🔄 Updating task \(pageId) title to: '\(title)'")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Network error updating title: \(error.localizedDescription)")
                    self.errorMessage = "Failed to update title: \(error.localizedDescription)"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ Successfully updated title for task \(pageId)")
                        self.statusUpdateMessage = "Title updated"
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            self.statusUpdateMessage = nil
                        }
                    } else {
                        print("❌ Failed to update title. Status code: \(httpResponse.statusCode)")
                        if let data = data,
                           let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorResponse["message"] as? String {
                            print("❌ Notion API error: \(message)")
                            self.errorMessage = "Failed to update title: \(message)"
                        } else {
                            self.errorMessage = "Failed to update title: HTTP \(httpResponse.statusCode)"
                        }
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Filtering and Sorting
    
    func applyFiltersAndSorting() {
        filteredTodos = applyFiltersAndSorting(to: todos)
    }
    
    // Generic method to apply current filters and sorting to any todo array
    func applyFiltersAndSorting(to todos: [TodoItem]) -> [TodoItem] {
        // First apply filters
        var filtered = todos.filter { todo in
            let statusMatch = statusFilter.contains(todo.status)
            let priorityMatch = todo.priority == nil || priorityFilter.contains(todo.priority!)
            return statusMatch && priorityMatch
        }
        
        // Then apply sorting
        filtered.sort { todo1, todo2 in
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
        
        return filtered
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
        // Update widget with new filtered data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new filter preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func togglePriorityFilter(_ priority: TodoPriority) {
        if priorityFilter.contains(priority) {
            priorityFilter.remove(priority)
        } else {
            priorityFilter.insert(priority)
        }
        PreferencesManager.shared.savePriorityFilter(priorityFilter)
        applyFiltersAndSorting()
        // Update widget with new filtered data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new filter preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func clearAllFilters() {
        statusFilter = Set(TodoStatus.allCases)
        priorityFilter = Set(TodoPriority.allCases)
        PreferencesManager.shared.saveStatusFilter(statusFilter)
        PreferencesManager.shared.savePriorityFilter(priorityFilter)
        applyFiltersAndSorting()
        // Update widget with new filtered data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new filter preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func setSortConfiguration(_ config: SortConfiguration) {
        sortConfiguration = config
        PreferencesManager.shared.saveSortConfiguration(config)
        applyFiltersAndSorting()
        // Update widget with new sorted data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new sort preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
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
        // Update widget with new sorted data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new sort preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
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
        // Update widget with new sorted data
        saveTodosToSharedCache(filteredTodos)
        // Also refresh cached data for all databases with new sort preferences
        refreshCachedDataForAllDatabases()
        WidgetCenter.shared.reloadAllTimelines()
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