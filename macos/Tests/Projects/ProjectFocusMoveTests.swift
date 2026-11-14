import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the unified keyboard focus moves (must 146, 147, 149):
/// `Opt+Tab` / `Opt+Shift+Tab` cycle (`.next` / `.previous`) and
/// `Cmd+Opt+arrow` moves to the spatial neighbor, over visible projects in the
/// overall view and over the zoomed project's panes while zoomed.
struct ProjectFocusMoveTests {
    private static func makeProject(
        name: String,
        kind: ProjectKind = .core,
        paneTree: SplitTree<TestPane> = .init(view: TestPane())
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: paneTree,
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeProjects(
        _ count: Int,
        kind: (Int) -> ProjectKind = { _ in .core }
    ) -> [TestProjectState] {
        (0..<count).map { makeProject(name: "p\($0)", kind: kind($0)) }
    }

    private static func makeModel(
        _ projects: [TestProjectState],
        hidden: Set<ProjectID> = [],
        focused: ProjectID? = nil,
        layoutType: ProjectLayoutType = .default,
        zoomed: ProjectID? = nil
    ) -> TestWorkspaceModel {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            hiddenProjectIDs: hidden,
            focusedProject: focused ?? projects.first?.id,
            layoutType: layoutType)
        state.relayout()
        state.zoomedProject = zoomed
        return TestWorkspaceModel(state)
    }

    /// Follow `.next` / `.previous` from the focused project `count` times,
    /// switching focus each time, and return the projects visited.
    private static func cycle(
        _ model: TestWorkspaceModel,
        _ direction: XGhostty.SplitFocusDirection,
        times count: Int
    ) throws -> [ProjectID] {
        var visited: [ProjectID] = []
        for _ in 0..<count {
            let target = try #require(model.focusMoveTarget(direction))
            guard case .project(let id) = target else {
                Issue.record("expected a project target, got \(target)")
                return visited
            }
            model.switchFocusedProject(to: id, savingOutgoingPaneTree: .init())
            visited.append(id)
        }
        return visited
    }

    // MARK: Overall view: next / previous

    @Test func nextCyclesVisibleProjectsInOrdinalOrderAndWraps() throws {
        let projects = Self.makeProjects(4)
        let model = Self.makeModel(projects)
        let ids = projects.map(\.id)

        let visited = try Self.cycle(model, .next, times: 4)
        #expect(visited == [ids[1], ids[2], ids[3], ids[0]])
    }

    @Test func previousCyclesBackwardAndWrapsFromTheFirst() throws {
        let projects = Self.makeProjects(4)
        let model = Self.makeModel(projects)
        let ids = projects.map(\.id)

        let visited = try Self.cycle(model, .previous, times: 4)
        #expect(visited == [ids[3], ids[2], ids[1], ids[0]])
    }

    @Test func cyclingFollowsTheOrdinalsCoreBeforeSide() throws {
        // Ledger order p0 (Core), p1 (Side), p2 (Core): the ordinals run
        // p0, p2, p1, so `Opt+Tab` does too.
        let projects = Self.makeProjects(3) { $0 == 1 ? .side : .core }
        let model = Self.makeModel(projects)
        let ids = projects.map(\.id)
        #expect(model.state.visibleProjectIDs == [ids[0], ids[2], ids[1]])

        let visited = try Self.cycle(model, .next, times: 3)
        #expect(visited == [ids[2], ids[1], ids[0]])
        #expect(visited.map { model.state.ordinal(of: $0) } == [2, 3, 1])
    }

    @Test func cyclingSkipsHiddenProjects() throws {
        let projects = Self.makeProjects(4)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, hidden: [ids[1], ids[3]])

        let forward = try Self.cycle(model, .next, times: 2)
        #expect(forward == [ids[2], ids[0]])
        let backward = try Self.cycle(model, .previous, times: 2)
        #expect(backward == [ids[2], ids[0]])
    }

    @Test func cyclingReachesPastTheNinthProject() throws {
        let projects = Self.makeProjects(12)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, focused: ids[8])

        let visited = try Self.cycle(model, .next, times: 4)
        #expect(visited == [ids[9], ids[10], ids[11], ids[0]])
        #expect(model.state.ordinal(of: ids[11]) == 12)
    }

    @Test func aSingleVisibleProjectHasNowhereToCycle() {
        let projects = Self.makeProjects(3)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, hidden: [ids[1], ids[2]])

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.previous) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func noProjectFocusMovesWithoutAFocusedProject() {
        let model = TestWorkspaceModel()
        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.left) == nil)
    }

    // MARK: Overall view: directions

    @Test func aDirectionMovesToTheNeighborInTheWideLayout() {
        // Wide, n=4: p0 p1 on the top row, p2 p3 on the bottom row.
        let projects = Self.makeProjects(4)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, layoutType: .wide)

        #expect(model.focusMoveTarget(.right) == .project(ids[1]))
        #expect(model.focusMoveTarget(.down) == .project(ids[2]))
        #expect(model.focusMoveTarget(.left) == nil)
        #expect(model.focusMoveTarget(.up) == nil)
    }

    @Test func aDirectionMovesToTheNeighborInTheTallLayout() {
        // Tall, n=4: p0 p1 down the left column, p2 p3 down the right one.
        let projects = Self.makeProjects(4)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, layoutType: .tall)

        #expect(model.focusMoveTarget(.right) == .project(ids[2]))
        #expect(model.focusMoveTarget(.down) == .project(ids[1]))
        #expect(model.focusMoveTarget(.left) == nil)
        #expect(model.focusMoveTarget(.up) == nil)
    }

    @Test func aDirectionSkipsHiddenProjects() {
        // p1 hidden: the visible p0 p2 p3 lay out wide as p0 / p2 p3 (n=3,
        // the remainder goes to the later row), so p0 has no right neighbor.
        let projects = Self.makeProjects(4)
        let ids = projects.map(\.id)
        let model = Self.makeModel(projects, hidden: [ids[1]], layoutType: .wide)

        #expect(model.focusMoveTarget(.right) == nil)
        let down = model.focusMoveTarget(.down)
        #expect(down == .project(ids[2]) || down == .project(ids[3]))
    }

    @Test func theOverallViewNeverTargetsAPane() throws {
        // A multi-pane project in the overall view: moves resolve to
        // projects only (inter-pane focus stays a no-op there, must 21).
        let a = TestPane(), b = TestPane()
        let tree = try SplitTree<TestPane>(view: a).inserting(view: b, at: a, direction: .right)
        let multi = Self.makeProject(name: "multi", paneTree: tree)
        let other = Self.makeProject(name: "other")
        let model = Self.makeModel([multi, other])

        #expect(model.focusMoveTarget(.next) == .project(other.id))
        #expect(model.focusMoveTarget(.right) == .project(other.id))
    }

    // MARK: Zoom: panes of the zoomed project

    /// A zoomed project of three panes laid out `a | b` over `c`:
    /// a on the left, b on the right with c below it.
    private static func makeZoomedModel() throws
        -> (model: TestWorkspaceModel, project: ProjectID, panes: [TestPane]) {
        let a = TestPane(), b = TestPane(), c = TestPane()
        var tree = try SplitTree<TestPane>(view: a).inserting(view: b, at: a, direction: .right)
        tree = try tree.inserting(view: c, at: b, direction: .down)
        let zoomed = makeProject(name: "zoomed", paneTree: tree)
        let other = makeProject(name: "other")
        let model = makeModel([zoomed, other], focused: zoomed.id, zoomed: zoomed.id)
        model.setFocusedSurface(SurfaceID(rawValue: a.id))
        return (model, zoomed.id, [a, b, c])
    }

    @Test func zoomedNextCyclesPanesInTreeOrderAndWraps() throws {
        let (model, project, panes) = try Self.makeZoomedModel()
        let order = panes.map { SurfaceID(rawValue: $0.id) }

        var visited: [SurfaceID] = []
        for _ in 0..<3 {
            let target = try #require(model.focusMoveTarget(.next))
            guard case .pane(let id) = target else {
                Issue.record("expected a pane target, got \(target)")
                return
            }
            model.setFocusedSurface(id)
            visited.append(id)
        }
        #expect(visited == [order[1], order[2], order[0]])
        // The zoom target never changes.
        #expect(model.state.zoomedProject == project)
        #expect(model.state.focusedProject == project)
    }

    @Test func zoomedPreviousCyclesPanesBackwardAndWraps() throws {
        let (model, _, panes) = try Self.makeZoomedModel()
        let order = panes.map { SurfaceID(rawValue: $0.id) }

        var visited: [SurfaceID] = []
        for _ in 0..<3 {
            let target = try #require(model.focusMoveTarget(.previous))
            guard case .pane(let id) = target else {
                Issue.record("expected a pane target, got \(target)")
                return
            }
            model.setFocusedSurface(id)
            visited.append(id)
        }
        #expect(visited == [order[2], order[1], order[0]])
    }

    @Test func zoomedCyclingMatchesTheSplitTreeTraversal() throws {
        // The order is the one the abolished `Cmd+]` (`goto_split:next`) used.
        let (model, project, _) = try Self.makeZoomedModel()
        let tree = try #require(model.state.projects[project]?.paneTree)
        let leaves = try #require(tree.root?.leaves())
        let focused = try #require(model.state.projects[project]?.focusedSurface)
        let node = try #require(tree.find(id: focused.rawValue))
        let upstreamNext = try #require(tree.focusTarget(for: .next, from: node))

        #expect(model.focusMoveTarget(.next) == .pane(SurfaceID(rawValue: upstreamNext.id)))
        #expect(leaves.count == 3)
    }

    @Test func zoomedDirectionMovesToTheNeighborPane() throws {
        let (model, _, panes) = try Self.makeZoomedModel()
        let (a, b, c) = (panes[0], panes[1], panes[2])

        #expect(model.focusMoveTarget(.right) == .pane(SurfaceID(rawValue: b.id)))
        #expect(model.focusMoveTarget(.left) == nil)
        #expect(model.focusMoveTarget(.up) == nil)

        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.focusMoveTarget(.down) == .pane(SurfaceID(rawValue: c.id)))
        #expect(model.focusMoveTarget(.left) == .pane(SurfaceID(rawValue: a.id)))
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func aZoomedSinglePaneProjectHasNowhereToMove() {
        let projects = Self.makeProjects(2)
        let model = Self.makeModel(projects, zoomed: projects[0].id)
        let pane = model.state.projects[projects[0].id]?.paneTree.root?.leftmostLeaf()
        model.setFocusedSurface(pane.map { SurfaceID(rawValue: $0.id) })

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.previous) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func zoomOnAnotherProjectMovesNothing() throws {
        // A transient divergence (zoomed != focused): pane operations are off
        // and no project move happens either.
        let (model, project, _) = try Self.makeZoomedModel()
        var state = model.state
        state.focusedProject = state.projectOrder.first { $0 != project }
        let diverged = TestWorkspaceModel(state)

        #expect(diverged.focusMoveTarget(.next) == nil)
        #expect(diverged.focusMoveTarget(.right) == nil)
    }

    // MARK: Overlays

    @Test func theProjectListBlocksFocusMoves() throws {
        let projects = Self.makeProjects(3)
        let model = Self.makeModel(projects)
        model.beginProjectList()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.previous) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func theNoteEditorBlocksFocusMoves() {
        let projects = Self.makeProjects(3)
        let model = Self.makeModel(projects)
        model.beginNoteEditingFocusedProject()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func theNoteOverviewBlocksFocusMoves() {
        let projects = Self.makeProjects(3)
        let model = Self.makeModel(projects)
        _ = model.toggleNoteOverview()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func theShortcutListBlocksFocusMoves() {
        let projects = Self.makeProjects(3)
        let model = Self.makeModel(projects)
        model.toggleShortcutList()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func theLayoutSelectionBlocksFocusMoves() {
        let projects = Self.makeProjects(3)
        let model = Self.makeModel(projects)
        model.beginLayoutSelection()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }

    @Test func overlaysBlockZoomedPaneMovesToo() throws {
        let (model, _, _) = try Self.makeZoomedModel()
        model.toggleShortcutList()

        #expect(model.focusMoveTarget(.next) == nil)
        #expect(model.focusMoveTarget(.right) == nil)
    }
}
