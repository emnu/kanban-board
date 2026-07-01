import SwiftUI

@main
struct KanbanApp: App {
    @StateObject private var store = KanbanStore()
    @StateObject private var syncEngine = GoogleDriveSync.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(store)
                .environmentObject(syncEngine)
                .onOpenURL { url in
                    // Handle deep link callback from Google OAuth redirect
                    if url.scheme == "com.kanbanapp.oauth" {
                        _Concurrency.Task {
                            let success = await syncEngine.handleRedirectURL(url)
                            if success {
                                store.triggerSync()
                            }
                        }
                    }
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
