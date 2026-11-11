import AppKit

extension TerminalRestorableState {
    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    struct InternalState<ViewType: NSView & Codable & Identifiable>: Codable where ViewType.ID == UUID {
        // MARK: - Version 5 (1.2.3)
        let focusedSurface: String?
        let surfaceTree: SplitTree<ViewType>

        // MARK: - Version 7 (1.3.0)
        let effectiveFullscreenMode: FullscreenMode?
        let titleOverride: String?

        // MARK: - Version 8 (project layer)
        ///
        /// The full project-layer state (`SPEC.md` §12.1). When present this is the
        /// authoritative layout on restore; `surfaceTree`/`focusedSurface` above
        /// describe only the focused project and are kept for backward decoding of
        /// pre-v8 saves. Optional so older archives (no project layer) decode as
        /// `nil` and fall back to the single-tree restore path.
        let workspace: WorkspaceStateOf<ViewType>?

        enum CodingKeys: String, CodingKey {
            case focusedSurface
            case surfaceTree
            case effectiveFullscreenMode
            case titleOverride
            case workspace
        }

        init(
            focusedSurface: String?,
            surfaceTree: SplitTree<ViewType>,
            effectiveFullscreenMode: FullscreenMode?,
            titleOverride: String?,
            workspace: WorkspaceStateOf<ViewType>?
        ) {
            self.focusedSurface = focusedSurface
            self.surfaceTree = surfaceTree
            self.effectiveFullscreenMode = effectiveFullscreenMode
            self.titleOverride = titleOverride
            self.workspace = workspace
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            focusedSurface = try container.decodeIfPresent(String.self, forKey: .focusedSurface)
            effectiveFullscreenMode = try container.decodeIfPresent(
                FullscreenMode.self, forKey: .effectiveFullscreenMode)
            titleOverride = try container.decodeIfPresent(String.self, forKey: .titleOverride)

            // The workspace is decoded first: when the restore takes the
            // workspace path, the legacy `surfaceTree` (a copy of the focused
            // project's panes) is never used, and decoding it would create a
            // second live surface — with its own shell — for every pane of
            // that project, only to free them on the main thread at the end
            // of the restore. Freeing joins the surface's IO thread, whose
            // reader can be blocked on the app mailbox that only the main
            // thread drains, so the restore could deadlock. Skip it instead.
            let workspace = try container.decodeIfPresent(
                WorkspaceStateOf<ViewType>.self, forKey: .workspace)
            self.workspace = workspace
            if let workspace, workspace.restoresAsWorkspace {
                surfaceTree = SplitTree()
            } else {
                surfaceTree = try container.decode(SplitTree<ViewType>.self, forKey: .surfaceTree)
            }
        }
    }
}

extension TerminalRestorableState.InternalState where ViewType == XGhostty.SurfaceView {
    init(from controller: TerminalController) {
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            effectiveFullscreenMode: controller.fullscreenStyle?.fullscreenMode,
            titleOverride: controller.titleOverride,
            // The focused project's pane tree is mirrored from `surfaceTree`
            // (always in sync via `surfaceTreeDidChange`), so the captured state
            // is consistent with `surfaceTree` above (`SPEC.md` §12.1).
            workspace: controller.workspace.state,
        )
    }
}
