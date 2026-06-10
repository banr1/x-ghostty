import SwiftUI

/// The name label drawn at a group's top-left corner (`SPEC.md` §7.1).
///
/// `GroupView` renders this as an overlay, so it never displaces the terminal
/// layout (invariant §14.13). Focused groups are emphasized (full opacity,
/// stronger material, accent border); unfocused groups recede to ~0.4 opacity
/// but stay legible.
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
struct GroupLabel: View {
    let title: String
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
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                let shape = RoundedRectangle(cornerRadius: 4)
                if isFocused || isRenaming {
                    shape.fill(.regularMaterial)
                } else {
                    shape.fill(.thinMaterial)
                }
            }
            .overlay {
                // A subtle accent border further emphasizes the focused group.
                if isFocused && !isRenaming {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
            // Focused groups are emphasized; unfocused groups stay visible but
            // recede (`SPEC.md` §7.1). The editor is always full opacity.
            .opacity(isRenaming ? 1.0 : (isFocused ? 1.0 : 0.4))
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

    private var renameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .frame(minWidth: 60)
            .focused($fieldFocused)
            .onSubmit { onCommitRename(draft) }
            .onExitCommand {
                // Revert the draft so the focus-loss commit below is a no-op,
                // then exit edit mode without changing the name.
                draft = title
                onCancelRename()
            }
            .onChange(of: fieldFocused) { focused in
                // Clicking elsewhere commits the current draft (macOS rename
                // convention). After Escape the draft equals the title, so this
                // commit changes nothing.
                if !focused { onCommitRename(draft) }
            }
            .onAppear {
                draft = title
                fieldFocused = true
            }
    }
}
