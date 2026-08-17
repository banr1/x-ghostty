import Foundation
import Testing
@testable import XGhostty

/// Tests for the registered-layout model layer (`SPEC.md` §26): the 11
/// built-in layouts' slot computation, ordinal-order assignment, count
/// matching (shortfall creation / excess hide-pick with exact-count confirm
/// gating), and the one-shot nature of an application. Pane trees stay empty
/// because constructing `XGhostty.SurfaceView` leaves requires a live
/// XGhostty app; the layout judgment arranges projects, not panes.
struct ProjectLayoutTests {
    /// Builds a project with an empty pane tree (see the type doc comment).
    private static func makeEmptyProject(name: String) -> ProjectState {
        ProjectState(id: ProjectID(), name: name, paneTree: .init(), createdAt: Date())
    }

    /// A model with `count` visible projects in canonical order a, b, c, …
    /// (each `openNewProject` splits right of the focused project, so the
    /// traversal order matches creation order). Focus ends on the last one.
    private static func makeModel(visible count: Int) throws -> (model: WorkspaceModel, ids: [ProjectID]) {
        let model = WorkspaceModel(wrapping: .init(), name: "a")
        var ids = [try #require(model.state.focusedProject)]
        for name in ["b", "c", "d", "e", "f", "g", "h", "i"].prefix(count - 1) {
            let project = makeEmptyProject(name: name)
            try model.openNewProject(project, direction: .right, savingOutgoingPaneTree: .init())
            ids.append(project.id)
        }
        return (model, ids)
    }

    /// The grid tree the model is expected to build for `ids` chunked by
    /// `rowCounts`, for direct tree comparison.
    private static func expectedTree(_ ids: [ProjectID], rowCounts: [Int]) -> SplitTree<ProjectRef> {
        var rows: [[ProjectRef]] = []
        var index = 0
        for count in rowCounts {
            rows.append(ids[index..<(index + count)].map { ProjectRef(id: $0) })
            index += count
        }
        return SplitTree(gridRows: rows)
    }

    // MARK: The 11 registered layouts and their slot computation (S-071)

    @Test func registeredLayoutsMatchTheDefinition() {
        let layouts = ProjectLayout.registered
        #expect(layouts.count == 11)

        // Equal-split for 4–9 projects, with the Essence's exact row table.
        let equalSplits = layouts.filter { $0.kind == .equalSplit }
        #expect(equalSplits.map(\.projectCount) == [4, 5, 6, 7, 8, 9])
        #expect(equalSplits.map(\.rowCounts) == [
            [2, 2], [3, 2], [3, 3], [3, 2, 2], [3, 3, 2], [3, 3, 3],
        ])

        // X+1 for X = 4–8: the X part follows the same rule, plus one
        // full-width bottom row.
        let xPlusOnes = layouts.filter { $0.kind == .xPlusOne }
        #expect(xPlusOnes.map(\.projectCount) == [5, 6, 7, 8, 9])
        #expect(xPlusOnes.map(\.rowCounts) == [
            [2, 2, 1], [3, 2, 1], [3, 3, 1], [3, 2, 2, 1], [3, 3, 2, 1],
        ])
    }

    @Test func equalSplitRowRuleMatchesTheEssenceTable() {
        // Rows = the integer nearest √n; leftovers dealt to the top rows.
        #expect(ProjectLayout.equalSplitRowCounts(4) == [2, 2])
        #expect(ProjectLayout.equalSplitRowCounts(5) == [3, 2])
        #expect(ProjectLayout.equalSplitRowCounts(6) == [3, 3])
        #expect(ProjectLayout.equalSplitRowCounts(7) == [3, 2, 2])
        #expect(ProjectLayout.equalSplitRowCounts(8) == [3, 3, 2])
        #expect(ProjectLayout.equalSplitRowCounts(9) == [3, 3, 3])
    }

    @Test func slotFramesFollowTheGridRule() {
        for layout in ProjectLayout.registered {
            let frames = layout.slotFrames
            let rows = layout.rowCounts
            #expect(frames.count == layout.projectCount)

            // Row heights equal; within a row, widths equal and cells run
            // left to right; assignment order is row-major (top row first),
            // so the X+1 bottom slot is last.
            let rowHeight = 1.0 / Double(rows.count)
            var frameIndex = 0
            for (rowIndex, cellCount) in rows.enumerated() {
                let cellWidth = 1.0 / Double(cellCount)
                for cell in 0..<cellCount {
                    let frame = frames[frameIndex]
                    #expect(abs(frame.minY - Double(rowIndex) * rowHeight) < 1e-9)
                    #expect(abs(frame.height - rowHeight) < 1e-9)
                    #expect(abs(frame.minX - Double(cell) * cellWidth) < 1e-9)
                    #expect(abs(frame.width - cellWidth) < 1e-9)
                    frameIndex += 1
                }
            }

            if layout.kind == .xPlusOne {
                // The +1 slot: full width, bottom row.
                let last = frames[frames.count - 1]
                #expect(last.minX == 0)
                #expect(last.width == 1)
                #expect(abs(last.maxY - 1) < 1e-9)
            }
        }

        // One concrete pin: the 7-project equal split is 3 rows of 1/3
        // height holding 3, 2, 2 slots.
        let seven = ProjectLayout(kind: .equalSplit, projectCount: 7)
        let frames = seven.slotFrames
        #expect(abs(frames[0].width - 1.0 / 3.0) < 1e-9)
        #expect(abs(frames[3].width - 0.5) < 1e-9)
        #expect(abs(frames[3].minY - 1.0 / 3.0) < 1e-9)
        #expect(abs(frames[5].minY - 2.0 / 3.0) < 1e-9)
    }

    @Test func gridTreeConstructionMatchesHandBuiltShape() {
        // [a,b,c] over [d,e]: a vertical 1/2 split of a 3-chain over a
        // 2-chain, every element at an equal share of its row.
        typealias Tree = SplitTree<ProjectRef>
        let refs = (0..<5).map { _ in ProjectRef(id: ProjectID()) }
        let tree = Tree(gridRows: [[refs[0], refs[1], refs[2]], [refs[3], refs[4]]])

        let topRow: Tree.Node = .split(.init(
            direction: .horizontal, ratio: 1.0 / 3.0,
            left: .leaf(view: refs[0]),
            right: .split(.init(
                direction: .horizontal, ratio: 0.5,
                left: .leaf(view: refs[1]),
                right: .leaf(view: refs[2])))))
        let bottomRow: Tree.Node = .split(.init(
            direction: .horizontal, ratio: 0.5,
            left: .leaf(view: refs[3]),
            right: .leaf(view: refs[4])))
        let expected: Tree.Node = .split(.init(
            direction: .vertical, ratio: 0.5,
            left: topRow,
            right: bottomRow))

        #expect(tree.root == expected)
        // Traversal (assignment) order is row-major.
        #expect(tree.map(\.id) == refs.map(\.id))
    }

    // MARK: Equal-count application (S-071)

    @Test func equalCountApplyAssignsOrdinalOrderAndOrdinalsFollow() throws {
        let (model, ids) = try Self.makeModel(visible: 4)
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 4)

        model.beginLayoutSelection()
        #expect(model.layoutSelectionActive == true)
        let outcome = model.chooseLayout(layout, savingOutgoingPaneTree: .init())

        #expect(outcome == .applied)
        #expect(model.layoutSelectionActive == false)
        // Visible projects keep their ordinal order into the slots (row-major).
        #expect(model.state.visibleProjectIDs == ids)
        #expect(ids.enumerated().allSatisfy { model.ordinal(of: $1) == $0 + 1 })
        // The canonical tree is exactly the layout grid.
        #expect(model.state.canonicalProjectTree.root
            == Self.expectedTree(ids, rowCounts: [2, 2]).root)
        #expect(model.state.zoomedProject == nil)
        // Nothing was hidden or created.
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.projects.count == 4)
    }

    // MARK: Shortfall: new projects at the ordinal tail (S-071)

    @Test func shortfallCreatesNewProjectsAtTheOrdinalTail() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 5)

        model.beginLayoutSelection()
        let outcome = model.chooseLayout(layout, savingOutgoingPaneTree: .init())
        #expect(outcome == .needsNewProjects(2))
        #expect(model.layoutSelectionActive == false)

        // The caller (controller) supplies the shortfall; the model appends
        // them at the ordinal tail and applies.
        let new1 = Self.makeEmptyProject(name: "n1")
        let new2 = Self.makeEmptyProject(name: "n2")
        let applied = model.applyLayout(
            layout, appending: [new1, new2], savingOutgoingPaneTree: .init())

        #expect(applied == true)
        let expectedOrder = ids + [new1.id, new2.id]
        #expect(model.state.visibleProjectIDs == expectedOrder)
        #expect(model.ordinal(of: new1.id) == 4)
        #expect(model.ordinal(of: new2.id) == 5)
        #expect(model.state.projects[new1.id] != nil)
        #expect(model.state.canonicalProjectTree.root
            == Self.expectedTree(expectedOrder, rowCounts: [3, 2]).root)
        // Focus stays on the previously focused project.
        #expect(model.state.focusedProject == ids[2])
    }

    @Test func applyLayoutRejectsAWrongShortfallCount() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 5)
        let before = model.state

        // 2 required, 1 supplied → rejected, nothing mutated.
        let applied = model.applyLayout(
            layout, appending: [Self.makeEmptyProject(name: "n1")],
            savingOutgoingPaneTree: .init())

        #expect(applied == false)
        #expect(model.state.visibleProjectIDs == ids)
        #expect(model.state.projects.count == before.projects.count)
    }

    // MARK: Excess: exact-count hide-pick (S-071)

    @Test func excessOpensHidePickGatedOnExactCount() throws {
        let (model, ids) = try Self.makeModel(visible: 6)
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 4)

        model.beginLayoutSelection()
        let outcome = model.chooseLayout(layout, savingOutgoingPaneTree: .init())
        #expect(outcome == .hidePickOpened(required: 2))
        #expect(model.layoutHidePick != nil)
        #expect(model.layoutHidePickRequiredCount == 2)
        #expect(model.layoutHidePickProjectIDs == ids)

        // Confirm is gated on exactly the excess count: 0, 1, and 3
        // selections cannot confirm.
        #expect(model.canConfirmLayoutHidePick == false)
        model.toggleLayoutHidePick(ids[1])
        #expect(model.canConfirmLayoutHidePick == false)
        #expect(model.confirmLayoutHidePick(savingOutgoingPaneTree: .init()) == nil)
        #expect(model.layoutHidePick != nil)
        model.toggleLayoutHidePick(ids[3])
        model.toggleLayoutHidePick(ids[4])
        #expect(model.canConfirmLayoutHidePick == false)
        model.toggleLayoutHidePick(ids[4])
        #expect(model.canConfirmLayoutHidePick == true)

        // Confirm: exactly the selected two are hidden — never closed — and
        // the remaining four take the slots in ordinal order.
        let result = try #require(model.confirmLayoutHidePick(savingOutgoingPaneTree: .init()))
        #expect(model.layoutHidePick == nil)
        #expect(model.state.hiddenProjectIDs == [ids[1], ids[3]])
        #expect(model.state.projects.count == 6)
        let remaining = [ids[0], ids[2], ids[4], ids[5]]
        #expect(model.state.visibleProjectIDs == remaining)
        #expect(model.state.canonicalProjectTree.root
            == Self.expectedTree(remaining, rowCounts: [2, 2]).root)
        // Ordinals follow the new arrangement.
        #expect(remaining.enumerated().allSatisfy { model.ordinal(of: $1) == $0 + 1 })
        // Focus was not among the hidden, so it stays.
        #expect(result.target == ids[5])
        #expect(model.state.focusedProject == ids[5])
    }

    @Test func hidePickFocusMovesToNearestSurvivorWhenFocusedProjectPicked() throws {
        let (model, ids) = try Self.makeModel(visible: 6)
        #expect(model.state.focusedProject == ids[5])
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 4)

        model.beginLayoutSelection()
        model.chooseLayout(layout, savingOutgoingPaneTree: .init())
        model.toggleLayoutHidePick(ids[4])
        model.toggleLayoutHidePick(ids[5])

        let result = try #require(model.confirmLayoutHidePick(savingOutgoingPaneTree: .init()))

        #expect(model.state.hiddenProjectIDs == [ids[4], ids[5]])
        // Nearest survivor measured on the pre-removal projection: 6 visible
        // projects sit in a wide 3+3 grid, so the leaf nearest to ids[5]
        // (bottom right) among the survivors is ids[2] right above it.
        #expect(result.target == ids[2])
        #expect(model.state.focusedProject == ids[2])
    }

    @Test func unselectedHiddenProjectsAreUnaffected() throws {
        let (model, ids) = try Self.makeModel(visible: 5)
        // Pre-hide one project the ordinary way; it must survive the layout
        // application untouched.
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenProjectIDs == [ids[0]])

        let layout = ProjectLayout(kind: .equalSplit, projectCount: 4)
        model.beginLayoutSelection()
        let outcome = model.chooseLayout(layout, savingOutgoingPaneTree: .init())

        // 4 visible == 4 slots: applied directly; the pre-hidden project is
        // not part of the input and keeps its shelf spot and state.
        #expect(outcome == .applied)
        #expect(model.state.hiddenProjectIDs == [ids[0]])
        #expect(model.state.projects[ids[0]] != nil)
        #expect(model.state.visibleProjectIDs == Array(ids[1...]))
    }

    // MARK: Cancel paths (S-071 / SPEC §26.2–26.3)

    @Test func escCancelsTheWholeApplication() throws {
        let (model, ids) = try Self.makeModel(visible: 6)
        let before = model.state
        let layout = ProjectLayout(kind: .equalSplit, projectCount: 4)

        // Cancel from the selector: nothing changes.
        model.beginLayoutSelection()
        model.cancelLayoutSelection()
        #expect(model.layoutSelectionActive == false)
        #expect(model.state.canonicalProjectTree.root == before.canonicalProjectTree.root)

        // Cancel from the hide-pick: the whole application dies — nothing
        // hidden, nothing rearranged.
        model.beginLayoutSelection()
        model.chooseLayout(layout, savingOutgoingPaneTree: .init())
        model.toggleLayoutHidePick(ids[0])
        model.cancelLayoutHidePick()
        #expect(model.layoutHidePick == nil)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.visibleProjectIDs == ids)
        #expect(model.state.canonicalProjectTree.root == before.canonicalProjectTree.root)
    }

    // MARK: Session mechanics

    @Test func beginReleasesZoomAndDeclinesWhileOtherOverlaysUp() throws {
        let (model, ids) = try Self.makeModel(visible: 2)
        var state = model.state
        state.zoomedProject = ids[1]
        let zoomed = WorkspaceModel(state)
        zoomed.beginLayoutSelection()
        #expect(zoomed.layoutSelectionActive == true)
        #expect(zoomed.state.zoomedProject == nil)

        // Each overlay owns the keyboard alone: no layout selector while the
        // note editor, the note overview, or the hide selection is up.
        let (editing, _) = try Self.makeModel(visible: 2)
        editing.beginNoteEditingFocusedProject()
        #expect(editing.canBeginLayoutSelection == false)
        editing.beginLayoutSelection()
        #expect(editing.layoutSelectionActive == false)

        let (overview, _) = try Self.makeModel(visible: 2)
        overview.toggleNoteOverview()
        #expect(overview.canBeginLayoutSelection == false)

        let (hiding, _) = try Self.makeModel(visible: 2)
        hiding.beginHideSelection()
        #expect(hiding.canBeginLayoutSelection == false)
    }

    @Test func layoutSessionsOwnTheInteractionWhileUp() throws {
        let (model, ids) = try Self.makeModel(visible: 6)
        model.beginLayoutSelection()

        // No focus moves, no note editing, no sorting, no hide selection,
        // no note overview while the selector is up.
        #expect(model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init()) == nil)
        #expect(model.gotoProjectIndexTarget(1) == nil)
        model.beginNoteEditing(ids[0])
        #expect(model.noteEditingProject == nil)
        #expect(model.canSortVisibleProjects == false)
        #expect(model.canBeginHideSelection == false)
        model.toggleNoteOverview()
        #expect(model.noteOverviewActive == false)

        // Same while the hide-pick is up.
        model.chooseLayout(
            ProjectLayout(kind: .equalSplit, projectCount: 4),
            savingOutgoingPaneTree: .init())
        #expect(model.layoutHidePick != nil)
        #expect(model.gotoProjectIndexTarget(1) == nil)
        #expect(model.canSortVisibleProjects == false)

        // Everything works again once the application is cancelled.
        model.cancelLayoutHidePick()
        #expect(model.gotoProjectIndexTarget(1) == ids[0])
        #expect(model.canSortVisibleProjects == true)
    }

    @Test func restoreStateAndTeardownEndTheSessions() throws {
        let (model, _) = try Self.makeModel(visible: 6)
        let snapshot = model.state
        model.beginLayoutSelection()
        model.restoreState(snapshot)
        #expect(model.layoutSelectionActive == false)

        let (picking, _) = try Self.makeModel(visible: 6)
        picking.beginLayoutSelection()
        picking.chooseLayout(
            ProjectLayout(kind: .equalSplit, projectCount: 4),
            savingOutgoingPaneTree: .init())
        #expect(picking.layoutHidePick != nil)
        picking.removeAllProjects()
        #expect(picking.layoutHidePick == nil)
    }

    // MARK: One-shot application, no persistent layout state (SPEC §26.4)

    @Test func applicationIsOneShotAndTheArrangementPersistsLikeAnyOther() throws {
        let (model, ids) = try Self.makeModel(visible: 4)
        model.beginLayoutSelection()
        model.chooseLayout(
            ProjectLayout(kind: .equalSplit, projectCount: 4),
            savingOutgoingPaneTree: .init())

        // No applied-layout state exists to fight later mutations: an
        // explicit sort still reorders the arrangement freely.
        model.setProjectPriority(ids[3], to: .high)
        #expect(model.sortVisibleProjectsByPriority() == true)
        #expect(model.state.visibleProjectIDs.first == ids[3])

        // And the arrangement saves and restores like any other: a Codable
        // round trip keeps the canonical tree (empty pane trees, so no live
        // surfaces are involved).
        let (applied, appliedIDs) = try Self.makeModel(visible: 4)
        applied.beginLayoutSelection()
        applied.chooseLayout(
            ProjectLayout(kind: .equalSplit, projectCount: 4),
            savingOutgoingPaneTree: .init())
        let data = try JSONEncoder().encode(applied.state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        #expect(decoded.canonicalProjectTree.root == applied.state.canonicalProjectTree.root)
        #expect(decoded.visibleProjectIDs == appliedIDs)
    }
}
