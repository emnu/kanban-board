import SwiftUI

struct CardDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: KanbanStore
    
    var columnId: UUID
    var task: Task? // If nil, we are creating a new task
    
    @State private var taskId = UUID()
    @State private var title = ""
    @State private var description = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var subtasks: [Subtask] = []
    @State private var newSubtaskTitle = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var insertTableTrigger = false
    
    var isEditing: Bool { task != nil }
    
    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                // LEFT COLUMN: Title & Description (Master Workspace)
                VStack(alignment: .leading, spacing: 16) {
                    // Title input
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 4)
                    
                    // Description section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Description", systemImage: "doc.text")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Rich Text Formatting Toolbar
                            HStack(spacing: 4) {
                                Button(action: {
                                    NSApp.sendAction(Selector("toggleBoldface:"), to: nil, from: nil)
                                }) {
                                    Image(systemName: "bold")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.bordered)
                                .help("Bold")
                                
                                Button(action: {
                                    NSApp.sendAction(Selector("toggleItalics:"), to: nil, from: nil)
                                }) {
                                    Image(systemName: "italic")
                                        .font(.system(size: 11))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.bordered)
                                .help("Italic")
                                
                                Button(action: {
                                    NSApp.sendAction(Selector("underline:"), to: nil, from: nil)
                                }) {
                                    Image(systemName: "underline")
                                        .font(.system(size: 11))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.bordered)
                                .help("Underline")
                                
                                Divider().frame(height: 12)
                                
                                Button(action: {
                                    insertTableTrigger = true
                                }) {
                                    Label("Table", systemImage: "tablecells")
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .help("Insert table")
                            }
                        }
                        
                        RichTextEditor(htmlString: $description, insertTableTrigger: $insertTableTrigger, isEditable: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity) // Grow to take up all space
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // RIGHT COLUMN: Sidebar Metadata (Due Date, Subtasks, Tags)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Due Date Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Due Date")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            Toggle("Enable Due Date", isOn: $hasDueDate)
                                .toggleStyle(.checkbox)
                            
                            if hasDueDate {
                                DatePicker("", selection: $dueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        }
                        
                        Divider()
                        
                        // Subtasks Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subtasks")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            if !subtasks.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach($subtasks) { $subtask in
                                        HStack {
                                            Toggle("", isOn: $subtask.isCompleted)
                                                .labelsHidden()
                                                .toggleStyle(.checkbox)
                                            
                                            TextField("Subtask title", text: $subtask.title)
                                                .textFieldStyle(.plain)
                                                .foregroundColor(subtask.isCompleted ? .secondary : .primary)
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                subtasks.removeAll(where: { $0.id == subtask.id })
                                            }) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                            
                            // Add Subtask Row
                            HStack {
                                Image(systemName: "plus")
                                    .foregroundColor(.secondary)
                                TextField("Add subtask...", text: $newSubtaskTitle)
                                    .textFieldStyle(.plain)
                                    .onSubmit(addSubtask)
                                
                                Button("Add") {
                                    addSubtask()
                                }
                                .buttonStyle(.borderless)
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        
                        Divider()
                        
                        // Tags Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("New tag...", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(addTag)
                                
                                Button("Add") {
                                    addTag()
                                }
                                .buttonStyle(.bordered)
                                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            
                            if !tags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.system(size: 10, weight: .medium))
                                            
                                            Button(action: {
                                                tags.removeAll(where: { $0 == tag })
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.trailing, 10)
                }
                .frame(width: 260)
            }
            .padding(20)
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .onAppear(perform: loadTaskDetails)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onChange(of: title) { _ in autosave() }
            .onChange(of: description) { _ in autosave() }
            .onChange(of: tags) { _ in autosave() }
            .onChange(of: subtasks) { _ in autosave() }
            .onChange(of: hasDueDate) { _ in autosave() }
            .onChange(of: dueDate) { _ in autosave() }
        }
        .frame(width: 950, height: 700)
    }
    
    // MARK: - Handlers
    
    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtasks.append(Subtask(title: trimmed))
        newSubtaskTitle = ""
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !tags.contains(trimmed) {
            tags.append(trimmed)
        }
        newTag = ""
    }
    
    private func loadTaskDetails() {
        if let task = task {
            taskId = task.id
            title = task.title
            description = task.description
            tags = task.tags
            subtasks = task.subtasks
            if let date = task.dueDate {
                hasDueDate = true
                dueDate = date
            } else {
                hasDueDate = false
                dueDate = Date()
            }
        }
    }
    
    private func saveTask() {
        let currentTask = Task(
            id: taskId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: tags,
            dueDate: hasDueDate ? dueDate : nil,
            subtasks: subtasks,
            createdAt: task?.createdAt ?? Date(),
            updatedAt: Date()
        )
        store.saveTask(currentTask, toColumnId: columnId)
    }
    
    private func autosave() {
        // Only autosave if the title is not empty, to avoid creating blank cards
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saveTask()
    }
}

// MARK: - FlowLayout helper for wrapping tags horizontally
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var width: CGFloat = 0
        
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth {
                // Next row
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            width = max(width, currentX)
            height = max(height, currentY + rowHeight)
        }
        
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let containerWidth = bounds.width
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.minX + containerWidth {
                // Next row
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
