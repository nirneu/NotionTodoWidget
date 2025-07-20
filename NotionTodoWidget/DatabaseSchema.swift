import Foundation

// MARK: - Database Schema Models

struct DatabaseSchema: Codable {
    let id: String
    let title: String
    let properties: [String: PropertyDefinition]
    
    var titleProperty: String? {
        // Find the title property (usually "Task name", "Name", "Title", etc.)
        return properties.first { $0.value.type == "title" }?.key
    }
    
    var statusProperty: (key: String, options: [String])? {
        // Find status/select properties with multiple options
        for (key, property) in properties {
            if property.type == "select", 
               let options = property.selectOptions,
               !options.isEmpty,
               key.lowercased().contains("status") {
                return (key, options.map { $0.name })
            }
        }
        return nil
    }
    
    var priorityProperty: (key: String, options: [String])? {
        // Find priority select properties
        for (key, property) in properties {
            if property.type == "select",
               let options = property.selectOptions,
               !options.isEmpty,
               key.lowercased().contains("priority") {
                return (key, options.map { $0.name })
            }
        }
        return nil
    }
    
    var dateProperties: [String] {
        return properties.compactMap { (key, property) in
            if property.type == "date" {
                return key
            }
            return nil
        }
    }
    
    var allSelectProperties: [(key: String, options: [String])] {
        return properties.compactMap { (key, property) in
            if property.type == "select",
               let options = property.selectOptions,
               !options.isEmpty {
                return (key, options.map { $0.name })
            }
            return nil
        }
    }
}

struct PropertyDefinition: Codable {
    let type: String
    let name: String
    let selectOptions: [SelectOption]?
    
    init(type: String, name: String, selectOptions: [SelectOption]? = nil) {
        self.type = type
        self.name = name
        self.selectOptions = selectOptions
    }
}

struct SelectOption: Codable {
    let id: String
    let name: String
    let color: String
}

// MARK: - Dynamic Todo Item

struct DynamicTodoItem: Codable, Identifiable, Equatable {
    let id: String
    let properties: [String: PropertyValue]
    let createdAt: Date
    let updatedAt: Date
    
    // Computed properties for common fields
    var title: String {
        // Try to find title from the most common property names
        let titleKeys = ["Task name", "Name", "Title", "Task", "name", "title", "task"]
        for key in titleKeys {
            if case .title(let value) = properties[key] {
                return value
            }
        }
        return "Untitled"
    }
    
    var status: String? {
        // Look for any select property that might be status
        for (key, value) in properties {
            if key.lowercased().contains("status"),
               case .select(let statusValue) = value {
                return statusValue
            }
        }
        return nil
    }
    
    var priority: String? {
        // Look for any select property that might be priority
        for (key, value) in properties {
            if key.lowercased().contains("priority"),
               case .select(let priorityValue) = value {
                return priorityValue
            }
        }
        return nil
    }
    
    var dueDate: Date? {
        // Look for any date property that might be due date
        let dueDateKeys = ["Due Date", "Due", "due_date", "due", "Deadline", "deadline"]
        for key in dueDateKeys {
            if case .date(let date) = properties[key] {
                return date
            }
        }
        return nil
    }
    
    // Get all select properties as key-value pairs
    var allSelectProperties: [(key: String, value: String)] {
        return properties.compactMap { (key, value) in
            if case .select(let selectValue) = value {
                return (key, selectValue)
            }
            return nil
        }
    }
    
    // Get all date properties as key-value pairs
    var allDateProperties: [(key: String, value: Date)] {
        return properties.compactMap { (key, value) in
            if case .date(let dateValue) = value {
                return (key, dateValue)
            }
            return nil
        }
    }
}

enum PropertyValue: Codable, Equatable {
    case title(String)
    case select(String)
    case date(Date)
    case text(String)
    case number(Double)
    case checkbox(Bool)
    case unknown
    
    enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "title":
            let value = try container.decode(String.self, forKey: .value)
            self = .title(value)
        case "select":
            let value = try container.decode(String.self, forKey: .value)
            self = .select(value)
        case "date":
            let value = try container.decode(Date.self, forKey: .value)
            self = .date(value)
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case "number":
            let value = try container.decode(Double.self, forKey: .value)
            self = .number(value)
        case "checkbox":
            let value = try container.decode(Bool.self, forKey: .value)
            self = .checkbox(value)
        default:
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .title(let value):
            try container.encode("title", forKey: .type)
            try container.encode(value, forKey: .value)
        case .select(let value):
            try container.encode("select", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value, forKey: .value)
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode("number", forKey: .type)
            try container.encode(value, forKey: .value)
        case .checkbox(let value):
            try container.encode("checkbox", forKey: .type)
            try container.encode(value, forKey: .value)
        case .unknown:
            try container.encode("unknown", forKey: .type)
        }
    }
}