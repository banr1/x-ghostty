import Foundation
import Testing
@testable import XGhostty

/// Tests for the list's clipboard judgment (SPEC §27.7, must 83): what each
/// column's cell value copies as, what a pasted string sets — per-column,
/// with unacceptable strings ignored — the editing shortcuts a cell edit
/// routes to its own editor, and the candidate menu's Tab / Shift+Tab
/// lateral move that closes the menu without changing the value.
struct ProjectListClipboardTests {
    private static func makeRow(
        title: String = "alpha",
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        nextTrigger: ProjectNextTrigger? = nil,
        note: String = ""
    ) -> ProjectListRow {
        ProjectListRow(
            id: ProjectID(),
            title: title,
            ordinal: 1,
            isHidden: false,
            priority: priority,
            deadline: deadline,
            nextTrigger: nextTrigger,
            note: note)
    }

    // MARK: Copy (value extraction)

    @Test func copyLiftsEachColumnsValueInItsOwnSpelling() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 8, day: 20))
        let row = Self.makeRow(
            title: "atlas",
            priority: .medium,
            deadline: deadline,
            nextTrigger: .externalPerson,
            note: "line 1\nline 2\nline 3")

        #expect(ProjectListClipboard.copyText(of: row, column: .title) == "atlas")
        #expect(ProjectListClipboard.copyText(of: row, column: .priority) == "med")
        #expect(ProjectListClipboard.copyText(of: row, column: .deadline) == "2026-08-20")
        #expect(ProjectListClipboard.copyText(of: row, column: .nextTrigger) == "external")
    }

    @Test("the note column copies every line, not the displayed first line")
    func copyLiftsTheWholeNote() {
        let note = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let row = Self.makeRow(note: note)
        #expect(ProjectListClipboard.copyText(of: row, column: .note) == note)
    }

    @Test("unset values copy as the blank the cell shows")
    func copyOfUnsetValuesIsBlank() {
        let row = Self.makeRow()
        #expect(ProjectListClipboard.copyText(of: row, column: .priority) == "")
        #expect(ProjectListClipboard.copyText(of: row, column: .deadline) == "")
        #expect(ProjectListClipboard.copyText(of: row, column: .nextTrigger) == "")
        #expect(ProjectListClipboard.copyText(of: row, column: .note) == "")
    }

    @Test("the visibility column has nothing to copy")
    func copyOfVisibilityIsNil() {
        #expect(ProjectListClipboard.copyText(of: Self.makeRow(), column: .visibility) == nil)
    }

    // MARK: Paste (value application)

    @Test func pasteAppliesAcceptedValuesPerColumn() throws {
        #expect(ProjectListClipboard.pasteApplication(of: "beta", column: .title)
            == .setTitle("beta"))
        #expect(ProjectListClipboard.pasteApplication(of: "  beta  ", column: .title)
            == .setTitle("beta"))
        #expect(ProjectListClipboard.pasteApplication(of: "high", column: .priority)
            == .setPriority(.high))
        #expect(ProjectListClipboard.pasteApplication(of: "med", column: .priority)
            == .setPriority(.medium))
        #expect(ProjectListClipboard.pasteApplication(of: "Medium", column: .priority)
            == .setPriority(.medium))
        let deadline = try #require(ProjectDeadline(year: 2026, month: 8, day: 20))
        #expect(ProjectListClipboard.pasteApplication(of: "2026-08-20", column: .deadline)
            == .setDeadline(deadline))
        #expect(ProjectListClipboard.pasteApplication(of: "2026/8/20", column: .deadline)
            == .setDeadline(deadline))
        #expect(ProjectListClipboard.pasteApplication(of: "me", column: .nextTrigger)
            == .setNextTrigger(.myself))
        #expect(ProjectListClipboard.pasteApplication(of: "external", column: .nextTrigger)
            == .setNextTrigger(.externalPerson))
        #expect(ProjectListClipboard.pasteApplication(of: "a\nb\nc", column: .note)
            == .setNote("a\nb\nc"))
    }

    @Test("a copied cell value pastes back as the same value (round trip)")
    func pasteRoundTripsCopiedValues() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 12, day: 31))
        let row = Self.makeRow(
            title: "atlas", priority: .low, deadline: deadline, nextTrigger: .event)
        for (column, expected) in [
            (ProjectListColumn.title, ProjectListPasteApplication.setTitle("atlas")),
            (.priority, .setPriority(.low)),
            (.deadline, .setDeadline(deadline)),
            (.nextTrigger, .setNextTrigger(.event)),
        ] {
            let copied = try #require(ProjectListClipboard.copyText(of: row, column: column))
            #expect(ProjectListClipboard.pasteApplication(of: copied, column: column) == expected)
        }
    }

    @Test("strings a column does not accept are ignored — no mutation")
    func pasteIgnoresUnacceptableStrings() {
        #expect(ProjectListClipboard.pasteApplication(of: "urgent", column: .priority)
            == .ignore)
        #expect(ProjectListClipboard.pasteApplication(of: "tomorrow", column: .deadline)
            == .ignore)
        #expect(ProjectListClipboard.pasteApplication(of: "2026-13-40", column: .deadline)
            == .ignore)
        #expect(ProjectListClipboard.pasteApplication(of: "team", column: .nextTrigger)
            == .ignore)
        // Blank never sets anything: clearing a value is Delete's job.
        for column in ProjectListColumn.allCases {
            #expect(ProjectListClipboard.pasteApplication(of: "  \n ", column: column)
                == .ignore)
        }
    }

    @Test("the visibility column never changes by paste")
    func pasteIntoVisibilityIsIgnored() {
        #expect(ProjectListClipboard.pasteApplication(of: "shown", column: .visibility)
            == .ignore)
        #expect(ProjectListClipboard.pasteApplication(of: "●", column: .visibility)
            == .ignore)
    }

    // MARK: Editing shortcuts during a cell edit (must 83)

    @Test func editingShortcutsMapTheSixStandardChords() {
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "a", shifted: false)
            == .selectAll)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "c", shifted: false)
            == .copy)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "x", shifted: false)
            == .cut)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "v", shifted: false)
            == .paste)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "z", shifted: false)
            == .undo)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "Z", shifted: true)
            == .redo)
    }

    @Test("chords outside the six keep their existing meaning")
    func editingShortcutsIgnoreOtherChords() {
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "n", shifted: false)
            == nil)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "a", shifted: true)
            == nil)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "v", shifted: true)
            == nil)
        #expect(ProjectListEditorShortcut.shortcut(forCommandCharacter: "/", shifted: false)
            == nil)
    }

    // MARK: Tab / Shift+Tab while candidates are enumerated (must 83)

    @Test("Tab closes the candidates without a commit and moves the cursor right")
    func candidateTabClosesAndMovesRight() {
        #expect(ProjectListCandidateMenu.routing(for: .tab, shifted: false)
            == .closeAndMoveCursor(.right))
        #expect(ProjectListCandidateMenu.routing(for: .tab, shifted: true)
            == .closeAndMoveCursor(.left))
    }

    @Test("the other candidate keys keep their meanings")
    func candidateRoutingKeepsExistingKeys() {
        #expect(ProjectListCandidateMenu.routing(for: .up, shifted: false)
            == .moveSelection(-1))
        #expect(ProjectListCandidateMenu.routing(for: .down, shifted: false)
            == .moveSelection(1))
        #expect(ProjectListCandidateMenu.routing(for: .enter, shifted: false)
            == .commitSelection)
        #expect(ProjectListCandidateMenu.routing(for: .escape, shifted: false)
            == .close)
        #expect(ProjectListCandidateMenu.routing(for: .other, shifted: false)
            == .ignore)
    }
}
