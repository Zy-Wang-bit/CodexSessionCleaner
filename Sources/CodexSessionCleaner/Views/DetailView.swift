import SwiftUI

struct DetailView: View {
    let session: SessionItem?
    let preview: DeletePlan?
    let deleteResult: DeletePlan?
    let canDelete: Bool
    let isLoading: Bool
    let errorMessage: String?
    @Binding var codexHome: String
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailCommandBar(
                codexHome: $codexHome,
                canInspect: session != nil && !isLoading,
                canDelete: canDelete,
                onPreview: onPreview,
                onDelete: onDelete
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session {
                        SessionSummaryView(session: session)
                        WorkflowView(hasPreview: preview != nil, canDelete: canDelete)

                        if let errorMessage {
                            MessageView(title: "Error", message: errorMessage, systemImage: "exclamationmark.triangle")
                        }

                        if let preview {
                            DeletePlanView(title: "Deletion Impact", plan: preview)
                        } else {
                            MessageView(
                                title: "Inspect before deleting",
                                message: "Run Inspect to calculate the exact files, logs, indexes, and database rows that will be removed.",
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }

                        if let deleteResult {
                            DeletePlanView(title: "Deleted", plan: deleteResult)
                        }
                    } else {
                        ContentUnavailableView("No Session Selected", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
                .padding(18)
            }
        }
        .background(AppTheme.appBackground)
    }
}

private struct DetailCommandBar: View {
    @Binding var codexHome: String
    let canInspect: Bool
    let canDelete: Bool
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Codex Home")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            TextField("Codex home", text: $codexHome)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.stroke)
                )

            Button(action: onPreview) {
                Label("Inspect", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canInspect)

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.regular)
            .disabled(!canDelete)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SessionSummaryView: View {
    let session: SessionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: session.archived ? "archivebox" : "text.bubble")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.primaryAccent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.primaryAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title.isEmpty ? "Untitled" : session.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(session.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    RoleBadge(session: session)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(SessionFormatters.updatedAtText(session.updatedAt))
                }
                if let rolloutPath = session.rolloutPath {
                    GridRow {
                        Text("Rollout")
                            .foregroundStyle(.secondary)
                        Text(rolloutPath)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                if let parentTitle = session.parentTitle, !parentTitle.isEmpty {
                    GridRow {
                        Text("Parent")
                            .foregroundStyle(.secondary)
                        Text(parentTitle)
                            .lineLimit(1)
                    }
                }
                if let agentNickname = session.agentNickname, !agentNickname.isEmpty {
                    GridRow {
                        Text("Agent")
                            .foregroundStyle(.secondary)
                        Text(agentNickname)
                    }
                }
            }
            .font(.callout)
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.stroke)
        )
    }
}

private struct RoleBadge: View {
    let session: SessionItem

    var body: some View {
        Label(session.roleLabel, systemImage: session.roleSystemImage)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(foreground.opacity(0.12), in: Capsule())
    }

    private var foreground: Color {
        switch session.agentRole {
        case "explorer":
            return .purple
        case "worker":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct WorkflowView: View {
    let hasPreview: Bool
    let canDelete: Bool

    var body: some View {
        HStack(spacing: 8) {
            StepBadge(title: "Selected", systemImage: "checkmark.circle.fill", isActive: true)
            StepSeparator()
            StepBadge(title: "Inspected", systemImage: hasPreview ? "checkmark.circle.fill" : "circle", isActive: hasPreview)
            StepSeparator()
            StepBadge(title: "Ready to Delete", systemImage: canDelete ? "exclamationmark.triangle.fill" : "circle", isActive: canDelete, isDestructive: canDelete)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct StepBadge: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var isDestructive = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(isDestructive ? .red : (isActive ? .primary : .secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StepSeparator: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct DeletePlanView: View {
    let title: String
    let plan: DeletePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: plan.dryRun ? "doc.text.magnifyingglass" : "trash")
                    .font(.headline)

                Spacer()

                Text("\(plan.files.count) files, \(plan.totalDatabaseRows) DB entries")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                ImpactMetric(title: "Sessions", value: plan.threadIds.count)
                ImpactMetric(title: "Child Agents", value: plan.descendantThreadIds.count)
                ImpactMetric(title: "Files", value: plan.files.count)
                ImpactMetric(title: "Logs", value: plan.logDeletes)
                ImpactMetric(title: "Threads", value: plan.stateDeletes["threads", default: 0])
                ImpactMetric(title: "Tool Rows", value: plan.stateDeletes["thread_dynamic_tools", default: 0])
                ImpactMetric(title: "Index Lines", value: plan.indexLinesRemoved)
                ImpactMetric(title: "Global State", valueText: plan.globalStateChanged ? "Changed" : "Clean")
            }

            if !plan.files.isEmpty {
                DisclosureGroup("Files") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(plan.files, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            if !plan.warnings.isEmpty {
                ForEach(plan.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.stroke)
        )
    }
}

private struct ImpactMetric: View {
    let title: String
    var value: Int? = nil
    var valueText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(valueText ?? "\(value ?? 0)")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MessageView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.stroke)
        )
    }
}
