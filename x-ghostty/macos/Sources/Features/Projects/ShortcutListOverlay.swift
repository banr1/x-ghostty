import SwiftUI

/// The shortcut-list overlay (`toggle_shortcut_list`, Cmd+/, `SPEC.md` §30).
///
/// A read-only enumeration of the effective shortcuts grouped by scene
/// (`ShortcutCatalog`). Unlike the other overlay sessions it stacks: it opens
/// above whatever is on screen — the plain terminal, a zoom, the project
/// list, the note editor, the overview — and closing it restores that scene
/// untouched, including an in-progress cell or note edit.
///
/// While the overlay is up it owns the keyboard through a local keyDown
/// monitor (`OverlayKeyDownMonitor`): Escape and a re-pressed Cmd+/ close
/// it, and every other key is consumed so the scene underneath (a focused
/// cell editor, the note editor's text view, the terminal) never sees a
/// keystroke. The overlays underneath yield their monitors while this one is
/// active, so the events reach here in installation order. The backdrop
/// swallows clicks — the overlay is viewing-only.
struct ShortcutListOverlay: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// Close the overlay (Escape / Cmd+/). State underneath is untouched.
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .onTapGesture {}

                panel
                    .frame(
                        maxWidth: 560,
                        maxHeight: geometry.size.height * 0.85)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2)
            }
        }
        .overlayKeyDownMonitor { event in
            let modifiers = event.modifierFlags
                .intersection([.command, .shift, .option, .control])
            if event.keyCode == 53 {
                onClose()
                return nil
            }
            if modifiers == [.command],
               event.charactersIgnoringModifiers == "/" {
                onClose()
                return nil
            }
            // Viewing-only: every other key is inert while the list is up,
            // so the scene underneath keeps its state (including an
            // in-progress edit) for when the overlay closes.
            return nil
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ShortcutCatalog.groups, id: \.scene) { group in
                        groupView(group)
                    }
                }
                .padding(12)
            }
        }
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    /// Header band styled like the other overlay families (`ProjectNoteEditor`,
    /// `ProjectListOverlay`) so the surfaces read as one family.
    private var header: some View {
        HStack {
            Text("Shortcuts")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("esc · ⌘/ close")
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

    private func groupView(_ group: ShortcutGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.scene.displayName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.bottom, 2)

            ForEach(group.items, id: \.chord) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.chord)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 150, alignment: .leading)
                    Text(item.label)
                        .font(.system(size: 11, design: .monospaced))
                        .opacity(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
