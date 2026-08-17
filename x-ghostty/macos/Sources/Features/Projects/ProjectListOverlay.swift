import SwiftUI

/// The project-list overlay (`list_projects`, Cmd+L, `SPEC.md` §27).
///
/// Tabulates every project — hidden ones included — as title, priority,
/// deadline and the note's first line, with the visible ones in ordinal order
/// and the hidden ones after them, marked as hidden. ↑/↓ move the cursor,
/// Space toggles the cursor row between hidden and visible in place, Enter
/// focuses a visible row's project and closes, Escape closes. This is the only
/// way back from hidden, which is why it takes the cheap chord.
///
/// Judgment stays on the model (`WorkspaceModel.projectListRows` /
/// `canToggleProjectListVisibility` / `canFocusProjectListRow`); this view
/// renders rows and forwards events. It is rendered only while the session is
/// up, so it occupies no permanent terminal area.
///
/// Keyboard mechanics are `ProjectLayoutSelector`'s: an invisible focused
/// text field owns first responder so the terminal sees no keystrokes,
/// Escape arrives via `onExitCommand`, Enter via `onSubmit`, Space as typed
/// text in the sink, and the arrows through the shared local keyDown monitor
/// (`overlayArrowKeys`) because a focused field editor eats them first.
struct ProjectListOverlay: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// Every project as a row, visible first in ordinal order.
    let rows: [ProjectListRow]

    /// Whether Space would change anything for a row — the model refuses to
    /// hide the last visible project and to show one past the visible cap.
    let canToggle: (ProjectID) -> Bool

    /// Whether Enter would focus a row (visible rows only).
    let canFocus: (ProjectID) -> Bool

    /// Deadline-overdue judgment for a row, for the single-stage emphasis.
    let isOverdue: (ProjectID) -> Bool

    /// Toggle the row between hidden and visible, immediately.
    let onToggle: (ProjectID) -> Void

    /// Focus the row's project and close (Enter on a visible row).
    let onFocus: (ProjectID) -> Void

    /// Close the list (Escape / backdrop click). Toggles already made stay.
    let onClose: () -> Void

    /// The keyboard cursor row. Pure presentation state.
    @State private var cursor = 0

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            panel

            keyCatcher
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyCatcher: some View {
        TextField("", text: $keyboardSink)
            .textFieldStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .focused($catcherFocused)
            .onExitCommand { onClose() }
            .onSubmit { focusCursorRow() }
            .overlayArrowKeys { moveCursor($0) }
            .onChange(of: keyboardSink) { typed in
                guard !typed.isEmpty else { return }
                if typed.contains(" ") { toggleCursorRow() }
                keyboardSink = ""
            }
            .accessibilityHidden(true)
            .onAppear {
                keyboardSink = ""
                // The next-runloop-turn dispatch is what makes the initial
                // focus stick (same workaround as the command palette).
                DispatchQueue.main.async {
                    catcherFocused = true
                }
            }
    }

    private func moveCursor(_ delta: Int) {
        guard !rows.isEmpty else { return }
        cursor = (cursor + delta + rows.count) % rows.count
    }

    private func toggleCursorRow() {
        guard rows.indices.contains(cursor) else { return }
        onToggle(rows[cursor].id)
    }

    private func focusCursorRow() {
        guard rows.indices.contains(cursor) else { return }
        onFocus(rows[cursor].id)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.1.id) { index, row in
                            self.row(row, index: index)
                                .id(row.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
                .onChange(of: cursor) { newValue in
                    guard rows.indices.contains(newValue) else { return }
                    proxy.scrollTo(rows[newValue].id)
                }
            }

            footerView
        }
        .frame(width: 520)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    /// One table row: number (or the hidden marker), title, priority and
    /// deadline, then the note's first line filling the rest. Unset fields
    /// render as nothing, so the columns stay quiet.
    private func row(_ row: ProjectListRow, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(row.ordinal.map(String.init) ?? "·")
                .opacity(row.isHidden ? 0.35 : 0.5)
                .frame(minWidth: 12, alignment: .trailing)

            Text(row.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 140, alignment: .leading)

            ProjectPriorityDeadlineMeta(
                priority: row.priority,
                deadline: row.deadline,
                isOverdue: isOverdue(row.id))
                .frame(width: 110, alignment: .leading)

            Text(row.noteFirstLine)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0.5)

            Spacer(minLength: 0)
        }
        // Hidden rows are dimmed as a whole: the row is still readable and
        // still togglable, but reads as "not on screen right now".
        .opacity(row.isHidden ? 0.45 : 1.0)
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(index == cursor ? Color.secondary.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            cursor = index
        }
    }

    private var header: some View {
        HStack {
            Text("projects")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("space hide/show · ↩ focus · esc close")
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

    /// Footer: what the cursor row's keys would do right now, so a refused
    /// Space (the last visible project, or the visible cap) explains itself
    /// instead of looking broken.
    private var footerView: some View {
        HStack {
            Text(footerText)
                .opacity(0.55)
            Spacer()
            Text("\(rows.filter { !$0.isHidden }.count) visible · \(rows.filter(\.isHidden).count) hidden")
                .opacity(0.4)
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

    private var footerText: String {
        guard rows.indices.contains(cursor) else { return "" }
        let row = rows[cursor]
        if row.isHidden {
            return canToggle(row.id)
                ? "space shows \(row.title)"
                : "no room to show — hide another project first"
        }
        if !canToggle(row.id) {
            return "at least one project must stay visible"
        }
        return canFocus(row.id)
            ? "space hides \(row.title) · ↩ focuses it"
            : "space hides \(row.title)"
    }
}
