import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: KanbanStore
    @EnvironmentObject var syncEngine: GoogleDriveSync
    
    @State private var clientIdInput = ""
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Form {
                    Section("Google Drive API Configuration") {
                        TextField("Client ID", text: $clientIdInput)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: clientIdInput) { oldValue, newValue in
                                syncEngine.clientId = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .help("Enter your Google Cloud OAuth Client ID")
                    }
                    
                    Section("Connection Status") {
                        HStack {
                            Text("Status:")
                                .fontWeight(.semibold)
                            Text(syncEngine.status.rawValue)
                                .foregroundColor(statusColor)
                            
                            Spacer()
                            
                            if syncEngine.hasSavedCredentials() {
                                Button("Disconnect") {
                                    syncEngine.disconnect()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button("Connect Account") {
                                    if let authURL = syncEngine.startAuthorizationURL() {
                                        #if os(macOS)
                                        NSWorkspace.shared.open(authURL)
                                        #endif
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        
                        if let lastSync = syncEngine.lastSyncTime {
                            LabeledContent("Last Sync", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                        }
                        
                        if let error = syncEngine.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .textSelection(.enabled)
                        }
                    }
                    
                    Section("Backup & Recovery") {
                        HStack(spacing: 12) {
                            Button("Export Backup JSON") {
                                exportBackup()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Import JSON File") {
                                importBackup()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .formStyle(.grouped)
                
                // Instructions Footer
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Setup Google Drive Sync:")
                        .font(.headline)
                    Text("1. Visit the Google Cloud Console.")
                    Text("2. Create a project and enable the **Google Drive API**.")
                    Text("3. On the OAuth Consent Screen, add scope `.../auth/drive.file`.")
                    Text("4. Create an **OAuth Client ID** (choose App Type: **iOS** or **Web Application**).")
                    Text("5. Set redirect URI to: `com.kanbanapp.oauth:/oauth2redirect`.")
                    Text("6. Paste your Client ID above and click Connect Account.")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .navigationTitle("Sync Settings")
            .onAppear {
                clientIdInput = syncEngine.clientId
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var statusColor: Color {
        switch syncEngine.status {
        case .disconnected: return .secondary
        case .connecting, .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        case .offline: return .orange
        }
    }
    
    // MARK: - Import/Export backups
    
    private func exportBackup() {
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "kanban_backup.json"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                
                if let data = try? encoder.encode(store.kanbanData) {
                    try? data.write(to: url)
                }
            }
        }
        #endif
    }
    
    private func importBackup() {
        #if os(macOS)
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url, let data = try? Data(contentsOf: url) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let decoded = try? decoder.decode(KanbanData.self, from: data) {
                    DispatchQueue.main.async {
                        store.kanbanData = decoded
                        if let activeId = decoded.activeBoardId {
                            store.activeBoard = decoded.boards.first(where: { $0.id == activeId })
                        }
                        if store.activeBoard == nil {
                            store.activeBoard = decoded.boards.first
                        }
                        store.dataChanged()
                    }
                }
            }
        }
        #endif
    }
}
