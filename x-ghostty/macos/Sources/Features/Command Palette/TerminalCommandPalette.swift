import SwiftUI
import XGhosttyKit

struct TerminalCommandPaletteView: View {
    /// The surface that this command palette represents.
    let surfaceView: XGhostty.SurfaceView

    /// Set this to true to show the view, this will be set to false if any actions
    /// result in the view disappearing.
    @Binding var isPresented: Bool

    /// The configuration so we can lookup keyboard shortcuts.
    @ObservedObject var ghosttyConfig: XGhostty.Config

    /// The update view model for showing update commands.
    var updateViewModel: UpdateViewModel?

    /// The callback when an action is submitted.
    var onAction: ((String) -> Void)

    var body: some View {
        ZStack {
            if isPresented {
                GeometryReader { geometry in
                    VStack {
                        Spacer().frame(height: geometry.size.height * 0.05)

                        ResponderChainInjector(responder: surfaceView)
                            .frame(width: 0, height: 0)

                        CommandPaletteView(
                            isPresented: $isPresented,
                            backgroundColor: ghosttyConfig.backgroundColor,
                            options: commandOptions
                        )
                        .zIndex(1) // Ensure it's on top

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            // When the command palette disappears we need to send focus back to the
            // surface view we were overlaid on top of. There's probably a better way
            // to handle the first responder state here but I don't know it.
            if !newValue {
                // Has to be on queue because onChange happens on a user-interactive
                // thread and Xcode is mad about this call on that.
                DispatchQueue.main.async {
                    surfaceView.window?.makeFirstResponder(surfaceView)
                }
            }
        }
    }

    /// All commands available in the command palette, combining update and terminal options.
    private var commandOptions: [CommandOption] {
        var options: [CommandOption] = []
        // Updates always appear first
        options.append(contentsOf: updateOptions)

        // Sort the rest. We replace ":" with a character that sorts before space
        // so that "Foo:" sorts before "Foo Bar:". Use sortKey as a tie-breaker
        // for stable ordering when titles are equal.
        options.append(contentsOf: (jumpOptions + terminalOptions).sorted { a, b in
            let aNormalized = a.title.replacingOccurrences(of: ":", with: "\t")
            let bNormalized = b.title.replacingOccurrences(of: ":", with: "\t")
            let comparison = aNormalized.localizedCaseInsensitiveCompare(bNormalized)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            // Tie-breaker: use sortKey if both have one
            if let aSortKey = a.sortKey, let bSortKey = b.sortKey {
                return aSortKey < bSortKey
            }
            return false
        })
        return options
    }

    /// Commands for installing or canceling available updates.
    private var updateOptions: [CommandOption] {
        var options: [CommandOption] = []

        guard let updateViewModel, updateViewModel.state.isInstallable else {
            return options
        }

        // We override the update available one only because we want to properly
        // convey it'll go all the way through.
        let title: String
        if case .updateAvailable = updateViewModel.state {
            title = "Update XGhostty and Restart"
        } else {
            title = updateViewModel.text
        }

        options.append(CommandOption(
            title: title,
            description: updateViewModel.description,
            leadingIcon: updateViewModel.iconName ?? "shippingbox.fill",
            badge: updateViewModel.badge,
            emphasis: true
        ) {
            (NSApp.delegate as? AppDelegate)?.updateController.installUpdate()
        })

        options.append(CommandOption(
            title: "Cancel or Skip Update",
            description: "Dismiss the current update process"
        ) {
            updateViewModel.state.cancel()
        })

        return options
    }

    /// Custom commands from the command-palette-entry configuration.
    private var terminalOptions: [CommandOption] {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return [] }
        return appDelegate.ghostty.config.commandPaletteEntries
            .map { c in
                let symbols = appDelegate.ghostty.config.keyboardShortcut(for: c.action)?.keyList
                return CommandOption(
                    title: c.title,
                    description: c.description,
                    symbols: symbols
                ) {
                    onAction(c.action)
                }
            }
    }

    /// Commands for jumping to other terminal surfaces.
    private var jumpOptions: [CommandOption] {
        guard let controller = TerminalController.shared,
              let window = controller.window else { return [] }

        // Every project's panes are reachable, not just the focused project's — the
        // present handler focuses the owning project before the surface.
        let focusedProject = controller.workspace.state.focusedProject

        return controller.allSurfaces.map { surface in
            // The window-scoped title override is a fallback here, not an
            // override: applying it to every entry would make all the panes in
            // the list read identically.
            let displayTitle: String
            if !surface.title.isEmpty {
                displayTitle = surface.title
            } else if let override = controller.titleOverride, !override.isEmpty {
                displayTitle = override
            } else if !window.title.isEmpty {
                displayTitle = window.title
            } else {
                displayTitle = "Untitled"
            }

            // Qualify panes that live outside the focused project by project name so
            // otherwise-identical entries are distinguishable.
            let projectName: String? = {
                guard let projectID = controller.projectID(containing: surface),
                      projectID != focusedProject else { return nil }
                return controller.workspace.state.projects[projectID]?.name
            }()

            let pwd = surface.pwd?.abbreviatedPath
            let pwdPart: String? = if let pwd, !displayTitle.contains(pwd) {
                pwd
            } else {
                nil
            }
            let subtitleParts = [projectName, pwdPart].compactMap { $0 }
            let subtitle: String? = subtitleParts.isEmpty
                ? nil
                : subtitleParts.joined(separator: " · ")

            return CommandOption(
                title: "Focus: \(displayTitle)",
                subtitle: subtitle,
                leadingIcon: "rectangle.on.rectangle",
                sortKey: AnySortKey(ObjectIdentifier(surface))
            ) {
                NotificationCenter.default.post(
                    name: XGhostty.Notification.ghosttyPresentTerminal,
                    object: surface
                )
            }
        }
    }
}

/// This is done to ensure that the given view is in the responder chain.
private struct ResponderChainInjector: NSViewRepresentable {
    let responder: NSResponder

    func makeNSView(context: Context) -> NSView {
        let dummy = NSView()
        DispatchQueue.main.async {
            dummy.nextResponder = responder
        }
        return dummy
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
