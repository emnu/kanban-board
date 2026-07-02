import SwiftUI

struct ColumnView: View {
    @EnvironmentObject var store: KanbanStore
    var column: Column
    var searchText: String
    
    @State private var showingRenameDialog = false
    @State private var showingAddTaskSheet = false
    @State private var columnNameInput = ""
    @State private var isTargeted = false
    
    private var columnIndex: Int? {
        store.activeBoard?.columns.firstIndex(where: { $0.id == column.id })
    }
    
    private var isFirstColumn: Bool {
        columnIndex == 0
    }
    
    private var isLastColumn: Bool {
        guard let index = columnIndex, let count = store.activeBoard?.columns.count else { return true }
        return index == count - 1
    }
    
    // Filter tasks based on search text and optionally sort flagged ones to the top
    private var filteredTasks: [Task] {
        let baseTasks: [Task]
        if searchText.isEmpty {
            baseTasks = column.tasks
        } else {
            baseTasks = column.tasks.filter { task in
                task.title.localizedCaseInsensitiveContains(searchText) ||
                task.description.localizedCaseInsensitiveContains(searchText) ||
                task.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }
        
        if store.sortFlaggedToTop {
            return baseTasks.sorted { (t1, t2) -> Bool in
                if t1.isFlagged && !t2.isFlagged {
                    return true
                }
                if !t1.isFlagged && t2.isFlagged {
                    return false
                }
                return false // stable sort, preserve relative order
            }
        } else {
            return baseTasks
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Column Header
            HStack {
                Text(column.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(column.tasks.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlColor))
                    .clipShape(Capsule())
                
                Spacer()
                
                // Column Action Menu
                Menu {
                    Button("Rename Column") {
                        columnNameInput = column.name
                        showingRenameDialog = true
                    }
                    
                    Divider()
                    
                    Button("Move Column Left") {
                        store.moveColumnLeft(column.id)
                    }
                    .disabled(isFirstColumn)
                    
                    Button("Move Column Right") {
                        store.moveColumnRight(column.id)
                    }
                    .disabled(isLastColumn)
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        store.deleteColumn(column.id)
                    }) {
                        Text("Delete Column")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 8)
            
            // Add Task Button (placed at the top of the column for easy access)
            Button(action: {
                showingAddTaskSheet = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Card")
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            
            // Task List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(filteredTasks.enumerated()), id: \.element.id) { index, task in
                        CardView(task: task, columnId: column.id)
                            // Drag support
                            .draggable(task.id.uuidString)
                            // Drop support to reorder or insert before this card
                            .dropDestination(for: String.self) { items, location in
                                handleDrop(items: items, destIndex: index)
                            }
                    }
                    
                    // Empty drop area / spacer at bottom to allow dropping at the end of the column
                    Spacer(minLength: 40)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .dropDestination(for: String.self) { items, location in
                // Drop on column background/bottom appends to the end
                handleDrop(items: items, destIndex: column.tasks.count)
            } isTargeted: { targeted in
                isTargeted = targeted
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .sheet(isPresented: $showingRenameDialog) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Column")
                    .font(.headline)
                
                TextField("Column Name", text: $columnNameInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !columnNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameColumn(column.id, to: columnNameInput)
                            showingRenameDialog = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingRenameDialog = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Save") {
                        if !columnNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameColumn(column.id, to: columnNameInput)
                            showingRenameDialog = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(columnNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showingAddTaskSheet) {
            CardDetailView(columnId: column.id, task: nil)
        }
    }
    
    private func handleDrop(items: [String], destIndex: Int) -> Bool {
        guard let taskIdString = items.first,
              let taskId = UUID(uuidString: taskIdString),
              let board = store.activeBoard else { return false }
        
        // Locate source column
        guard let sourceColumn = board.columns.first(where: { col in
            col.tasks.contains(where: { $0.id == taskId })
        }) else { return false }
        
        store.moveTask(taskId, from: sourceColumn.id, to: column.id, atIndex: destIndex)
        return true
    }
}
