import SwiftUI

/// The note editor overlay, opened by the `edit_project_note` action (Cmd+E)
/// for the focused project (`SPEC.md` §21.2).
///
/// `TerminalWorkspaceView` presents this over the whole project layer while
/// `WorkspaceModel.noteEditingProject` is set, and removes it entirely when the
/// editor closes, so the terminal returns to the full area.
///
/// The editor reaches the full note by scrolling (the model caps stored notes
/// at `ProjectState.maxNoteLines` lines). Cmd+Enter (or a backdrop click)
/// saves the draft and closes — through the over-limit confirmation when the
/// draft exceeds the cap (`SPEC.md` §21.1); Escape discards the draft and
/// closes without confirmation, keeping the text the note had when the editor
/// opened.
///
/// Standard text-editing chords (Cmd+A/C/X/V) act on the editor while the
/// overlay is shown (`SPEC.md` §21.2): the Edit menu's key equivalents are
/// synced to terminal actions (`copy_to_clipboard` etc.), which do not reach
/// the text view, so a local keyDown monitor scoped to the overlay's
/// lifetime (`OverlayKeyDownMonitor`) intercepts the chords before any
/// key-equivalent or menu dispatch and performs the standard
/// `selectAll:`/`copy:`/`cut:`/`paste:` selectors directly on the focused
/// text view. Hidden `keyboardShortcut` receivers with
/// `NSApp.sendAction(to: nil)` were tried first and delivered
/// `selectAll:`/`copy:` but never `cut:`/`paste:` on device, so the chords
/// rely neither on the key-equivalent pass nor on action dispatch. The
/// monitor exists only while the overlay does; terminal copy/paste behavior
/// outside the editor is unchanged.
struct ProjectNoteEditor: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The edited project's name, shown as the overlay header.
    let projectName: String

    /// The note text at open time; seeds the draft.
    let note: String

    /// Save the note draft and close the editor (Cmd+Enter / backdrop
    /// click). Priority and deadline are set in the project list's cells,
    /// never here (SPEC §24.1, §27.2).
    let onEnd: (String) -> Void

    /// Discard the draft and close the editor (Escape).
    let onCancel: () -> Void

    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    /// The session's undo history for the note body (`SPEC.md` §21.2). Created
    /// with the editor and dropped with it, so Cmd+Z can never reach past the
    /// open into the project layer's own undo entries.
    @State private var history = NoteEditHistory("")

    /// Commit the note draft (every save path funnels here). A draft within
    /// the line cap saves silently; an over-limit draft asks for confirmation
    /// (`SPEC.md` §21.1) — OK truncates to the first `maxNoteLines` lines and
    /// saves, Cancel returns to editing with the draft untouched. Editing
    /// input and paste themselves are never limited or silently truncated.
    private func commit() {
        if ProjectState.noteExceedsLimit(draft) {
            let alert = NSAlert()
            alert.messageText = "Note exceeds \(ProjectState.maxNoteLines) lines"
            alert.informativeText =
                "Saving will keep the first \(ProjectState.maxNoteLines) lines "
                + "and drop the rest."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        onEnd(draft)
    }

    var body: some View {
        // Fill the workspace so the panel centers regardless of the parent
        // ZStack's alignment. The backdrop dims the terminal slightly so the
        // panel reads as a transient layer above it, and a click on the
        // backdrop saves and closes like Cmd+Enter does (only Escape
        // discards).
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { commit() }

            panel

            // Cmd+Enter save chord. The system key-equivalent pass delivers
            // it here even while the TextEditor owns keyboard focus (same
            // hidden-button pattern as ProjectNoteOverviewKeyCatcher). Only
            // works because this fork unbinds the upstream
            // cmd+enter=toggle_fullscreen default (Config.zig).
            Button { commit() } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Standard text-editing chords. Without this, the Edit menu's synced
        // key equivalents (terminal copy/paste actions) would match and the
        // chords would never reach the text view. A local monitor rather
        // than hidden shortcut buttons: the button + sendAction path proved
        // partial on device (Cmd+A/C acted, Cmd+X/V did nothing), so the
        // chords are taken before any dispatch and performed on the focused
        // text view directly.
        .overlayKeyDownMonitor { event in
            let modifiers = event.modifierFlags
                .intersection([.command, .shift, .option, .control])
            guard let chord = event.charactersIgnoringModifiers?.lowercased()
            else { return event }

            // Undo/redo run on the session history rather than the responder
            // chain's undo manager (`SPEC.md` §21.2): that one belongs to the
            // window and holds the project layer's entries.
            if chord == "z", modifiers == [.command] {
                if let text = history.undo() { draft = text }
                return nil
            }
            if chord == "z", modifiers == [.command, .shift] {
                if let text = history.redo() { draft = text }
                return nil
            }

            guard modifiers == [.command],
                  let selector = Self.editingSelectors[chord]
            else { return event }
            Self.performOnEditor(selector)
            return nil
        }
    }

    /// The standard editing selectors the overlay guarantees while shown
    /// (`SPEC.md` §21.2), keyed by their Cmd chord letter.
    private static let editingSelectors: [String: Selector] = [
        "a": #selector(NSText.selectAll(_:)),
        "c": #selector(NSText.copy(_:)),
        "x": #selector(NSText.cut(_:)),
        "v": #selector(NSText.paste(_:)),
    ]

    /// Performs an editing selector on the focused text view directly (the
    /// note editor's NSTextView), falling back to the responder chain when
    /// first responder is not a text view.
    private static func performOnEditor(_ selector: Selector) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
           editor.responds(to: selector) {
            editor.perform(selector, with: nil)
        } else {
            NSApp.sendAction(selector, to: nil, from: nil)
        }
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
                .onChange(of: draft) { text in
                    // Every edit — typed, pasted, cut, or applied by an undo
                    // — passes through here; the history ignores the ones it
                    // caused itself. `systemUptime` is monotonic, so a clock
                    // change cannot make a typing run coalesce oddly.
                    history.record(text, at: ProcessInfo.processInfo.systemUptime)
                }
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
            // The session's history starts at the text the editor opened with,
            // so the first Cmd+Z returns to it and no further.
            history = NoteEditHistory(note)
            // Grab focus on appearance. Dispatching to the next runloop turn
            // is required for the initial focus to stick (same workaround as
            // the command palette, ghostty#8497).
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
    }

    /// Header band: the project name plus the save/discard affordances. Styled
    /// like `ProjectLabel`'s band so the overlay reads as part of the project UI.
    private var header: some View {
        HStack {
            Text(projectName)
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

    /// A monospaced font matching `ProjectLabel`'s terminal-adjacent styling.
    private var editorFont: Font {
        .system(size: 12, design: .monospaced)
    }

    /// A fixed visible height; the editor scrolls to reach the full text
    /// (`SPEC.md` §21.3) — with the cap at 100 lines, sizing to the cap would
    /// overflow the window.
    private var editorHeight: CGFloat {
        20 * 17
    }
}
