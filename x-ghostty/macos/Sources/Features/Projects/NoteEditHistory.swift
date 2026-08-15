import Foundation

/// Undo/redo history for one note-editing session (`SPEC.md` §21.2).
///
/// Scope is the Essence's, exactly: the history opens with the editor and dies
/// with it, and it covers the note body alone — priority and deadline are not
/// in it. That is why this is our own stack rather than the text view's
/// `NSUndoManager`: the responder chain's undo manager is the *window's*, which
/// holds the project-layer's own undo entries (hide, show, apply layout), so
/// routing Cmd+Z there would let a note edit undo a workspace change.
///
/// Typing coalesces: consecutive single-character edits made without a pause
/// collapse into one step, so Cmd+Z takes back a word-sized burst rather than
/// one letter. Anything bigger — a paste, a cut, a selection replacement —
/// always starts its own step, so a 10-line paste is undone in one press.
struct NoteEditHistory: Equatable {
    /// How long a typing run may pause before the next keystroke starts a new
    /// undo step.
    static var coalescingWindow: TimeInterval { 0.75 }

    /// The text the editor currently shows, as far as the history knows.
    private(set) var current: String

    private var undoStack: [String] = []
    private var redoStack: [String] = []

    /// When the last recorded change happened, on a monotonic clock; `nil`
    /// closes the current typing run, so the next edit always starts a step.
    private var lastRecordedAt: TimeInterval?

    init(_ initial: String) {
        current = initial
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Record `text` as the editor's new content, made at `time`.
    ///
    /// Idempotent for an unchanged value, which is what makes applying an undo
    /// back into the editor safe: the resulting change notification records
    /// nothing.
    mutating func record(_ text: String, at time: TimeInterval) {
        guard text != current else { return }

        // A step boundary is pushed unless this edit continues a typing run:
        // a one-character difference within the coalescing window. Not pushing
        // is what makes the run collapse — undo then returns to the state the
        // run started from, which is already on top of the stack.
        let continuesTypingRun = abs(text.count - current.count) <= 1
            && (lastRecordedAt.map { time - $0 <= Self.coalescingWindow } ?? false)
        if !continuesTypingRun {
            undoStack.append(current)
        }

        current = text
        redoStack.removeAll()
        lastRecordedAt = time
    }

    /// Step back one edit.
    ///
    /// - Returns: the text the editor should show, or `nil` when there is
    ///   nothing left to undo (the editor then stays as it is).
    mutating func undo() -> String? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        current = previous
        // An undo always ends the typing run: what is typed next must not be
        // folded into the step we just stepped out of.
        lastRecordedAt = nil
        return previous
    }

    /// Step forward one undone edit.
    ///
    /// - Returns: the text the editor should show, or `nil` when nothing was
    ///   undone (or something has been typed since, which drops the redos).
    mutating func redo() -> String? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        current = next
        lastRecordedAt = nil
        return next
    }
}
