import Foundation
import Combine

public class KanbanStore: ObservableObject {
    @Published public var kanbanData: KanbanData = KanbanData()
    @Published public var activeBoard: Board? = nil
    @Published public var sortFlaggedToTop: Bool = false
    
    private var remoteFileId: String? = nil
    private var cancellables = Set<AnyCancellable>()
    private var syncDebounceTimer: AnyCancellable? = nil
    
    private var localFileURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirURL = appSupportURL.appendingPathComponent("com.kanbanapp")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appDirURL.path) {
            try? fileManager.createDirectory(at: appDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return appDirURL.appendingPathComponent("kanban_board_data.json")
    }
    
    public init() {
        loadLocalData()
        
        // Listen to Google Drive auth status changes to trigger a sync once logged in
        GoogleDriveSync.shared.$status
            .sink { [weak self] status in
                if status == .offline || status == .synced {
                    // Trigger sync when sync engine becomes available or logs in
                    self?.triggerSync()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Local Persistence
    
    public func loadLocalData() {
        let fileURL = localFileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(KanbanData.self, from: data)
                self.kanbanData = decoded
                
                // Set active board
                if let activeId = decoded.activeBoardId {
                    self.activeBoard = decoded.boards.first(where: { $0.id == activeId })
                }
                
                if self.activeBoard == nil {
                    self.activeBoard = decoded.boards.first
                }
            } catch {
                print("Error loading local data: \(error)")
                loadPreviewData()
            }
        } else {
            loadPreviewData()
        }
    }
    
    private func loadPreviewData() {
        self.kanbanData = KanbanData.previewData
        self.activeBoard = self.kanbanData.boards.first(where: { $0.id == self.kanbanData.activeBoardId })
        saveLocalData()
    }
    
    public func saveLocalData() {
        // Update modification timestamp
        kanbanData.lastSavedTimestamp = Date().timeIntervalSince1970
        kanbanData.activeBoardId = activeBoard?.id
        
        // Update board array to ensure current active board details are synchronized
        if let activeBoard = activeBoard,
           let index = kanbanData.boards.firstIndex(where: { $0.id == activeBoard.id }) {
            kanbanData.boards[index] = activeBoard
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(kanbanData)
            try data.write(to: localFileURL, options: .atomic)
        } catch {
            print("Error saving local data: \(error)")
        }
    }
    
    // Call this whenever user modifies data (drag/drop, edits, additions)
    public func dataChanged() {
        saveLocalData()
        scheduleSyncDebounce()
    }
    
    private func scheduleSyncDebounce() {
        syncDebounceTimer?.cancel()
        syncDebounceTimer = Just(())
            .delay(for: .seconds(2.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.triggerSync()
            }
    }
    
    // MARK: - Synchronisation Engine
    
    public func triggerSync() {
        guard GoogleDriveSync.shared.hasSavedCredentials() else { return }
        
        _Concurrency.Task {
            let (remoteData, fileId) = await GoogleDriveSync.shared.fetchRemoteData()
            
            // Store remote file id if found
            if let fileId = fileId {
                await MainActor.run {
                    self.remoteFileId = fileId
                }
            }
            
            guard let remote = remoteData else {
                // Remote file does not exist on Drive, upload current local state
                _ = await GoogleDriveSync.shared.uploadData(self.kanbanData, fileId: self.remoteFileId)
                return
            }
            
            // Compare timestamps
            await MainActor.run {
                if remote.lastSavedTimestamp > self.kanbanData.lastSavedTimestamp {
                    // Remote is newer: Pull remote changes
                    self.kanbanData = remote
                    if let activeId = remote.activeBoardId {
                        self.activeBoard = remote.boards.first(where: { $0.id == activeId })
                    }
                    if self.activeBoard == nil {
                        self.activeBoard = remote.boards.first
                    }
                    
                    // Save pulled data locally
                    let fileURL = self.localFileURL
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    if let data = try? encoder.encode(remote) {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                } else if self.kanbanData.lastSavedTimestamp > remote.lastSavedTimestamp {
                    // Local is newer: Push local changes
                    _Concurrency.Task {
                        _ = await GoogleDriveSync.shared.uploadData(self.kanbanData, fileId: self.remoteFileId)
                    }
                } else {
                    // Timestamps are equal, already in sync
                    GoogleDriveSync.shared.status = .synced
                }
            }
        }
    }
    
    // MARK: - Board Management
    
    public func addBoard(name: String) {
        let newBoard = Board(name: name, columns: [
            Column(name: "To Do"),
            Column(name: "In Progress"),
            Column(name: "Done")
        ])
        kanbanData.boards.append(newBoard)
        activeBoard = newBoard
        dataChanged()
    }
    
    public func deleteBoard(_ board: Board) {
        guard kanbanData.boards.count > 1 else { return } // Keep at least one board
        kanbanData.boards.removeAll(where: { $0.id == board.id })
        if activeBoard?.id == board.id {
            activeBoard = kanbanData.boards.first
        }
        dataChanged()
    }
    
    // MARK: - Column Management
    
    public func addColumn(name: String) {
        guard var board = activeBoard else { return }
        let newColumn = Column(name: name)
        board.columns.append(newColumn)
        activeBoard = board
        dataChanged()
    }
    
    public func renameColumn(_ columnId: UUID, to newName: String) {
        guard var board = activeBoard,
              let index = board.columns.firstIndex(where: { $0.id == columnId }) else { return }
        board.columns[index].name = newName
        activeBoard = board
        dataChanged()
    }
    
    public func deleteColumn(_ columnId: UUID) {
        guard var board = activeBoard else { return }
        board.columns.removeAll(where: { $0.id == columnId })
        activeBoard = board
        dataChanged()
    }
    
    public func moveColumnLeft(_ columnId: UUID) {
        guard var board = activeBoard,
              let index = board.columns.firstIndex(where: { $0.id == columnId }),
              index > 0 else { return }
        let col = board.columns.remove(at: index)
        board.columns.insert(col, at: index - 1)
        activeBoard = board
        dataChanged()
    }
    
    public func moveColumnRight(_ columnId: UUID) {
        guard var board = activeBoard,
              let index = board.columns.firstIndex(where: { $0.id == columnId }),
              index < board.columns.count - 1 else { return }
        let col = board.columns.remove(at: index)
        board.columns.insert(col, at: index + 1)
        activeBoard = board
        dataChanged()
    }
    
    // MARK: - Task Management
    
    public func saveTask(_ task: Task, toColumnId columnId: UUID) {
        guard var board = activeBoard,
              let colIndex = board.columns.firstIndex(where: { $0.id == columnId }) else { return }
        
        var column = board.columns[colIndex]
        if let taskIndex = column.tasks.firstIndex(where: { $0.id == task.id }) {
            // Update existing task
            var updatedTask = task
            updatedTask.updatedAt = Date()
            column.tasks[taskIndex] = updatedTask
        } else {
            // Add new task
            column.tasks.append(task)
        }
        
        board.columns[colIndex] = column
        activeBoard = board
        dataChanged()
    }
    
    public func deleteTask(id: UUID, fromColumnId columnId: UUID) {
        guard var board = activeBoard,
              let colIndex = board.columns.firstIndex(where: { $0.id == columnId }) else { return }
        
        board.columns[colIndex].tasks.removeAll(where: { $0.id == id })
        activeBoard = board
        dataChanged()
    }
    
    public func moveTask(_ taskId: UUID, from sourceColId: UUID, to destColId: UUID, atIndex destIndex: Int) {
        guard var board = activeBoard,
              let sourceColIndex = board.columns.firstIndex(where: { $0.id == sourceColId }),
              let destColIndex = board.columns.firstIndex(where: { $0.id == destColId }) else { return }
        
        var sourceCol = board.columns[sourceColIndex]
        guard let taskIndex = sourceCol.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        
        var task = sourceCol.tasks.remove(at: taskIndex)
        task.updatedAt = Date()
        board.columns[sourceColIndex] = sourceCol
        
        var destCol = board.columns[destColIndex]
        let insertIndex = min(max(0, destIndex), destCol.tasks.count)
        destCol.tasks.insert(task, at: insertIndex)
        board.columns[destColIndex] = destCol
        
        activeBoard = board
        dataChanged()
    }
    
    public func toggleFlag(for taskId: UUID, inColumnId columnId: UUID) {
        guard var board = activeBoard,
              let colIndex = board.columns.firstIndex(where: { $0.id == columnId }) else { return }
        
        var column = board.columns[colIndex]
        if let taskIndex = column.tasks.firstIndex(where: { $0.id == taskId }) {
            column.tasks[taskIndex].isFlagged.toggle()
            column.tasks[taskIndex].updatedAt = Date()
            board.columns[colIndex] = column
            activeBoard = board
            dataChanged()
        }
    }
}
