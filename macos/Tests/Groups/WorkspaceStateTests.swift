import Foundation
import Testing
@testable import XGhostty

/// Phase 0 tests for the group-layer data model. These exercise the value-type
/// pieces (`WorkspaceState`, `effectiveVisibleGroupTree`, Codable) without
/// requiring a live XGhostty app, so pane trees are kept empty.
struct WorkspaceStateTests {
    // MARK: Helpers

    /// Builds a two-group canonical tree `(g1 | g2)` with empty pane trees and
    /// `g1` focused. Returns the state plus the two group ids.
    static func makeTwoGroupState() throws -> (state: WorkspaceState, ids: (GroupID, GroupID)) {
        let g1 = GroupID()
        let g2 = GroupID()

        var tree = SplitTree<GroupRef>(view: GroupRef(id: g1))
        tree = try tree.inserting(view: GroupRef(id: g2), at: GroupRef(id: g1), direction: .right)

        let now = Date()
        let groups: [GroupID: GroupState] = [
            g1: GroupState(id: g1, name: "g1", paneTree: .init(), createdAt: now),
            g2: GroupState(id: g2, name: "g2", paneTree: .init(), createdAt: now),
        ]

        let state = WorkspaceState(canonicalGroupTree: tree, groups: groups, focusedGroup: g1)
        return (state, (g1, g2))
    }

    // MARK: Invariants (SPEC §14.1–3)

    @Test func phase0InvariantsHoldForTwoGroupState() throws {
        let (state, _) = try Self.makeTwoGroupState()
        let leafIDs = Set(state.canonicalGroupTree.map(\.id))
        let groupKeys = Set(state.groups.keys)

        // §14.1: every canonical leaf exists in groups.
        #expect(leafIDs.isSubset(of: groupKeys))
        // §14.2: no group id exists outside the canonical tree.
        #expect(groupKeys.isSubset(of: leafIDs))
        // §14.3: hidden ids are a subset of group keys.
        #expect(state.hiddenGroupIDs.isSubset(of: groupKeys))
    }

    // MARK: effectiveVisibleGroupTree (SPEC §13)

    @Test func effectiveVisibleGroupTreeMatchesCanonicalWhenNothingHidden() throws {
        let (state, _) = try Self.makeTwoGroupState()
        let effective = state.effectiveVisibleGroupTree
        #expect(effective?.structuralIdentity == state.canonicalGroupTree.structuralIdentity)
    }

    @Test func effectiveVisibleGroupTreePrunesHiddenGroups() throws {
        var (state, ids) = try Self.makeTwoGroupState()
        state.hiddenGroupIDs = [ids.1]

        let effective = state.effectiveVisibleGroupTree
        #expect(effective?.find(id: ids.0) != nil)
        #expect(effective?.find(id: ids.1) == nil)
    }

    @Test func effectiveVisibleGroupTreeShowsOnlyZoomedGroup() throws {
        var (state, ids) = try Self.makeTwoGroupState()
        state.zoomedGroup = ids.0

        let effective = state.effectiveVisibleGroupTree
        #expect(effective?.find(id: ids.0) != nil)
        #expect(effective?.find(id: ids.1) == nil)
    }

    @Test func effectiveVisibleGroupTreeReturnsNilWhenZoomedGroupIsHidden() throws {
        var (state, ids) = try Self.makeTwoGroupState()
        state.zoomedGroup = ids.0
        state.hiddenGroupIDs = [ids.0]

        #expect(state.effectiveVisibleGroupTree == nil)
    }

    // MARK: Codable (SPEC §12)

    @Test func codableRoundTripsPersistentFieldsAndClearsRuntimeState() throws {
        var (state, ids) = try Self.makeTwoGroupState()
        // Runtime-only fields must not survive a round trip (§12.2).
        state.hiddenGroupIDs = [ids.1]
        state.zoomedGroup = ids.0

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(decoded.version == WorkspaceState.currentVersion)
        #expect(Set(decoded.groups.keys) == Set(state.groups.keys))
        #expect(decoded.canonicalGroupTree.structuralIdentity == state.canonicalGroupTree.structuralIdentity)
        #expect(decoded.focusedGroup == ids.0)

        // Runtime-only state cleared on decode.
        #expect(decoded.hiddenGroupIDs.isEmpty)
        #expect(decoded.zoomedGroup == nil)
    }

    @Test func groupsEncodeAsKeyedObjectWithUUIDStringKeys() throws {
        let (state, ids) = try Self.makeTwoGroupState()
        let data = try JSONEncoder().encode(state)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let groups = try #require(object?["groups"] as? [String: Any])

        #expect(groups[ids.0.rawValue.uuidString] != nil)
        #expect(groups[ids.1.rawValue.uuidString] != nil)
        #expect(groups.count == 2)
    }

    // MARK: restoring (SPEC §12.3)

    @Test func restoringClearsHiddenAndZoom() throws {
        var (state, ids) = try Self.makeTwoGroupState()
        state.hiddenGroupIDs = [ids.1]
        state.zoomedGroup = ids.0

        let restored = WorkspaceState.restoring(state)

        // Everything comes back visible and non-zoomed.
        #expect(restored.hiddenGroupIDs.isEmpty)
        #expect(restored.zoomedGroup == nil)
        // Canonical layout, groups and names are preserved.
        #expect(Set(restored.groups.keys) == Set(state.groups.keys))
        #expect(restored.canonicalGroupTree.structuralIdentity == state.canonicalGroupTree.structuralIdentity)
    }

    @Test func restoringKeepsValidFocusedGroup() throws {
        let (state, ids) = try Self.makeTwoGroupState()
        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedGroup == ids.0)
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusedGroupUnknown() throws {
        var (state, _) = try Self.makeTwoGroupState()
        // A focused group that no longer exists falls back to the canonical
        // tree's first leaf (§12.3).
        state.focusedGroup = GroupID()

        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedGroup != nil)
        #expect(restored.focusedGroup == state.canonicalGroupTree.firstLeaf?.id)
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusedGroupNil() throws {
        var (state, _) = try Self.makeTwoGroupState()
        state.focusedGroup = nil

        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedGroup == state.canonicalGroupTree.firstLeaf?.id)
    }
}
