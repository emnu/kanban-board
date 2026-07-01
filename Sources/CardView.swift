import SwiftUI

struct CardView: View {
    @EnvironmentObject var store: KanbanStore
    var task: Task
    var columnId: UUID
    
    @State private var showingEditSheet = false
    @State private var isHovering = false
    
    private var isOverdue: Bool {
        guard let dueDate = task.dueDate else { return false }
        return dueDate < Date() && !isCompletedColumn
    }
    
    private var isCompletedColumn: Bool {
        // Try to identify if the current column is a "Done" or "Completed" column
        guard let board = store.activeBoard,
              let col = board.columns.first(where: { $0.id == columnId }) else { return false }
        let name = col.name.lowercased()
        return name == "done" || name == "completed" || name == "archive"
    }
    
    private var formattedDueDate: String {
        guard let date = task.dueDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Task Header (Title + Icons)
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Show due date indicator if overdue or pending
                    if task.dueDate != nil {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(isOverdue ? .red : .secondary)
                    }
                    
                    // Outlook-style Flag Button
                    Button(action: {
                        store.toggleFlag(for: task.id, inColumnId: columnId)
                    }) {
                        Image(systemName: task.isFlagged ? "flag.fill" : "flag")
                            .font(.system(size: 12))
                            .foregroundColor(task.isFlagged ? .red : (isHovering ? .secondary : .clear))
                    }
                    .buttonStyle(.plain)
                    .help(task.isFlagged ? "Unflag task" : "Flag task")
                }
            }
            
            // Task Description Snippet
            let cleanDescription = task.description.strippingHTML
            if !cleanDescription.isEmpty {
                Text(cleanDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            // Subtask Progress Bar
            if !task.subtasks.isEmpty {
                let completedCount = task.subtasks.filter { $0.isCompleted }.count
                let totalCount = task.subtasks.count
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(completedCount)/\(totalCount) subtasks")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(task.completionProgress * 100))%")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: task.completionProgress)
                        .tint(task.completionProgress == 1.0 ? .green : .accentColor)
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                }
                .padding(.top, 2)
            }
            
            // Tags & Metadata Row
            if !task.tags.isEmpty || task.dueDate != nil {
                HStack(alignment: .center, spacing: 6) {
                    // Due Date Badge
                    if let _ = task.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(formattedDueDate)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isOverdue ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15))
                        .foregroundColor(isOverdue ? .red : .secondary)
                        .cornerRadius(4)
                    }
                    
                    // Tag badges (limit to 2 tags to avoid overflow)
                    ForEach(task.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tagColor(tag).opacity(0.15))
                            .foregroundColor(tagColor(tag))
                            .cornerRadius(4)
                    }
                    
                    if task.tags.count > 2 {
                        Text("+\(task.tags.count - 2)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 4 : 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovering ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            showingEditSheet = true
        }
        .contextMenu {
            Button("Edit Card") {
                showingEditSheet = true
            }
            
            Menu("Move to Column") {
                if let board = store.activeBoard {
                    ForEach(board.columns.filter { $0.id != columnId }) { destCol in
                        Button(destCol.name) {
                            store.moveTask(task.id, from: columnId, to: destCol.id, atIndex: destCol.tasks.count)
                        }
                    }
                }
            }
            
            Button(task.isFlagged ? "Unflag Task" : "Flag Task") {
                store.toggleFlag(for: task.id, inColumnId: columnId)
            }
            
            Divider()
            
            Button(role: .destructive, action: {
                store.deleteTask(id: task.id, fromColumnId: columnId)
            }) {
                Label("Delete Card", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CardDetailView(columnId: columnId, task: task)
        }
    }
    
    // Generate deterministic colors for tags
    private func tagColor(_ tag: String) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo]
        let hash = abs(tag.hashValue)
        return colors[hash % colors.count]
    }
}
