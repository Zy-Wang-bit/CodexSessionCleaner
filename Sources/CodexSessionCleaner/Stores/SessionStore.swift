import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [SessionItem] = []
    @Published var searchText = ""
    @Published var roleFilter: SessionRoleFilter = .all
    @Published var selectedProjectID: ProjectGroup.ID?
    @Published var selectedID: SessionItem.ID?
    @Published var selectedBatchIDs: Set<SessionItem.ID> = []
    @Published var expandedParentIDs: Set<SessionItem.ID> = []
    @Published var preview: DeletePlan?
    @Published var lastDeleteResult: DeletePlan?
    @Published var isLoading = false
    @Published var status = "Ready"
    @Published var errorMessage: String?
    @Published var codexHome: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
        .path

    private let service = CodexCLIService()

    var projectGroups: [ProjectGroup] {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: sessions) { session in
            projectKey(for: session, sessionByID: sessionByID)
        }

        return grouped.map { key, items in
            makeProjectGroup(id: key, sessions: items.sortedByUpdateDescending())
        }
        .sorted { lhs, rhs in
            if lhs.exists != rhs.exists {
                return lhs.exists && !rhs.exists
            }
            if lhs.latestUpdatedAt != rhs.latestUpdatedAt {
                return (lhs.latestUpdatedAt ?? 0) > (rhs.latestUpdatedAt ?? 0)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var selectedProject: ProjectGroup? {
        guard let selectedProjectID else {
            return projectGroups.first
        }
        return projectGroups.first { $0.id == selectedProjectID } ?? projectGroups.first
    }

    var visibleSessionRows: [SessionTreeRow] {
        let projectSessions = selectedProject?.sessions ?? []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return makeSessionTreeRows(from: projectSessions, query: query)
    }

    var visibleSessions: [SessionItem] {
        visibleSessionRows.map(\.session)
    }

    var selectedSession: SessionItem? {
        guard let selectedID else {
            return visibleSessions.first
        }
        return sessions.first { $0.id == selectedID }
    }

    var selectedPreview: DeletePlan? {
        guard preview?.threadId == selectedID else {
            return nil
        }
        return preview
    }

    var selectedDeleteResult: DeletePlan? {
        guard lastDeleteResult?.threadId == selectedID else {
            return nil
        }
        return lastDeleteResult
    }

    var canDeleteSelected: Bool {
        selectedSession != nil && selectedPreview != nil && !isLoading
    }

    var canDeleteBatch: Bool {
        !selectedBatchIDs.isEmpty && !isLoading
    }

    func refresh() async {
        await perform("Refreshing sessions") {
            let items = try await service.listSessions(codexHome: codexHome)
            sessions = items
            selectedBatchIDs.removeAll()
            syncProjectSelection()
            syncSelectionWithFilter()
            preview = nil
            lastDeleteResult = nil
            status = "Loaded \(items.count) sessions"
        }
    }

    func previewSelectedDelete() async {
        guard let selectedSession else {
            return
        }
        await perform("Inspecting session") {
            preview = try await service.previewDelete(codexHome: codexHome, threadId: selectedSession.id)
            lastDeleteResult = nil
            selectedBatchIDs.removeAll()
            status = "Inspect ready"
        }
    }

    func deleteSelected() async {
        guard let selectedSession else {
            return
        }
        guard selectedPreview != nil else {
            errorMessage = "Run Inspect before deleting this session."
            status = "Inspect required"
            return
        }
        await perform("Deleting session") {
            let result = try await service.deleteSession(codexHome: codexHome, threadId: selectedSession.id)
            lastDeleteResult = result
            preview = nil
            sessions = try await service.listSessions(codexHome: codexHome)
            expandedParentIDs = expandedParentIDs.intersection(Set(sessions.map(\.id)))
            syncProjectSelection()
            syncSelectionWithFilter()
            let count = result.found ? result.threadIds.count : 0
            status = count > 0 ? "Deleted \(count) sessions" : "Session was already absent"
        }
    }

    func deleteBatch() async {
        let ids = selectedBatchIDs
        guard !ids.isEmpty else {
            return
        }

        await perform("Deleting \(ids.count) sessions") {
            var affected = 0
            for id in rootDeletionIDs(from: ids) {
                let result = try await service.deleteSession(codexHome: codexHome, threadId: id)
                if result.found {
                    affected += result.threadIds.count
                }
            }
            sessions = try await service.listSessions(codexHome: codexHome)
            expandedParentIDs = expandedParentIDs.intersection(Set(sessions.map(\.id)))
            selectedBatchIDs.removeAll()
            preview = nil
            lastDeleteResult = nil
            syncProjectSelection()
            syncSelectionWithFilter()
            status = "Deleted \(affected) sessions"
        }
    }

    func clearTransientResults() {
        preview = nil
        lastDeleteResult = nil
    }

    func setSelectedProject(_ projectID: ProjectGroup.ID) {
        selectedProjectID = projectID
        searchText = ""
        roleFilter = .all
        selectedBatchIDs.removeAll()
        expandedParentIDs.removeAll()
        clearTransientResults()
        selectedID = visibleSessions.first?.id
        status = selectedProject.map { "\($0.count) sessions in project" } ?? "No project selected"
    }

    func syncSelectionWithFilter() {
        let matches = visibleSessions
        if let selectedID, matches.contains(where: { $0.id == selectedID }) {
            status = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (selectedProject.map { "\($0.count) sessions in project" } ?? "Loaded \(sessions.count) sessions")
                : "Showing \(matches.count) matches"
            return
        }
        selectedID = matches.first?.id
        clearTransientResults()
        status = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedProject.map { "\($0.count) sessions in project" } ?? "Loaded \(sessions.count) sessions")
            : "Showing \(matches.count) matches"
    }

    func syncSelectionWithRoleFilter() {
        selectedBatchIDs.removeAll()
        syncSelectionWithFilter()
    }

    func toggleExpanded(_ sessionID: SessionItem.ID) {
        if expandedParentIDs.contains(sessionID) {
            expandedParentIDs.remove(sessionID)
        } else {
            expandedParentIDs.insert(sessionID)
        }
        syncSelectionWithFilter()
    }

    func toggleBatchSelection(_ sessionID: SessionItem.ID) {
        clearTransientResults()
        let familyIDs = Set([sessionID]).union(descendantIDs(of: sessionID))
        if selectedBatchIDs.contains(sessionID) {
            if let ancestorID = selectedAncestorID(of: sessionID, in: selectedBatchIDs) {
                selectedBatchIDs.subtract(Set([ancestorID]).union(descendantIDs(of: ancestorID)))
            } else {
                selectedBatchIDs.subtract(familyIDs)
            }
        } else {
            selectedBatchIDs.formUnion(familyIDs)
        }
        status = "\(selectedBatchIDs.count) selected"
    }

    func selectAllVisible() {
        var ids = Set<SessionItem.ID>()
        for session in visibleSessions {
            ids.insert(session.id)
            ids.formUnion(descendantIDs(of: session.id))
        }
        selectedBatchIDs = ids
        clearTransientResults()
        status = "\(selectedBatchIDs.count) selected"
    }

    func clearBatchSelection() {
        selectedBatchIDs.removeAll()
        status = selectedProject.map { "\($0.count) sessions in project" } ?? "Selection cleared"
    }

    func selectOlderThan(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60).timeIntervalSince1970
        var ids = Set<SessionItem.ID>()
        for session in visibleSessions {
            guard let updatedAt = session.updatedAt, Double(updatedAt) < cutoff else {
                continue
            }
            ids.insert(session.id)
            ids.formUnion(descendantIDs(of: session.id))
        }
        selectedBatchIDs = ids
        clearTransientResults()
        status = "\(selectedBatchIDs.count) older than \(days)d"
    }

    private func syncProjectSelection() {
        let groups = projectGroups
        if let selectedProjectID, groups.contains(where: { $0.id == selectedProjectID }) {
            return
        }
        selectedProjectID = groups.first?.id
    }

    private func projectKey(for session: SessionItem, sessionByID: [SessionItem.ID: SessionItem]) -> String {
        let root = rootSession(for: session, sessionByID: sessionByID)
        guard let cwd = root.cwd, !cwd.isEmpty else {
            return "missing::all"
        }
        if FileManager.default.fileExists(atPath: cwd) {
            return "path::\(cwd)"
        }
        return "missing::all"
    }

    private func makeProjectGroup(id: String, sessions: [SessionItem]) -> ProjectGroup {
        let path = sessions.first?.cwd
        let exists = id.hasPrefix("path::") && (path.map { FileManager.default.fileExists(atPath: $0) } ?? false)
        let title: String
        let detail: String?
        if !exists {
            title = "Missing Projects"
            detail = "Project directories no longer exist"
        } else if let path, !path.isEmpty {
            title = URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent
            detail = path
        } else {
            title = "Unknown Project"
            detail = nil
        }
        return ProjectGroup(
            id: id,
            title: title,
            path: detail,
            exists: exists,
            sessions: sessions,
            latestUpdatedAt: sessions.map { $0.updatedAt ?? 0 }.max()
        )
    }

    private func makeSessionTreeRows(from projectSessions: [SessionItem], query: String) -> [SessionTreeRow] {
        let ids = Set(projectSessions.map(\.id))
        let childSessions = projectSessions.filter { session in
            guard let parentThreadID = session.parentThreadID else {
                return false
            }
            return ids.contains(parentThreadID)
        }
        let childrenByParent = Dictionary(grouping: childSessions) { session in
            session.parentThreadID ?? ""
        }.mapValues { $0.sortedByUpdateDescending() }
        let roots = projectSessions.filter { session in
            guard let parentThreadID = session.parentThreadID else {
                return true
            }
            return !ids.contains(parentThreadID)
        }.sortedByUpdateDescending()
        let forceExpanded = !query.isEmpty || roleFilter != .all
        var rows: [SessionTreeRow] = []

        func descendantCount(for sessionID: SessionItem.ID, seen: Set<SessionItem.ID> = []) -> Int {
            guard !seen.contains(sessionID) else {
                return 0
            }
            let children = childrenByParent[sessionID] ?? []
            let nextSeen = seen.union([sessionID])
            return children.reduce(children.count) { partial, child in
                partial + descendantCount(for: child.id, seen: nextSeen)
            }
        }

        func append(_ session: SessionItem, depth: Int, seen: Set<SessionItem.ID>) {
            guard !seen.contains(session.id) else {
                return
            }
            let nextSeen = seen.union([session.id])
            let children = childrenByParent[session.id] ?? []
            let hasChildren = !children.isEmpty
            let isExpanded = forceExpanded || expandedParentIDs.contains(session.id)
            let selfMatches = roleFilter.includes(session) && matchesSearch(session, query: query)

            if selfMatches {
                rows.append(
                    SessionTreeRow(
                        session: session,
                        depth: depth,
                        descendantCount: descendantCount(for: session.id),
                        isExpanded: isExpanded
                    )
                )
            }

            if hasChildren && (isExpanded || !selfMatches) {
                for child in children {
                    append(child, depth: depth + 1, seen: nextSeen)
                }
            }
        }

        for root in roots {
            append(root, depth: 0, seen: [])
        }
        return rows
    }

    private func matchesSearch(_ session: SessionItem, query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }
        return session.title.localizedCaseInsensitiveContains(query)
            || session.id.localizedCaseInsensitiveContains(query)
            || (session.rolloutPath?.localizedCaseInsensitiveContains(query) ?? false)
            || (session.cwd?.localizedCaseInsensitiveContains(query) ?? false)
            || (session.parentTitle?.localizedCaseInsensitiveContains(query) ?? false)
            || (session.agentNickname?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func rootSession(
        for session: SessionItem,
        sessionByID: [SessionItem.ID: SessionItem]
    ) -> SessionItem {
        var current = session
        var seen = Set<SessionItem.ID>()
        while let parentID = current.parentThreadID,
              !seen.contains(parentID),
              let parent = sessionByID[parentID] {
            seen.insert(current.id)
            current = parent
        }
        return current
    }

    private func descendantIDs(of sessionID: SessionItem.ID) -> Set<SessionItem.ID> {
        let childrenByParent = Dictionary(grouping: sessions.filter { $0.parentThreadID != nil }) { session in
            session.parentThreadID ?? ""
        }
        var result = Set<SessionItem.ID>()

        func collect(_ id: SessionItem.ID) {
            for child in childrenByParent[id] ?? [] where !result.contains(child.id) {
                result.insert(child.id)
                collect(child.id)
            }
        }

        collect(sessionID)
        return result
    }

    private func selectedAncestorID(of sessionID: SessionItem.ID, in ids: Set<SessionItem.ID>) -> SessionItem.ID? {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var parentID = sessionByID[sessionID]?.parentThreadID
        while let id = parentID {
            if ids.contains(id) {
                return id
            }
            parentID = sessionByID[id]?.parentThreadID
        }
        return nil
    }

    private func rootDeletionIDs(from ids: Set<SessionItem.ID>) -> [SessionItem.ID] {
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let visibleOrder = Dictionary(uniqueKeysWithValues: visibleSessions.enumerated().map { ($0.element.id, $0.offset) })
        return ids.filter { id in
            var parentID = sessionByID[id]?.parentThreadID
            while let ancestorID = parentID {
                if ids.contains(ancestorID) {
                    return false
                }
                parentID = sessionByID[ancestorID]?.parentThreadID
            }
            return true
        }
        .sorted {
            visibleOrder[$0, default: Int.max] < visibleOrder[$1, default: Int.max]
        }
    }

    private func perform(_ loadingStatus: String, operation: () async throws -> Void) async {
        isLoading = true
        status = loadingStatus
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            status = "Failed"
        }
    }
}

private extension Array where Element == SessionItem {
    func sortedByUpdateDescending() -> [SessionItem] {
        sorted {
            ($0.updatedAt ?? 0, $0.id) > ($1.updatedAt ?? 0, $1.id)
        }
    }
}
