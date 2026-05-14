import SwiftUI

struct SessionListView: View {
    let project: ProjectGroup?
    let rows: [SessionTreeRow]
    @Binding var searchText: String
    @Binding var roleFilter: SessionRoleFilter
    @Binding var selectedID: SessionItem.ID?
    let selectedBatchIDs: Set<SessionItem.ID>
    let onToggleExpanded: (SessionItem.ID) -> Void
    let onToggleBatch: (SessionItem.ID) -> Void
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onSelectOlderThan: (Int) -> Void
    let onDeleteBatch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            batchBar
            Divider()
            list
        }
        .background(AppTheme.appBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project?.title ?? "Sessions")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(project?.path ?? "No project selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(project?.count ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.subtleFill, in: Capsule())
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search sessions in project", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.stroke)
            )

            Picker("Role", selection: $roleFilter) {
                ForEach(SessionRoleFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
    }

    private var batchBar: some View {
        HStack(spacing: 8) {
            Button("All", action: onSelectAll)
                .buttonStyle(.borderless)
            Button("Clear", action: onClearSelection)
                .buttonStyle(.borderless)
                .disabled(selectedBatchIDs.isEmpty)

            Menu("Older Than") {
                Button("7 days", action: { onSelectOlderThan(7) })
                Button("30 days", action: { onSelectOlderThan(30) })
                Button("90 days", action: { onSelectOlderThan(90) })
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Text("\(selectedBatchIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(role: .destructive, action: onDeleteBatch) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedBatchIDs.isEmpty)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    @ViewBuilder
    private var list: some View {
        if rows.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "text.bubble")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { row in
                        SessionListRow(
                            row: row,
                            isSelected: selectedID == row.session.id,
                            isBatchSelected: selectedBatchIDs.contains(row.session.id),
                            onToggleExpanded: {
                                onToggleExpanded(row.session.id)
                            },
                            onToggleBatch: {
                                onToggleBatch(row.session.id)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedID = row.session.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct SessionListRow: View {
    let row: SessionTreeRow
    let isSelected: Bool
    let isBatchSelected: Bool
    let onToggleExpanded: () -> Void
    let onToggleBatch: () -> Void

    private var session: SessionItem {
        row.session
    }

    var body: some View {
        HStack(spacing: 9) {
            Spacer()
                .frame(width: CGFloat(row.depth) * 18)

            if row.hasChildren {
                Button(action: onToggleExpanded) {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 18)
                }
                .buttonStyle(.plain)
            } else if row.depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 18)
            } else {
                Spacer()
                    .frame(width: 14)
            }

            Button(action: onToggleBatch) {
                Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isBatchSelected ? AppTheme.primaryAccent : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)

            Image(systemName: session.archived ? "archivebox" : "text.bubble")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? AppTheme.primaryAccent : .secondary)
                .frame(width: 26, height: 26)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.isEmpty ? "Untitled" : session.title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Text(SessionFormatters.updatedAtText(session.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    RoleBadge(session: session)
                    if row.descendantCount > 0 {
                        Text("\(row.descendantCount) child agents")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.primaryAccent)
                            .lineLimit(1)
                    }
                    if let parentTitle = session.parentTitle, !parentTitle.isEmpty {
                        Text("from \(parentTitle)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isSelected ? AppTheme.primaryAccent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? AppTheme.primaryAccent.opacity(0.18) : .clear)
        )
    }

    private var iconBackground: Color {
        isSelected ? AppTheme.primaryAccent.opacity(0.14) : AppTheme.subtleFill
    }
}

private struct RoleBadge: View {
    let session: SessionItem

    var body: some View {
        Label(session.roleLabel, systemImage: session.roleSystemImage)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
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

    private var background: Color {
        foreground.opacity(0.12)
    }
}
