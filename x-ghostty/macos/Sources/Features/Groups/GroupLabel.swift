import SwiftUI

/// The name-header band drawn across a group's top edge (`SPEC.md` §7.1).
///
/// `GroupView` stacks this above the terminal in a `VStack`, so the band takes
/// its own height and pushes the terminal layout down (invariant §14.13) — it
/// is not an overlay. The band blends with the terminal: it fills with the
/// configured terminal background color and is separated from the panes by a
/// hairline in the split-divider color, so it reads as part of the terminal
/// rather than a floating chip.
///
/// Focused groups are emphasized (full-opacity text, medium weight); unfocused
/// groups recede (text dimmed to ~0.4) but stay legible. The band background is
/// drawn at full opacity in both states so only the text dims.
///
/// Interaction (§7.1):
/// - single click  → focus that group
/// - double click  → begin inline rename
///
/// Inline rename is also entered by the `rename_group` action; both paths set
/// `WorkspaceModel.renamingGroup`, which drives `isRenaming` here, so they share
/// one editing UI. The text field commits on Return or when it loses focus, and
/// cancels on Escape. To keep Escape unambiguous, Escape reverts the draft to
/// the current title first, so the trailing focus-loss commit becomes a no-op.
/// The header shows `"{ordinal}. {name}"` (e.g. `3. calm-river`) so the group's
/// `goto_group:<N>` / Cmd+N number is visible where the group is. The ordinal is
/// a display prefix only: it is never stored in the name, and the inline editor
/// below edits `name` alone.
struct GroupLabel: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    /// The group's bare name — what rename edits and `show_group:<name>` matches.
    let name: String

    /// The group's 1-based display number, or `nil` when it has none (it is not
    /// a visible group). Rendered as a prefix, never merged into `name`.
    let ordinal: Int?

    let isFocused: Bool
    let isRenaming: Bool

    let onFocus: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void

    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        content
            .font(headerFont)
            .lineLimit(1)
            .foregroundStyle(.primary)
            // Focused groups are emphasized; unfocused groups stay visible but
            // recede (`SPEC.md` §7.1). The editor is always full opacity. This
            // dims only the text — the band background below stays opaque.
            .opacity(isRenaming ? 1.0 : (isFocused ? 1.0 : 0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            // Blend with the terminal: fill with the terminal background and
            // separate from the panes with a divider-colored hairline.
            .background(ghostty.config.backgroundColor)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ghostty.config.splitDividerColor)
                    .frame(height: 1)
            }
    }

    /// A monospaced system font so the header rhymes with the terminal text
    /// without threading the (C-API-private) terminal `font-family` through.
    /// Focused groups use a slightly heavier weight for emphasis.
    private var headerFont: Font {
        .system(size: 11, weight: isFocused ? .medium : .regular, design: .monospaced)
    }

    /// The displayed header text: the group's number, then its name. Falls back
    /// to the bare name when the group has no number.
    private var title: String {
        guard let ordinal else { return name }
        return "\(ordinal). \(name)"
    }

    @ViewBuilder
    private var content: some View {
        if isRenaming {
            renameField
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            // The double-click handler is declared before the single-click one
            // so SwiftUI prefers it; otherwise a double click also fires focus.
            .onTapGesture(count: 2, perform: onBeginRename)
            .onTapGesture(count: 1, perform: onFocus)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Group \(title)"))
    }

    /// The inline editor works on the bare `name`: the ordinal prefix is display
    /// only, so it must never end up in the draft (and from there in the stored
    /// name) — the user edits `calm-river`, not `3. calm-river`.
    private var renameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .frame(minWidth: 60)
            .focused($fieldFocused)
            .onSubmit { onCommitRename(draft) }
            .onExitCommand {
                // Revert the draft so the focus-loss commit below is a no-op,
                // then exit edit mode without changing the name.
                draft = name
                onCancelRename()
            }
            .onChange(of: fieldFocused) { focused in
                // Clicking elsewhere commits the current draft (macOS rename
                // convention). After Escape the draft equals the name, so this
                // commit changes nothing.
                if !focused { onCommitRename(draft) }
            }
            .onAppear {
                draft = name
                fieldFocused = true
            }
    }
}
