import SwiftUI

/// A local keyDown `NSEvent` monitor scoped to a view's on-screen lifetime,
/// shared by the project overlay family (`SPEC.md` §21.2, §25, §26.2).
///
/// The overlays own the keyboard through focused text machinery — the note
/// editor's `TextEditor`, the selection screens' invisible sink `TextField` —
/// and a focused text view consumes key events during key-binding
/// interpretation before SwiftUI's higher-level key handlers are guaranteed
/// a look: on-device, ↑/↓ never reached the sink field's `onMoveCommand`,
/// and the note editor's hidden Cmd+X / Cmd+V shortcut receivers never
/// affected the text view even though Cmd+A / Cmd+C did. A local monitor
/// observes each event before any dispatch, so the handler runs regardless
/// of what holds first responder; returning nil swallows the event so no
/// other responder acts on it.
struct OverlayKeyDownMonitor: ViewModifier {
    /// Handles one keyDown event: return nil to consume it, or the event to
    /// let normal dispatch continue.
    let handler: (NSEvent) -> NSEvent?

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown, handler: handler)
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// Installs a local keyDown monitor while this view is on screen
    /// (`OverlayKeyDownMonitor`). The overlay sessions are mutually
    /// exclusive on the model (`WorkspaceModel.overlaySessionActive`), so at
    /// most one overlay's monitor is installed at a time.
    func overlayKeyDownMonitor(
        _ handler: @escaping (NSEvent) -> NSEvent?
    ) -> some View {
        modifier(OverlayKeyDownMonitor(handler: handler))
    }

    /// Delivers plain (unmodified) ↑/↓ presses to `move` (-1 up, +1 down)
    /// while this view is on screen, consuming them so a focused field
    /// editor never sees them. Shared by the selection screens
    /// (`ProjectHideSelector`, `ProjectLayoutSelector`).
    func overlayArrowKeys(_ move: @escaping (Int) -> Void) -> some View {
        overlayKeyDownMonitor { event in
            guard event.modifierFlags
                .intersection([.command, .shift, .option, .control])
                .isEmpty
            else { return event }
            switch event.specialKey {
            case .some(.upArrow):
                move(-1)
                return nil
            case .some(.downArrow):
                move(1)
                return nil
            default:
                return event
            }
        }
    }
}
