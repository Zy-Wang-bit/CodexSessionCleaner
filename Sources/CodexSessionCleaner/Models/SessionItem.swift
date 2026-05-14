import Foundation

struct SessionItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let updatedAt: Int?
    let rolloutPath: String?
    let cwd: String?
    let agentRole: String?
    let agentNickname: String?
    let parentThreadID: String?
    let parentTitle: String?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case updatedAt = "updated_at"
        case rolloutPath = "rollout_path"
        case cwd
        case agentRole = "agent_role"
        case agentNickname = "agent_nickname"
        case parentThreadID = "parent_thread_id"
        case parentTitle = "parent_title"
        case archived
    }

    var isSubagent: Bool {
        agentRole?.isEmpty == false || parentThreadID?.isEmpty == false
    }

    var roleLabel: String {
        guard let agentRole, !agentRole.isEmpty else {
            return "Main"
        }
        return agentRole.prefix(1).uppercased() + agentRole.dropFirst()
    }

    var roleSystemImage: String {
        switch agentRole {
        case "explorer":
            return "binoculars"
        case "worker":
            return "hammer"
        default:
            return isSubagent ? "person.2" : "person"
        }
    }
}

enum SessionRoleFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case main = "Main"
    case subagents = "Subagents"
    case explorers = "Explorers"
    case workers = "Workers"

    var id: String { rawValue }

    func includes(_ session: SessionItem) -> Bool {
        switch self {
        case .all:
            return true
        case .main:
            return !session.isSubagent
        case .subagents:
            return session.isSubagent
        case .explorers:
            return session.agentRole == "explorer"
        case .workers:
            return session.agentRole == "worker"
        }
    }
}

struct SessionTreeRow: Identifiable, Hashable {
    let session: SessionItem
    let depth: Int
    let descendantCount: Int
    let isExpanded: Bool

    var id: String {
        session.id
    }

    var hasChildren: Bool {
        descendantCount > 0
    }
}

struct ProjectGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String?
    let exists: Bool
    let sessions: [SessionItem]
    let latestUpdatedAt: Int?

    var count: Int {
        sessions.count
    }

    var detail: String {
        exists ? (path ?? "Unknown project") : "Missing project"
    }
}

struct DeletePlan: Codable, Hashable {
    let threadId: String
    let threadIds: [String]
    let descendantThreadIds: [String]
    let dryRun: Bool
    let found: Bool
    let files: [String]
    let stateDeletes: [String: Int]
    let logDeletes: Int
    let indexLinesRemoved: Int
    let globalStateChanged: Bool
    let vacuumed: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case threadIds = "thread_ids"
        case descendantThreadIds = "descendant_thread_ids"
        case dryRun = "dry_run"
        case found
        case files
        case stateDeletes = "state_deletes"
        case logDeletes = "log_deletes"
        case indexLinesRemoved = "index_lines_removed"
        case globalStateChanged = "global_state_changed"
        case vacuumed
        case warnings
    }

    var totalDatabaseRows: Int {
        stateDeletes.values.reduce(0, +) + logDeletes + indexLinesRemoved + (globalStateChanged ? 1 : 0)
    }
}
