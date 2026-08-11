import SwiftUI

/// The layout-selection overlay, opened by the `choose_project_layout`
/// action (Cmd+L) over the whole workspace (`SPEC.md` §26.2).
///
/// Lists the 11 built-in registered layouts: ↑/↓ move the cursor, Enter (or
/// a row click) chooses the highlighted layout, Escape (or a backdrop click)
/// closes changing nothing. What choosing does — apply directly, create the
/// shortfall, or open the excess hide-pick — is the model's count-matching
/// judgment (`WorkspaceModel.chooseLayout`); each row previews it against
/// the current visible count. Rendered only while the selector is up, so no
/// permanent terminal area is occupied.
///
/// Keyboard mechanics follow `ProjectHideSelector` / `CommandPaletteView`:
/// an invisible focused text field holds first responder so the terminal
/// sees no keystrokes, delivering Escape via `onExitCommand` and Enter via
/// `onSubmit`; typed text is discarded. The arrows come through the shared
/// local keyDown monitor (`overlayArrowKeys`) instead of `onMoveCommand`,
/// which the focused sink field's editor starved on device (see
/// `ProjectHideSelector`).
struct ProjectLayoutSelector: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The listed layouts, in display order (`ProjectLayout.registered`).
    let layouts: [ProjectLayout]

    /// The current visible-project count, for each row's effect preview.
    let visibleCount: Int

    /// Choose a layout (Enter / row click).
    let onChoose: (ProjectLayout) -> Void

    /// Close the selector changing nothing (Escape / backdrop click).
    let onCancel: () -> Void

    /// The keyboard cursor row. Pure presentation state.
    @State private var cursor = 0

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

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
    /// the selector is up (the same mechanics as `ProjectHideSelector`).
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
                // Grab focus on appearance. Dispatching to the next runloop
                // turn is required for the initial focus to stick (same
                // workaround as the command palette, ghostty#8497).
                DispatchQueue.main.async {
                    catcherFocused = true
                }
            }
    }

    private func moveCursor(_ delta: Int) {
        guard !layouts.isEmpty else { return }
        cursor = (cursor + delta + layouts.count) % layouts.count
    }

    private func chooseCursorRow() {
        guard layouts.indices.contains(cursor) else { return }
        onChoose(layouts[cursor])
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(layouts.enumerated()), id: \.1.id) { index, layout in
                            row(layout, index: index)
                                .id(layout.id)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
                .onChange(of: cursor) { newValue in
                    guard layouts.indices.contains(newValue) else { return }
                    proxy.scrollTo(layouts[newValue].id)
                }
            }
        }
        .frame(width: 420)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    private func row(_ layout: ProjectLayout, index: Int) -> some View {
        HStack(spacing: 8) {
            Text(layout.label)
                .frame(minWidth: 72, alignment: .leading)

            Text("\(layout.projectCount) projects")
                .opacity(0.5)

            Spacer(minLength: 0)

            Text(effectPreview(layout))
                .opacity(0.5)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(index == cursor ? Color.secondary.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            cursor = index
            onChoose(layout)
        }
    }

    /// Previews the model's count-matching judgment for this row: what
    /// choosing the layout will do given the current visible count.
    private func effectPreview(_ layout: ProjectLayout) -> String {
        let delta = layout.projectCount - visibleCount
        if delta > 0 { return "+\(delta) new" }
        if delta < 0 { return "pick \(-delta) to hide" }
        return "fits"
    }

    /// Header band, styled like the other overlay headers so the family
    /// reads as one.
    private var header: some View {
        HStack {
            Text("apply layout")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            Text("↑↓ choose · ↩ apply · esc cancel")
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
