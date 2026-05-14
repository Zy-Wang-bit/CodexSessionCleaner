import SwiftUI

struct SidebarView: View {
    let projects: [ProjectGroup]
    let selectedProjectID: ProjectGroup.ID?
    let status: String
    let isLoading: Bool
    let onSelectProject: (ProjectGroup.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            projectList
        }
        .background(AppTheme.sidebarBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Projects")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                StatusPill(text: isLoading ? "Working" : status, isLoading: isLoading)
            }

            Text("\(projects.count) directories")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var projectList: some View {
        if projects.isEmpty {
            ContentUnavailableView("No Projects", systemImage: "folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(projects) { project in
                        ProjectRow(project: project, isSelected: selectedProjectID == project.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectProject(project.id)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectGroup
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: project.exists ? "folder" : "folder.badge.questionmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(project.exists ? (isSelected ? AppTheme.primaryAccent : .secondary) : .orange)
                .frame(width: 30, height: 30)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Text(project.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("\(project.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.subtleFill, in: Capsule())
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
        if !project.exists {
            return .orange.opacity(0.12)
        }
        return isSelected ? AppTheme.primaryAccent.opacity(0.14) : AppTheme.subtleFill
    }
}

private struct StatusPill: View {
    let text: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.subtleFill, in: Capsule())
    }
}
