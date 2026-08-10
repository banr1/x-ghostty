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
/// - note glyph click (trailing edge) → open that group's note editor
///   (`SPEC.md` §21.2 — the mouse counterpart of Cmd+N; the group focus is
///   left unchanged)
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

    /// The group's priority, shown as a subtle trailing mark; `nil` (unset)
    /// shows nothing (SPEC §24).
    let priority: GroupPriority?

    /// The group's deadline, shown as trailing `YYYY-MM-DD` text; `nil`
    /// (unset) shows nothing (SPEC §24).
    let deadline: GroupDeadline?

    /// Whether the deadline is past today — drives the single-stage subtle
    /// overdue emphasis (SPEC §24.2). Judged by the model; the band only
    /// renders it.
    let isOverdue: Bool

    let onFocus: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void

    /// Open this group's note editor (the trailing note-glyph click).
    let onOpenNote: () -> Void

    @State private var draft: String = ""
    @State private var noteButtonHovered = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            content
                // Focused groups are emphasized; unfocused groups stay visible
                // but recede (`SPEC.md` §7.1). The editor is always full
                // opacity. This dims only the text — the band background below
                // stays opaque, and the note button manages its own dimming.
                .opacity(isRenaming ? 1.0 : (isFocused ? 1.0 : 0.4))

            // The meta and note affordance are hidden while renaming so the
            // band holds exactly one interactive mode at a time.
            if !isRenaming {
                Spacer(minLength: 0)
                GroupPriorityDeadlineMeta(
                    priority: priority, deadline: deadline, isOverdue: isOverdue)
                    // Recede with the band on unfocused groups, but less than
                    // the name text: the meta is workspace-level information.
                    .opacity(isFocused ? 1.0 : 0.6)
                noteButton
            }
        }
            .font(headerFont)
            .lineLimit(1)
            .foregroundStyle(.primary)
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

    /// The trailing note affordance: a small pencil glyph that opens this
    /// group's note editor (`SPEC.md` §21.2). It recedes further than the
    /// header text so the band stays name-first, and brightens on hover to
    /// read as clickable. Its own opacity is independent of the focus dimming
    /// above so the affordance stays discoverable on unfocused groups.
    private var noteButton: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: 10))
            .opacity(noteButtonHovered ? 0.9 : (isFocused ? 0.5 : 0.3))
            .contentShape(Rectangle())
            .onHover { noteButtonHovered = $0 }
            .onTapGesture(perform: onOpenNote)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Edit note for group \(name)"))
            .help("Edit note")
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

/// The subtle priority mark and deadline readout shared by the label band and
/// the note-overview panel header (SPEC §24): unset values show nothing, and
/// an overdue deadline gets the single-stage subtle emphasis — a reddish tint,
/// no extra stages, no animation. Judgment stays in the model (`GroupPriority`
/// / `GroupDeadline` / the overdue predicate); this view only renders values
/// it is handed.
struct GroupPriorityDeadlineMeta: View {
    let priority: GroupPriority?
    let deadline: GroupDeadline?
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let priority {
                Text(priority.markText)
                    .opacity(0.6)
                    .accessibilityLabel(Text("Priority \(priority.rawValue)"))
            }
            if let deadline {
                Text(deadline.displayText)
                    .foregroundStyle(
                        isOverdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                    .opacity(isOverdue ? 0.9 : 0.5)
                    .accessibilityLabel(Text(
                        "Deadline \(deadline.displayText)\(isOverdue ? ", overdue" : "")"))
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .lineLimit(1)
        .allowsHitTesting(false)
    }
}

private extension GroupPriority {
    /// The band's compact terminal-style mark: bang density mirrors urgency,
    /// so the mark stays subtle (no color, no icon) yet ordered at a glance.
    var markText: String {
        switch self {
        case .high: return "!!!"
        case .medium: return "!!"
        case .low: return "!"
        }
    }
}
