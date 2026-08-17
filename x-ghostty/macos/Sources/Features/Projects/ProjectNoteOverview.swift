import SwiftUI

/// The read-only note panel the note overview (`toggle_note_overview`,
/// Cmd+Opt+E, `SPEC.md` §21.3) lays over one visible project.
///
/// `ProjectView` renders this over its own content while the overview is
/// active, so every visible project shows its note at once. The panel never
/// edits: it only displays the note, truncated to whatever fits the project
/// without breaking the layout — the edit overlay (`ProjectNoteEditor`) is
/// where the full text is guaranteed visible.
struct ProjectNoteOverviewOverlay: View {
    @EnvironmentObject private var ghostty: XGhostty.App

    let project: ProjectState

    var body: some View {
        ZStack {
            // Local backdrop: dims this project's terminal so the note reads as
            // a transient layer above it, and swallows clicks — the overview
            // is viewing-only.
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture {}

            panel
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The model's single judgment of what this panel shows (`SPEC.md`
    /// §21.3, §24): note, priority, deadline, and next trigger.
    private var content: ProjectOverviewContent { project.overviewContent }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Group {
                if content.note.isEmpty {
                    Text("no note")
                        .opacity(0.4)
                } else {
                    Text(content.note)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            // The model caps notes at `maxNoteLines`; the line limit plus the
            // project-bounded frame truncate the display when the project is too
            // small, instead of growing past its bounds.
            .lineLimit(ProjectState.maxNoteLines)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(maxWidth: 480)
        .background(ghostty.config.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ghostty.config.splitDividerColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 8)
    }

    /// Header band: the project name plus the priority/deadline meta and the
    /// next trigger (SPEC §24 — the overview shows them with the note; unset
    /// values show nothing, an overdue deadline is subtly emphasized; the
    /// next trigger appears here and never in the label band, §24.6). Styled
    /// like `ProjectNoteEditor`'s header so the two note surfaces read as one
    /// family.
    private var header: some View {
        HStack {
            Text(project.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Spacer()
            ProjectPriorityDeadlineMeta(
                priority: content.priority,
                deadline: content.deadline,
                isOverdue: content.deadline?.isOverdue(today: ProjectDeadline(from: Date())) ?? false)
            if let trigger = content.nextTrigger {
                Text(trigger.displayText)
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.5)
                    .lineLimit(1)
                    .accessibilityLabel(Text("Next trigger \(trigger.rawValue)"))
            }
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

/// Invisible interaction layer for the note overview, rendered over the whole
/// workspace while the mode is active.
///
/// It blocks mouse interaction with everything underneath (the overview is
/// viewing-only) and owns the keyboard: Escape and the overview's own
/// Cmd+Opt+E chord both leave the mode. An invisible focused text field holds
/// first responder — the terminal must not see keystrokes while the mode is
/// up, and `onExitCommand` needs a focused view to deliver Escape to (the
/// same mechanics as `ProjectNoteEditor`'s TextEditor).
struct ProjectNoteOverviewKeyCatcher: View {
    /// Leave the overview (Escape).
    let onExit: () -> Void

    /// Toggle the overview (the re-pressed Cmd+Opt+E chord). The surface's
    /// binding path is inert while it is not first responder, so the default
    /// `toggle_note_overview` chord is re-matched here.
    let onToggle: () -> Void

    @FocusState private var catcherFocused: Bool
    @State private var keyboardSink = ""

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            TextField("", text: $keyboardSink)
                .textFieldStyle(.plain)
                .opacity(0)
                .frame(width: 0, height: 0)
                .focused($catcherFocused)
                .onExitCommand { onExit() }
                .accessibilityHidden(true)

            Button { onToggle() } label: { Color.clear }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("e", modifiers: [.command, .option])
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            keyboardSink = ""
            // Grab focus on appearance. Dispatching to the next runloop turn
            // is required for the initial focus to stick (same workaround as
            // the command palette, ghostty#8497).
            DispatchQueue.main.async {
                catcherFocused = true
            }
        }
    }
}
