import Foundation
import Testing
@testable import XGhostty

/// Phase 0 tests for `WorkspaceModel`, the mirror that wraps the focused
/// group's pane tree. Pane trees are kept empty because constructing
/// `XGhostty.SurfaceView` leaves requires a live XGhostty app; richer pane
/// operations are covered by the existing `SplitTreeTests` and manual
/// integration checks.
struct WorkspaceModelTests {
    @Test func wrappingCreatesSingleDefaultFocusedGroup() {
        // Inject a fixed name so the assertion is deterministic; production draws
        // a random `adjective-noun` name from `GroupNameGenerator`.
        let model = WorkspaceModel(wrapping: .init(), name: "amber-owl")

        #expect(model.state.groups.count == 1)
        let focused = model.state.focusedGroup
        #expect(focused != nil)
        #expect(model.state.canonicalGroupTree.find(id: focused!) != nil)
        #expect(model.focusedGroupState != nil)
        #expect(model.focusedGroupState?.name == "amber-owl")
    }

    @Test func wrappingWithoutNameDrawsARandomGroupName() {
        // No injected name: a random `adjective-noun` (or `group-N` fallback) is
        // generated, so the group is always named (never empty).
        let model = WorkspaceModel(wrapping: .init())
        let name = model.focusedGroupState?.name
        #expect(name?.isEmpty == false)
    }

    @Test func wrappingEmptyPaneTreeHasNoFocusedSurface() {
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.focusedGroupState?.focusedSurface == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func emptyModelHasNoFocusedGroup() {
        let model = WorkspaceModel()
        #expect(model.state.focusedGroup == nil)
        #expect(model.focusedGroupState == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func replaceFocusedPaneTreeUpdatesFocusedGroupOnly() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        model.replaceFocusedPaneTree(.init())

        // Still a single focused group; only its pane tree was touched.
        #expect(model.state.groups.count == 1)
        #expect(model.state.focusedGroup == focused)
        #expect(model.focusedGroupState?.paneTree.isEmpty == true)
        #expect(model.focusedGroupState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceIgnoresSurfaceNotInPaneTree() {
        let model = WorkspaceModel(wrapping: .init())
        // The surface id is not present in the (empty) pane tree, so this is a
        // no-op rather than recording a dangling focus.
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedGroupState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceOnEmptyModelIsNoOp() {
        let model = WorkspaceModel()
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedGroupState == nil)
    }

    // MARK: openNewGroup (SPEC §11.1, invariants §14.10–11)

    /// Builds a group with an empty pane tree. Pane trees stay empty because
    /// constructing real `SurfaceView` leaves requires a live XGhostty app; the
    /// group-structure transition is independent of pane contents.
    private static func makeEmptyGroup(name: String) -> GroupState {
        GroupState(id: GroupID(), name: name, paneTree: .init(), createdAt: Date())
    }

    @Test func openNewGroupInsertsSiblingAndSwitchesFocus() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedGroup)
        let newGroup = Self.makeEmptyGroup(name: "amber-owl")

        try model.openNewGroup(newGroup, direction: .right, savingOutgoingPaneTree: .init())

        // §14.10: the canonical tree gained the new group.
        #expect(model.state.groups.count == 2)
        let leafIDs = Set(model.state.canonicalGroupTree.map(\.id))
        #expect(leafIDs == Set([anchor, newGroup.id]))
        // §14.11: focus moved to the new group.
        #expect(model.state.focusedGroup == newGroup.id)
        #expect(model.focusedGroupState?.id == newGroup.id)
        #expect(model.focusedGroupState?.name == "amber-owl")
    }

    @Test func openNewGroupKeepsCanonicalAndGroupsConsistent() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedGroup)
        let newGroup = Self.makeEmptyGroup(name: "brave-river")

        try model.openNewGroup(newGroup, direction: .down, savingOutgoingPaneTree: .init())

        // §14.1–2: canonical leaves and groups keys stay in bijection.
        let leafIDs = Set(model.state.canonicalGroupTree.map(\.id))
        let groupKeys = Set(model.state.groups.keys)
        #expect(leafIDs == groupKeys)
        // The original anchor group is still present and reachable.
        #expect(model.state.canonicalGroupTree.find(id: anchor) != nil)
        #expect(model.state.groups[anchor] != nil)
    }

    @Test func openNewGroupThrowsWithoutFocusedGroup() {
        let model = WorkspaceModel()
        let newGroup = Self.makeEmptyGroup(name: "calm-moon")

        #expect(throws: WorkspaceModel.WorkspaceError.noFocusedGroup) {
            try model.openNewGroup(newGroup, direction: .right, savingOutgoingPaneTree: .init())
        }
        // The model is untouched on throw.
        #expect(model.state.groups.isEmpty)
        #expect(model.state.focusedGroup == nil)
    }

    // MARK: switchFocusedGroup (SPEC §7.1, invariant §14.12)

    @Test func switchFocusedGroupFlipsFocusToTarget() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedGroup)
        let other = Self.makeEmptyGroup(name: "amber-owl")
        try model.openNewGroup(other, direction: .right, savingOutgoingPaneTree: .init())
        #expect(model.state.focusedGroup == other.id)

        // Switching back to the original anchor flips focus without changing
        // the group set or canonical tree.
        model.switchFocusedGroup(to: anchor, savingOutgoingPaneTree: .init())

        #expect(model.state.focusedGroup == anchor)
        #expect(Set(model.state.groups.keys) == Set([anchor, other.id]))
        let leafIDs = Set(model.state.canonicalGroupTree.map(\.id))
        #expect(leafIDs == Set([anchor, other.id]))
    }

    @Test func switchFocusedGroupIsNoOpWhenAlreadyFocused() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        let result = model.switchFocusedGroup(to: focused!, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedGroup == focused)
    }

    @Test func switchFocusedGroupIsNoOpForUnknownGroup() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        let result = model.switchFocusedGroup(to: GroupID(), savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedGroup == focused)
    }

    // MARK: gotoGroupTarget (SPEC §11.3)

    /// Build a focused model with two groups split horizontally: the original
    /// anchor on the left and a new group on the right (which becomes focused).
    private static func makeTwoGroupHorizontal() throws -> (model: WorkspaceModel, left: GroupID, right: GroupID) {
        let model = WorkspaceModel(wrapping: .init())
        let left = try #require(model.state.focusedGroup)
        let right = makeEmptyGroup(name: "amber-owl")
        try model.openNewGroup(right, direction: .right, savingOutgoingPaneTree: .init())
        return (model, left, right.id)
    }

    /// The ratio of the canonical tree's root split, if it is a split.
    private static func rootSplitRatio(_ model: WorkspaceModel) -> Double? {
        guard case .split(let split) = model.state.canonicalGroupTree.root else { return nil }
        return split.ratio
    }

    @Test func gotoGroupTargetMovesToVisibleNeighbor() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        #expect(model.state.focusedGroup == right)

        // From the right group, the left neighbor exists; the right/up do not.
        #expect(model.gotoGroupTarget(.spatial(.left)) == left)
        #expect(model.gotoGroupTarget(.spatial(.right)) == nil)
        #expect(model.gotoGroupTarget(.spatial(.up)) == nil)
    }

    @Test func gotoGroupTargetIsNilForSingleGroup() {
        let model = WorkspaceModel(wrapping: .init())
        // A single group has no neighbor, and next/previous would wrap to itself.
        #expect(model.gotoGroupTarget(.spatial(.left)) == nil)
        #expect(model.gotoGroupTarget(.next) == nil)
        #expect(model.gotoGroupTarget(.previous) == nil)
    }

    @Test func gotoGroupTargetIsNilWithoutFocusedGroup() {
        let model = WorkspaceModel()
        #expect(model.gotoGroupTarget(.spatial(.left)) == nil)
    }

    @Test func gotoGroupTargetIsNilWhenZoomed() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()

        // Zoom is Phase 5; construct the zoomed state directly to exercise the
        // §11.3 "no-op while zoomed" guard.
        var zoomed = model.state
        zoomed.zoomedGroup = right
        let zoomedModel = WorkspaceModel(zoomed)

        #expect(zoomedModel.gotoGroupTarget(.spatial(.left)) == nil)
    }

    // MARK: resizeFocusedGroup (SPEC §11.4)

    @Test func resizeFocusedGroupAdjustsCanonicalSplitRatio() throws {
        let (model, _, _) = try Self.makeTwoGroupHorizontal()
        let before = try #require(Self.rootSplitRatio(model))

        // Focused is the right group; resizing left shrinks the leading (left)
        // child, decreasing the root horizontal split's ratio by the delta.
        model.resizeFocusedGroup(.left, ratioDelta: 0.1)

        let after = try #require(Self.rootSplitRatio(model))
        #expect(abs(after - (before - 0.1)) < 1e-9)
    }

    @Test func resizeFocusedGroupShrinkDirectionWorks() throws {
        // Regression: pressing the "shrink" direction (no spatial neighbor on
        // that side) was previously a no-op. The ancestor-based approach must
        // find the root split even when the focused group is at the wall.
        let (model, left, _) = try Self.makeTwoGroupHorizontal()
        // Switch focus to the LEFT group so pressing LEFT has no spatial
        // neighbor to the left.
        model.switchFocusedGroup(to: left, savingOutgoingPaneTree: .init())
        let before = try #require(Self.rootSplitRatio(model))

        model.resizeFocusedGroup(.left, ratioDelta: 0.1)

        let after = try #require(Self.rootSplitRatio(model))
        #expect(abs(after - (before - 0.1)) < 1e-9)
    }

    @Test func resizeFocusedGroupNoAxisMatchIsNoOp() throws {
        let (model, _, _) = try Self.makeTwoGroupHorizontal()
        let before = try #require(Self.rootSplitRatio(model))

        // No vertical ancestor split in a horizontal-only tree → no change.
        model.resizeFocusedGroup(.up, ratioDelta: 0.1)

        #expect(Self.rootSplitRatio(model) == before)
    }

    @Test func resizeFocusedGroupSingleGroupIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())
        // No split exists; nothing to resize, and no crash.
        model.resizeFocusedGroup(.left, ratioDelta: 0.1)
        #expect(model.state.canonicalGroupTree.root != nil)
    }

    @Test func resizeFocusedGroupIsNoOpWhenZoomed() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()

        var zoomed = model.state
        zoomed.zoomedGroup = right
        let zoomedModel = WorkspaceModel(zoomed)
        let before = try #require(Self.rootSplitRatio(zoomedModel))

        zoomedModel.resizeFocusedGroup(.left, ratioDelta: 0.1)

        #expect(Self.rootSplitRatio(zoomedModel) == before)
    }

    // MARK: moveFocusedGroup (move_group)

    /// Builds a horizontal row of three groups `[left, middle, right]` with
    /// `middle` focused.
    private static func makeThreeGroupRow() throws
        -> (model: WorkspaceModel, ids: (left: GroupID, middle: GroupID, right: GroupID)) {
        let model = WorkspaceModel(wrapping: .init())
        let left = try #require(model.state.focusedGroup)
        let middle = makeEmptyGroup(name: "amber-owl")
        try model.openNewGroup(middle, direction: .right, savingOutgoingPaneTree: .init())
        let right = makeEmptyGroup(name: "coral-fox")
        try model.openNewGroup(right, direction: .right, savingOutgoingPaneTree: .init())
        model.switchFocusedGroup(to: middle.id, savingOutgoingPaneTree: .init())
        return (model, (left, middle.id, right.id))
    }

    /// Every split ratio in the canonical group tree, depth-first.
    private static func canonicalRatios(_ model: WorkspaceModel) -> [Double] {
        func walk(_ node: SplitTree<GroupRef>.Node) -> [Double] {
            guard case .split(let split) = node else { return [] }
            return [split.ratio] + walk(split.left) + walk(split.right)
        }
        guard let root = model.state.canonicalGroupTree.root else { return [] }
        return walk(root)
    }

    @Test func moveFocusedGroupSwapsWithSpatialNeighbor() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        // Skew the split so a structure/ratio-preserving swap is observable.
        model.resizeFocusedGroup(.left, ratioDelta: 0.2)
        let ratios = Self.canonicalRatios(model)
        #expect(model.state.canonicalGroupTree.map(\.id) == [left, right])

        #expect(model.moveFocusedGroup(.spatial(.left)) == true)

        // The two leaves traded places; ratios (and so the layout) are identical
        // and focus followed the moved group to its new slot.
        #expect(model.state.canonicalGroupTree.map(\.id) == [right, left])
        #expect(Self.canonicalRatios(model) == ratios)
        #expect(model.state.focusedGroup == right)
    }

    @Test func moveFocusedGroupIsNotPerformableAtTheEdge() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        // The focused group is the rightmost, so right/up/down have no neighbor.
        #expect(model.canMoveFocusedGroup(.spatial(.right)) == false)
        #expect(model.canMoveFocusedGroup(.spatial(.up)) == false)
        #expect(model.moveFocusedGroup(.spatial(.right)) == false)

        #expect(model.state.canonicalGroupTree.map(\.id) == [left, right])
        #expect(model.state.focusedGroup == right)
    }

    @Test func moveFocusedGroupPreviousSwapsInOrderNeighbor() throws {
        let (model, ids) = try Self.makeThreeGroupRow()

        #expect(model.moveFocusedGroup(.previous) == true)

        #expect(model.state.canonicalGroupTree.map(\.id) == [ids.middle, ids.left, ids.right])
        #expect(model.state.focusedGroup == ids.middle)
    }

    @Test func moveFocusedGroupNextSwapsInOrderNeighbor() throws {
        let (model, ids) = try Self.makeThreeGroupRow()

        #expect(model.moveFocusedGroup(.next) == true)

        #expect(model.state.canonicalGroupTree.map(\.id) == [ids.left, ids.right, ids.middle])
        #expect(model.state.focusedGroup == ids.middle)
    }

    @Test func moveFocusedGroupSingleGroupIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.moveFocusedGroup(.next) == false)
        #expect(model.moveFocusedGroup(.previous) == false)
        #expect(model.moveFocusedGroup(.spatial(.left)) == false)
    }

    @Test func moveFocusedGroupIsNoOpWhenZoomed() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        var zoomed = model.state
        zoomed.zoomedGroup = right
        let zoomedModel = WorkspaceModel(zoomed)

        #expect(zoomedModel.canMoveFocusedGroup(.spatial(.left)) == false)
        #expect(zoomedModel.moveFocusedGroup(.spatial(.left)) == false)
        #expect(zoomedModel.state.canonicalGroupTree.map(\.id) == [left, right])
    }

    @Test func moveFocusedGroupWithoutFocusedGroupIsNoOp() {
        let model = WorkspaceModel()
        #expect(model.moveFocusedGroup(.next) == false)
    }

    // MARK: equalizeGroups (SPEC §11.5)

    @Test func equalizeGroupsRebalancesWhenNoHidden() throws {
        let (model, _, _) = try Self.makeTwoGroupHorizontal()
        // Skew the split, then equalize: two equally-weighted leaves → 0.5.
        model.resizeFocusedGroup(.left, ratioDelta: 0.2)
        #expect(Self.rootSplitRatio(model) != 0.5)

        #expect(model.equalizeGroups() == true)
        let ratio = try #require(Self.rootSplitRatio(model))
        #expect(abs(ratio - 0.5) < 1e-9)
    }

    @Test func equalizeGroupsRebalancesVisibleGroupsWithHiddenPresent() throws {
        // Hidden groups have no leaf in the canonical tree, so equalizing it
        // inherently ignores them — no guard needed.
        let (model, ids) = try Self.makeThreeGroupRow()
        model.switchFocusedGroup(to: ids.right, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenGroupIDs == [ids.right])

        model.resizeFocusedGroup(.left, ratioDelta: 0.2)
        #expect(Self.rootSplitRatio(model) != 0.5)

        #expect(model.equalizeGroups() == true)

        let ratio = try #require(Self.rootSplitRatio(model))
        #expect(abs(ratio - 0.5) < 1e-9)
        // The hidden group stays hidden and out of the tree.
        #expect(model.state.hiddenGroupIDs == [ids.right])
        #expect(Set(model.state.canonicalGroupTree.map(\.id)) == Set([ids.left, ids.middle]))
    }

    @Test func equalizeGroupsDeclinesWithNothingToEqualize() {
        // A single group has no split; the keybind should stay unconsumed.
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.equalizeGroups() == false)
        #expect(WorkspaceModel().equalizeGroups() == false)
    }

    // MARK: Rename (SPEC §7.1, §9.1)

    @Test func renameGroupTrimsAndSetsName() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedGroup!

        model.renameGroup(id, to: "  calm-river  ")

        #expect(model.state.groups[id]?.name == "calm-river")
    }

    @Test func renameGroupRejectsEmpty() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedGroup!
        let original = model.state.groups[id]?.name

        model.renameGroup(id, to: "   ")

        #expect(model.state.groups[id]?.name == original)
    }

    @Test func renameGroupUnknownIdIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedGroup!
        let original = model.state.groups[id]?.name

        model.renameGroup(GroupID(), to: "ghost")

        #expect(model.state.groups[id]?.name == original)
        #expect(model.state.groups.count == 1)
    }

    @Test func renameGroupClearsRenameModeForThatGroup() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedGroup!
        model.beginRenaming(id)
        #expect(model.renamingGroup == id)

        model.renameGroup(id, to: "lucky-spark")

        #expect(model.renamingGroup == nil)
    }

    @Test func beginRenamingFocusedGroupTargetsFocused() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        model.beginRenamingFocusedGroup()

        #expect(model.renamingGroup == focused)
    }

    @Test func beginRenamingUnknownGroupIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())

        model.beginRenaming(GroupID())

        #expect(model.renamingGroup == nil)
    }

    @Test func cancelRenamingClearsRenameMode() {
        let model = WorkspaceModel(wrapping: .init())
        model.beginRenamingFocusedGroup()
        #expect(model.renamingGroup != nil)

        model.cancelRenaming()

        #expect(model.renamingGroup == nil)
    }

    // MARK: toggle_group_zoom (SPEC §11.6, invariants §14.5, §14.15)

    @Test func toggleGroupZoomZoomsAndUnzoomsFocusedGroup() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        #expect(model.state.zoomedGroup == nil)

        // First toggle zooms the focused (right) group; second clears it.
        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == right)

        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == nil)
    }

    @Test func toggleGroupZoomIsNoOpWithoutFocusedGroup() {
        let model = WorkspaceModel()
        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == nil)
    }

    @Test func canToggleGroupZoomRequiresOnlyAFocusedGroup() throws {
        // With no focused group there is nothing to zoom.
        #expect(WorkspaceModel().canToggleGroupZoom == false)

        // Since the overall view renders only each group's primary pane and
        // disables pane operations (SPEC §22.3, §22.5), zoom is the gateway
        // to a group's full pane layout — meaningful even for a single
        // visible group.
        let single = WorkspaceModel(wrapping: .init())
        #expect(single.canToggleGroupZoom == true)

        // More than one visible group → zoom is meaningful as before.
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        #expect(model.canToggleGroupZoom == true)

        // A zoom can always be cleared, even when the visible tree is a single
        // (zoomed) leaf.
        var zoomed = model.state
        zoomed.zoomedGroup = right
        #expect(WorkspaceModel(zoomed).canToggleGroupZoom == true)
    }

    // MARK: hide_group (SPEC §11.7, §18.2–3, invariants §14.7, §14.16–17)

    @Test func hideFocusedGroupHidesAndMovesFocusToNeighbor() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        #expect(model.state.focusedGroup == right)

        let result = try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))

        // The hidden group joins `hiddenGroupIDs`; focus moves to the neighbor.
        #expect(result.target == left)
        #expect(model.state.hiddenGroupIDs == [right])
        #expect(model.state.focusedGroup == left)
        // Its leaf leaves the canonical tree so the visible groups reclaim the
        // space, but §14.7: the group stays alive in `groups`, so its
        // processes/panes persist for `show_group`.
        #expect(model.state.groups.count == 2)
        #expect(model.state.groups[right] != nil)
        #expect(model.state.canonicalGroupTree.map(\.id) == [left])
        #expect(model.state.canonicalGroupTree.isSplit == false)
    }

    @Test func hideFocusedGroupRejectsLastVisibleGroup() {
        // §18.2: the last visible group cannot be hidden.
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        let result = model.hideFocusedGroup(savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.state.focusedGroup == focused)
    }

    @Test func hideFocusedGroupRejectsWhenOnlyOtherGroupAlreadyHidden() throws {
        // Two groups, the left already hidden, the right focused. Hiding the
        // right would leave nothing visible → rejected (§18.2).
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        model.switchFocusedGroup(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenGroupIDs == [left])
        #expect(model.state.focusedGroup == right)

        #expect(model.canHideFocusedGroup == false)
        #expect(model.hideFocusedGroup(savingOutgoingPaneTree: .init()) == nil)
        #expect(model.state.hiddenGroupIDs == [left])
        #expect(model.state.focusedGroup == right)
        #expect(model.state.canonicalGroupTree.map(\.id) == [right])
    }

    @Test func hideFocusedGroupClearsZoom() throws {
        // §18.3: a zoomed group un-zooms before being hidden.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        var state = model.state
        state.zoomedGroup = right
        let zoomedModel = WorkspaceModel(state)

        let result = try #require(zoomedModel.hideFocusedGroup(savingOutgoingPaneTree: .init()))

        #expect(result.target == left)
        #expect(zoomedModel.state.zoomedGroup == nil)
        #expect(zoomedModel.state.hiddenGroupIDs == [right])
        #expect(zoomedModel.state.focusedGroup == left)
    }

    @Test func canHideFocusedGroupReflectsVisibleGroupCount() throws {
        let single = WorkspaceModel(wrapping: .init())
        #expect(single.canHideFocusedGroup == false)

        let (model, _, _) = try Self.makeTwoGroupHorizontal()
        #expect(model.canHideFocusedGroup == true)
    }

    // MARK: show_group (SPEC §11.8, §7.2)

    @Test func showGroupUnhidesAndFocuses() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        // Hide the focused (right) group; focus falls back to the left.
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedGroup == left)

        // Showing it again un-hides and focuses it, re-attaching its leaf.
        model.showGroup(right, savingOutgoingPaneTree: .init())

        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.state.focusedGroup == right)
        #expect(Set(model.state.canonicalGroupTree.map(\.id)) == Set([left, right]))
    }

    @Test func showGroupSplitsTrailingGroupAndTakesRightHalf() throws {
        // Hide the *leftmost* of three groups: showing it again does not put it
        // back on the left, it takes the right half of the trailing group.
        let (model, ids) = try Self.makeThreeGroupRow()
        model.switchFocusedGroup(to: ids.left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.canonicalGroupTree.map(\.id) == [ids.middle, ids.right])

        // Skew the surviving split to check the show leaves it untouched.
        model.resizeFocusedGroup(.left, ratioDelta: 0.2)

        model.showGroup(ids.left, savingOutgoingPaneTree: .init())

        // The trailing group (in-order last) was split; the shown group is the
        // new in-order last.
        #expect(model.state.canonicalGroupTree.map(\.id) == [ids.middle, ids.right, ids.left])
        #expect(model.state.focusedGroup == ids.left)
        #expect(model.state.hiddenGroupIDs.isEmpty)
        // The skewed split survives; the new trailing split is 50/50.
        let ratios = Self.canonicalRatios(model)
        #expect(ratios.count == 2)
        #expect(abs(ratios[0] - 0.3) < 1e-9)
        #expect(abs(ratios[1] - 0.5) < 1e-9)
    }

    @Test func showGroupClearsZoom() throws {
        // A group hidden while another is zoomed: showing it clears the zoom.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedGroup == left)

        var state = model.state
        state.zoomedGroup = left
        let staged = WorkspaceModel(state)

        staged.showGroup(right, savingOutgoingPaneTree: .init())

        #expect(staged.state.zoomedGroup == nil)
        #expect(staged.state.hiddenGroupIDs.isEmpty)
        #expect(staged.state.focusedGroup == right)
    }

    @Test func showGroupIsNoOpForUnknownGroup() throws {
        // A stale hidden id with no `GroupState` must not add a dangling leaf.
        let (model, left, _) = try Self.makeTwoGroupHorizontal()
        var state = model.state
        let ghost = GroupID()
        state.hiddenGroupIDs = [ghost]
        let staged = WorkspaceModel(state)

        #expect(staged.showGroup(ghost, savingOutgoingPaneTree: .init()) == nil)
        #expect(staged.state.canonicalGroupTree.find(id: ghost) == nil)
        #expect(staged.state.canonicalGroupTree.find(id: left) != nil)
    }

    @Test func showGroupIsNoOpForNonHiddenGroup() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        // `right` is focused and visible; showing it is a no-op.
        let result = model.showGroup(right, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedGroup == right)
        #expect(model.state.hiddenGroupIDs.isEmpty)
    }

    @Test func hiddenGroupIDNamedResolvesOnlyHiddenGroups() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        let rightName = try #require(model.state.groups[right]?.name)

        // While visible, the name does not resolve to a hidden group.
        #expect(model.hiddenGroupID(named: rightName) == nil)

        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))

        // Once hidden, the name resolves; unknown names still do not.
        #expect(model.hiddenGroupID(named: rightName) == right)
        #expect(model.hiddenGroupID(named: "no-such-group") == nil)
    }

    // MARK: close_group (SPEC §11.9, §18.5)

    @Test func closeFocusedGroupSwitchesToNeighborAndPrunes() throws {
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        #expect(model.state.focusedGroup == right)

        // Closing the focused (right) group moves focus to the left neighbor and
        // removes the closed group from the canonical tree and `groups`.
        let outcome = model.closeFocusedGroup()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(model.state.focusedGroup == left)
        #expect(model.state.groups.count == 1)
        #expect(model.state.groups[left] != nil)
        #expect(model.state.groups[right] == nil)
        #expect(Set(model.state.canonicalGroupTree.map(\.id)) == Set([left]))
    }

    @Test func closeFocusedGroupReturnsClosedLastForOnlyGroup() {
        // §18.5: the only group's close is delegated to tab/window close, and the
        // model is left untouched so the close can be undone.
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        let outcome = model.closeFocusedGroup()

        #expect(outcome == .closedLast)
        #expect(model.state.focusedGroup == focused)
        #expect(model.state.groups.count == 1)
        #expect(model.state.canonicalGroupTree.map(\.id) == [focused].compactMap { $0 })
    }

    @Test func closeFocusedGroupReturnsNilWithoutFocusedGroup() {
        let model = WorkspaceModel()
        #expect(model.closeFocusedGroup() == nil)
    }

    @Test func closeFocusedGroupClearsZoomOnClosedGroup() throws {
        // The focused (right) group is also zoomed; closing it clears the zoom.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        var state = model.state
        state.zoomedGroup = right
        let zoomedModel = WorkspaceModel(state)

        let outcome = zoomedModel.closeFocusedGroup()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(zoomedModel.state.zoomedGroup == nil)
        #expect(zoomedModel.state.focusedGroup == left)
    }

    @Test func closeFocusedGroupRevealsHiddenGroupWhenNoVisibleNeighbor() throws {
        // The left group is hidden and the right is focused. Closing the right
        // leaves no visible neighbor, so the hidden left is revealed (re-attached
        // to the tree) and focused — the focused group must always be visible
        // (invariant §14.6).
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        model.switchFocusedGroup(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedGroup == right)

        let outcome = model.closeFocusedGroup()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(model.state.focusedGroup == left)
        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.state.groups[right] == nil)
        #expect(model.state.canonicalGroupTree.map(\.id) == [left])
    }

    @Test func closeFocusedGroupKeepsOtherHiddenGroupHidden() throws {
        // Three groups, the middle hidden, the rightmost focused. Closing the
        // focused group moves focus to the remaining visible group (the left),
        // never to the hidden middle, which stays hidden.
        let (model, ids) = try Self.makeThreeGroupRow()
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenGroupIDs == [ids.middle])
        model.switchFocusedGroup(to: ids.right, savingOutgoingPaneTree: .init())

        let outcome = model.closeFocusedGroup()

        #expect(outcome == .switched(target: ids.left, focus: nil))
        #expect(model.state.focusedGroup == ids.left)
        #expect(model.state.hiddenGroupIDs == [ids.middle])
        #expect(model.state.groups[ids.right] == nil)
        #expect(model.state.canonicalGroupTree.map(\.id) == [ids.left])
        // The hidden group is still alive in `groups`, just not in the tree.
        #expect(model.state.groups[ids.middle] != nil)
    }

    // MARK: restoreState (group-aware undo)

    @Test func restoreStateSwapsEntireState() throws {
        // A snapshot captured from one model fully replaces another model's
        // state — focusedGroup, canonical tree, groups, hidden, and zoom.
        let (source, left, right) = try Self.makeTwoGroupHorizontal()
        var snapshot = source.state
        snapshot.focusedGroup = left
        snapshot.hiddenGroupIDs = [right]
        snapshot.zoomedGroup = left

        let model = WorkspaceModel(wrapping: .init())
        model.restoreState(snapshot)

        #expect(model.state.focusedGroup == left)
        #expect(model.state.hiddenGroupIDs == [right])
        #expect(model.state.zoomedGroup == left)
        #expect(Set(model.state.groups.keys) == Set([left, right]))
        #expect(Set(model.state.canonicalGroupTree.map(\.id)) == Set([left, right]))
    }

    @Test func restoreStateRoundTripsAfterHide() throws {
        // Capture, hide the focused group (which switches focus + flips hidden),
        // then restore the snapshot — the pre-hide state comes back intact. This
        // is exactly the undo path the controller wraps.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        let before = model.state
        #expect(before.focusedGroup == right)

        let hidden = model.hideFocusedGroup(savingOutgoingPaneTree: .init())
        #expect(hidden?.target == left)
        #expect(model.state.hiddenGroupIDs == [right])
        #expect(model.state.focusedGroup == left)
        #expect(model.state.canonicalGroupTree.map(\.id) == [left])

        model.restoreState(before)

        #expect(model.state.focusedGroup == right)
        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(Set(model.state.groups.keys) == Set([left, right]))
        // The snapshot carries the pre-hide tree, so the leaf comes back exactly
        // where it was rather than at the right edge.
        #expect(model.state.canonicalGroupTree.map(\.id) == [left, right])
    }

    @Test func restoreStateCancelsRenameForMissingGroup() throws {
        // Restoring to a state that no longer contains the group being renamed
        // clears the transient rename mode so it can't outlive its group.
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        let snapshotWithoutRight = WorkspaceModel(wrapping: .init()).state

        model.beginRenaming(right)
        #expect(model.renamingGroup == right)

        model.restoreState(snapshotWithoutRight)
        #expect(model.renamingGroup == nil)
    }

    @Test func restoreStateKeepsRenameForSurvivingGroup() throws {
        // Restoring to a state that still contains the renamed group keeps the
        // rename mode active.
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        let snapshot = model.state

        model.beginRenaming(right)
        #expect(model.renamingGroup == right)

        model.restoreState(snapshot)
        #expect(model.renamingGroup == right)
    }

    // MARK: Teardown

    @Test func removeAllGroupsDropsEveryGroup() throws {
        // A window close must release *every* group's surfaces, not just the
        // focused one's, so no unfocused/hidden group's shell outlives the window.
        let (model, _, _) = try Self.makeTwoGroupHorizontal()
        #expect(model.state.groups.count == 2)

        model.removeAllGroups()

        #expect(model.state.groups.isEmpty)
        #expect(model.state.canonicalGroupTree.isEmpty)
        #expect(model.state.focusedGroup == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func removeAllGroupsClearsRename() throws {
        let (model, _, right) = try Self.makeTwoGroupHorizontal()
        model.beginRenaming(right)

        model.removeAllGroups()

        #expect(model.renamingGroup == nil)
    }

    @Test func removeAllGroupsAlsoDropsHiddenGroups() throws {
        // Hidden groups are the ones most at risk: they're invisible, still
        // running, and only reachable through `groups`.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        model.hideFocusedGroup(savingOutgoingPaneTree: .init())
        #expect(model.state.hiddenGroupIDs == [right])
        #expect(model.state.focusedGroup == left)

        model.removeAllGroups()

        #expect(model.state.groups.isEmpty)
        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.state.zoomedGroup == nil)
    }

    // MARK: Group numbering (SPEC §4.1)

    /// Builds a horizontal row of `count` groups (1 ≤ count ≤ 9) in traversal
    /// order, with the *first* one focused so the tests can hide/close from a
    /// known slot. Returns the ids in traversal order.
    private static func makeRow(_ count: Int) throws -> (model: WorkspaceModel, ids: [GroupID]) {
        let model = WorkspaceModel(wrapping: .init(), name: "group-1")
        var ids = [try #require(model.state.focusedGroup)]

        for index in 1..<count {
            let group = makeEmptyGroup(name: "group-\(index + 1)")
            try model.openNewGroup(group, direction: .right, savingOutgoingPaneTree: .init())
            ids.append(group.id)
        }

        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())
        #expect(model.state.canonicalGroupTree.map(\.id) == ids)
        return (model, ids)
    }

    @Test func ordinalsFollowCanonicalTraversalOrder() throws {
        let (model, ids) = try Self.makeRow(3)

        #expect(ids.map { model.ordinal(of: $0) } == [1, 2, 3])
        #expect(model.state.visibleGroupIDs == ids)
        #expect(model.state.visibleGroupCount == 3)
        #expect(model.state.groupOrdinals == [ids[0]: 1, ids[1]: 2, ids[2]: 3])
        // The inverse lookup agrees, and stops at the end of the row.
        #expect(model.state.visibleGroupID(ordinal: 2) == ids[1])
        #expect(model.state.visibleGroupID(ordinal: 4) == nil)
        #expect(model.state.visibleGroupID(ordinal: 0) == nil)
    }

    @Test func ordinalsFollowInOrderTraversalUsedByNextFocus() throws {
        // The numbering must match what `previous`/`next` walk, so the numbers
        // read in the same order as group-to-group navigation.
        let (model, ids) = try Self.makeRow(3)
        var walked = [ids[0]]
        for _ in 1..<3 {
            let next = try #require(model.gotoGroupTarget(.next))
            model.switchFocusedGroup(to: next, savingOutgoingPaneTree: .init())
            walked.append(next)
        }

        #expect(walked == ids)
        #expect(walked.map { model.ordinal(of: $0) } == [1, 2, 3])
    }

    @Test func ordinalsRepackAfterHide() throws {
        let (model, ids) = try Self.makeRow(3)
        // Hide the middle group: the trailing group moves up to number 2.
        model.switchFocusedGroup(to: ids[1], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))

        #expect(model.ordinal(of: ids[0]) == 1)
        #expect(model.ordinal(of: ids[2]) == 2)
        // A hidden group has no number at all (the shelf shows bare names).
        #expect(model.ordinal(of: ids[1]) == nil)
        #expect(model.state.visibleGroupCount == 2)
    }

    @Test func ordinalsRepackAfterClose() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())
        #expect(model.closeFocusedGroup() != nil)

        // The survivors slide down to 1 and 2.
        #expect(model.ordinal(of: ids[1]) == 1)
        #expect(model.ordinal(of: ids[2]) == 2)
        #expect(model.ordinal(of: ids[0]) == nil)
    }

    @Test func ordinalsRepackAfterMoveGroup() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())

        #expect(model.moveFocusedGroup(.next) == true)

        // The two leaves traded slots, so their numbers traded too.
        #expect(model.ordinal(of: ids[1]) == 1)
        #expect(model.ordinal(of: ids[0]) == 2)
        #expect(model.ordinal(of: ids[2]) == 3)
    }

    @Test func ordinalsRepackAfterShowGroup() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.ordinal(of: ids[1]) == 1)

        // `show_group` re-attaches at the trailing leaf, so it takes the last
        // number rather than its old one.
        model.showGroup(ids[0], savingOutgoingPaneTree: .init())

        #expect(model.ordinal(of: ids[1]) == 1)
        #expect(model.ordinal(of: ids[2]) == 2)
        #expect(model.ordinal(of: ids[0]) == 3)
    }

    @Test func zoomedGroupKeepsItsCanonicalOrdinal() throws {
        // Zoom is a display state over the canonical tree, so the zoomed group
        // keeps the number it has in the full layout instead of showing `1`.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedGroup = ids[2]
        state.zoomedGroup = ids[2]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.ordinal(of: ids[2]) == 3)
        #expect(zoomed.state.groupOrdinals == [ids[0]: 1, ids[1]: 2, ids[2]: 3])
        // The effective (rendered) tree really is just the one group.
        #expect(zoomed.state.effectiveVisibleGroupTree?.map(\.id) == [ids[2]])
    }

    // MARK: Visible-group cap (max 9)

    @Test func openNewGroupSucceedsBelowTheVisibleCap() throws {
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleGroups - 1)
        #expect(model.canAddVisibleGroup == true)

        let extra = Self.makeEmptyGroup(name: "ninth")
        model.switchFocusedGroup(to: ids.last!, savingOutgoingPaneTree: .init())
        try model.openNewGroup(extra, direction: .right, savingOutgoingPaneTree: .init())

        #expect(model.state.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        #expect(model.ordinal(of: extra.id) == WorkspaceState.maxVisibleGroups)
    }

    @Test func openNewGroupIsRejectedAtTheVisibleCap() throws {
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleGroups)
        #expect(model.canAddVisibleGroup == false)
        let before = model.state

        #expect(throws: WorkspaceModel.WorkspaceError.visibleGroupLimitReached) {
            try model.openNewGroup(
                Self.makeEmptyGroup(name: "tenth"),
                direction: .right,
                savingOutgoingPaneTree: .init())
        }

        // Silently rejected: the state is byte-for-byte unchanged.
        #expect(model.state.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        #expect(model.state.canonicalGroupTree.map(\.id) == ids)
        #expect(Set(model.state.groups.keys) == Set(before.groups.keys))
        #expect(model.state.focusedGroup == before.focusedGroup)
    }

    @Test func showGroupSucceedsBelowTheVisibleCap() throws {
        // 9 groups with one hidden → 8 visible, so the reveal fits.
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleGroups)
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(model.state.visibleGroupCount == WorkspaceState.maxVisibleGroups - 1)
        #expect(model.canShowGroup(ids[0]) == true)

        model.showGroup(ids[0], savingOutgoingPaneTree: .init())

        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.state.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        #expect(model.state.focusedGroup == ids[0])
    }

    @Test func showGroupIsRejectedAtTheVisibleCap() throws {
        // 9 visible groups plus a hidden 10th: the pill must stay on the shelf.
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleGroups)
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        let extra = Self.makeEmptyGroup(name: "tenth")
        try model.openNewGroup(extra, direction: .right, savingOutgoingPaneTree: .init())
        #expect(model.state.visibleGroupCount == WorkspaceState.maxVisibleGroups)

        let before = model.state
        #expect(model.canShowGroup(ids[0]) == false)
        #expect(model.showGroup(ids[0], savingOutgoingPaneTree: .init()) == nil)

        #expect(model.state.hiddenGroupIDs == [ids[0]])
        #expect(model.state.canonicalGroupTree.map(\.id) == before.canonicalGroupTree.map(\.id))
        #expect(model.state.focusedGroup == before.focusedGroup)
    }

    @Test func closeGroupStillRevealsAHiddenGroupAtTheCap() throws {
        // §14.6 is unaffected by the cap: closing only ever frees a slot, so the
        // "no visible neighbor left" reveal can always run.
        let (model, left, right) = try Self.makeTwoGroupHorizontal()
        model.switchFocusedGroup(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))

        #expect(model.closeFocusedGroup() == .switched(target: left, focus: nil))
        #expect(model.state.hiddenGroupIDs.isEmpty)
        #expect(model.ordinal(of: left) == 1)
        #expect(model.state.groups[right] == nil)
    }

    // MARK: goto_group:<1-9> (index jump)

    @Test func gotoGroupIndexResolvesNthVisibleGroup() throws {
        let (model, ids) = try Self.makeRow(3)
        // Focused is the first group, so 2 and 3 resolve.
        #expect(model.gotoGroupIndexTarget(2) == ids[1])
        #expect(model.gotoGroupIndexTarget(3) == ids[2])
    }

    @Test func gotoGroupIndexBeyondVisibleCountIsNil() throws {
        let (model, _) = try Self.makeRow(3)
        #expect(model.gotoGroupIndexTarget(4) == nil)
        #expect(model.gotoGroupIndexTarget(9) == nil)
        #expect(model.gotoGroupIndexTarget(0) == nil)
    }

    @Test func gotoGroupIndexToSelfIsNil() throws {
        let (model, ids) = try Self.makeRow(3)
        // The focused group is number 1; jumping to it changes nothing, so the
        // keybind stays unconsumed.
        #expect(model.state.focusedGroup == ids[0])
        #expect(model.gotoGroupIndexTarget(1) == nil)
        #expect(model.gotoGroup(index: 1, savingOutgoingPaneTree: .init()) == nil)
    }

    @Test func gotoGroupIndexSkipsHiddenGroups() throws {
        // Hidden groups have no number, so the numbering re-packs and index 2
        // lands on what used to be number 3.
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedGroup(to: ids[1], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        model.switchFocusedGroup(to: ids[0], savingOutgoingPaneTree: .init())

        #expect(model.gotoGroupIndexTarget(2) == ids[2])
        #expect(model.gotoGroupIndexTarget(3) == nil)
    }

    @Test func gotoGroupIndexSwitchesFocusToTarget() throws {
        let (model, ids) = try Self.makeRow(3)

        let result = try #require(model.gotoGroup(index: 3, savingOutgoingPaneTree: .init()))

        #expect(result.target == ids[2])
        #expect(model.state.focusedGroup == ids[2])
        // A pure focus change: the layout and the group set are untouched.
        #expect(model.state.canonicalGroupTree.map(\.id) == ids)
        #expect(model.state.zoomedGroup == nil)
    }

    @Test func gotoGroupIndexClearsZoomAndJumps() throws {
        // Unlike the directional `goto_group`, an index jump works while zoomed:
        // it clears the zoom and lands on the target in one operation.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedGroup = ids[0]
        state.zoomedGroup = ids[0]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.gotoGroupIndexTarget(3) == ids[2])
        let result = try #require(zoomed.gotoGroup(index: 3, savingOutgoingPaneTree: .init()))

        #expect(result.target == ids[2])
        #expect(zoomed.state.zoomedGroup == nil)
        #expect(zoomed.state.focusedGroup == ids[2])
        // The un-zoomed multi-group layout is what renders again.
        #expect(zoomed.state.effectiveVisibleGroupTree?.map(\.id) == ids)
    }

    @Test func gotoGroupIndexToZoomedGroupKeepsZoom() throws {
        // Asking for the group you are already zoomed into is a no-op — the zoom
        // survives, so Cmd+N doesn't accidentally un-zoom.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedGroup = ids[1]
        state.zoomedGroup = ids[1]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.gotoGroupIndexTarget(2) == nil)
        #expect(zoomed.gotoGroup(index: 2, savingOutgoingPaneTree: .init()) == nil)
        #expect(zoomed.state.zoomedGroup == ids[1])
        #expect(zoomed.state.focusedGroup == ids[1])
    }

    @Test func gotoGroupIndexOnEmptyModelIsNil() {
        let model = WorkspaceModel()
        #expect(model.gotoGroupIndexTarget(1) == nil)
        #expect(model.gotoGroup(index: 1, savingOutgoingPaneTree: .init()) == nil)
    }
}
