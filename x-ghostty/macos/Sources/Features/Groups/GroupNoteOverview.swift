import SwiftUI

/// The read-only note panel the note overview (`toggle_note_overview`,
/// Cmd+Opt+N, `SPEC.md` §21.3) lays over one visible group.
///
/// `GroupView` renders this over its own content while the overview is
/// active, so every visible group shows its note at once. The panel never
/// edits: it only displays the note, truncated to whatever fits the group
/// without breaking the layout — the edit overlay (`GroupNoteEditor`) is
/// where the full text is guaranteed visible.
struct GroupNoteOverviewOverlay: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    let group: GroupState

    var body: some View {
        ZStack {
            // Local backdrop: dims this group's terminal so the note reads as
            // a transient layer above it, and swallows clicks — the overview
            // is viewing-only.
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture {}

            panel
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Group {
                if group.note.isEmpty {
                    Text("no note")
                        .opacity(0.4)
                } else {
                    Text(group.note)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            // The model caps notes at `maxNoteLines`; the line limit plus the
            // group-bounded frame truncate the display when the group is too
            // small, instead of growing past its bounds.
            .lineLimit(GroupState.maxNoteLines)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(maxWidth: 480)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    /// Header band: the group name, styled like `GroupNoteEditor`'s header so
    /// the two note surfaces read as one family.
    private var header: some View {
        HStack {
            Text(group.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ghostty.config.backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ghostty.config.splitDividerColor)
                .frame(height: 1)
        }
    }
}

/// Invisible interaction layer for the note overview, rendered over the whole
/// workspace while the mode is active.
///
/// It blocks mouse interaction with everything underneath (the overview is
/// viewing-only) and owns the keyboard: Escape and the overview's own
/// Cmd+Opt+N chord both leave the mode. An invisible focused text field holds
/// first responder — the terminal must not see keystrokes while the mode is
/// up, and `onExitCommand` needs a focused view to deliver Escape to (the
/// same mechanics as `GroupNoteEditor`'s TextEditor).
struct GroupNoteOverviewKeyCatcher: View {
    /// Leave the overview (Escape).
    let onExit: () -> Void

    /// Toggle the overview (the re-pressed Cmd+Opt+N chord). The surface's
    /// binding path is inert while it is not first responder, so the default
    /// `toggle_note_overview` chord is re-matched here.
    let onToggle: () -> Void

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            TextField("", text: $keyboardSink)
                .textFieldStyle(.plain)
                .opacity(0)
                .frame(width: 0, height: 0)
                .focused($catcherFocused)
                .onExitCommand { onExit() }
                .accessibilityHidden(true)

            Button { onToggle() } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("n", modifiers: [.command, .option])
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            keyboardSink = ""
            // Grab focus on appearance. Dispatching to the next runloop turn
            // is required for the initial focus to stick (same workaround as
            // the command palette, ghostty#8497).
            DispatchQueue.main.async {
                catcherFocused = true
            }
        }
    }
}
