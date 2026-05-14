import SwiftUI

struct ContentView: View {
    @StateObject private var store = SessionStore()
    @State private var showingSingleDeleteConfirmation = false
    @State private var showingBatchDeleteConfirmation = false

    var body: some View {
        HSplitView {
            SidebarView(
                projects: store.projectGroups,
                selectedProjectID: store.selectedProject?.id,
                status: store.status,
                isLoading: store.isLoading,
                onSelectProject: store.setSelectedProject
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)

            SessionListView(
                project: store.selectedProject,
                rows: store.visibleSessionRows,
                searchText: $store.searchText,
                roleFilter: $store.roleFilter,
                selectedID: $store.selectedID,
                selectedBatchIDs: store.selectedBatchIDs,
                onToggleExpanded: store.toggleExpanded,
                onToggleBatch: store.toggleBatchSelection,
                onSelectAll: store.selectAllVisible,
                onClearSelection: store.clearBatchSelection,
                onSelectOlderThan: store.selectOlderThan(days:),
                onDeleteBatch: {
                    showingBatchDeleteConfirmation = true
                }
            )
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, maxHeight: .infinity)

            DetailView(
                session: store.selectedSession,
                preview: store.selectedPreview,
                deleteResult: store.selectedDeleteResult,
                canDelete: store.canDeleteSelected,
                isLoading: store.isLoading,
                errorMessage: store.errorMessage,
                codexHome: $store.codexHome,
                onPreview: {
                    Task {
                        await store.previewSelectedDelete()
                    }
                },
                onDelete: {
                    showingSingleDeleteConfirmation = true
                }
            )
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await store.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)

                Button {
                    Task {
                        await store.previewSelectedDelete()
                    }
                } label: {
                    Label("Inspect", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(store.selectedSession == nil || store.isLoading)

                Button(role: .destructive) {
                    showingSingleDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!store.canDeleteSelected)
            }
        }
        .alert("Delete session permanently?", isPresented: $showingSingleDeleteConfirmation, presenting: store.selectedSession) { _ in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await store.deleteSelected()
                }
            }
        } message: { session in
            let count = store.selectedPreview?.totalDatabaseRows ?? 0
            let childCount = store.selectedPreview?.descendantThreadIds.count ?? 0
            Text("This permanently removes \(session.id) and \(childCount) child agent sessions, including rollout content, local indexes, logs, snapshots, and \(count) database entries.")
        }
        .alert("Delete selected sessions permanently?", isPresented: $showingBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(store.selectedBatchIDs.count)", role: .destructive) {
                Task {
                    await store.deleteBatch()
                }
            }
        } message: {
            Text("This permanently deletes \(store.selectedBatchIDs.count) selected sessions. Batch deletion uses the same full cleanup path as single deletion.")
        }
        .onChange(of: store.selectedID) {
            store.clearTransientResults()
        }
        .onChange(of: store.searchText) {
            store.syncSelectionWithFilter()
        }
        .onChange(of: store.roleFilter) {
            store.syncSelectionWithRoleFilter()
        }
        .task {
            await store.refresh()
        }
    }
}
