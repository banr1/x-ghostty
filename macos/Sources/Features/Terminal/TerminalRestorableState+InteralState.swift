import AppKit

extension TerminalRestorableState {
    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    struct InternalState<ViewType: NSView & Codable & Identifiable>: Codable {
        // MARK: - Version 5 (1.2.3)
        let focusedSurface: String?
        let surfaceTree: SplitTree<ViewType>

        // MARK: - Version 7 (1.3.0)
        let effectiveFullscreenMode: FullscreenMode?
        let tabColor: TerminalTabColor?
        let titleOverride: String?

        // MARK: - Version 8 (group layer)
        ///
        /// The full group-layer state (`SPEC.md` §12.1). When present this is the
        /// authoritative layout on restore; `surfaceTree`/`focusedSurface` above
        /// describe only the focused group and are kept for backward decoding of
        /// pre-v8 saves. Optional so older archives (no group layer) decode as
        /// `nil` and fall back to the single-tree restore path.
        let workspace: WorkspaceState?
    }
}

extension TerminalRestorableState.InternalState where ViewType == XGhostty.SurfaceView {
    init(from controller: TerminalController) {
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            effectiveFullscreenMode: controller.fullscreenStyle?.fullscreenMode,
            tabColor: (controller.window as? TerminalWindow)?.tabColor,
            titleOverride: controller.titleOverride,
            // The focused group's pane tree is mirrored from `surfaceTree`
            // (always in sync via `surfaceTreeDidChange`), so the captured state
            // is consistent with `surfaceTree` above (`SPEC.md` §12.1).
            workspace: controller.workspace.state,
        )
    }
}
