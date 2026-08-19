import AppKit
import SwiftUI

/// The list's in-place cell editor (`SPEC.md` §27.5): a borderless AppKit text
/// field, so editing a cell is ordinary macOS text input — Japanese IME
/// composition included.
///
/// The SwiftUI `TextField` this replaces could not do that. The overlay owns
/// the keyboard through a local keyDown monitor that runs before any dispatch
/// (`OverlayKeyDownMonitor`), and the monitor consumed the keystroke that
/// starts an edit and seeded the draft with its raw characters — so the first
/// stroke never reached an input context and no composition could begin. Two
/// pieces fix that here:
///
/// - `pendingKeyEvent`: the starting keystroke is handed to this editor
///   instead of to the draft, and replayed into the field editor's input
///   context the moment the field takes first responder — the IME sees it as
///   the first stroke of a composition (must 78).
/// - `isComposing`: while the field editor holds a marked (uncommitted)
///   string, the monitor yields Space / Enter / Escape / Tab to the IME rather
///   than reading them as the session's own cycle / commit / cancel / move
///   (`ProjectListCellEdit.routing(for:shifted:composing:)`).
///
/// The field owns its own first responder: SwiftUI's `@FocusState` is released
/// while the edit is up, so nothing fights the field editor for focus mid
/// composition.
final class ProjectListCellEditorHandle {
    /// The live cell field, while an edit is up.
    weak var field: NSTextField?

    /// The keystroke that started the edit, waiting to be replayed into the
    /// field editor's input context. Consumed once, on seating.
    var pendingKeyEvent: NSEvent?

    /// Whether seating places the caret at the end of the seeded text
    /// instead of leaving the field's select-all default. Set for the
    /// Enter-opened edit (`SPEC.md` §27.2: the caret enters the existing
    /// text — typing must extend it, not replace it); a typed edit starts
    /// from an empty draft, where selection is moot.
    var placeCaretAtEnd = false

    /// Whether the IME currently holds a marked (uncommitted) string in the
    /// cell's field editor.
    var isComposing: Bool {
        guard let editor = field?.currentEditor() as? NSTextView else { return false }
        return editor.hasMarkedText()
    }
}

struct ProjectListCellEditor: NSViewRepresentable {
    /// The edit session's draft. The field is the source of truth while it is
    /// up; this binding follows every committed change.
    @Binding var text: String

    /// The bridge the overlay's keyDown monitor reads (`isComposing`) and
    /// writes (`pendingKeyEvent`).
    let handle: ProjectListCellEditorHandle

    /// The cell font, matching the table's rows.
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        handle.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        handle.field = field
        context.coordinator.text = $text

        // Never write over a composition: the marked string lives in the field
        // editor, and replacing the field's value would discard it.
        if !handle.isComposing, field.stringValue != text {
            field.stringValue = text
        }

        guard !context.coordinator.seated else { return }
        seat(field, coordinator: context.coordinator, attemptsLeft: 5)
    }

    /// Give the field first responder and replay the keystroke that started
    /// the edit into its field editor (SwiftUI's focus is released for the
    /// duration of the edit, so nothing fights it). The field is not in a
    /// window on the first update pass, so this retries across a few runloop
    /// turns — the same next-turn dispatch the overlay family already uses to
    /// make an initial focus stick.
    private func seat(
        _ field: NSTextField, coordinator: Coordinator, attemptsLeft: Int
    ) {
        DispatchQueue.main.async {
            guard !coordinator.seated else { return }
            guard let window = field.window else {
                if attemptsLeft > 1 {
                    seat(field, coordinator: coordinator, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            coordinator.seated = true
            window.makeFirstResponder(field)
            if handle.placeCaretAtEnd {
                // The Enter-opened edit: collapse the select-all default so
                // the caret sits at the end of the existing text (SPEC §27.2).
                handle.placeCaretAtEnd = false
                let length = field.stringValue.utf16.count
                field.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
            }
            guard let event = handle.pendingKeyEvent else { return }
            handle.pendingKeyEvent = nil
            (field.currentEditor() as? NSTextView)?.interpretKeyEvents([event])
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.handle?.field = nil
        coordinator.handle?.pendingKeyEvent = nil
        coordinator.handle?.placeCaretAtEnd = false
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.text = $text
        coordinator.handle = handle
        return coordinator
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>?
        var handle: ProjectListCellEditorHandle?

        /// Whether the field has already claimed first responder and replayed
        /// the starting keystroke.
        var seated = false

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text?.wrappedValue = field.stringValue
        }
    }
}
