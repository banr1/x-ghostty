import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// (`GroupStateOf` / `WorkspaceStateOf` / `WorkspaceModelOf`) runs the exact
/// same code for both element types, so these tests exercise the real
/// primary-pane judgment logic (SPEC §22) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestGroupState = GroupStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the primary-pane model layer (SPEC §22): default assignment,
/// per-group uniqueness, nearest-leaf promotion when the primary closes,
/// persistence with restore normalization, and the overall-view display
/// target.
struct GroupPrimaryPaneTests {
    /// A group around a single-leaf tree, primary unassigned (defaulted).
    private static func makeGroup(
        _ tree: SplitTree<TestPane>,
        name: String = "group",
        primaryPane: SurfaceID? = nil
    ) -> TestGroupState {
        TestGroupState(
            id: GroupID(),
            name: name,
            paneTree: tree,
            primaryPane: primaryPane,
            createdAt: Date()
        )
    }

    // MARK: Default assignment & uniqueness (SPEC §22.1)

    @Test func initialPaneOfNewGroupIsPrimary() {
        let pane = TestPane()
        let group = Self.makeGroup(.init(view: pane))

        #expect(group.primaryPane == SurfaceID(rawValue: pane.id))
        #expect(group.isPrimary(SurfaceID(rawValue: pane.id)))
    }

    @Test func emptyPaneTreeHasNoPrimary() {
        let group = Self.makeGroup(.init())
        #expect(group.primaryPane == nil)
    }

    @Test func wrappingModelAssignsPrimaryToFirstPane() {
        let pane = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: pane), name: "amber-owl")

        #expect(model.focusedGroupState?.primaryPane == SurfaceID(rawValue: pane.id))
    }

    @Test func laterSplitPanesAreNotPrimary() throws {
        let first = TestPane()
        var group = Self.makeGroup(.init(view: first))

        // Grow the tree the way the mirror does: replace `paneTree` with the
        // post-split tree. The primary must stay on the first pane.
        let second = TestPane()
        let third = TestPane()
        var tree = try group.paneTree.inserting(view: second, at: first, direction: .right)
        tree = try tree.inserting(view: third, at: second, direction: .down)
        group.paneTree = tree

        #expect(group.primaryPane == SurfaceID(rawValue: first.id))
        #expect(!group.isPrimary(SurfaceID(rawValue: second.id)))
        #expect(!group.isPrimary(SurfaceID(rawValue: third.id)))
    }

    @Test func setPrimaryPaneMovesFlagAndDemotesFormerPrimary() throws {
        let first = TestPane()
        let second = TestPane()
        var group = Self.makeGroup(.init(view: first))
        group.paneTree = try group.paneTree.inserting(view: second, at: first, direction: .right)

        let moved = group.setPrimaryPane(SurfaceID(rawValue: second.id))

        #expect(moved)
        #expect(group.primaryPane == SurfaceID(rawValue: second.id))
        #expect(!group.isPrimary(SurfaceID(rawValue: first.id)))
    }

    @Test func setPrimaryPaneRejectsPaneOutsideTheTree() {
        let pane = TestPane()
        var group = Self.makeGroup(.init(view: pane))

        let moved = group.setPrimaryPane(SurfaceID(rawValue: UUID()))

        #expect(!moved)
        #expect(group.primaryPane == SurfaceID(rawValue: pane.id))
    }

    // MARK: Promotion on close (SPEC §22.2)

    @Test func primaryCloseProotesNearestLeaf() throws {
        // Layout: [A | B] with A primary. Closing A promotes B, the nearest
        // remaining leaf in the split tree.
        let a = TestPane()
        let b = TestPane()
        var group = Self.makeGroup(.init(view: a))
        group.paneTree = try group.paneTree.inserting(view: b, at: a, direction: .right)
        #expect(group.primaryPane == SurfaceID(rawValue: a.id))

        let removed = group.paneTree.removing(.leaf(view: a))
        group.paneTree = removed

        #expect(group.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func primaryClosePromotionPicksNearestLeafInDeepTree() throws {
        // Layout: [A | [B | C]] (a row, A at the left). Closing the primary A
        // promotes B — the nearest remaining leaf — not the farther C.
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        var group = Self.makeGroup(.init(view: a))
        var tree = try group.paneTree.inserting(view: b, at: a, direction: .right)
        tree = try tree.inserting(view: c, at: b, direction: .right)
        group.paneTree = tree
        #expect(group.primaryPane == SurfaceID(rawValue: a.id))

        group.paneTree = group.paneTree.removing(.leaf(view: a))

        #expect(group.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func nonPrimaryCloseKeepsPrimary() throws {
        let a = TestPane()
        let b = TestPane()
        var group = Self.makeGroup(.init(view: a))
        group.paneTree = try group.paneTree.inserting(view: b, at: a, direction: .right)

        group.paneTree = group.paneTree.removing(.leaf(view: b))

        #expect(group.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func closingLastPaneClearsPrimary() {
        let a = TestPane()
        var group = Self.makeGroup(.init(view: a))

        group.paneTree = group.paneTree.removing(.leaf(view: a))

        #expect(group.paneTree.isEmpty)
        #expect(group.primaryPane == nil)
    }

    // MARK: Persistence & restore normalization (SPEC §22.1)

    @Test func saveRestoreRoundTripKeepsPrimaryOnSamePane() throws {
        let a = TestPane()
        let b = TestPane()
        var group = Self.makeGroup(.init(view: a))
        group.paneTree = try group.paneTree.inserting(view: b, at: a, direction: .right)
        group.setPrimaryPane(SurfaceID(rawValue: b.id))

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(TestGroupState.self, from: data)

        // The non-default primary survives the round trip on the same pane.
        #expect(decoded.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func decodeNormalizesZeroPrimariesToFirstLeaf() throws {
        let a = TestPane()
        let b = TestPane()
        var group = Self.makeGroup(.init(view: a))
        group.paneTree = try group.paneTree.inserting(view: b, at: a, direction: .right)
        group.setPrimaryPane(SurfaceID(rawValue: b.id))

        // Tamper the save into the invalid zero-primaries shape.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)) as? [String: Any])
        json["primaryPanes"] = []
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestGroupState.self, from: tampered)

        // Exactly one primary comes back: the tree's first leaf.
        #expect(decoded.primaryPane == SurfaceID(rawValue: decoded.paneTree.firstLeaf!.id))
    }

    @Test func decodeWithoutPrimaryKeyDefaultsToFirstLeaf() throws {
        // A save written before primary panes existed has no `primaryPanes`
        // key at all; it restores like the zero case.
        let a = TestPane()
        let group = Self.makeGroup(.init(view: a))

        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)) as? [String: Any])
        json.removeValue(forKey: "primaryPanes")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestGroupState.self, from: legacy)

        #expect(decoded.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func decodeNormalizesMultiplePrimariesToOne() throws {
        let a = TestPane()
        let b = TestPane()
        var group = Self.makeGroup(.init(view: a))
        group.paneTree = try group.paneTree.inserting(view: b, at: a, direction: .right)

        // Tamper the save into the invalid several-primaries shape.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)) as? [String: Any])
        json["primaryPanes"] = [
            ["rawValue": b.id.uuidString],
            ["rawValue": a.id.uuidString],
        ]
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestGroupState.self, from: tampered)

        // Exactly one primary comes back (the first stored valid flag), and
        // the other pane is not primary.
        #expect(decoded.primaryPane == SurfaceID(rawValue: b.id))
        #expect(!decoded.isPrimary(SurfaceID(rawValue: a.id)))
    }

    @Test func decodeNormalizesDanglingPrimaryToFirstLeaf() throws {
        let a = TestPane()
        let group = Self.makeGroup(.init(view: a))

        // Tamper the save so the flag points at a pane not in the tree.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(group)) as? [String: Any])
        json["primaryPanes"] = [["rawValue": UUID().uuidString]]
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestGroupState.self, from: tampered)

        #expect(decoded.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func workspaceRoundTripRestoresEveryGroupsPrimary() throws {
        // Two groups with multi-pane trees and non-default primaries; the
        // whole workspace save/restore path (the same one app restoration
        // rides) brings the flags back to the same panes.
        let a1 = TestPane(); let a2 = TestPane()
        var groupA = Self.makeGroup(.init(view: a1), name: "a")
        groupA.paneTree = try groupA.paneTree.inserting(view: a2, at: a1, direction: .right)
        groupA.setPrimaryPane(SurfaceID(rawValue: a2.id))

        let b1 = TestPane()
        let groupB = Self.makeGroup(.init(view: b1), name: "b")

        let tree = try SplitTree<GroupRef>(view: GroupRef(id: groupA.id))
            .inserting(view: GroupRef(id: groupB.id), at: GroupRef(id: groupA.id), direction: .right)
        let state = TestWorkspaceState(
            canonicalGroupTree: tree,
            groups: [groupA.id: groupA, groupB.id: groupB],
            focusedGroup: groupA.id
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        #expect(decoded.groups[groupA.id]?.primaryPane == SurfaceID(rawValue: a2.id))
        #expect(decoded.groups[groupB.id]?.primaryPane == SurfaceID(rawValue: b1.id))
    }

    // MARK: Overall-view display target (SPEC §22.3)

    @Test func overallViewDisplaySetIsEachVisibleGroupsPrimaryOnly() throws {
        // Group A: [a1 | a2] with a2 primary. Group B: single pane. Group C:
        // hidden. The overall (non-zoomed) view draws exactly one pane per
        // visible group — the primary — and nothing for hidden groups.
        let a1 = TestPane(); let a2 = TestPane()
        var groupA = Self.makeGroup(.init(view: a1), name: "a")
        groupA.paneTree = try groupA.paneTree.inserting(view: a2, at: a1, direction: .right)
        groupA.setPrimaryPane(SurfaceID(rawValue: a2.id))

        let b1 = TestPane()
        let groupB = Self.makeGroup(.init(view: b1), name: "b")
        let c1 = TestPane()
        let groupC = Self.makeGroup(.init(view: c1), name: "c")

        // Hidden groups have no canonical leaf (SPEC §11.7).
        let tree = try SplitTree<GroupRef>(view: GroupRef(id: groupA.id))
            .inserting(view: GroupRef(id: groupB.id), at: GroupRef(id: groupA.id), direction: .right)
        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalGroupTree: tree,
            groups: [groupA.id: groupA, groupB.id: groupB, groupC.id: groupC],
            hiddenGroupIDs: [groupC.id],
            focusedGroup: groupA.id
        ))

        let displaySet = model.overallViewPaneIDs
        #expect(displaySet == [
            groupA.id: SurfaceID(rawValue: a2.id),
            groupB.id: SurfaceID(rawValue: b1.id),
        ])
        #expect(displaySet[groupC.id] == nil)
        #expect(model.primaryPaneID(of: groupA.id) == SurfaceID(rawValue: a2.id))
    }

    // MARK: Overall-view behavior (SPEC §22.3–22.5)

    /// A focused model around one group holding the row [a | b] with `a` the
    /// (default) primary — the smallest layout where primary and non-primary
    /// panes differ.
    private static func makeTwoPaneModel() throws -> (
        model: TestWorkspaceModel, groupID: GroupID, a: TestPane, b: TestPane
    ) {
        let a = TestPane()
        let b = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")
        let split = try model.focusedPaneTree.inserting(view: b, at: a, direction: .right)
        model.replaceFocusedPaneTree(split)
        return (model, model.state.focusedGroup!, a, b)
    }

    @Test func overallViewPaneTreeContainsExactlyThePrimaryLeaf() throws {
        let a1 = TestPane(); let a2 = TestPane()
        var group = Self.makeGroup(.init(view: a1))
        group.paneTree = try group.paneTree.inserting(view: a2, at: a1, direction: .right)
        group.setPrimaryPane(SurfaceID(rawValue: a2.id))

        // The overall view renders a single-leaf tree: the primary, nothing else.
        let display = group.overallViewPaneTree
        #expect(display.map(\.id) == [a2.id])

        // An empty group renders nothing.
        #expect(Self.makeGroup(.init()).overallViewPaneTree.isEmpty)
    }

    @Test func paneOperationsAreEnabledOnlyWhileTheFocusedGroupIsZoomed() throws {
        let (model, groupID, _, _) = try Self.makeTwoPaneModel()

        // The overall (non-zoomed) view: pane operations are no-ops.
        #expect(model.paneOperationsEnabled == false)

        // Zoomed into the focused group: pane operations are allowed.
        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == groupID)
        #expect(model.paneOperationsEnabled == true)

        // Released again: back to no-ops.
        model.toggleGroupZoom()
        #expect(model.paneOperationsEnabled == false)
    }

    @Test func paneOperationsAreDisabledWhenTheZoomedGroupIsNotFocused() throws {
        // A zoom on a *different* group (transient divergence) must not allow
        // pane operations on the focused group's invisible tree.
        let (model, _, _, _) = try Self.makeTwoPaneModel()
        let other = TestGroupState(
            id: GroupID(), name: "other", paneTree: .init(view: TestPane()), createdAt: Date())

        var state = model.state
        state.groups[other.id] = other
        state.canonicalGroupTree = state.canonicalGroupTree
            .appendingAtTrailingLeaf(GroupRef(id: other.id))
        state.zoomedGroup = other.id
        let diverged = TestWorkspaceModel(state)

        #expect(diverged.paneOperationsEnabled == false)
    }

    @Test func setFocusedSurfaceInOverallViewSnapsToPrimary() throws {
        let (model, groupID, a, b) = try Self.makeTwoPaneModel()

        // Outside zoom, focus can only rest on the primary (SPEC §22.4).
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: a.id))

        // While zoomed, any pane in the tree can hold focus.
        model.toggleGroupZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: b.id))
    }

    @Test func zoomReleaseSnapsFocusToPrimary() throws {
        let (model, groupID, a, b) = try Self.makeTwoPaneModel()

        // Zoom in and focus the non-primary pane.
        model.toggleGroupZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: b.id))

        // Releasing the zoom lands in the overall view: focus snaps to the
        // primary (SPEC §22.4).
        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == nil)
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: a.id))
    }

    @Test func switchFocusedGroupInOverallViewLandsOnPrimary() throws {
        // Group B stores a non-primary last-focused pane; switching to it in
        // the overall view focuses its primary instead.
        let (model, _, _, _) = try Self.makeTwoPaneModel()
        let b1 = TestPane(); let b2 = TestPane()
        var groupB = Self.makeGroup(.init(view: b1), name: "b")
        groupB.paneTree = try groupB.paneTree.inserting(view: b2, at: b1, direction: .right)
        groupB.focusedSurface = SurfaceID(rawValue: b2.id)

        var state = model.state
        state.groups[groupB.id] = groupB
        state.canonicalGroupTree = state.canonicalGroupTree
            .appendingAtTrailingLeaf(GroupRef(id: groupB.id))
        let workspace = TestWorkspaceModel(state)

        let focus = workspace.switchFocusedGroup(
            to: groupB.id, savingOutgoingPaneTree: workspace.focusedPaneTree)

        #expect(focus == SurfaceID(rawValue: b1.id))
        #expect(workspace.state.groups[groupB.id]?.focusedSurface == SurfaceID(rawValue: b1.id))
    }

    @Test func primaryCloseInOverallViewMovesFocusToPromotedPrimary() throws {
        // The primary's pane leaves the tree outside zoom (shell exit, Cmd+W,
        // process death): the promoted primary also takes the focus.
        let (model, groupID, a, b) = try Self.makeTwoPaneModel()
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: a.id))

        model.replaceFocusedPaneTree(model.focusedPaneTree.removing(.leaf(view: a)))

        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: b.id))
        #expect(model.state.groups[groupID]?.focusedSurface == SurfaceID(rawValue: b.id))
    }

    // MARK: set_primary (SPEC §22.4)

    @Test func setPrimaryWhileZoomedMovesFlagToFocusedPane() throws {
        let (model, groupID, a, b) = try Self.makeTwoPaneModel()

        // Zoom in and focus the non-primary pane; reassignment is allowed.
        model.toggleGroupZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.canSetPrimaryToFocusedPane)

        #expect(model.setPrimaryToFocusedPane())

        // The focused pane took the flag and the former primary is demoted.
        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: b.id))
        #expect(model.state.groups[groupID]?.isPrimary(SurfaceID(rawValue: a.id)) == false)
    }

    @Test func setPrimaryOutsideZoomIsNoOp() throws {
        let (model, groupID, a, _) = try Self.makeTwoPaneModel()

        // The overall view: assignment is zoom-only.
        #expect(!model.canSetPrimaryToFocusedPane)
        #expect(!model.setPrimaryToFocusedPane())
        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: a.id))
    }

    @Test func setPrimaryOnAlreadyPrimaryPaneIsNoOp() throws {
        let (model, groupID, a, _) = try Self.makeTwoPaneModel()

        // Zoomed with the primary itself focused: nothing would change, so
        // the action declines (and the keybind falls through).
        model.toggleGroupZoom()
        model.setFocusedSurface(SurfaceID(rawValue: a.id))

        #expect(!model.canSetPrimaryToFocusedPane)
        #expect(!model.setPrimaryToFocusedPane())
        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: a.id))
    }

    // MARK: Primary mark (SPEC §22.6)

    @Test func primaryMarkShowsOnlyWhileZoomedWithMultiplePanes() throws {
        let (model, groupID, a, _) = try Self.makeTwoPaneModel()

        // Overall view: no mark anywhere.
        #expect(model.primaryMarkPaneIDs.isEmpty)

        // Zoomed multi-pane group: exactly the primary is marked.
        model.toggleGroupZoom()
        #expect(model.primaryMarkPaneIDs == [groupID: SurfaceID(rawValue: a.id)])

        // Released again: the mark disappears with the zoom.
        model.toggleGroupZoom()
        #expect(model.primaryMarkPaneIDs.isEmpty)
    }

    @Test func primaryMarkHiddenForSinglePaneGroup() {
        let a = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")

        // Zoomed, but the group has a single pane: the only pane is
        // trivially the primary, so no mark is shown.
        model.toggleGroupZoom()
        #expect(model.primaryMarkPaneIDs.isEmpty)
    }

    @Test func primaryMarkFollowsReassignment() throws {
        let (model, groupID, _, b) = try Self.makeTwoPaneModel()

        model.toggleGroupZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        model.setPrimaryToFocusedPane()

        #expect(model.primaryMarkPaneIDs == [groupID: SurfaceID(rawValue: b.id)])
    }

    @Test func paneTreeMirrorKeepsPrimaryThroughModelReplace() throws {
        // The controller mirrors every surface-tree change through
        // `replaceFocusedPaneTree`; the primary must survive the mirror and
        // promote when the primary pane disappeared from the mirrored tree.
        let a = TestPane()
        let b = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")
        let groupID = model.state.focusedGroup!

        let split = try model.focusedPaneTree.inserting(view: b, at: a, direction: .right)
        model.replaceFocusedPaneTree(split)
        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: a.id))

        model.replaceFocusedPaneTree(split.removing(.leaf(view: a)))
        #expect(model.primaryPaneID(of: groupID) == SurfaceID(rawValue: b.id))
    }
}
