import SwiftUI

/// The layout-type selection overlay, opened by the `choose_project_layout`
/// action (Cmd+Opt+L) over the whole workspace (`SPEC.md` §26.2).
///
/// Lists only the choices for the *current* visible count — the shape ×
/// orientation combinations left after exact-match collapsing
/// (`ProjectLayoutType.choices(forVisibleCount:)`): ↑/↓ move the cursor,
/// Enter (or a row click) applies the highlighted type, Escape (or a
/// backdrop click) closes changing nothing. The project count never changes.
/// When only one choice exists there is nothing to choose, and the panel
/// says so instead of listing it. Rendered only while the selector is up, so
/// no permanent terminal area is occupied.
///
/// Keyboard mechanics follow `CommandPaletteView`: an invisible focused
/// text field holds first responder so the terminal sees no keystrokes,
/// delivering Escape via `onExitCommand` and Enter via `onSubmit`; typed
/// text is discarded. The arrows come through the shared local keyDown
/// monitor (`overlayArrowKeys`) instead of `onMoveCommand`, which the
/// focused sink field's editor starved on device.
struct ProjectLayoutSelector: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The listed choices for the current visible count
    /// (`WorkspaceModel.layoutTypeChoices`).
    let choices: [ProjectLayoutType]

    /// The choice standing for the remembered type at this count
    /// (`WorkspaceModel.currentLayoutTypeChoice`) — highlighted as current.
    let current: ProjectLayoutType

    /// Apply a type (Enter / row click).
    let onChoose: (ProjectLayoutType) -> Void

    /// Close the selector changing nothing (Escape / backdrop click).
    let onCancel: () -> Void

    /// The keyboard cursor row. Pure presentation state, seeded on the
    /// current type so Enter with no arrows re-applies what is already set.
    @State private var cursor = 0

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

    /// Whether there is anything to choose (`SPEC.md` §26.2): a single
    /// collapsed choice means the arrangement for this count is forced.
    private var nothingToChoose: Bool { choices.count <= 1 }

    var body: some View {
        ZStack {
            // Backdrop: dims the terminal so the selector reads as a
            // transient layer above it. A click outside the panel cancels —
            // only Enter (or a row click) ever applies anything.
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }

            panel

            keyCatcher
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The invisible first-responder text field that owns the keyboard while
    /// the selector is up (the same mechanics as `CommandPaletteView`).
    private var keyCatcher: some View {
        TextField("", text: $keyboardSink)
            .textFieldStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .focused($catcherFocused)
            .onExitCommand { onCancel() }
            .onSubmit { chooseCursorRow() }
            .overlayArrowKeys { moveCursor($0) }
            .onChange(of: keyboardSink) { typed in
                // Typed text lands here instead of the terminal; the
                // selector has no text input, so it is discarded.
                if !typed.isEmpty { keyboardSink = "" }
            }
            .accessibilityHidden(true)
            .onAppear {
                keyboardSink = ""
                cursor = choices.firstIndex(of: current) ?? 0
                // Grab focus on appearance. Dispatching to the next runloop
                // turn is required for the initial focus to stick (same
                // workaround as the command palette, ghostty#8497).
                DispatchQueue.main.async {
                    catcherFocused = true
                }
            }
    }

    private func moveCursor(_ delta: Int) {
        guard !nothingToChoose else { return }
        cursor = (cursor + delta + choices.count) % choices.count
    }

    private func chooseCursorRow() {
        guard !nothingToChoose, choices.indices.contains(cursor) else { return }
        onChoose(choices[cursor])
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if nothingToChoose {
                // A single collapsed choice: nothing to choose for this
                // visible count (`SPEC.md` §26.2).
                Text("nothing to choose for this layout count")
                    .font(.system(size: 12, design: .monospaced))
                    .opacity(0.6)
                    .padding(10)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(choices.enumerated()), id: \.1.id) { index, choice in
                        row(choice, index: index)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 340)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    private func row(_ choice: ProjectLayoutType, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(choice.label)
                .frame(minWidth: 140, alignment: .leading)

            Spacer(minLength: 0)

            if choice == current {
                Text("current")
                    .opacity(0.5)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(index == cursor ? Color.secondary.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            cursor = index
            onChoose(choice)
        }
    }

    /// Header band, styled like the other overlay headers so the family
    /// reads as one.
    private var header: some View {
        HStack {
            Text("layout type")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text(nothingToChoose ? "esc close" : "↑↓ choose · ↩ apply · esc cancel")
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
}
