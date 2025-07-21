import Foundation

class PreferencesManager {
    static let shared = PreferencesManager()
    
    private let suiteName = "group.com.nirneu.notiontodowidget"
    
    private init() {}
    
    // MARK: - Sort Configuration
    
    func saveSortConfiguration(_ config: SortConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            // Save to App Groups for widget access
            UserDefaults(suiteName: suiteName)?.set(data, forKey: "sortConfiguration")
            // Save to regular UserDefaults as fallback
            UserDefaults.standard.set(data, forKey: "sortConfiguration")
        }
    }
    
    func loadSortConfiguration() -> SortConfiguration {
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: suiteName),
           let data = sharedDefaults.data(forKey: "sortConfiguration"),
           let config = try? JSONDecoder().decode(SortConfiguration.self, from: data) {
            return config
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "sortConfiguration"),
           let config = try? JSONDecoder().decode(SortConfiguration.self, from: data) {
            return config
        }
        
        // Default configuration
        return SortConfiguration(primary: .dueDate, secondary: .priority)
    }
    
    // MARK: - Status Filter
    
    func saveStatusFilter(_ filter: Set<TodoStatus>) {
        if let data = try? JSONEncoder().encode(filter) {
            // Save to App Groups for widget access
            UserDefaults(suiteName: suiteName)?.set(data, forKey: "statusFilter")
            // Save to regular UserDefaults as fallback
            UserDefaults.standard.set(data, forKey: "statusFilter")
        }
    }
    
    func loadStatusFilter() -> Set<TodoStatus> {
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: suiteName),
           let data = sharedDefaults.data(forKey: "statusFilter"),
           let filter = try? JSONDecoder().decode(Set<TodoStatus>.self, from: data) {
            return filter
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "statusFilter"),
           let filter = try? JSONDecoder().decode(Set<TodoStatus>.self, from: data) {
            return filter
        }
        
        // Default to all statuses
        return Set(TodoStatus.allCases)
    }
    
    // MARK: - Priority Filter
    
    func savePriorityFilter(_ filter: Set<TodoPriority>) {
        if let data = try? JSONEncoder().encode(filter) {
            // Save to App Groups for widget access
            UserDefaults(suiteName: suiteName)?.set(data, forKey: "priorityFilter")
            // Save to regular UserDefaults as fallback
            UserDefaults.standard.set(data, forKey: "priorityFilter")
        }
    }
    
    func loadPriorityFilter() -> Set<TodoPriority> {
        // Try App Groups first
        if let sharedDefaults = UserDefaults(suiteName: suiteName),
           let data = sharedDefaults.data(forKey: "priorityFilter"),
           let filter = try? JSONDecoder().decode(Set<TodoPriority>.self, from: data) {
            return filter
        }
        
        // Fallback to regular UserDefaults
        if let data = UserDefaults.standard.data(forKey: "priorityFilter"),
           let filter = try? JSONDecoder().decode(Set<TodoPriority>.self, from: data) {
            return filter
        }
        
        // Default to all priorities
        return Set(TodoPriority.allCases)
    }
}