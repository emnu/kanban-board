import Foundation

public struct Subtask: Identifiable, Codable, Hashable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

public struct Task: Identifiable, Codable, Hashable {
    public var id: UUID
    public var title: String
    public var description: String
    public var tags: [String]
    public var dueDate: Date?
    public var subtasks: [Subtask]
    public var isFlagged: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        tags: [String] = [],
        dueDate: Date? = nil,
        subtasks: [Subtask] = [],
        isFlagged: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.tags = tags
        self.dueDate = dueDate
        self.subtasks = subtasks
        self.isFlagged = isFlagged
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public var completionProgress: Double {
        guard !subtasks.isEmpty else { return 0.0 }
        let completed = subtasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(subtasks.count)
    }
}

// MARK: - HTML Stripper Utility
extension String {
    public var strippingHTML: String {
        var clean = self
        
        // 1. Remove style blocks and their contents
        let stylePattern = #"<style[^>]*>([\s\S]*?)<\/style>"#
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            let nsString = clean as NSString
            let range = NSRange(location: 0, length: nsString.length)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
        
        // 2. Remove head blocks and their contents
        let headPattern = #"<head[^>]*>([\s\S]*?)<\/head>"#
        if let regex = try? NSRegularExpression(pattern: headPattern, options: .caseInsensitive) {
            let nsString = clean as NSString
            let range = NSRange(location: 0, length: nsString.length)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
        
        // 3. Strip remaining HTML tags
        let tagPattern = #"<[^>]+>"#
        clean = clean.replacingOccurrences(of: tagPattern, with: "", options: .regularExpression, range: nil)
        
        // 4. Decode common HTML entities
        return clean
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Column: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var tasks: [Task]

    public init(id: UUID = UUID(), name: String, tasks: [Task] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

public struct Board: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var columns: [Column]

    public init(id: UUID = UUID(), name: String, columns: [Column] = []) {
        self.id = id
        self.name = name
        self.columns = columns
    }
}

public struct Note: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var content: String // Rich HTML text
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(id: UUID = UUID(), title: String, content: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct KanbanData: Codable {
    public var activeBoardId: UUID?
    public var boards: [Board]
    public var notes: [Note]
    public var lastSavedTimestamp: Double

    public init(activeBoardId: UUID? = nil, boards: [Board] = [], notes: [Note] = [], lastSavedTimestamp: Double = Date().timeIntervalSince1970) {
        self.activeBoardId = activeBoardId
        self.boards = boards
        self.notes = notes
        self.lastSavedTimestamp = lastSavedTimestamp
    }
    
    enum CodingKeys: String, CodingKey {
        case activeBoardId
        case boards
        case notes
        case lastSavedTimestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.activeBoardId = try container.decodeIfPresent(UUID.self, forKey: .activeBoardId)
        self.boards = try container.decode([Board].self, forKey: .boards)
        self.notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
        self.lastSavedTimestamp = try container.decode(Double.self, forKey: .lastSavedTimestamp)
    }
    
    public static var previewData: KanbanData {
        let board1 = Board(name: "Work Project", columns: [
            Column(name: "To Do", tasks: [
                Task(title: "Draft Project Proposal", description: "Outline key deliverables and timelines for the client.", tags: ["Writing", "High Priority"], subtasks: [
                    Subtask(title: "Research competitor models", isCompleted: true),
                    Subtask(title: "Draft executive summary", isCompleted: false),
                    Subtask(title: "Revise pricing tables", isCompleted: false)
                ]),
                Task(title: "Security Audit", description: "Verify OAuth2 endpoints and check file token security.", tags: ["Audit"], dueDate: Date().addingTimeInterval(86400 * 2))
            ]),
            Column(name: "In Progress", tasks: [
                Task(title: "Design Landing Page", description: "Create a modern landing page design with glassmorphism.", tags: ["Design", "UI/UX"], subtasks: [
                    Subtask(title: "Wireframing", isCompleted: true),
                    Subtask(title: "Figma design system", isCompleted: true),
                    Subtask(title: "User testing session 1", isCompleted: false)
                ])
            ]),
            Column(name: "Done", tasks: [
                Task(title: "Initialize Git Repo", description: "Create Kanban directory and configure basic ignore files.", tags: ["Dev"], createdAt: Date().addingTimeInterval(-86400))
            ])
        ])
        
        let board2 = Board(name: "Personal Life", columns: [
            Column(name: "Goals", tasks: [
                Task(title: "Read Swift Concurrency book", description: "Understand async/await and actors fully.", tags: ["Reading"]),
                Task(title: "Book vacation flights", description: "Trip to Tokyo planned for November.", tags: ["Travel"])
            ])
        ])
        
        return KanbanData(activeBoardId: board1.id, boards: [board1, board2])
    }
}
