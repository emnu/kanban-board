import SwiftUI

struct BoardView: View {
    @EnvironmentObject var store: KanbanStore
    var board: Board
    var searchText: String
    
    @State private var showingAddColumnAlert = false
    @State private var newColumnName = ""
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(board.columns) { column in
                    ColumnView(column: column, searchText: searchText)
                        .frame(width: 280)
                }
                
                // Add Column Button (placeholder style card at the end)
                Button(action: {
                    newColumnName = ""
                    showingAddColumnAlert = true
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                        Text("Add Column")
                            .font(.headline)
                    }
                    .foregroundColor(.secondary)
                    .frame(width: 280, height: 120)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 40) // Alignment relative to column headers
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            // Premium background: Subtle gradient or desktop style window background
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: $showingAddColumnAlert) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Column")
                    .font(.headline)
                
                TextField("Column Name", text: $newColumnName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addColumn(name: newColumnName)
                            showingAddColumnAlert = false
                        }
                    }
                
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddColumnAlert = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Add") {
                        if !newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.addColumn(name: newColumnName)
                            showingAddColumnAlert = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
}
