import SwiftUI

/// The project-list overlay (`list_projects`, Cmd+L, `SPEC.md` §27).
///
/// The ledger's table form: every project — hidden ones included — as one row
/// in the single ledger order, with the six columns (visibility, title,
/// priority, deadline, next trigger, note) in the persisted column order.
/// Unset cells render blank. The panel takes ~80% of the window in both
/// dimensions, exists only while the session is up, and scrolls with the cell
/// cursor when the rows do not fit.
///
/// Cell mechanics (`SPEC.md` §27.2): Tab / Shift+Tab / Enter / Shift+Enter
/// (and the arrows) move the cell cursor with the row-end wrap and the
/// last-row stop; typing on a text column starts an in-place edit that Enter
/// / Tab commit and Escape cancels (only the edit); Space cycles the
/// selection columns — visibility toggles hide/show immediately, with the
/// layout re-forming behind the list; Cmd+↑/↓ move the cursor row and
/// Cmd+←/→ the cursor column, persistently; Cmd+Enter focuses a visible
/// row's project and closes; Cmd+Opt+E toggles whole-list full-note display;
/// Escape outside an edit closes the list.
///
/// Judgment stays on the model — `ProjectListCellCursor` owns the movement
/// rules, `ProjectListCellEdit` the edit session, and the `WorkspaceModel`
/// session wrappers every mutation; this view renders rows and forwards
/// events. Keyboard mechanics are the overlay family's: an invisible focused
/// text field owns first responder so the terminal sees no keystrokes, and a
/// local keyDown monitor (`OverlayKeyDownMonitor`) observes every key before
/// any dispatch — including the ones a focused field editor would eat.
///
/// While a cell edit is up, first responder passes to the edit's AppKit field
/// (`ProjectListCellEditor`) so the cell is ordinary macOS text input: the
/// keystroke that started the edit is replayed through its input context and
/// the monitor yields every key to the IME while a marked string is up
/// (`SPEC.md` §27.5).
struct ProjectListOverlay: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// Every project as a row, in the ledger's single row order.
    let rows: [ProjectListRow]

    /// The persisted column order the table renders (`SPEC.md` §27.1).
    let columns: [ProjectListColumn]

    /// Whether the note column shows every line instead of first lines only
    /// (`Cmd+Opt+E` inside the list, viewing-only, transient).
    let fullNotes: Bool

    /// A just-created project whose title cell should open in edit mode
    /// (`Cmd+N`, `SPEC.md` §27.4), or `nil`. Consumed once seated via
    /// `onConsumePendingTitleEdit`.
    let pendingTitleEdit: ProjectID?

    /// The active sort state the bar highlights (`SPEC.md` §24.5).
    let sortState: ProjectSortState

    /// Whether Space would change anything for a row — the model refuses to
    /// hide the last visible project and to show one past the visible cap.
    let canToggle: (ProjectID) -> Bool

    /// Whether Cmd+Enter would focus a row (visible rows only).
    let canFocus: (ProjectID) -> Bool

    /// Deadline-overdue judgment for a row, for the single-stage emphasis.
    let isOverdue: (ProjectID) -> Bool

    /// Toggle the row between hidden and visible, immediately (Space on the
    /// visibility column).
    let onToggle: (ProjectID) -> Void

    /// Focus the row's project and close (Cmd+Enter on a visible row).
    let onFocus: (ProjectID) -> Void

    /// Close the list (Escape outside an edit / backdrop click). Edits
    /// committed and toggles made during the session stay.
    let onClose: () -> Void

    /// Commit an in-place text-cell edit (draft, column, row id).
    let onCommitEdit: (String, ProjectListColumn, ProjectID) -> Void

    /// Space on a cycling selection cell (priority / next trigger).
    let onCycle: (ProjectListColumn, ProjectID) -> Void

    /// Space (`true`) / Shift+Space (`false`) on the deadline cell outside
    /// an edit (`SPEC.md` §27.2): step the date, committing immediately.
    let onStepDeadline: (ProjectID, Bool) -> Void

    /// Move a row by ±1 in the ledger order (Cmd+↑ / Cmd+↓). Returns the
    /// row's new index, or `nil` when nothing moved (a clamped end).
    let onMoveRow: (ProjectID, Int) -> Int?

    /// Move a column by ±1 in the column order (Cmd+← / Cmd+→). Returns the
    /// column's new index, or `nil` when nothing moved.
    let onMoveColumn: (ProjectListColumn, Int) -> Int?

    /// Toggle whole-list full-note display (Cmd+Opt+E inside the list).
    let onToggleFullNotes: () -> Void

    /// Apply a sort state (the bar's Enter, or a mouse click on a bar chip,
    /// `SPEC.md` §24.5). Selecting manual inherits the current display order
    /// — the model's judgment.
    let onSetSortState: (ProjectSortState) -> Void

    /// Create a new project below the given cursor row (Cmd+N inside the
    /// list, `SPEC.md` §27.4). The new row comes back via `pendingTitleEdit`.
    let onCreate: (ProjectID?) -> Void

    /// The pending title edit has been seated on the new row's title cell;
    /// clear it so a later re-render does not re-open the edit.
    let onConsumePendingTitleEdit: () -> Void

    /// The keyboard cell cursor. Pure presentation state; the movement rules
    /// live on `ProjectListCellCursor`.
    @State private var cursor = ProjectListCellCursor(row: 0, column: 0)

    /// The in-place edit session, or `nil`. Commit applies the draft through
    /// `onCommitEdit`; cancel just discards this value (`SPEC.md` §27.2).
    @State private var edit: ProjectListCellEdit?

    /// The sort bar's keyboard selection, or `nil` while the cursor is in
    /// the table (`SPEC.md` §24.5). Entered with Up from the top row seeded
    /// with the active state; Left/Right move it (`movedInBar`), Enter
    /// applies it and returns to the table, Escape returns without applying.
    /// Pure presentation state, like `cursor`.
    @State private var sortBarSelection: ProjectSortState?

    private enum FocusTarget: Hashable { case catcher }
    @FocusState private var focus: FocusTarget?
    @State private var keyboardSink = ""

    /// The bridge to the cell editor's AppKit field (`SPEC.md` §27.5): the
    /// keystroke that starts an edit is replayed through it, and it reports
    /// whether the IME currently holds a marked string.
    @State private var editor = ProjectListCellEditorHandle()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                panel
                    // ~80% of the window in both dimensions (SPEC §27.1).
                    .frame(
                        width: geometry.size.width * 0.8,
                        height: geometry.size.height * 0.8)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2)

                keyCatcher
            }
        }
        .overlayKeyDownMonitor { handleKey($0) }
        // Both faces of Cmd+N (SPEC §27.4): a creation from inside the list
        // fires onChange; the outside-the-list action opens the list with the
        // pending edit already set, which onAppear picks up.
        .onAppear { DispatchQueue.main.async { seatPendingTitleEdit() } }
        .onChange(of: pendingTitleEdit) { _ in seatPendingTitleEdit() }
    }

    // MARK: Keyboard

    /// The invisible sink that owns first responder while no cell edit is
    /// up, so the terminal never sees the session's keystrokes. All actual
    /// key handling happens in the keyDown monitor; text that still reaches
    /// the sink is discarded.
    private var keyCatcher: some View {
        TextField("", text: $keyboardSink)
            .textFieldStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .focused($focus, equals: .catcher)
            .onChange(of: keyboardSink) { typed in
                if !typed.isEmpty { keyboardSink = "" }
            }
            .accessibilityHidden(true)
            .onAppear {
                keyboardSink = ""
                // The next-runloop-turn dispatch is what makes the initial
                // focus stick (same workaround as the command palette).
                DispatchQueue.main.async {
                    focus = .catcher
                }
            }
    }

    /// One keyDown event, observed before any dispatch. Returns `nil` to
    /// consume, or the event to let normal dispatch continue (menu key
    /// equivalents stay reachable that way).
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags
            .intersection([.command, .shift, .option, .control])
        let isEscape = event.keyCode == 53

        if edit != nil {
            // While editing, the cell field owns every key except the edit's
            // own terminators (SPEC §27.2): Enter / Tab commit and move,
            // Escape cancels only this edit — unless the IME holds a marked
            // string, in which case every key is the IME's (SPEC §27.5, must
            // 78). The routing itself is the model's judgment.
            let shifted = modifiers == [.shift] || event.specialKey == .some(.backTab)
            let press = Self.editKeyPress(for: event, isEscape: isEscape)
            switch ProjectListCellEdit.routing(
                for: press, shifted: shifted, composing: editor.isComposing
            ) {
            case .commit(let move):
                commitEdit(thenMove: move)
                return nil
            case .cancel:
                cancelEdit()
                return nil
            case .editor:
                return event
            }
        }

        // While the keyboard is on the sort bar it owns every plain key
        // (`SPEC.md` §24.5): Left/Right choose, Enter applies and returns to
        // the table, Escape (or Down) returns without applying. Cmd-chords
        // fall through so the session shortcuts keep working.
        if let selection = sortBarSelection {
            guard modifiers.subtracting([.shift]).isEmpty else { return event }
            if isEscape {
                sortBarSelection = nil
                return nil
            }
            switch event.specialKey {
            case .some(.leftArrow):
                sortBarSelection = selection.movedInBar(by: -1)
            case .some(.rightArrow):
                sortBarSelection = selection.movedInBar(by: 1)
            case .some(.carriageReturn), .some(.enter):
                onSetSortState(selection)
                sortBarSelection = nil
            case .some(.downArrow):
                // Down is Escape's twin: back into the table, not applying.
                sortBarSelection = nil
            default:
                break
            }
            return nil
        }

        if isEscape {
            onClose()
            return nil
        }

        // Cmd+Opt+E: whole-list full-note toggle (SPEC §27.2).
        if modifiers == [.command, .option],
           event.charactersIgnoringModifiers?.lowercased() == "e" {
            onToggleFullNotes()
            return nil
        }

        // Cmd+N: create a new project below the cursor row (SPEC §27.4). The
        // new row arrives through `pendingTitleEdit`, which seats the cursor
        // on its title cell in edit mode.
        if modifiers == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "n" {
            onCreate(cursorRow?.id)
            return nil
        }

        // Cmd+Enter focuses the cursor row's project (visible rows only —
        // a hidden row is inert and the list stays up, SPEC §27.3).
        if modifiers == [.command],
           event.specialKey == .carriageReturn || event.specialKey == .enter {
            if let row = cursorRow { onFocus(row.id) }
            return nil
        }

        // Cmd+arrows reorder: the cursor row through the ledger, the cursor
        // column through the persisted column order (SPEC §27.1). The model
        // reports the moved row's/column's new index and the cursor follows
        // it, so consecutive moves keep acting on the same row/column; a
        // clamped move reports nothing and the cursor stays put.
        if modifiers == [.command], let special = event.specialKey {
            switch special {
            case .upArrow, .downArrow:
                let delta = special == .upArrow ? -1 : 1
                if let row = cursorRow, let moved = onMoveRow(row.id, delta) {
                    cursor.row = moved
                }
                return nil
            case .leftArrow, .rightArrow:
                let delta = special == .leftArrow ? -1 : 1
                if let column = cursorColumn, let moved = onMoveColumn(column, delta) {
                    cursor.column = moved
                }
                return nil
            default:
                break
            }
        }

        guard modifiers.subtracting([.shift]).isEmpty else { return event }

        // Plain movement: Tab / Shift+Tab / Enter / Shift+Enter and the
        // arrows, with the row-end wrap and the edge stops
        // (`ProjectListCellCursor`). Up from the top row leaves the table
        // and enters the sort bar, seeded with the active state
        // (`SPEC.md` §24.5).
        if let move = Self.cursorMove(for: event, shifted: modifiers == [.shift]) {
            // The Up *arrow* specifically — not Shift+Enter's up move —
            // mounts the bar (SPEC §24.5).
            if move == .up, cursor.row == 0, event.specialKey == .some(.upArrow) {
                sortBarSelection = sortState
            } else {
                moveCursor(move)
            }
            return nil
        }

        // Space: the selection columns cycle, and the deadline cell steps
        // its date — Space forward, Shift+Space back (SPEC §27.2). On the
        // other text columns it does nothing — typing there starts an edit,
        // and a stray leading space is not a useful edit to start.
        if event.charactersIgnoringModifiers == " " {
            spaceOnCursorCell(shifted: modifiers == [.shift])
            return nil
        }

        // Any other printable character starts an in-place edit on a text
        // column (SPEC §27.2). The keystroke is *not* seeded into the draft:
        // it is replayed into the new editor's input context, so an IME
        // composition starts on this very stroke instead of its raw character
        // landing in the cell (SPEC §27.5, must 78).
        if let typed = event.characters,
           !typed.isEmpty,
           event.specialKey == nil,
           !typed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
           let row = cursorRow,
           let column = cursorColumn,
           column.isTextColumn {
            beginEdit(row: row, column: column, replaying: event)
            return nil
        }

        return event
    }

    /// How the edit session reads a key event (`SPEC.md` §27.5). Shift+Tab
    /// arrives as its own special key and means the same press as Tab.
    private static func editKeyPress(
        for event: NSEvent, isEscape: Bool
    ) -> ProjectListEditKeyPress {
        if isEscape { return .escape }
        switch event.specialKey {
        case .some(.carriageReturn), .some(.enter): return .enter
        case .some(.tab), .some(.backTab): return .tab
        default: return .other
        }
    }

    /// The plain-movement reading of a key event, or `nil` when the event is
    /// not a movement key.
    private static func cursorMove(
        for event: NSEvent, shifted: Bool
    ) -> ProjectListCellCursor.Move? {
        switch event.specialKey {
        case .some(.tab): return shifted ? .left : .right
        case .some(.backTab): return .left
        case .some(.carriageReturn), .some(.enter): return shifted ? .up : .down
        case .some(.rightArrow): return .right
        case .some(.leftArrow): return .left
        case .some(.downArrow): return .down
        case .some(.upArrow): return .up
        default: return nil
        }
    }

    // MARK: Cursor and cells

    private var cursorRow: ProjectListRow? {
        rows.indices.contains(cursor.row) ? rows[cursor.row] : nil
    }

    private var cursorColumn: ProjectListColumn? {
        columns.indices.contains(cursor.column) ? columns[cursor.column] : nil
    }

    private func moveCursor(_ move: ProjectListCellCursor.Move) {
        cursor = cursor.moved(
            move, rowCount: rows.count, columnCount: columns.count)
    }

    private func spaceOnCursorCell(shifted: Bool) {
        guard let row = cursorRow, let column = cursorColumn else { return }
        switch column {
        case .visibility:
            onToggle(row.id)
        case .priority, .nextTrigger:
            onCycle(column, row.id)
        case .deadline:
            onStepDeadline(row.id, !shifted)
        case .title, .note:
            break
        }
    }

    /// Start an in-place edit, handing `event` — the keystroke that started
    /// it — to the cell editor to replay through the IME (`SPEC.md` §27.5).
    /// Passing `nil` starts an edit no keystroke opened (the Cmd+N title
    /// cell).
    private func beginEdit(
        row: ProjectListRow, column: ProjectListColumn, replaying event: NSEvent?
    ) {
        guard let session = ProjectListCellEdit.started(on: row, column: column) else {
            return
        }
        editor.pendingKeyEvent = event
        // The cell field takes first responder itself, so SwiftUI's focus
        // claim is released first — released synchronously, before the editor
        // exists, so nothing fights it mid composition.
        focus = nil
        edit = session
    }

    private func commitEdit(thenMove move: ProjectListCellCursor.Move) {
        guard let session = edit else { return }
        onCommitEdit(session.draft, session.column, session.rowID)
        endEdit()
        moveCursor(move)
    }

    private func cancelEdit() {
        endEdit()
    }

    private func endEdit() {
        edit = nil
        editor.pendingKeyEvent = nil
        DispatchQueue.main.async { focus = .catcher }
    }

    /// Seat the cursor on the pending new row's title cell in edit mode
    /// (`Cmd+N`, SPEC §27.4). The draft starts empty so the title can be
    /// typed immediately; cancelling keeps the generated name.
    private func seatPendingTitleEdit() {
        guard let id = pendingTitleEdit,
              let rowIndex = rows.firstIndex(where: { $0.id == id }),
              let columnIndex = columns.firstIndex(of: .title)
        else { return }
        cursor = ProjectListCellCursor(row: rowIndex, column: columnIndex)
        beginEdit(row: rows[rowIndex], column: .title, replaying: nil)
        onConsumePendingTitleEdit()
    }

    // MARK: Table

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            sortBar

            columnHeader

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
                .onChange(of: cursor) { newValue in
                    // The cursor stays on screen: scroll follows it
                    // (SPEC §27.1).
                    guard rows.indices.contains(newValue.row) else { return }
                    proxy.scrollTo(rows[newValue.row].id)
                }
            }

            footerView
        }
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
        .onChange(of: rows.count) { newCount in
            // A row set that shrank under the cursor (close elsewhere, a
            // future in-list create) clamps it back onto the grid.
            cursor = cursor.clamped(
                rowCount: max(newCount, 1), columnCount: max(columns.count, 1))
        }
    }

    /// The fixed width of a column's cells, or `nil` for the flexible title
    /// and note columns, which share the panel width left by the fixed ones.
    /// Fixed widths hold each column's widest value at the 12pt monospaced
    /// cell font: "●" / "·", "high", "YYYY-MM-DD", "external".
    private static func width(of column: ProjectListColumn) -> CGFloat? {
        switch column {
        case .visibility: return 34
        case .title: return nil
        case .priority: return 48
        case .deadline: return 92
        case .nextTrigger: return 72
        case .note: return nil
        }
    }

    /// The one width rule both the header band and the cells apply, so the
    /// columns stay aligned: a fixed column takes its width, a flexible one
    /// expands into an equal share of the remaining panel width.
    @ViewBuilder
    private static func columnFrame(
        _ column: ProjectListColumn, _ content: some View
    ) -> some View {
        if let width = width(of: column) {
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func headerLabel(of column: ProjectListColumn) -> String {
        switch column {
        case .visibility: return "show"
        case .title: return "title"
        case .priority: return "prio"
        case .deadline: return "deadline"
        case .nextTrigger: return "next"
        case .note: return "note"
        }
    }

    /// The sort bar (`SPEC.md` §24.5): the five states at the very top of
    /// the table. The active state is always marked; while the keyboard is
    /// on the bar (Up from the top row) the selection candidate carries the
    /// stronger highlight. A mouse click applies a state directly.
    private var sortBar: some View {
        HStack(spacing: 6) {
            Text("sort")
                .opacity(0.4)

            ForEach(ProjectSortState.barOrder, id: \.self) { state in
                sortBarChip(state)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ghostty.config.splitDividerColor.opacity(0.3))
                .frame(height: 1)
        }
    }

    private func sortBarChip(_ state: ProjectSortState) -> some View {
        let isActive = state == sortState
        let isSelected = state == sortBarSelection
        return Text(state.displayText)
            .opacity(isActive ? 0.95 : 0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                isSelected
                    ? Color.secondary.opacity(0.3)
                    : isActive ? Color.secondary.opacity(0.12) : Color.clear)
            .cornerRadius(3)
            .contentShape(Rectangle())
            .onTapGesture {
                guard edit == nil else { return }
                onSetSortState(state)
                sortBarSelection = nil
            }
    }

    /// The column-label band, in the persisted column order, with the cursor
    /// column marked.
    private var columnHeader: some View {
        HStack(spacing: 8) {
            // The ordinal gutter's slot.
            Text("")
                .frame(minWidth: 16, alignment: .trailing)

            ForEach(Array(columns.enumerated()), id: \.1.id) { index, column in
                Self.columnFrame(
                    column,
                    Text(Self.headerLabel(of: column))
                        .opacity(index == cursor.column ? 0.9 : 0.4))
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ghostty.config.splitDividerColor.opacity(0.5))
                .frame(height: 1)
        }
    }

    /// One table row: the ordinal gutter (or the hidden marker), then the
    /// cells in column order. Unset fields render as nothing, so the columns
    /// stay quiet.
    private func row(_ row: ProjectListRow, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(row.ordinal.map(String.init) ?? "·")
                .opacity(row.isHidden ? 0.35 : 0.5)
                .frame(minWidth: 16, alignment: .trailing)

            ForEach(Array(columns.enumerated()), id: \.1.id) { columnIndex, column in
                cell(row: row, rowIndex: index, column: column, columnIndex: columnIndex)
            }

            Spacer(minLength: 0)
        }
        // Hidden rows are dimmed as a whole: still readable, still editable,
        // but reading as "not on screen right now".
        .opacity(row.isHidden ? 0.5 : 1.0)
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(index == cursor.row ? Color.secondary.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            guard edit == nil else { return }
            cursor.row = index
        }
    }

    /// One cell: the in-place editor when this cell holds the edit session,
    /// the column's display value otherwise. The cursor cell carries the
    /// stronger highlight.
    @ViewBuilder
    private func cell(
        row: ProjectListRow, rowIndex: Int,
        column: ProjectListColumn, columnIndex: Int
    ) -> some View {
        let isCursor = rowIndex == cursor.row && columnIndex == cursor.column
        let isEditing = isCursor && edit != nil

        Self.columnFrame(column, Group {
            if isEditing {
                // An AppKit field, not a SwiftUI TextField: the cell edit has
                // to be ordinary macOS text input, IME composition included
                // (SPEC §27.5).
                ProjectListCellEditor(
                    text: Binding(
                        get: { edit?.draft ?? "" },
                        set: { edit?.draft = $0 }),
                    handle: editor)
            } else {
                cellText(row: row, column: column)
            }
        })
        .padding(.horizontal, 2)
        .background(
            isCursor ? Color.secondary.opacity(isEditing ? 0.3 : 0.22) : Color.clear)
        .cornerRadius(2)
        .onTapGesture {
            guard edit == nil else { return }
            cursor = ProjectListCellCursor(row: rowIndex, column: columnIndex)
        }
    }

    @ViewBuilder
    private func cellText(row: ProjectListRow, column: ProjectListColumn) -> some View {
        switch column {
        case .visibility:
            Text(row.isHidden ? "·" : "●")
                .opacity(row.isHidden ? 0.4 : 0.7)

        case .title:
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.tail)

        case .priority:
            Text(row.priority.map(Self.priorityText) ?? "")
                .opacity(0.75)

        case .deadline:
            // The single-stage overdue emphasis (SPEC §24.2), same styling
            // family as the label band's.
            Text(row.deadline?.displayText ?? "")
                .foregroundStyle(
                    isOverdue(row.id)
                        ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .opacity(isOverdue(row.id) ? 0.9 : 0.6)

        case .nextTrigger:
            Text(row.nextTrigger?.displayText ?? "")
                .opacity(0.6)

        case .note:
            // Full-note display shows every line (viewing-only, Cmd+Opt+E);
            // the normal table shows the first line.
            Text(fullNotes ? row.note : row.noteFirstLine)
                .lineLimit(fullNotes ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0.55)
        }
    }

    private static func priorityText(_ priority: ProjectPriority) -> String {
        switch priority {
        case .high: return "high"
        case .medium: return "med"
        case .low: return "low"
        }
    }

    private var header: some View {
        HStack {
            Text("projects")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("type edit · space cycle · ↑ sort · ⌘n new · ⌘↩ focus · ⌘⌥e notes · esc close")
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

    /// Footer: what the cursor cell's keys would do right now, so a refused
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
        if edit != nil {
            return "↩/⇥ commit · esc cancel edit"
        }
        if sortBarSelection != nil {
            return "←→ choose · ↩ apply sort · esc back to table"
        }
        guard let row = cursorRow, let column = cursorColumn else { return "" }
        switch column {
        case .visibility:
            if row.isHidden {
                return canToggle(row.id)
                    ? "space shows \(row.title)"
                    : "no room to show — hide another project first"
            }
            return canToggle(row.id)
                ? "space hides \(row.title)"
                : "at least one project must stay visible"
        case .priority:
            return "space cycles priority"
        case .nextTrigger:
            return "space cycles next trigger"
        case .deadline:
            let base = "space today/+1d · ⇧space back · type to edit deadline"
            return canFocus(row.id) ? base + " · ⌘↩ focuses \(row.title)" : base
        case .title, .note:
            let base = "type to edit \(Self.headerLabel(of: column))"
            return canFocus(row.id) ? base + " · ⌘↩ focuses \(row.title)" : base
        }
    }
}
