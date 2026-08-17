import Foundation
import Testing
@testable import XGhostty

/// Phase 0 tests for the project-layer data model. These exercise the value-type
/// pieces (`WorkspaceState`, `effectiveVisibleProjectTree`, Codable) without
/// requiring a live XGhostty app, so pane trees are kept empty.
struct WorkspaceStateTests {
    // MARK: Helpers

    /// Builds a two-project canonical tree `(g1 | g2)` with empty pane trees and
    /// `g1` focused. Returns the state plus the two project ids.
    static func makeTwoProjectState() throws -> (state: WorkspaceState, ids: (ProjectID, ProjectID)) {
        let g1 = ProjectID()
        let g2 = ProjectID()

        var tree = SplitTree<ProjectRef>(view: ProjectRef(id: g1))
        tree = try tree.inserting(view: ProjectRef(id: g2), at: ProjectRef(id: g1), direction: .right)

        let now = Date()
        let projects: [ProjectID: ProjectState] = [
            g1: ProjectState(id: g1, name: "g1", paneTree: .init(), createdAt: now),
            g2: ProjectState(id: g2, name: "g2", paneTree: .init(), createdAt: now),
        ]

        let state = WorkspaceState(canonicalProjectTree: tree, projects: projects, focusedProject: g1)
        return (state, (g1, g2))
    }

    // MARK: Invariants (SPEC §14.1–3)

    @Test func phase0InvariantsHoldForTwoProjectState() throws {
        let (state, _) = try Self.makeTwoProjectState()
        let leafIDs = Set(state.canonicalProjectTree.map(\.id))
        let projectKeys = Set(state.projects.keys)

        // §14.1: every canonical leaf exists in projects.
        #expect(leafIDs.isSubset(of: projectKeys))
        // §14.2: no project id exists outside the canonical tree.
        #expect(projectKeys.isSubset(of: leafIDs))
        // §14.3: hidden ids are a subset of project keys.
        #expect(state.hiddenProjectIDs.isSubset(of: projectKeys))
    }

    // MARK: effectiveVisibleProjectTree (SPEC §13)

    @Test func effectiveVisibleProjectTreeMatchesCanonicalWhenNothingHidden() throws {
        let (state, _) = try Self.makeTwoProjectState()
        let effective = state.effectiveVisibleProjectTree
        #expect(effective?.structuralIdentity == state.canonicalProjectTree.structuralIdentity)
    }

    @Test func effectiveVisibleProjectTreePrunesHiddenProjects() throws {
        var (state, ids) = try Self.makeTwoProjectState()
        state.hiddenProjectIDs = [ids.1]

        let effective = state.effectiveVisibleProjectTree
        #expect(effective?.find(id: ids.0) != nil)
        #expect(effective?.find(id: ids.1) == nil)
    }

    @Test func effectiveVisibleProjectTreeShowsOnlyZoomedProject() throws {
        var (state, ids) = try Self.makeTwoProjectState()
        state.zoomedProject = ids.0

        let effective = state.effectiveVisibleProjectTree
        #expect(effective?.find(id: ids.0) != nil)
        #expect(effective?.find(id: ids.1) == nil)
    }

    @Test func effectiveVisibleProjectTreeReturnsNilWhenZoomedProjectIsHidden() throws {
        var (state, ids) = try Self.makeTwoProjectState()
        state.zoomedProject = ids.0
        state.hiddenProjectIDs = [ids.0]

        #expect(state.effectiveVisibleProjectTree == nil)
    }

    // MARK: Codable (SPEC §12)

    @Test func codableRoundTripsLedgerAndClearsZoom() throws {
        var (state, ids) = try Self.makeTwoProjectState()
        // Visibility is a persisted ledger fact (§27.2); zoom is runtime-only.
        state.setProjectHidden(ids.1, true)
        state.zoomedProject = ids.0

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(decoded.version == WorkspaceState.currentVersion)
        #expect(Set(decoded.projects.keys) == Set(state.projects.keys))
        #expect(decoded.projectOrder == state.projectOrder)
        // The hidden project comes back hidden, and the arrangement is
        // re-derived from the ledger: only the visible row holds a leaf.
        #expect(decoded.hiddenProjectIDs == [ids.1])
        #expect(decoded.canonicalProjectTree.map(\.id) == [ids.0])
        #expect(decoded.focusedProject == ids.0)

        // Runtime-only state cleared on decode.
        #expect(decoded.zoomedProject == nil)
    }

    @Test func projectsEncodeAsKeyedObjectWithUUIDStringKeys() throws {
        let (state, ids) = try Self.makeTwoProjectState()
        let data = try JSONEncoder().encode(state)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let projects = try #require(object?["projects"] as? [String: Any])

        #expect(projects[ids.0.rawValue.uuidString] != nil)
        #expect(projects[ids.1.rawValue.uuidString] != nil)
        #expect(projects.count == 2)
    }

    @Test func decodesLegacyGroupVocabularyKeys() throws {
        // Workspaces saved before the project rename used "group" key
        // spellings; they must keep decoding so no persisted state is lost.
        let (state, ids) = try Self.makeTwoProjectState()
        let data = try JSONEncoder().encode(state)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["canonicalGroupTree"] = object.removeValue(forKey: "canonicalProjectTree")
        object["groups"] = object.removeValue(forKey: "projects")
        object["focusedGroup"] = object.removeValue(forKey: "focusedProject")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: legacyData)
        #expect(Set(decoded.projects.keys) == Set(state.projects.keys))
        #expect(decoded.canonicalProjectTree.structuralIdentity == state.canonicalProjectTree.structuralIdentity)
        #expect(decoded.focusedProject == ids.0)
    }

    // MARK: restoring (SPEC §12.3)

    @Test func restoringKeepsHiddenRowsAndClearsZoom() throws {
        var (state, ids) = try Self.makeTwoProjectState()
        state.setProjectHidden(ids.1, true)
        state.zoomedProject = ids.0

        let restored = WorkspaceState.restoring(state)

        // Visibility is a persisted ledger fact (§27.2): the hidden row stays
        // hidden. Zoom is runtime-only and cleared.
        #expect(restored.hiddenProjectIDs == [ids.1])
        #expect(restored.zoomedProject == nil)
        // Projects and the ledger are preserved; the arrangement re-derives
        // over the visible rows only.
        #expect(Set(restored.projects.keys) == Set(state.projects.keys))
        #expect(restored.projectOrder == state.projectOrder)
        #expect(restored.canonicalProjectTree.map(\.id) == [ids.0])
    }

    @Test func restoringKeepsValidFocusedProject() throws {
        let (state, ids) = try Self.makeTwoProjectState()
        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedProject == ids.0)
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusedProjectUnknown() throws {
        var (state, _) = try Self.makeTwoProjectState()
        // A focused project that no longer exists falls back to the canonical
        // tree's first leaf (§12.3).
        state.focusedProject = ProjectID()

        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedProject != nil)
        #expect(restored.focusedProject == state.canonicalProjectTree.firstLeaf?.id)
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusedProjectNil() throws {
        var (state, _) = try Self.makeTwoProjectState()
        state.focusedProject = nil

        let restored = WorkspaceState.restoring(state)
        #expect(restored.focusedProject == state.canonicalProjectTree.firstLeaf?.id)
    }

    // MARK: Ledger repair (SPEC §12.3, §27.1)

    /// Hides `id` through the ledger: the row keeps its position, only its
    /// visibility flips, and the projection re-derives without it.
    private static func hiding(_ id: ProjectID, in state: WorkspaceState) -> WorkspaceState {
        var next = state
        next.setProjectHidden(id, true)
        return next
    }

    @Test func restoringAppendsProjectsMissingFromTheRowOrder() throws {
        // A corrupt/legacy save can carry a project that the row order does
        // not name: `normalizeLedger` appends it (creation order) so nothing
        // leaks, and it comes back visible when there is room.
        let (base, ids) = try Self.makeTwoProjectState()
        var state = base
        state.projectOrder = [ids.0]

        let restored = WorkspaceState.restoring(state)

        #expect(restored.projectOrder == [ids.0, ids.1])
        #expect(restored.hiddenProjectIDs.isEmpty)
        #expect(restored.canonicalProjectTree.map(\.id) == [ids.0, ids.1])
        #expect(Set(restored.projects.keys) == Set([ids.0, ids.1]))
    }

    @Test func restoringMovesFocusOffAHiddenRow() throws {
        // The focused project was hidden at save time: visibility persists, so
        // focus falls back to the first visible row (§14.6: the focused
        // project is always visible).
        let (base, ids) = try Self.makeTwoProjectState()
        var state = Self.hiding(ids.1, in: base)
        state.focusedProject = ids.1

        let restored = WorkspaceState.restoring(state)

        #expect(restored.hiddenProjectIDs == [ids.1])
        #expect(restored.focusedProject == ids.0)
    }

    @Test func restoringLeavesAConsistentTreeUntouched() throws {
        let (state, _) = try Self.makeTwoProjectState()
        let restored = WorkspaceState.restoring(state)
        #expect(restored.canonicalProjectTree.structuralIdentity == state.canonicalProjectTree.structuralIdentity)
    }

    @Test func decodingKeepsHiddenRowsHiddenAtTheirPositions() throws {
        let (base, ids) = try Self.makeTwoProjectState()
        let state = Self.hiding(ids.1, in: base)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        // Both projects persist; the hidden one keeps its ledger row and its
        // hidden state, and the projection re-derives without it.
        #expect(Set(decoded.projects.keys) == Set([ids.0, ids.1]))
        #expect(decoded.projectOrder == state.projectOrder)
        #expect(decoded.hiddenProjectIDs == [ids.1])
        #expect(decoded.canonicalProjectTree.map(\.id) == [ids.0])
    }

    // MARK: Project numbering (SPEC §4.1)

    @Test func ordinalsNumberVisibleProjectsInTraversalOrder() throws {
        let (state, ids) = try Self.makeTwoProjectState()

        #expect(state.visibleProjectIDs == [ids.0, ids.1])
        #expect(state.visibleProjectCount == 2)
        #expect(state.ordinal(of: ids.0) == 1)
        #expect(state.ordinal(of: ids.1) == 2)
        #expect(state.visibleProjectID(ordinal: 1) == ids.0)
        #expect(state.visibleProjectID(ordinal: 3) == nil)
        #expect(state.ordinal(of: ProjectID()) == nil)
    }

    // MARK: Restore cap (max 9 visible)

    /// Builds a state with `count` projects in a horizontal row, all visible and
    /// with strictly increasing `createdAt` so orphan reconciliation order is
    /// deterministic. The first project is focused. Returns the ids in traversal
    /// (and creation) order.
    private static func makeRowState(_ count: Int) throws -> (state: WorkspaceState, ids: [ProjectID]) {
        precondition(count >= 1)
        let base = Date(timeIntervalSince1970: 0)

        var ids = [ProjectID()]
        var tree = SplitTree<ProjectRef>(view: ProjectRef(id: ids[0]))
        var projects: [ProjectID: ProjectState] = [
            ids[0]: ProjectState(id: ids[0], name: "g1", paneTree: .init(), createdAt: base),
        ]

        for index in 1..<count {
            let id = ProjectID()
            tree = try tree.inserting(
                view: ProjectRef(id: id),
                at: ProjectRef(id: ids[index - 1]),
                direction: .right)
            projects[id] = ProjectState(
                id: id,
                name: "g\(index + 1)",
                paneTree: .init(),
                createdAt: base.addingTimeInterval(Double(index)))
            ids.append(id)
        }

        let state = WorkspaceState(canonicalProjectTree: tree, projects: projects, focusedProject: ids[0])
        // The ledger caps the visible rows at construction already: rows past
        // the ninth visible one start hidden.
        #expect(state.canonicalProjectTree.map(\.id)
            == Array(ids.prefix(WorkspaceState.maxVisibleProjects)))
        return (state, ids)
    }

    /// The §14.1–3 invariants: every canonical leaf is a known project, every
    /// project is either a leaf or hidden, and hidden projects have no leaf.
    private static func expectInvariants(_ state: WorkspaceState) {
        let leafIDs = Set(state.canonicalProjectTree.map(\.id))
        let projectKeys = Set(state.projects.keys)

        #expect(leafIDs.isSubset(of: projectKeys))
        #expect(state.hiddenProjectIDs.isSubset(of: projectKeys))
        // §14.3: a hidden project must not have a canonical leaf.
        #expect(leafIDs.isDisjoint(with: state.hiddenProjectIDs))
        // §14.2: every project is accounted for as visible or hidden.
        #expect(leafIDs.union(state.hiddenProjectIDs) == projectKeys)
    }

    @Test func restoringLeavesEverythingVisibleUnderTheCap() throws {
        // At most 9 projects: unchanged behaviour, everything comes back visible.
        let (state, ids) = try Self.makeRowState(WorkspaceState.maxVisibleProjects)

        let restored = WorkspaceState.restoring(state)

        #expect(restored.canonicalProjectTree.map(\.id) == ids)
        #expect(restored.hiddenProjectIDs.isEmpty)
        #expect(restored.focusedProject == ids[0])
        Self.expectInvariants(restored)
    }

    @Test func restoringPrunesALegacyTreeWithMoreThanNineLeaves() throws {
        // A save with more than 9 rows visible keeps the first 9 rows visible;
        // the rest are hidden, still alive in `projects`.
        let (state, ids) = try Self.makeRowState(12)

        let restored = WorkspaceState.restoring(state)

        #expect(restored.visibleProjectCount == WorkspaceState.maxVisibleProjects)
        #expect(restored.canonicalProjectTree.map(\.id) == Array(ids.prefix(9)))
        #expect(restored.hiddenProjectIDs == Set(ids.dropFirst(9)))
        #expect(Set(restored.projects.keys) == Set(ids))
        Self.expectInvariants(restored)
    }

    @Test func restoringKeepsHiddenRowsHiddenUnderTheCap() throws {
        // 12 projects of which 8 were hidden at save time (rows 5..12, of
        // which 10..12 started hidden by the cap): visibility is a persisted
        // ledger fact, so exactly the 4 visible rows come back visible — no
        // re-attachment happens.
        let (base, ids) = try Self.makeRowState(12)
        var state = base
        for id in ids.dropFirst(4) {
            state = Self.hiding(id, in: state)
        }
        #expect(state.canonicalProjectTree.map(\.id) == Array(ids.prefix(4)))

        let restored = WorkspaceState.restoring(state)

        #expect(restored.visibleProjectCount == 4)
        #expect(restored.canonicalProjectTree.map(\.id) == Array(ids.prefix(4)))
        #expect(restored.hiddenProjectIDs == Set(ids.dropFirst(4)))
        #expect(Set(restored.projects.keys) == Set(ids))
        Self.expectInvariants(restored)
    }

    @Test func restoringNumbersTheCappedVisibleProjectsOneThroughNine() throws {
        let (state, ids) = try Self.makeRowState(12)
        let restored = WorkspaceState.restoring(state)

        #expect(ids.prefix(9).compactMap { restored.ordinal(of: $0) } == Array(1...9))
        // The overflow projects are hidden, so they have no number.
        #expect(ids.dropFirst(9).allSatisfy { restored.ordinal(of: $0) == nil })
    }

    @Test func restoringFallsBackToFirstLeafWhenFocusIsCappedOut() throws {
        // The saved focused project is beyond the cap, so it comes back hidden and
        // focus falls back to the canonical tree's first leaf (§14.6: the focused
        // project is always visible).
        let (base, ids) = try Self.makeRowState(12)
        var state = base
        state.focusedProject = ids[11]

        let restored = WorkspaceState.restoring(state)

        #expect(restored.hiddenProjectIDs.contains(ids[11]))
        #expect(restored.focusedProject == ids[0])
        let focused = try #require(restored.focusedProject)
        #expect(restored.canonicalProjectTree.find(id: focused) != nil)
        Self.expectInvariants(restored)
    }

    @Test func restoringIsIdempotent() throws {
        // Decode already applies the restore layout, and `restoring(_:)` runs it
        // again on top: the second pass must not move anything.
        let (state, ids) = try Self.makeRowState(12)
        let once = WorkspaceState.restoring(state)
        let twice = WorkspaceState.restoring(once)

        #expect(twice.canonicalProjectTree.map(\.id) == once.canonicalProjectTree.map(\.id))
        #expect(twice.hiddenProjectIDs == once.hiddenProjectIDs)
        #expect(twice.focusedProject == once.focusedProject)
        #expect(Set(twice.projects.keys) == Set(ids))
    }

    @Test func decodingCapsVisibleProjectsAtNine() throws {
        let (state, ids) = try Self.makeRowState(12)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(Set(decoded.projects.keys) == Set(ids))
        #expect(decoded.visibleProjectCount == WorkspaceState.maxVisibleProjects)
        #expect(decoded.canonicalProjectTree.map(\.id) == Array(ids.prefix(9)))
        #expect(decoded.hiddenProjectIDs == Set(ids.dropFirst(9)))
        Self.expectInvariants(decoded)
    }
}
