import Foundation
import Testing
@testable import XGhostty

/// Tests for the note editor's session undo history (SPEC §21.3): the step
/// boundaries typing produces, the scope of a session, and that redo follows
/// undo but dies on the next edit.
struct ProjectNoteUndoTests {
    /// A time that is far enough past `at` to close a typing run.
    private static func afterPause(_ at: TimeInterval) -> TimeInterval {
        at + NoteEditHistory.coalescingWindow + 0.1
    }

    @Test func aFreshSessionHasNothingToUndo() {
        var history = NoteEditHistory("deploy notes")
        #expect(history.canUndo == false)
        #expect(history.canRedo == false)
        #expect(history.undo() == nil)
        #expect(history.redo() == nil)
        #expect(history.current == "deploy notes")
    }

    @Test func undoReturnsToTheTextTheEditorOpenedWith() {
        var history = NoteEditHistory("open")
        history.record("open text", at: 10)

        #expect(history.undo() == "open")
        #expect(history.current == "open")
        // And no further: the session's history starts at the open.
        #expect(history.undo() == nil)
    }

    @Test func aTypingRunCollapsesIntoOneStep() {
        var history = NoteEditHistory("")
        // Five keystrokes in quick succession.
        for (index, text) in ["h", "he", "hel", "hell", "hello"].enumerated() {
            history.record(text, at: 10 + Double(index) * 0.1)
        }

        #expect(history.current == "hello")
        #expect(history.undo() == "")
        #expect(history.canUndo == false)
    }

    @Test func aPauseStartsANewStep() {
        var history = NoteEditHistory("")
        history.record("a", at: 10)
        history.record("ab", at: 10.1)
        let resumed = Self.afterPause(10.1)
        history.record("abc", at: resumed)
        history.record("abcd", at: resumed + 0.1)

        // The second run undoes back to where it began, the first to the open.
        #expect(history.undo() == "ab")
        #expect(history.undo() == "")
        #expect(history.undo() == nil)
    }

    @Test func aPasteIsAlwaysItsOwnStep() {
        var history = NoteEditHistory("")
        history.record("a", at: 10)
        // A multi-character change is never folded into a typing run, even
        // with no pause at all: one Cmd+Z takes back the whole paste.
        history.record("a" + String(repeating: "pasted line\n", count: 12), at: 10.05)

        #expect(history.undo() == "a")
        #expect(history.undo() == "")
    }

    @Test func redoFollowsUndoAndDiesOnTheNextEdit() {
        var history = NoteEditHistory("")
        history.record("first", at: 10)
        history.record("second", at: Self.afterPause(10))

        #expect(history.undo() == "first")
        #expect(history.canRedo == true)
        #expect(history.redo() == "second")
        #expect(history.canRedo == false)

        // Undo, then type: the redo branch is dropped.
        #expect(history.undo() == "first")
        history.record("first branch", at: 100)
        #expect(history.canRedo == false)
        #expect(history.redo() == nil)
    }

    @Test func typingAfterAnUndoStartsItsOwnStep() {
        // Without closing the run on undo, the next keystroke would coalesce
        // into the step we just stepped out of and the undo would look lost.
        var history = NoteEditHistory("")
        history.record("a", at: 10)
        #expect(history.undo() == "")
        history.record("b", at: 10.05)

        #expect(history.current == "b")
        #expect(history.undo() == "")
    }

    @Test func reapplyingTheSameTextRecordsNothing() {
        // The editor writes an undone value back into its draft, which comes
        // straight back here as a change; it must not become a step.
        var history = NoteEditHistory("note")
        history.record("note edited", at: 10)
        let undone = history.undo()
        #expect(undone == "note")

        history.record("note", at: 10.2)
        #expect(history.canUndo == false)
        #expect(history.redo() == "note edited")
    }
}
