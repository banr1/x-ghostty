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
    let paneAction: (TerminalSplitOperation) -> Void

    /// Group-boundary resize. Wired up in Phase 4; `nil` until then.
    var groupAction: ((GroupSplitOperation) -> Void)?

    /// Group labels only appear once more than one group exists so a single
    /// group stays visually identical to the previous (group-less) rendering.
    private var showsGroupLabels: Bool { groups.count > 1 }

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            GroupSplitSubtreeView(
                node: node,
                groups: groups,
                focusedGroup: focusedGroup,
                showsLabels: showsGroupLabels,
                paneAction: paneAction,
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
    @EnvironmentObject var ghostty: Ghostty.App

    let node: SplitTree<GroupRef>.Node
    let groups: [GroupID: GroupState]
    let focusedGroup: GroupID?
    let showsLabels: Bool
    let paneAction: (TerminalSplitOperation) -> Void
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
                    showsLabel: showsLabels,
                    paneAction: paneAction)
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
                        showsLabels: showsLabels,
                        paneAction: paneAction,
                        groupAction: groupAction)
                },
                right: {
                    GroupSplitSubtreeView(
                        node: split.right,
                        groups: groups,
                        focusedGroup: focusedGroup,
                        showsLabels: showsLabels,
                        paneAction: paneAction,
                        groupAction: groupAction)
                },
                onEqualize: {
                    // Group-boundary equalize arrives in Phase 4
                    // (`equalize_groups`).
                }
            )
        }
    }
}
