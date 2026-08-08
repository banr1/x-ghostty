import SwiftUI

/// The note editor overlay, opened by the `edit_group_note` action (Cmd+N)
/// for the focused group.
///
/// `TerminalWorkspaceView` presents this over the whole group layer while
/// `WorkspaceModel.noteEditingGroup` is set, and removes it entirely when the
/// editor closes, so the terminal returns to the full area.
///
/// The editor shows the full note — the model caps notes at
/// `GroupState.maxNoteLines` lines, and the editor is sized to fit that many
/// lines — and Escape saves the draft and closes (there is no separate
/// cancel path; leaving the editor always saves).
struct GroupNoteEditor: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The edited group's name, shown as the overlay header.
    let groupName: String

    /// The note text at open time; seeds the draft.
    let note: String

    /// Save the given draft and close the editor.
    let onEnd: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        // Fill the workspace so the panel centers regardless of the parent
        // ZStack's alignment. The backdrop dims the terminal slightly so the
        // panel reads as a transient layer above it, and a click on the
        // backdrop saves and closes like Escape does.
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onEnd(draft) }

            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            TextEditor(text: $draft)
                .font(editorFont)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: editorHeight, maxHeight: editorHeight)
                .padding(8)
                .focused($editorFocused)
                .onExitCommand { onEnd(draft) }
        }
        .frame(width: 480)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
        .onExitCommand { onEnd(draft) }
        .onAppear {
            draft = note
            // Grab focus on appearance. Dispatching to the next runloop turn
            // is required for the initial focus to stick (same workaround as
            // the command palette, ghostty#8497).
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
    }

    /// Header band: the group name plus the save-and-close affordance. Styled
    /// like `GroupLabel`'s band so the overlay reads as part of the group UI.
    private var header: some View {
        HStack {
            Text(groupName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("esc to save & close")
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.5)
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

    /// A monospaced font matching `GroupLabel`'s terminal-adjacent styling.
    private var editorFont: Font {
        .system(size: 12, design: .monospaced)
    }

    /// Tall enough to show the model's full line cap at once, so the edit
    /// overlay always shows the entire note.
    private var editorHeight: CGFloat {
        CGFloat(GroupState.maxNoteLines) * 17
    }
}
