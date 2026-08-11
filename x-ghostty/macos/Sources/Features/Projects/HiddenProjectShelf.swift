import SwiftUI

/// The hidden-project shelf: a top-trailing overlay listing hidden projects as
/// clickable pills (`SPEC.md` §7.2). Clicking a pill shows that project; the
/// overflow menu does the same for projects beyond the inline limit.
///
/// Layout rules (`SPEC.md` §7.2):
/// - 0 hidden    → the shelf is not rendered (the caller omits it).
/// - 1–4 hidden  → one pill per project.
/// - 5+ hidden   → the first 3 as pills plus a `[+N]` overflow menu.
///
/// The shelf is a `TerminalWorkspaceView` overlay, not a `ProjectView` overlay
/// (invariant §14.14): it sits above the whole workspace, independent of the
/// project layout.
struct HiddenProjectShelf: View {
    /// Hidden projects in a stable display order (the caller sorts them).
    let projects: [ProjectState]

    /// Show the project with this id (`SPEC.md` §11.8). Wired to the controller.
    let onShow: (ProjectID) -> Void

    /// Inline pills shown before collapsing into the overflow menu. With more
    /// than `maxInline` hidden projects, only `inlineWithOverflow` are shown inline
    /// and the rest move into the menu (`SPEC.md` §7.2 shows `[a] [b] [c] [+N]`).
    private static let maxInline = 4
    private static let inlineWithOverflow = 3

    private var inlineCount: Int {
        projects.count <= Self.maxInline ? projects.count : Self.inlineWithOverflow
    }

    private var inlineProjects: ArraySlice<ProjectState> { projects.prefix(inlineCount) }
    private var overflowProjects: ArraySlice<ProjectState> { projects.dropFirst(inlineCount) }

    var body: some View {
        if !projects.isEmpty {
            HStack(spacing: 4) {
                Text("hidden:")
                    .foregroundStyle(.secondary)

                ForEach(inlineProjects) { project in
                    pill(project)
                }

                if !overflowProjects.isEmpty {
                    overflowMenu
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 4).fill(.thinMaterial)
            }
        }
    }

    private func pill(_ project: ProjectState) -> some View {
        Button {
            onShow(project.id)
        } label: {
            Text(project.name)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 3).fill(.regularMaterial)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show project \(project.name)"))
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(overflowProjects) { project in
                Button(project.name) { onShow(project.id) }
            }
        } label: {
            Text("+\(overflowProjects.count)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text("Show more hidden projects"))
    }
}
