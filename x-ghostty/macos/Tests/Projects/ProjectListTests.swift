import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise the
/// real project-list judgment logic (SPEC §27) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the project-list model layer (SPEC §27): the row set and its
/// ordering, the row contents, the immediate Space toggle with its
/// at-least-one-visible rule, and Enter's visible-only focus.
struct ProjectListTests {
    private static func makeProject(
        name: String,
        note: String = "",
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        createdAt: Date = Date()
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: note,
            priority: priority,
            deadline: deadline,
            createdAt: createdAt)
    }

    /// A model whose visible projects are `visible`, in exactly that layout
    /// order, plus `hidden` projects with no canonical leaf (SPEC §11.7).
    private static func makeModel(
        visible: [TestProjectState], hidden: [TestProjectState] = []
    ) throws -> TestWorkspaceModel {
        var tree = SplitTree<ProjectRef>(view: ProjectRef(id: visible[0].id))
        for (previous, next) in zip(visible, visible.dropFirst()) {
            tree = try tree.inserting(
                view: ProjectRef(id: next.id), at: ProjectRef(id: previous.id), direction: .right)
        }
        var projects: [ProjectID: TestProjectState] = [:]
        for project in visible + hidden { projects[project.id] = project }
        return TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: tree,
            projects: projects,
            hiddenProjectIDs: Set(hidden.map(\.id)),
            focusedProject: visible[0].id))
    }

    // MARK: Opening the list

    @Test func beginProjectListOverlaysAZoomWithoutReleasingIt() throws {
        // Opened while zoomed, the list sits over the zoom and closing
        // returns to it untouched (SPEC §27.3).
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        var state = try Self.makeModel(visible: [a, b]).state
        state.zoomedProject = b.id
        let model = TestWorkspaceModel(state)
        #expect(model.projectListActive == false)
        #expect(model.projectListRows.isEmpty)

        model.beginProjectList()

        #expect(model.projectListActive == true)
        #expect(model.state.zoomedProject == b.id)
        #expect(model.projectListRows.count == 2)

        model.endProjectList()
        #expect(model.state.zoomedProject == b.id)
    }

    @Test func beginProjectListDeclinesWhileAnotherOverlayOwnsTheKeyboard() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")

        let overview = try Self.makeModel(visible: [a, b])
        #expect(overview.toggleNoteOverview() == true)
        #expect(overview.canBeginProjectList == false)
        overview.beginProjectList()
        #expect(overview.projectListActive == false)

        let editing = try Self.makeModel(visible: [a, b])
        editing.noteEditingProject = a.id
        #expect(editing.canBeginProjectList == false)
        editing.beginProjectList()
        #expect(editing.projectListActive == false)
    }

    @Test func endProjectListKeepsToggledVisibility() throws {
        // Escape closes the list, but the toggles it made were real mutations.
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])
        model.beginProjectList()

        model.toggleProjectListVisibility(b.id, savingOutgoingPaneTree: .init())
        model.endProjectList()

        #expect(model.projectListActive == false)
        #expect(model.state.visibleProjectIDs == [a.id])
        #expect(model.state.isProjectHidden(b.id))
    }

    // MARK: Rows: membership and ordering (SPEC §27.1)

    @Test func rowsCoverEveryProjectWithVisibleInOrdinalOrderThenHidden() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let a = Self.makeProject(name: "a", createdAt: base)
        let b = Self.makeProject(name: "b", createdAt: base.addingTimeInterval(1))
        let c = Self.makeProject(name: "c", createdAt: base.addingTimeInterval(2))
        // Hidden, created out of order: rows must present them by creation.
        let y = Self.makeProject(name: "y", createdAt: base.addingTimeInterval(9))
        let x = Self.makeProject(name: "x", createdAt: base.addingTimeInterval(3))
        let model = try Self.makeModel(visible: [a, b, c], hidden: [y, x])
        model.beginProjectList()

        let rows = model.projectListRows

        #expect(rows.map(\.id) == [a.id, b.id, c.id, x.id, y.id])
        #expect(Set(rows.map(\.id)) == Set(model.state.projects.keys))
        #expect(rows.map(\.ordinal) == [1, 2, 3, nil, nil])
        #expect(rows.map(\.isHidden) == [false, false, false, true, true])
    }

    @Test func rowContentIsTitlePriorityDeadlineAndTheNotesFirstLine() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 8, day: 20))
        let a = Self.makeProject(
            name: "alpha",
            note: "first line\nsecond line\nthird",
            priority: .high,
            deadline: deadline)
        let b = Self.makeProject(name: "beta")
        let model = try Self.makeModel(visible: [a, b])
        model.beginProjectList()

        let rows = model.projectListRows

        #expect(rows[0].title == "alpha")
        #expect(rows[0].priority == .high)
        #expect(rows[0].deadline == deadline)
        #expect(rows[0].noteFirstLine == "first line")
        // Unset fields stay unset so the view renders blanks.
        #expect(rows[1].title == "beta")
        #expect(rows[1].priority == nil)
        #expect(rows[1].deadline == nil)
        #expect(rows[1].noteFirstLine == "")
    }

    @Test func rowsAreEmptyWhileNoSessionIsUp() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])
        #expect(model.projectListRows.isEmpty)
        // The underlying state derivation is always available; only the
        // session-scoped accessor gates on the overlay being up.
        #expect(model.state.projectListRows.count == 2)
    }

    // MARK: Space toggles visibility immediately (SPEC §27.2)

    @Test func spaceTogglesHideAndShowImmediately() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let c = Self.makeProject(name: "c")
        let model = try Self.makeModel(visible: [a, b, c])
        model.beginProjectList()

        model.toggleProjectListVisibility(c.id, savingOutgoingPaneTree: .init())

        #expect(model.state.isProjectHidden(c.id))
        #expect(model.state.visibleProjectIDs == [a.id, b.id])
        #expect(model.projectListRows.map(\.id) == [a.id, b.id, c.id])
        #expect(model.projectListRows.map(\.isHidden) == [false, false, true])
        // The list stays up: there is no confirm step.
        #expect(model.projectListActive == true)

        model.toggleProjectListVisibility(c.id, savingOutgoingPaneTree: .init())

        #expect(model.state.isProjectHidden(c.id) == false)
        #expect(model.state.visibleProjectIDs.contains(c.id))
        #expect(model.projectListRows.allSatisfy { !$0.isHidden })
    }

    @Test func showingFromTheListDoesNotMoveFocus() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let hidden = Self.makeProject(name: "h")
        let model = try Self.makeModel(visible: [a, b], hidden: [hidden])
        model.beginProjectList()

        let moved = model.toggleProjectListVisibility(hidden.id, savingOutgoingPaneTree: .init())

        #expect(moved == nil)
        #expect(model.state.focusedProject == a.id)
        #expect(model.state.isProjectHidden(hidden.id) == false)
    }

    @Test func hidingTheFocusedProjectHandsFocusToTheNearestSurvivor() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])
        #expect(model.state.focusedProject == a.id)
        model.beginProjectList()

        let moved = model.toggleProjectListVisibility(a.id, savingOutgoingPaneTree: .init())

        #expect(moved?.target == b.id)
        #expect(model.state.focusedProject == b.id)
        #expect(model.state.isProjectHidden(a.id))
    }

    @Test func hidingANonFocusedProjectLeavesFocusAlone() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])
        model.beginProjectList()

        let moved = model.toggleProjectListVisibility(b.id, savingOutgoingPaneTree: .init())

        #expect(moved == nil)
        #expect(model.state.focusedProject == a.id)
    }

    // MARK: The at-least-one-visible rule (SPEC §27.2 / §25)

    @Test func hidingTheLastVisibleProjectIsRefused() throws {
        let only = Self.makeProject(name: "only")
        let hidden = Self.makeProject(name: "h")
        let model = try Self.makeModel(visible: [only], hidden: [hidden])
        model.beginProjectList()

        #expect(model.canToggleProjectListVisibility(only.id) == false)
        let moved = model.toggleProjectListVisibility(only.id, savingOutgoingPaneTree: .init())

        #expect(moved == nil)
        #expect(model.state.visibleProjectIDs == [only.id])
        #expect(model.state.isProjectHidden(only.id) == false)
        // A hidden row is still toggleable — the rule only guards the last
        // *visible* project.
        #expect(model.canToggleProjectListVisibility(hidden.id) == true)
    }

    @Test func toggleIsInertWhileNoSessionIsUp() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])

        #expect(model.canToggleProjectListVisibility(b.id) == false)
        model.toggleProjectListVisibility(b.id, savingOutgoingPaneTree: .init())

        #expect(model.state.visibleProjectIDs == [a.id, b.id])
    }

    // MARK: Enter (SPEC §27.3)

    @Test func enterOnAVisibleRowFocusesThatProjectAndClosesTheList() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let model = try Self.makeModel(visible: [a, b])
        model.beginProjectList()
        #expect(model.canFocusProjectListRow(b.id) == true)

        model.focusProjectListRow(b.id, savingOutgoingPaneTree: .init())

        #expect(model.state.focusedProject == b.id)
        #expect(model.projectListActive == false)
    }

    @Test func enterOnAHiddenRowClosesTheListAndFocusesANearbyVisibleProject() throws {
        // A hidden row has no place on screen: the focus request resolves to
        // a nearby visible project and the list closes (SPEC §27.3).
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let hidden = Self.makeProject(name: "h")
        let model = try Self.makeModel(visible: [a, b], hidden: [hidden])
        model.beginProjectList()

        #expect(model.canFocusProjectListRow(hidden.id))
        model.focusProjectListRow(hidden.id, savingOutgoingPaneTree: .init())

        // The ledger order is [a, b, hidden]: the nearest visible row is b.
        #expect(model.state.focusedProject == b.id)
        #expect(model.projectListActive == false)
    }

    @Test func hiddenRowFocusResolvesToTheNearestVisibleRowPreferringAbove() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let hiddenMiddle = Self.makeProject(name: "hm")
        let hiddenEnd = Self.makeProject(name: "he")
        var state = try Self.makeModel(visible: [a, b]).state
        state.insertProject(hiddenMiddle, after: a.id)
        state.setProjectHidden(hiddenMiddle.id, true)
        state.insertProject(hiddenEnd, after: b.id)
        state.setProjectHidden(hiddenEnd.id, true)
        // Ledger order: [a, hm(hidden), b, he(hidden)].

        // A visible row resolves to itself.
        #expect(state.resolvedListFocusTarget(for: a.id) == a.id)
        // Equidistant visible neighbors: the row above wins the tie.
        #expect(state.resolvedListFocusTarget(for: hiddenMiddle.id) == a.id)
        // A trailing hidden row walks up to the nearest visible one.
        #expect(state.resolvedListFocusTarget(for: hiddenEnd.id) == b.id)
        // Unknown rows resolve to nothing.
        #expect(state.resolvedListFocusTarget(for: ProjectID()) == nil)
    }

    @Test func focusWhileZoomedSwitchesTheZoomTargetWithoutReleasing() throws {
        let a = Self.makeProject(name: "a")
        let b = Self.makeProject(name: "b")
        let hidden = Self.makeProject(name: "h")
        var state = try Self.makeModel(visible: [a, b], hidden: [hidden]).state
        state.zoomedProject = a.id
        let model = TestWorkspaceModel(state)
        model.beginProjectList()

        // A visible row: the zoom stays up, its target switches (SPEC §27.3).
        model.focusProjectListRow(b.id, savingOutgoingPaneTree: .init())
        #expect(model.state.zoomedProject == b.id)
        #expect(model.state.focusedProject == b.id)
        #expect(model.projectListActive == false)

        // A hidden row while zoomed: the resolved visible project becomes
        // the zoom target likewise.
        model.beginProjectList()
        model.focusProjectListRow(hidden.id, savingOutgoingPaneTree: .init())
        #expect(model.state.zoomedProject == b.id)
        #expect(model.state.focusedProject == b.id)
    }
}
