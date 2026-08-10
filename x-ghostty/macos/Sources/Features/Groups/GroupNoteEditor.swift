import SwiftUI

/// The note editor overlay, opened by the `edit_group_note` action (Cmd+N)
/// for the focused group (`SPEC.md` §21.2).
///
/// `TerminalWorkspaceView` presents this over the whole group layer while
/// `WorkspaceModel.noteEditingGroup` is set, and removes it entirely when the
/// editor closes, so the terminal returns to the full area.
///
/// The editor shows the full note — the model caps notes at
/// `GroupState.maxNoteLines` lines, and the editor is sized to fit that many
/// lines. Cmd+Enter (or a backdrop click) saves the draft and closes;
/// Escape discards the draft and closes without confirmation, keeping the
/// text the note had when the editor opened.
///
/// Standard text-editing chords (Cmd+A/C/X/V) act on the editor while the
/// overlay is shown (`SPEC.md` §21.2): the Edit menu's key equivalents are
/// synced to terminal actions (`copy_to_clipboard` etc.), which do not reach
/// the text view, so hidden shortcut receivers in the overlay forward the
/// chords to the first responder (the editor's text view) as the standard
/// `selectAll:`/`copy:`/`cut:`/`paste:` selectors. The window's key-equivalent
/// pass runs before the menu bar's, so this wins only while the overlay
/// exists; terminal copy/paste behavior outside the editor is unchanged.
struct GroupNoteEditor: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The edited group's name, shown as the overlay header.
    let groupName: String

    /// The note text at open time; seeds the draft.
    let note: String

    /// Save the given draft and close the editor (Cmd+Enter / backdrop click).
    let onEnd: (String) -> Void

    /// Discard the draft and close the editor (Escape).
    let onCancel: () -> Void

    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        // Fill the workspace so the panel centers regardless of the parent
        // ZStack's alignment. The backdrop dims the terminal slightly so the
        // panel reads as a transient layer above it, and a click on the
        // backdrop saves and closes like Cmd+Enter does (only Escape
        // discards).
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onEnd(draft) }

            panel

            // Cmd+Enter save chord. The system key-equivalent pass delivers
            // it here even while the TextEditor owns keyboard focus (same
            // hidden-button pattern as GroupNoteOverviewKeyCatcher). Only
            // works because this fork unbinds the upstream
            // cmd+enter=toggle_fullscreen default (Config.zig).
            Button { onEnd(draft) } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            // Standard text-editing chords. Without these, the Edit menu's
            // synced key equivalents (terminal copy/paste actions) would match
            // first and the chords would never reach the text view; these
            // receivers forward them to the first responder — the focused
            // editor — as the standard editing selectors.
            editingChordReceiver(#selector(NSText.selectAll(_:)), key: "a")
            editingChordReceiver(#selector(NSText.copy(_:)), key: "c")
            editingChordReceiver(#selector(NSText.cut(_:)), key: "x")
            editingChordReceiver(#selector(NSText.paste(_:)), key: "v")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A hidden Cmd+`key` receiver that sends `selector` down the responder
    /// chain (first responder is the editor's text view while the overlay is
    /// up). Same hidden-button pattern as the Cmd+Enter save chord above.
    private func editingChordReceiver(
        _ selector: Selector, key: KeyEquivalent
    ) -> some View {
        Button { NSApp.sendAction(selector, to: nil, from: nil) } label: { Color.clear }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut(key, modifiers: [.command])
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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
                .onExitCommand { onCancel() }
        }
        .frame(width: 480)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
        .onExitCommand { onCancel() }
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

    /// Header band: the group name plus the save/discard affordances. Styled
    /// like `GroupLabel`'s band so the overlay reads as part of the group UI.
    private var header: some View {
        HStack {
            Text(groupName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("⌘↩ save · esc discard")
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
