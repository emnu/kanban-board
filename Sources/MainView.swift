import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: KanbanStore
    @EnvironmentObject var syncEngine: GoogleDriveSync
    
    @State private var showingSettings = false
    @State private var showingAddBoardAlert = false
    @State private var newBoardName = ""
    @State private var searchText = ""
    @State private var showingRenameBoardSheet = false
    @State private var boardToRename: Board? = nil
    @State private var renameBoardNameInput = ""
    
    // Notes sheets and states
    @State private var showingAddNoteAlert = false
    @State private var newNoteTitle = ""
    @State private var showingRenameNoteSheet = false
    @State private var noteToRename: Note? = nil
    @State private var renameNoteTitleInput = ""
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Partitioned list of Boards and Notes
            List(selection: $store.sidebarSelection) {
                // Section 1: Kanban Boards
                Section {
                    ForEach(store.kanbanData.boards) { board in
                        NavigationLink(value: SidebarSelection.board(board.id)) {
                            Label(board.name, systemImage: "folder")
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteBoard(board)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .disabled(store.kanbanData.boards.count <= 1)
                                }
                        }
                        .contextMenu {
                            Button {
                                boardToRename = board
                                renameBoardNameInput = board.name
                                showingRenameBoardSheet = true
                            } label: {
                                Label("Rename Board", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                store.deleteBoard(board)
                            } label: {
                                Label("Delete Board", systemImage: "trash")
                            }
                            .disabled(store.kanbanData.boards.count <= 1)
                        }
                    }
                } header: {
                    HStack {
                        Text("My Boards")
                        Spacer()
                        Button(action: {
                            newBoardName = ""
                            showingAddBoardAlert = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Create New Board")
                    }
                }
                
                // Section 2: Notes
                Section {
                    ForEach(store.kanbanData.notes) { note in
                        NavigationLink(value: SidebarSelection.note(note.id)) {
                            Label(note.title, systemImage: "note.text")
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteNote(note.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .contextMenu {
                            Button {
                                noteToRename = note
                                renameNoteTitleInput = note.title
                                showingRenameNoteSheet = true
                            } label: {
                                Label("Rename Note", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                store.deleteNote(note.id)
                            } label: {
                                Label("Delete Note", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("My Notes")
                        Spacer()
                        Button(action: {
                            newNoteTitle = ""
                            showingAddNoteAlert = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Create New Note")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Sidebar Footer: Sync Status and Settings
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        // Sync Status Indicator
                        Button(action: {
                            showingSettings = true
                        }) {
                            HStack(spacing: 6) {
                                syncStatusIcon
                                    .font(.system(size: 12))
                                Text(syncEngine.status.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Google Drive Connection Settings")
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            // Workspace Detail Router
            switch store.sidebarSelection {
            case .board(let boardId):
                if let board = store.kanbanData.boards.first(where: { $0.id == boardId }) {
                    BoardView(board: board, searchText: searchText)
                        .navigationTitle(board.name)
                } else {
                    ContentUnavailableView("Select or Create a Board", systemImage: "folder", description: Text("Choose a board from the sidebar to get started."))
                }
            case .note(let noteId):
                if let note = store.kanbanData.notes.first(where: { $0.id == noteId }) {
                    NoteEditorView(noteId: noteId)
                        .navigationTitle(note.title)
                } else {
                    ContentUnavailableView("Select or Create a Note", systemImage: "note.text", description: Text("Choose a note from the sidebar to get started."))
                }
            case .none:
                ContentUnavailableView("Welcome", systemImage: "square.grid.2x2", description: Text("Select a board or note from the sidebar to begin."))
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search cards by title, tag, or desc...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $store.sortFlaggedToTop) {
                    Label("Sort Flagged to Top", systemImage: "flag.fill")
                }
                .toggleStyle(.button)
                .help("Sort flagged tasks to the top of columns")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    store.triggerSync()
                }) {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }
                .disabled(!syncEngine.hasSavedCredentials())
                .help("Sync data with Google Drive")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(width: 480, height: 420)
        }
        .sheet(isPresented: $showingAddBoardAlert) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Kanban Board")
                    .font(.headline)
                
                TextField("Board Name", text: $newBoardName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addBoard(name: newBoardName)
                            showingAddBoardAlert = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddBoardAlert = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Create") {
                        if !newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addBoard(name: newBoardName)
                            showingAddBoardAlert = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newBoardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showingRenameBoardSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Board")
                    .font(.headline)
                
                TextField("Board Name", text: $renameBoardNameInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let board = boardToRename, !renameBoardNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameBoard(board.id, to: renameBoardNameInput)
                            showingRenameBoardSheet = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingRenameBoardSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Save") {
                        if let board = boardToRename, !renameBoardNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameBoard(board.id, to: renameBoardNameInput)
                            showingRenameBoardSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameBoardNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showingAddNoteAlert) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Note")
                    .font(.headline)
                
                TextField("Note Title", text: $newNoteTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addNote(title: newNoteTitle)
                            showingAddNoteAlert = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddNoteAlert = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Create") {
                        if !newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addNote(title: newNoteTitle)
                            showingAddNoteAlert = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $showingRenameNoteSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Note")
                    .font(.headline)
                
                TextField("Note Title", text: $renameNoteTitleInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let note = noteToRename, !renameNoteTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameNote(note.id, to: renameNoteTitleInput)
                            showingRenameNoteSheet = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingRenameNoteSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Save") {
                        if let note = noteToRename, !renameNoteTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.renameNote(note.id, to: renameNoteTitleInput)
                            showingRenameNoteSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameNoteTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncEngine.status {
        case .disconnected:
            Image(systemName: "icloud.slash")
                .foregroundColor(.secondary)
        case .connecting, .syncing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundColor(.red)
        case .offline:
            Image(systemName: "icloud.and.arrow.up")
                .foregroundColor(.orange)
        }
    }
}
