import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject var store: KanbanStore
    var noteId: UUID
    
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var insertTableTrigger = false
    @State private var loadedNoteId: UUID? = nil
    @State private var isSettingData = false
    @State private var saveTask: _Concurrency.Task<Void, Never>? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Title Input
            TextField("Note Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            // Premium Editor Toolbar
            HStack(spacing: 8) {
                // Formatting Controls
                HStack(spacing: 4) {
                    Button(action: {
                        NSApp.sendAction(Selector("toggleBoldface:"), to: nil, from: nil)
                    }) {
                        Image(systemName: "bold")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help("Bold (Cmd+B)")
                    
                    Button(action: {
                        NSApp.sendAction(Selector("toggleItalics:"), to: nil, from: nil)
                    }) {
                        Image(systemName: "italic")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help("Italic (Cmd+I)")
                    
                    Button(action: {
                        NSApp.sendAction(Selector("underline:"), to: nil, from: nil)
                    }) {
                        Image(systemName: "underline")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .help("Underline (Cmd+U)")
                }
                
                Divider().frame(height: 16)
                
                // Table and Layout Actions
                Button(action: {
                    insertTableTrigger = true
                }) {
                    Label("Insert Table", systemImage: "tablecells")
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                }
                .buttonStyle(.bordered)
                .help("Insert standard table skeleton")
                
                Spacer()
                
                // Note Metadata / Timestamps
                if let note = store.kanbanData.notes.first(where: { $0.id == noteId }) {
                    Text("Last updated: \(formattedDate(note.updatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            // Rich Text Editor Component
            RichTextEditor(htmlString: $content, insertTableTrigger: $insertTableTrigger, isEditable: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(24)
        .onAppear {
            loadNote(id: noteId)
        }
        .onDisappear {
            saveNote(id: noteId)
        }
        .onChange(of: noteId) { oldId, newId in
            switchNote(from: oldId, to: newId)
        }
        .onChange(of: title) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: content) { _, _ in
            scheduleAutosave()
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadNote(id: UUID) {
        guard let note = store.kanbanData.notes.first(where: { $0.id == id }) else { return }
        isSettingData = true
        title = note.title
        content = note.content
        loadedNoteId = id
        isSettingData = false
    }
    
    private func saveNote(id: UUID) {
        guard !isSettingData else { return }
        guard loadedNoteId == id else { return }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle
        
        store.updateNote(id: id, title: resolvedTitle, content: content)
    }
    
    private func switchNote(from oldId: UUID, to newId: UUID) {
        saveTask?.cancel()
        saveNote(id: oldId)
        loadNote(id: newId)
    }
    
    private func scheduleAutosave() {
        guard !isSettingData else { return }
        
        saveTask?.cancel()
        saveTask = _Concurrency.Task {
            // Debounce for 0.5 seconds
            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            
            await MainActor.run {
                saveNote(id: noteId)
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
