import SwiftUI

/// Renders a single group: its pane split tree with an optional name-label
/// overlay (`SPEC.md` §6.3).
///
/// The label is an overlay (`ZStack`) so it never pushes the terminal layout
/// down (invariant §14.13). Phase 1 keeps the label intentionally minimal —
/// just the name, full opacity when focused and dimmed otherwise (§7.1) — and
/// only shows it when more than one group exists, so a single-group workspace
/// stays visually identical to the pre-group-layer view. Full label styling and
/// interaction (single-click focus, double-click rename) arrive in Phase 3
/// (`GroupLabel.swift`).
struct GroupView: View {
    let group: GroupState
    let isFocused: Bool

    /// Whether to draw the name label. Driven by group count so single-group
    /// layouts remain pixel-identical to the previous rendering.
    var showsLabel: Bool = true

    /// Pane-level operations within this group's terminal split tree. In Phase 1
    /// only the focused group exists, so this routes to the controller's
    /// `surfaceTree`-based handler.
    let paneAction: (TerminalSplitOperation) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalSplitTreeView(
                tree: group.paneTree,
                action: paneAction)

            if showsLabel {
                Text(group.name)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    // Focused groups are emphasized; unfocused groups stay
                    // visible but recede (`SPEC.md` §7.1).
                    .opacity(isFocused ? 1.0 : 0.4)
                    .padding(6)
                    // Phase 1 label is decorative only; focus/rename hit-testing
                    // is added in Phase 3.
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
