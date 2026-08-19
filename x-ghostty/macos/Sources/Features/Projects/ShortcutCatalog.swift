import Foundation

/// The scenes the shortcut list groups by (`SPEC.md` §30): every place where
/// the keyboard means something different. The order here is the display
/// order of the overlay's groups.
enum ShortcutScene: CaseIterable, Equatable {
    case overallView
    case zoom
    case projectList
    case noteEditor
    case noteOverview

    /// The group header the overlay shows.
    var displayName: String {
        switch self {
        case .overallView: return "Overall view"
        case .zoom: return "Zoom (inside a project)"
        case .projectList: return "Project list"
        case .noteEditor: return "Note editor"
        case .noteOverview: return "Overview"
        }
    }
}

/// One listed shortcut: a display chord and what it does.
struct ShortcutItem: Equatable {
    let chord: String
    let label: String
}

/// One scene's shortcuts.
struct ShortcutGroup: Equatable {
    let scene: ShortcutScene
    let items: [ShortcutItem]
}

/// The model's single judgment of what the shortcut-list overlay shows
/// (`SPEC.md` §30): the effective shortcuts — the fork's project layer plus
/// the upstream-derived terminal chords that remain bound — grouped by scene.
///
/// The catalog is a curated static value rather than a config introspection:
/// the fork guarantees no keybind backward compatibility (`SPEC.md` §2) and
/// the overlay documents the effective defaults. Keep it in sync with the
/// defaults in `Config.zig` and the overlay key handlers; the removed
/// upstream defaults (Cmd+Enter fullscreen, Cmd+E search, Cmd+K clear) must
/// not appear here.
enum ShortcutCatalog {
    /// Every group in display order. `ShortcutScene.allCases` order.
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(scene: .overallView, items: [
            ShortcutItem(chord: "⌘1–9", label: "Focus project by ordinal"),
            ShortcutItem(chord: "⌘⌃⌥⇧←→↑↓", label: "Focus project (directional)"),
            ShortcutItem(chord: "⌘⌃⇧←→↑↓", label: "Move project"),
            ShortcutItem(chord: "⌘⌥↩", label: "Zoom into the focused project"),
            ShortcutItem(chord: "⌘⌥H", label: "Hide the focused project"),
            ShortcutItem(chord: "⌘L", label: "Project list (the ledger)"),
            ShortcutItem(chord: "⌘N", label: "New project (opens the list)"),
            ShortcutItem(chord: "⌘⌥L", label: "Layout-type selector"),
            ShortcutItem(chord: "⌘E", label: "Edit the focused project's note"),
            ShortcutItem(chord: "⌘⌥E", label: "Note overview (all visible projects)"),
            ShortcutItem(chord: "⌘⌥R", label: "Rename the focused project"),
            ShortcutItem(chord: "⌘W", label: "Close pane / project (confirms)"),
            ShortcutItem(chord: "⌘C · ⌘V", label: "Copy · paste"),
            ShortcutItem(chord: "⌘A", label: "Select all"),
            ShortcutItem(chord: "⌘F", label: "Find"),
            ShortcutItem(chord: "⌘↑ · ⌘↓", label: "Jump to previous · next prompt"),
            ShortcutItem(chord: "⌘Z · ⌘⇧Z", label: "Terminal undo · redo"),
            ShortcutItem(chord: "⌘⇧P", label: "Command palette"),
            ShortcutItem(chord: "⌘Q", label: "Quit"),
            ShortcutItem(chord: "⌘/", label: "This shortcut list"),
        ]),
        ShortcutGroup(scene: .zoom, items: [
            ShortcutItem(chord: "⌘D · ⌘⇧D", label: "Split right · down"),
            ShortcutItem(chord: "⌘[ · ⌘]", label: "Previous · next pane"),
            ShortcutItem(chord: "⌘⌥←→↑↓", label: "Focus pane (directional)"),
            ShortcutItem(chord: "⌘⌃←→↑↓", label: "Resize pane"),
            ShortcutItem(chord: "⌘⌃=", label: "Equalize panes"),
            ShortcutItem(chord: "⌘⇧↩", label: "Toggle pane zoom"),
            ShortcutItem(chord: "⌘P", label: "Make the focused pane primary"),
            ShortcutItem(chord: "⌘⌥↩", label: "Leave the zoom"),
            ShortcutItem(chord: "⌘L", label: "Project list (overlays the zoom)"),
            ShortcutItem(chord: "⌘/", label: "This shortcut list"),
        ]),
        ShortcutGroup(scene: .projectList, items: [
            ShortcutItem(chord: "←→↑↓ · ⇥ ⇧⇥", label: "Move the cell cursor"),
            ShortcutItem(chord: "⌘←→↑↓", label: "Jump the cursor to an edge"),
            ShortcutItem(chord: "↩", label: "Edit cell / toggle visibility / open candidates"),
            ShortcutItem(chord: "typing", label: "Replace-edit a text cell"),
            ShortcutItem(chord: "⇧↩", label: "Newline (note cell edit)"),
            ShortcutItem(chord: "esc", label: "Row selection · cancel an edit"),
            ShortcutItem(chord: "⌫", label: "Clear cell value · delete row (row selection)"),
            ShortcutItem(chord: "⌥↑↓ · ⌥←→", label: "Move row · column"),
            ShortcutItem(chord: "↑ (top row)", label: "Enter the sort bar"),
            ShortcutItem(chord: "⌘N", label: "New project below the cursor"),
            ShortcutItem(chord: "⌘↩", label: "Focus the cursor row's project"),
            ShortcutItem(chord: "⌘⌥E", label: "Toggle full-note display"),
            ShortcutItem(chord: "⌘L", label: "Close the list"),
            ShortcutItem(chord: "⌘/", label: "This shortcut list"),
        ]),
        ShortcutGroup(scene: .noteEditor, items: [
            ShortcutItem(chord: "⌘↩", label: "Save and close"),
            ShortcutItem(chord: "esc", label: "Discard and close"),
            ShortcutItem(chord: "⌘A ⌘C ⌘X ⌘V", label: "Standard text editing"),
            ShortcutItem(chord: "⌘Z · ⌘⇧Z", label: "Undo · redo (note body)"),
            ShortcutItem(chord: "⌘/", label: "This shortcut list"),
        ]),
        ShortcutGroup(scene: .noteOverview, items: [
            ShortcutItem(chord: "⌘⌥E", label: "Leave the overview"),
            ShortcutItem(chord: "esc", label: "Leave the overview"),
            ShortcutItem(chord: "⌘/", label: "This shortcut list"),
        ]),
    ]
}
