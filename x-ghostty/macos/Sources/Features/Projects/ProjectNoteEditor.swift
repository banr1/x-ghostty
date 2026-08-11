import SwiftUI

/// The note editor overlay, opened by the `edit_project_note` action (Cmd+N)
/// for the focused project (`SPEC.md` §21.2).
///
/// `TerminalWorkspaceView` presents this over the whole project layer while
/// `WorkspaceModel.noteEditingProject` is set, and removes it entirely when the
/// editor closes, so the terminal returns to the full area.
///
/// The editor shows the full note — the model caps notes at
/// `ProjectState.maxNoteLines` lines, and the editor is sized to fit that many
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
struct ProjectNoteEditor: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The edited project's name, shown as the overlay header.
    let projectName: String

    /// The note text at open time; seeds the draft.
    let note: String

    /// The priority at open time; seeds the priority draft (SPEC §24.1).
    let priority: ProjectPriority?

    /// The deadline at open time; seeds the deadline text draft (SPEC §24.1).
    let deadline: ProjectDeadline?

    /// Save the given draft set — note, priority, deadline text input — and
    /// close the editor (Cmd+Enter / backdrop click). The deadline input is
    /// validated at the model boundary: invalid input is rejected to unset.
    let onEnd: (String, ProjectPriority?, String) -> Void

    /// Discard all drafts and close the editor (Escape).
    let onCancel: () -> Void

    @State private var draft: String = ""
    @State private var priorityDraft: ProjectPriority?
    @State private var deadlineDraft: String = ""
    @FocusState private var editorFocused: Bool

    /// Commit the full draft set (every save path funnels here).
    private func commit() {
        onEnd(draft, priorityDraft, deadlineDraft)
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

            metaRow
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
            priorityDraft = priority
            deadlineDraft = deadline?.displayText ?? ""
            // Grab focus on appearance. Dispatching to the next runloop turn
            // is required for the initial focus to stick (same workaround as
            // the command palette, ghostty#8497).
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
    }

    /// Priority and deadline controls (SPEC §24.1), sharing the note's commit
    /// point: nothing here touches the model directly — the drafts ride the
    /// same Cmd+Enter save / Escape discard as the note text.
    private var metaRow: some View {
        HStack(spacing: 6) {
            Text("priority")
                .opacity(0.5)
            Picker("", selection: $priorityDraft) {
                Text("none").tag(ProjectPriority?.none)
                Text("high").tag(ProjectPriority?.some(.high))
                Text("med").tag(ProjectPriority?.some(.medium))
                Text("low").tag(ProjectPriority?.some(.low))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            Spacer(minLength: 8)

            Text("deadline")
                .opacity(0.5)
            TextField("YYYY-MM-DD", text: $deadlineDraft)
                .textFieldStyle(.plain)
                .frame(width: 84)
                .onSubmit { commit() }
            // The save-time judgment is the model's (invalid input is
            // rejected to unset); this hint only previews it, reusing the
            // same parser so the two can never disagree.
            if deadlineDraftInvalid {
                Text("→ unset")
                    .opacity(0.5)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ghostty.config.splitDividerColor)
                .frame(height: 1)
        }
    }

    /// Whether the current deadline draft would be rejected to unset on save:
    /// non-empty but not a real date (SPEC §24.1).
    private var deadlineDraftInvalid: Bool {
        let trimmed = deadlineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && ProjectDeadline(parsing: trimmed) == nil
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

    /// Tall enough to show the model's full line cap at once, so the edit
    /// overlay always shows the entire note.
    private var editorHeight: CGFloat {
        CGFloat(ProjectState.maxNoteLines) * 17
    }
}
