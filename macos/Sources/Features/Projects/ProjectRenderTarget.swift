import Foundation

/// What the workspace draws right now, and what it merely keeps alive
/// (`SPEC.md` §31).
///
/// The two sets are deliberately separate. `drawn` is the render target: the
/// surfaces whose renderer and display link must be running. `retained` is
/// every surface the process still owns — a hidden project's panes and a
/// project's non-primary panes are not drawn, but their shells and PTYs keep
/// running, so they stay retained. A surface that leaves `retained` is gone
/// for good and must be freed, not merely stopped.
struct RenderTargetSnapshot: Equatable {
    var drawn: Set<SurfaceID>
    var retained: Set<SurfaceID>

    init(drawn: Set<SurfaceID> = [], retained: Set<SurfaceID> = []) {
        self.drawn = drawn
        self.retained = retained
    }

    /// This snapshot as it stands once a transition into it was applied, minus
    /// the surfaces the transition could not be delivered to (`SPEC.md` §31.2).
    ///
    /// Recording the result of an application, not the intent, is what keeps a
    /// failed delivery from being forgotten: a surface dropped from both sets
    /// reads as newly born on the next transition, so it is derived again —
    /// into `resume` if it is drawn by then, into `stop` otherwise.
    func applied(except unapplied: Set<SurfaceID>) -> RenderTargetSnapshot {
        RenderTargetSnapshot(
            drawn: drawn.subtracting(unapplied),
            retained: retained.subtracting(unapplied))
    }
}

/// The work one workspace transition implies for the render path
/// (`SPEC.md` §31.2): which surfaces stop drawing, which resume, and which are
/// released outright.
///
/// Derived purely from two snapshots, so every operation that changes what is
/// on screen — hide/show, entering and leaving zoom, reassigning the primary
/// pane, the list's visibility toggle, close, and the restart of an exited
/// pane — goes through the same judgment.
struct RenderTargetTransition: Equatable {
    /// Alive and not drawn now, and either drawn before or born in this
    /// transition: stop the renderer and the display link. Its shell and PTY
    /// keep running.
    ///
    /// A newly born surface (restored, split, or a restarted exited pane) is
    /// included because the core starts every renderer visible and its display
    /// link running; nothing but an explicit stop keeps a surface born outside
    /// the render target from drawing (`SPEC.md` §31.2).
    var stop: Set<SurfaceID>

    /// Drawn now and not before: resume drawing. The surface draws the latest
    /// screen, including whatever its shell produced while it was stopped.
    var resume: Set<SurfaceID>

    /// Retained before and gone now: a closed pane or project, or the surface
    /// an exited-pane restart replaced. Free the surface with its renderer,
    /// display link and threads — stopping is not enough.
    var released: Set<SurfaceID>

    var isEmpty: Bool { stop.isEmpty && resume.isEmpty && released.isEmpty }

    /// A surface that disappeared entirely is released, never "stopped": the
    /// release path tears down the very renderer the stop would have paused.
    /// That is why `stop` is drawn from what is still retained:
    /// `stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born)`, where
    /// `born = after.retained − before.retained`.
    init(from before: RenderTargetSnapshot, to after: RenderTargetSnapshot) {
        let born = after.retained.subtracting(before.retained)
        released = before.retained.subtracting(after.retained)
        stop = after.retained.subtracting(after.drawn)
            .intersection(before.drawn.union(born))
        resume = after.drawn.subtracting(before.drawn)
    }
}

extension WorkspaceStateOf {
    /// The render target (`SPEC.md` §31.1): in the overall view exactly each
    /// visible project's primary pane; while zoomed exactly every pane of the
    /// zoomed project.
    ///
    /// Hidden projects' panes, the overall view's non-primary panes, and the
    /// other projects' panes while zoomed are all outside it. Overlays (the
    /// project list, the note overview, the shortcut list, the layout picker,
    /// the note editor) only cover the terminal behind them and are therefore
    /// absent from this judgment — they never change what is drawn underneath.
    ///
    /// A zoom on a project that is no longer renderable (hidden, or gone) reads
    /// as the overall view, matching `relayout()`, which releases exactly such
    /// a zoom, and `effectiveVisibleProjectTree`.
    var renderTargetSurfaceIDs: Set<SurfaceID> {
        if let zoomedProject,
           !hiddenProjectIDs.contains(zoomedProject),
           let project = projects[zoomedProject] {
            return Set(project.paneTree.map { SurfaceID(rawValue: $0.id) })
        }
        return Set(overallViewPaneIDs.values)
    }

    /// Every surface the process owns, drawn or not: all panes of all projects,
    /// hidden ones included. Hidden projects stay alive (`SPEC.md` §14.7) —
    /// what stops for them is drawing, not the shell.
    var retainedSurfaceIDs: Set<SurfaceID> {
        var result: Set<SurfaceID> = []
        for project in projects.values {
            for pane in project.paneTree {
                result.insert(SurfaceID(rawValue: pane.id))
            }
        }
        return result
    }

    var renderTargetSnapshot: RenderTargetSnapshot {
        RenderTargetSnapshot(drawn: renderTargetSurfaceIDs, retained: retainedSurfaceIDs)
    }
}
