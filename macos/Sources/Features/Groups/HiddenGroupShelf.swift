import SwiftUI

/// The hidden-group shelf: a top-trailing overlay listing hidden groups as
/// clickable pills (`SPEC.md` §7.2). Clicking a pill shows that group; the
/// overflow menu does the same for groups beyond the inline limit.
///
/// Layout rules (`SPEC.md` §7.2):
/// - 0 hidden    → the shelf is not rendered (the caller omits it).
/// - 1–4 hidden  → one pill per group.
/// - 5+ hidden   → the first 3 as pills plus a `[+N]` overflow menu.
///
/// The shelf is a `TerminalWorkspaceView` overlay, not a `GroupView` overlay
/// (invariant §14.14): it sits above the whole workspace, independent of the
/// group layout.
struct HiddenGroupShelf: View {
    /// Hidden groups in a stable display order (the caller sorts them).
    let groups: [GroupState]

    /// Show the group with this id (`SPEC.md` §11.8). Wired to the controller.
    let onShow: (GroupID) -> Void

    /// Inline pills shown before collapsing into the overflow menu. With more
    /// than `maxInline` hidden groups, only `inlineWithOverflow` are shown inline
    /// and the rest move into the menu (`SPEC.md` §7.2 shows `[a] [b] [c] [+N]`).
    private static let maxInline = 4
    private static let inlineWithOverflow = 3

    private var inlineCount: Int {
        groups.count <= Self.maxInline ? groups.count : Self.inlineWithOverflow
    }

    private var inlineGroups: ArraySlice<GroupState> { groups.prefix(inlineCount) }
    private var overflowGroups: ArraySlice<GroupState> { groups.dropFirst(inlineCount) }

    var body: some View {
        if !groups.isEmpty {
            HStack(spacing: 4) {
                Text("hidden:")
                    .foregroundStyle(.secondary)

                ForEach(inlineGroups) { group in
                    pill(group)
                }

                if !overflowGroups.isEmpty {
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

    private func pill(_ group: GroupState) -> some View {
        Button {
            onShow(group.id)
        } label: {
            Text(group.name)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 3).fill(.regularMaterial)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show group \(group.name)"))
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(overflowGroups) { group in
                Button(group.name) { onShow(group.id) }
            }
        } label: {
            Text("+\(overflowGroups.count)")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text("Show more hidden groups"))
    }
}
