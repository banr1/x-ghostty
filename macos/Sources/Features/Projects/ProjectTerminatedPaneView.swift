import SwiftUI

/// Covers a terminated pane — a project's protected last pane whose shell has
/// exited (`SPEC.md` §23.2–23.3).
///
/// `ProjectView` renders this over the project's pane area while the project is in
/// the terminated state, so the dead terminal reads as "finished, resumable"
/// rather than as a live shell: the project and its note are preserved, and
/// pressing Enter starts a new shell in the same pane (the key itself is
/// routed by the surface view's exited-pane key path, not by this view).
///
/// Styling follows the note-surface family (`ProjectNoteOverviewOverlay`): the
/// terminal's own background color and split-divider stroke, monospaced type,
/// so the overlay fits the terminal. Hit-testing is disabled: clicks pass
/// through to the dead surface underneath, so clicking a terminated project
/// still focuses it — which is exactly what routes the subsequent Enter to
/// the restart path.
struct ProjectTerminatedPaneView: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    var body: some View {
        ZStack {
            // Dim the dead terminal's last frame rather than blanking it: the
            // final output often says how the shell ended.
            Color.black.opacity(0.45)

            panel
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var panel: some View {
        VStack(spacing: 6) {
            Image(systemName: "poweroff")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Shell exited")
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            Text("Press ⏎ to start a new shell")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shell exited. Press Return to start a new shell.")
    }
}
