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
        var model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedGroup

        model.replaceFocusedPaneTree(.init())

        // Still a single focused group; only its pane tree was touched.
        #expect(model.state.groups.count == 1)
        #expect(model.state.focusedGroup == focused)
        #expect(model.focusedGroupState?.paneTree.isEmpty == true)
        #expect(model.focusedGroupState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceIgnoresSurfaceNotInPaneTree() {
        var model = WorkspaceModel(wrapping: .init())
        // The surface id is not present in the (empty) pane tree, so this is a
        // no-op rather than recording a dangling focus.
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedGroupState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceOnEmptyModelIsNoOp() {
        var model = WorkspaceModel()
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedGroupState == nil)
    }
}
