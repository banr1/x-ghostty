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

    // MARK: Orphan reconciliation (SPEC §12.3)

    /// Removes `id`'s leaf from the canonical tree, reproducing what `hide_group`
    /// leaves behind: the `GroupState` survives in `groups` with no leaf.
    private static func hiding(_ id: GroupID, in state: WorkspaceState) -> WorkspaceState {
        var next = state
        next.canonicalGroupTree = next.canonicalGroupTree.removing(.leaf(view: GroupRef(id: id)))
        next.hiddenGroupIDs.insert(id)
        return next
    }

    @Test func restoringReattachesGroupsMissingFromTree() throws {
        // Saved while g2 was hidden: `hiddenGroupIDs` is not persisted, so
        // without reconciliation g2 would come back alive but unreachable.
        let (base, ids) = try Self.makeTwoGroupState()
        let state = Self.hiding(ids.1, in: base)
        #expect(state.canonicalGroupTree.map(\.id) == [ids.0])

        let restored = WorkspaceState.restoring(state)

        // Re-attached by splitting the trailing leaf, everything visible again
        // (§12.3).
        #expect(restored.canonicalGroupTree.map(\.id) == [ids.0, ids.1])
        #expect(restored.hiddenGroupIDs.isEmpty)
        #expect(Set(restored.groups.keys) == Set([ids.0, ids.1]))
        #expect(restored.effectiveVisibleGroupTree?.map(\.id) == [ids.0, ids.1])
    }

    @Test func restoringKeepsFocusValidAfterReattaching() throws {
        // The focused group is the one that was hidden: reconciliation runs
        // before the focus check, so it stays focused rather than being reset.
        let (base, ids) = try Self.makeTwoGroupState()
        var state = Self.hiding(ids.1, in: base)
        state.focusedGroup = ids.1

        let restored = WorkspaceState.restoring(state)

        #expect(restored.focusedGroup == ids.1)
        #expect(restored.canonicalGroupTree.find(id: ids.1) != nil)
    }

    @Test func restoringLeavesAConsistentTreeUntouched() throws {
        let (state, _) = try Self.makeTwoGroupState()
        let restored = WorkspaceState.restoring(state)
        #expect(restored.canonicalGroupTree.structuralIdentity == state.canonicalGroupTree.structuralIdentity)
    }

    @Test func decodingReattachesGroupsMissingFromTree() throws {
        let (base, ids) = try Self.makeTwoGroupState()
        let state = Self.hiding(ids.1, in: base)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        // Both groups persist; the orphan is re-attached so nothing leaks.
        #expect(Set(decoded.groups.keys) == Set([ids.0, ids.1]))
        #expect(Set(decoded.canonicalGroupTree.map(\.id)) == Set([ids.0, ids.1]))
        #expect(decoded.hiddenGroupIDs.isEmpty)
    }

    // MARK: Group numbering (SPEC §4.1)

    @Test func ordinalsNumberVisibleGroupsInTraversalOrder() throws {
        let (state, ids) = try Self.makeTwoGroupState()

        #expect(state.visibleGroupIDs == [ids.0, ids.1])
        #expect(state.visibleGroupCount == 2)
        #expect(state.ordinal(of: ids.0) == 1)
        #expect(state.ordinal(of: ids.1) == 2)
        #expect(state.visibleGroupID(ordinal: 1) == ids.0)
        #expect(state.visibleGroupID(ordinal: 3) == nil)
        #expect(state.ordinal(of: GroupID()) == nil)
    }

    // MARK: Restore cap (max 9 visible)

    /// Builds a state with `count` groups in a horizontal row, all visible and
    /// with strictly increasing `createdAt` so orphan reconciliation order is
    /// deterministic. The first group is focused. Returns the ids in traversal
    /// (and creation) order.
    private static func makeRowState(_ count: Int) throws -> (state: WorkspaceState, ids: [GroupID]) {
        precondition(count >= 1)
        let base = Date(timeIntervalSince1970: 0)

        var ids = [GroupID()]
        var tree = SplitTree<GroupRef>(view: GroupRef(id: ids[0]))
        var groups: [GroupID: GroupState] = [
            ids[0]: GroupState(id: ids[0], name: "g1", paneTree: .init(), createdAt: base),
        ]

        for index in 1..<count {
            let id = GroupID()
            tree = try tree.inserting(
                view: GroupRef(id: id),
                at: GroupRef(id: ids[index - 1]),
                direction: .right)
            groups[id] = GroupState(
                id: id,
                name: "g\(index + 1)",
                paneTree: .init(),
                createdAt: base.addingTimeInterval(Double(index)))
            ids.append(id)
        }

        let state = WorkspaceState(canonicalGroupTree: tree, groups: groups, focusedGroup: ids[0])
        #expect(state.canonicalGroupTree.map(\.id) == ids)
        return (state, ids)
    }

    /// The §14.1–3 invariants: every canonical leaf is a known group, every
    /// group is either a leaf or hidden, and hidden groups have no leaf.
    private static func expectInvariants(_ state: WorkspaceState) {
        let leafIDs = Set(state.canonicalGroupTree.map(\.id))
        let groupKeys = Set(state.groups.keys)

        #expect(leafIDs.isSubset(of: groupKeys))
        #expect(state.hiddenGroupIDs.isSubset(of: groupKeys))
        // §14.3: a hidden group must not have a canonical leaf.
        #expect(leafIDs.isDisjoint(with: state.hiddenGroupIDs))
        // §14.2: every group is accounted for as visible or hidden.
        #expect(leafIDs.union(state.hiddenGroupIDs) == groupKeys)
    }

    @Test func restoringLeavesEverythingVisibleUnderTheCap() throws {
        // At most 9 groups: unchanged behaviour, everything comes back visible.
        let (state, ids) = try Self.makeRowState(WorkspaceState.maxVisibleGroups)

        let restored = WorkspaceState.restoring(state)

        #expect(restored.canonicalGroupTree.map(\.id) == ids)
        #expect(restored.hiddenGroupIDs.isEmpty)
        #expect(restored.focusedGroup == ids[0])
        Self.expectInvariants(restored)
    }

    @Test func restoringPrunesALegacyTreeWithMoreThanNineLeaves() throws {
        // A save written before the cap existed can carry >9 canonical leaves.
        // The first 9 in traversal order keep their slots; the rest move to the
        // shelf, still alive in `groups`.
        let (state, ids) = try Self.makeRowState(12)

        let restored = WorkspaceState.restoring(state)

        #expect(restored.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        #expect(restored.canonicalGroupTree.map(\.id) == Array(ids.prefix(9)))
        #expect(restored.hiddenGroupIDs == Set(ids.dropFirst(9)))
        #expect(Set(restored.groups.keys) == Set(ids))
        Self.expectInvariants(restored)
    }

    @Test func restoringReattachesOrphansOnlyUpToTheCap() throws {
        // 12 groups of which 8 were hidden at save time: 4 stay placed, 5 of the
        // orphans fit under the cap (in creation order), the last 3 stay hidden.
        let (base, ids) = try Self.makeRowState(12)
        var state = base
        for id in ids.dropFirst(4) {
            state = Self.hiding(id, in: state)
        }
        #expect(state.canonicalGroupTree.map(\.id) == Array(ids.prefix(4)))

        let restored = WorkspaceState.restoring(state)

        #expect(restored.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        // Orphans are re-attached at the trailing leaf in creation order, so the
        // visible set is simply the first 9 groups.
        #expect(restored.canonicalGroupTree.map(\.id) == Array(ids.prefix(9)))
        #expect(restored.hiddenGroupIDs == Set(ids.dropFirst(9)))
        #expect(Set(restored.groups.keys) == Set(ids))
        Self.expectInvariants(restored)
    }

    @Test func restoringNumbersTheCappedVisibleGroupsOneThroughNine() throws {
        let (state, ids) = try Self.makeRowState(12)
        let restored = WorkspaceState.restoring(state)

        #expect(ids.prefix(9).compactMap { restored.ordinal(of: $0) } == Array(1...9))
        // The overflow groups are hidden, so they have no number.
        #expect(ids.dropFirst(9).allSatisfy { restored.ordinal(of: $0) == nil })
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusIsCappedOut() throws {
        // The saved focused group is beyond the cap, so it comes back hidden and
        // focus falls back to the canonical tree's first leaf (§14.6: the focused
        // group is always visible).
        let (base, ids) = try Self.makeRowState(12)
        var state = base
        state.focusedGroup = ids[11]

        let restored = WorkspaceState.restoring(state)

        #expect(restored.hiddenGroupIDs.contains(ids[11]))
        #expect(restored.focusedGroup == ids[0])
        let focused = try #require(restored.focusedGroup)
        #expect(restored.canonicalGroupTree.find(id: focused) != nil)
        Self.expectInvariants(restored)
    }

    @Test func restoringIsIdempotent() throws {
        // Decode already applies the restore layout, and `restoring(_:)` runs it
        // again on top: the second pass must not move anything.
        let (state, ids) = try Self.makeRowState(12)
        let once = WorkspaceState.restoring(state)
        let twice = WorkspaceState.restoring(once)

        #expect(twice.canonicalGroupTree.map(\.id) == once.canonicalGroupTree.map(\.id))
        #expect(twice.hiddenGroupIDs == once.hiddenGroupIDs)
        #expect(twice.focusedGroup == once.focusedGroup)
        #expect(Set(twice.groups.keys) == Set(ids))
    }

    @Test func decodingCapsVisibleGroupsAtNine() throws {
        let (state, ids) = try Self.makeRowState(12)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(Set(decoded.groups.keys) == Set(ids))
        #expect(decoded.visibleGroupCount == WorkspaceState.maxVisibleGroups)
        #expect(decoded.canonicalGroupTree.map(\.id) == Array(ids.prefix(9)))
        #expect(decoded.hiddenGroupIDs == Set(ids.dropFirst(9)))
        Self.expectInvariants(decoded)
    }
}
