import SwiftUI

/// A single group-level operation within the canonical group tree.
///
/// As with `TerminalSplitOperation`, the tree is immutable, so mutating
/// operations are surfaced to the embedder instead of bound directly. Only
/// resize is modelled today; it is wired up in Phase 4 (`resize_group`). Until
/// then the action is optional and dragging a group divider is a no-op.
enum GroupSplitOperation {
    case resize(Resize)

    struct Resize {
        let node: SplitTree<GroupRef>.Node
        let ratio: Double
    }
}

/// Renders the group layer: a `SplitTree<GroupRef>` whose leaves are individual
/// groups (`SPEC.md` §6.1). Mirrors the structure of `TerminalSplitTreeView`
/// one level up.
struct GroupSplitTreeView: View {
    let tree: SplitTree<GroupRef>
    let groups: [GroupID: GroupState]
    let focusedGroup: GroupID?

    /// Every visible group's 1-based display number, keyed by id
    /// (`WorkspaceState.groupOrdinals`). Derived from the *canonical* tree, so a
    /// zoomed group keeps its number in the full layout instead of showing `1`.
    let ordinals: [GroupID: Int]

    /// The group currently in inline-rename mode, if any (`WorkspaceModel`).
    let renamingGroup: GroupID?

    /// Whether the note overview is active (`toggle_note_overview`): each
    /// rendered group lays its note over its content.
    let noteOverview: Bool

    let paneAction: (TerminalSplitOperation) -> Void

    /// Label focus / rename callbacks.
    let labelActions: GroupLabelActions

    /// Double-click on a group divider (`equalize_groups`, `SPEC.md` §11.5).
    let onEqualize: () -> Void

    /// Group-boundary resize. Wired up in Phase 4; `nil` until then.
    var groupAction: ((GroupSplitOperation) -> Void)?

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            GroupSplitSubtreeView(
                node: node,
                groups: groups,
                focusedGroup: focusedGroup,
                ordinals: ordinals,
                renamingGroup: renamingGroup,
                noteOverview: noteOverview,
                paneAction: paneAction,
                labelActions: labelActions,
                onEqualize: onEqualize,
                groupAction: groupAction)
            // Like `TerminalSplitTreeView`, we can't rely on SwiftUI's implicit
            // structural identity across the split tree. Keying on the group
            // tree's structural identity keeps each group's view (and the pane
            // tree nested within it) stable across unrelated mutations.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct GroupSplitSubtreeView: View {
    @EnvironmentObject var ghostty: XGhostty.App

    let node: SplitTree<GroupRef>.Node
    let groups: [GroupID: GroupState]
    let focusedGroup: GroupID?
    let ordinals: [GroupID: Int]
    let renamingGroup: GroupID?
    let noteOverview: Bool
    let paneAction: (TerminalSplitOperation) -> Void
    let labelActions: GroupLabelActions
    let onEqualize: () -> Void
    let groupAction: ((GroupSplitOperation) -> Void)?

    var body: some View {
        switch node {
        case .leaf(let ref):
            // A leaf whose group is missing from `groups` violates invariant
            // §14.1; render nothing rather than crash if that ever happens.
            if let group = groups[ref.id] {
                GroupView(
                    group: group,
                    isFocused: ref.id == focusedGroup,
                    ordinal: ordinals[ref.id],
                    isRenaming: ref.id == renamingGroup,
                    paneAction: paneAction,
                    labelActions: labelActions,
                    showsNoteOverlay: noteOverview)
            }

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    groupAction?(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    GroupSplitSubtreeView(
                        node: split.left,
                        groups: groups,
                        focusedGroup: focusedGroup,
                        ordinals: ordinals,
                        renamingGroup: renamingGroup,
                        noteOverview: noteOverview,
                        paneAction: paneAction,
                        labelActions: labelActions,
                        onEqualize: onEqualize,
                        groupAction: groupAction)
                },
                right: {
                    GroupSplitSubtreeView(
                        node: split.right,
                        groups: groups,
                        focusedGroup: focusedGroup,
                        ordinals: ordinals,
                        renamingGroup: renamingGroup,
                        noteOverview: noteOverview,
                        paneAction: paneAction,
                        labelActions: labelActions,
                        onEqualize: onEqualize,
                        groupAction: groupAction)
                },
                // Double-clicking any group divider equalizes the whole group
                // layout, exactly like the `equalize_groups` keybind.
                onEqualize: onEqualize
            )
        }
    }
}
