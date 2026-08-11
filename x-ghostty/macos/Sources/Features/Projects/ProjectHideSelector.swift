import SwiftUI

/// A project multi-pick screen over the whole workspace: the hide-selection
/// screen (`hide_project`, Cmd+Opt+H, `SPEC.md` §25) and the layout
/// application's excess hide-pick (`SPEC.md` §26.3) share it — both pick
/// visible projects to hide, differing only in wording and in the model's
/// confirm judgment, which the caller passes in.
///
/// Lists every visible project in ordinal order for multi-toggle selection:
/// ↑/↓ move the cursor, Space (or a row click) toggles the row, Enter
/// confirms, Escape (or a backdrop click) cancels without hiding anything.
/// All selection judgment lives on the model; this view only renders it and
/// forwards events. Rendered only while a session is up, so no permanent
/// terminal area is occupied.
///
/// Keyboard mechanics follow `CommandPaletteView`: an invisible focused text
/// field holds first responder so the terminal sees no keystrokes, delivering
/// Escape via `onExitCommand` and Enter via `onSubmit`. Space arrives as
/// typed text into the sink field and is consumed as the toggle key;
/// everything else typed is discarded. The arrows come through a local
/// keyDown monitor (`overlayArrowKeys`) instead of `onMoveCommand`: while
/// the editable sink field is focused, the field editor consumes arrow
/// presses before `onMoveCommand` fires (found dead on device), so the
/// cursor keys are taken before any dispatch.
struct ProjectHideSelector: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The header title (e.g. "hide projects").
    let title: String

    /// The header key hint (e.g. "space toggle · ↩ hide · esc cancel").
    let hint: String

    /// The footer status line — the pending count, or why Enter is blocked.
    /// Computed by the caller from the model's judgment so the two screens
    /// can word it differently.
    let footer: String

    /// The listed projects, in ordinal (canonical traversal) order.
    let projects: [ProjectState]

    /// Each visible project's display number, for the row prefix.
    let ordinals: [ProjectID: Int]

    /// The projects currently toggled for hiding.
    let selection: Set<ProjectID>

    /// Whether Enter would confirm (the model's judgment: the hide-selection
    /// rejects a select-all, the layout hide-pick requires exactly the
    /// excess count).
    let canConfirm: Bool

    /// Toggle one project in the selection.
    let onToggle: (ProjectID) -> Void

    /// Confirm the selection (Enter). The model re-judges `canConfirm`, so
    /// forwarding a rejected confirm is harmless — the screen stays up.
    let onConfirm: () -> Void

    /// Close the screen hiding nothing (Escape / backdrop click).
    let onCancel: () -> Void

    /// The keyboard cursor row. Pure presentation state: which row Space
    /// toggles next; the selection itself lives on the model.
    @State private var cursor = 0

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

    var body: some View {
        ZStack {
            // Backdrop: dims the terminal so the screen reads as a transient
            // layer above it. A click outside the panel cancels — only Enter
            // ever hides anything.
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            panel

            keyCatcher
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The invisible first-responder text field that owns the keyboard while
    /// the screen is up (the same mechanics as `CommandPaletteQuery`).
    private var keyCatcher: some View {
        TextField("", text: $keyboardSink)
            .textFieldStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .focused($catcherFocused)
            .onExitCommand { onCancel() }
            .onSubmit { onConfirm() }
            .overlayArrowKeys { moveCursor($0) }
            .onChange(of: keyboardSink) { typed in
                // Typed text lands here instead of the terminal. Space is the
                // toggle key; everything else is discarded.
                guard !typed.isEmpty else { return }
                if typed.contains(" ") { toggleCursorRow() }
                keyboardSink = ""
            }
            .accessibilityHidden(true)
            .onAppear {
                keyboardSink = ""
                // Grab focus on appearance. Dispatching to the next runloop
                // turn is required for the initial focus to stick (same
                // workaround as the command palette, ghostty#8497).
                DispatchQueue.main.async {
                    catcherFocused = true
                }
            }
    }

    private func moveCursor(_ delta: Int) {
        guard !projects.isEmpty else { return }
        cursor = (cursor + delta + projects.count) % projects.count
    }

    private func toggleCursorRow() {
        guard projects.indices.contains(cursor) else { return }
        onToggle(projects[cursor].id)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(projects.enumerated()), id: \.1.id) { index, project in
                            row(project, index: index)
                                .id(project.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 220)
                .onChange(of: cursor) { newValue in
                    guard projects.indices.contains(newValue) else { return }
                    proxy.scrollTo(projects[newValue].id)
                }
            }

            footerView
        }
        .frame(width: 420)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    private func row(_ project: ProjectState, index: Int) -> some View {
        let isSelected = selection.contains(project.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .opacity(isSelected ? 0.9 : 0.4)

            if let ordinal = ordinals[project.id] {
                Text("\(ordinal)")
                    .opacity(0.5)
                    .frame(minWidth: 12, alignment: .trailing)
            }

            Text(project.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(isSelected ? 1.0 : 0.8)

            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(index == cursor ? Color.secondary.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            cursor = index
            onToggle(project.id)
        }
    }

    /// Header band, styled like `ProjectNoteEditor`'s so the overlay family
    /// reads as one.
    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text(hint)
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

    /// Footer: the caller-provided status line, dimmed when Enter is blocked.
    private var footerView: some View {
        HStack {
            Text(footer)
                .opacity(canConfirm ? 0.6 : 0.5)
            Spacer()
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ghostty.config.splitDividerColor)
                .frame(height: 1)
        }
    }
}
