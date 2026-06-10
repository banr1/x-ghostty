import Foundation
import Testing
@testable import Ghostty

/// Phase 0 tests for `WorkspaceModel`, the mirror that wraps the focused
/// group's pane tree. Pane trees are kept empty because constructing
/// `Ghostty.SurfaceView` leaves requires a live Ghostty app; richer pane
/// operations are covered by the existing `SplitTreeTests` and manual
/// integration checks.
struct WorkspaceModelTests {
    @Test func wrappingCreatesSingleDefaultFocusedGroup() {
        let model = WorkspaceModel(wrapping: .init())

        #expect(model.state.groups.count == 1)
        let focused = model.state.focusedGroup
        #expect(focused != nil)
        #expect(model.state.canonicalGroupTree.find(id: focused!) != nil)
        #expect(model.focusedGroupState != nil)
        #expect(model.focusedGroupState?.name == WorkspaceModel.defaultGroupName)
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
    /// constructing real `SurfaceView` leaves requires a live Ghostty app; the
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
}
