import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real priority/deadline judgment logic (SPEC §24) with real leaves in
/// the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the priority/deadline model layer (SPEC §24): unset defaults,
/// persistence, the invalid-to-unset deadline boundary, the overdue judgment,
/// and the stable visible-only sort orderings.
struct ProjectPriorityDeadlineTests {
    private static func makeProject(name: String) -> TestProjectState {
        TestProjectState(
            id: ProjectID(), name: name, paneTree: .init(view: TestPane()), createdAt: Date())
    }

    /// A model whose visible projects are `visible`, in exactly that layout
    /// order, plus `hidden` projects on the shelf (no canonical leaf,
    /// SPEC §11.7).
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

    private static func deadline(_ year: Int, _ month: Int, _ day: Int) -> ProjectDeadline {
        ProjectDeadline(year: year, month: month, day: day)!
    }

    // MARK: Defaults (SPEC §24.1)

    @Test func newProjectDefaultsToUnsetPriorityAndDeadline() {
        let project = Self.makeProject(name: "fresh")
        #expect(project.priority == nil)
        #expect(project.deadline == nil)
    }

    // MARK: Persistence (SPEC §24.1)

    @Test func priorityAndDeadlineRoundTripThroughSaveRestore() throws {
        let projectA = Self.makeProject(name: "alpha")
        let projectB = Self.makeProject(name: "beta")
        let model = try Self.makeModel(visible: [projectA, projectB])

        model.setProjectPriority(projectA.id, to: .high)
        #expect(model.setProjectDeadline(projectA.id, parsing: "2026-12-31"))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        let restoredA = try #require(decoded.projects[projectA.id])
        #expect(restoredA.priority == .high)
        #expect(restoredA.deadline == Self.deadline(2026, 12, 31))
        let restoredB = try #require(decoded.projects[projectB.id])
        #expect(restoredB.priority == nil)
        #expect(restoredB.deadline == nil)
    }

    @Test func corruptStoredPriorityAndDeadlineDecodeAsUnset() throws {
        // The invalid-to-unset rule holds on the restore path too: a save
        // carrying an unknown priority value or an impossible date comes back
        // unset instead of rejecting the whole project record.
        var project = Self.makeProject(name: "alpha")
        project.priority = .high
        project.deadline = Self.deadline(2026, 12, 31)

        let json = String(decoding: try JSONEncoder().encode(project), as: UTF8.self)
            .replacingOccurrences(of: "\"high\"", with: "\"urgent\"")
            .replacingOccurrences(of: "2026-12-31", with: "2026-02-30")
        let decoded = try JSONDecoder().decode(TestProjectState.self, from: Data(json.utf8))

        #expect(decoded.priority == nil)
        #expect(decoded.deadline == nil)
        #expect(decoded.name == "alpha")
    }

    // MARK: Deadline input boundary (SPEC §24.1)

    @Test func invalidDeadlineInputIsRejectedToUnset() throws {
        let project = Self.makeProject(name: "alpha")
        let model = try Self.makeModel(visible: [project])
        #expect(model.setProjectDeadline(project.id, parsing: "2026-08-15"))
        #expect(model.projectDeadline(of: project.id) == Self.deadline(2026, 8, 15))

        // An impossible date is rejected — and the stored value is unset, not
        // the previous deadline.
        #expect(!model.setProjectDeadline(project.id, parsing: "2026-02-30"))
        #expect(model.projectDeadline(of: project.id) == nil)
    }

    @Test func emptyDeadlineInputClearsDeliberately() throws {
        let project = Self.makeProject(name: "alpha")
        let model = try Self.makeModel(visible: [project])
        model.setProjectDeadline(project.id, to: Self.deadline(2026, 8, 15))

        // Empty input is a deliberate clear, not a rejection.
        #expect(model.setProjectDeadline(project.id, parsing: "  "))
        #expect(model.projectDeadline(of: project.id) == nil)
    }

    @Test func deadlineParserAcceptsOnlyRealDates() {
        #expect(ProjectDeadline(parsing: "2026-08-15") == Self.deadline(2026, 8, 15))
        #expect(ProjectDeadline(parsing: "2026/8/5") == Self.deadline(2026, 8, 5))
        #expect(ProjectDeadline(parsing: " 2026-01-01 ") == Self.deadline(2026, 1, 1))
        #expect(ProjectDeadline(parsing: "2024-02-29") == Self.deadline(2024, 2, 29))

        #expect(ProjectDeadline(parsing: "2023-02-29") == nil)
        #expect(ProjectDeadline(parsing: "2026-13-01") == nil)
        #expect(ProjectDeadline(parsing: "2026-00-10") == nil)
        #expect(ProjectDeadline(parsing: "26-01-01") == nil)
        #expect(ProjectDeadline(parsing: "2026-01") == nil)
        #expect(ProjectDeadline(parsing: "2026-01-01-01") == nil)
        #expect(ProjectDeadline(parsing: "not-a-date") == nil)
        #expect(ProjectDeadline(parsing: "") == nil)
    }

    @Test func todayDerivationMatchesCalendarComponents() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 10
        components.hour = 23
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(calendar.date(from: components))

        // The time of day never leaks into the date-only value.
        #expect(ProjectDeadline(from: date, calendar: calendar) == Self.deadline(2026, 8, 10))
    }

    // MARK: Overdue judgment (SPEC §24.2)

    @Test func overdueIsStrictlyPastTheDeadlineDay() throws {
        let past = Self.makeProject(name: "past")
        let today = Self.makeProject(name: "today")
        let future = Self.makeProject(name: "future")
        let unset = Self.makeProject(name: "unset")
        let hiddenPast = Self.makeProject(name: "hidden-past")
        let model = try Self.makeModel(
            visible: [past, today, future, unset], hidden: [hiddenPast])

        let now = Self.deadline(2026, 8, 10)
        model.setProjectDeadline(past.id, to: Self.deadline(2026, 8, 9))
        model.setProjectDeadline(today.id, to: now)
        model.setProjectDeadline(future.id, to: Self.deadline(2026, 8, 11))
        model.setProjectDeadline(hiddenPast.id, to: Self.deadline(2025, 12, 31))

        #expect(model.isProjectOverdue(past.id, today: now))
        #expect(!model.isProjectOverdue(today.id, today: now))
        #expect(!model.isProjectOverdue(future.id, today: now))
        #expect(!model.isProjectOverdue(unset.id, today: now))
        // The judgment covers hidden projects too: overdue-ness survives hiding;
        // the display layers are already visibility-scoped.
        #expect(model.overdueProjectIDs(today: now) == [past.id, hiddenPast.id])
    }

    // MARK: Sort orderings (SPEC §24.3)

    @Test func prioritySortOrdersHighMediumLowUnsetWithStableTies() throws {
        let unset1 = Self.makeProject(name: "unset-1")
        let low = Self.makeProject(name: "low")
        let medium1 = Self.makeProject(name: "medium-1")
        let high = Self.makeProject(name: "high")
        let medium2 = Self.makeProject(name: "medium-2")
        let model = try Self.makeModel(visible: [unset1, low, medium1, high, medium2])

        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(medium1.id, to: .medium)
        model.setProjectPriority(high.id, to: .high)
        model.setProjectPriority(medium2.id, to: .medium)

        // high → medium → low → unset; the two mediums keep their current
        // relative order (medium1 before medium2).
        #expect(model.priorityOrderedProjectIDs()
                == [high.id, medium1.id, medium2.id, low.id, unset1.id])
    }

    @Test func deadlineSortOrdersNearestFirstUnsetLastWithStableTies() throws {
        let unset = Self.makeProject(name: "unset")
        let december = Self.makeProject(name: "december")
        let september1 = Self.makeProject(name: "september-1")
        let september2 = Self.makeProject(name: "september-2")
        let august = Self.makeProject(name: "august")
        let model = try Self.makeModel(
            visible: [unset, december, september1, september2, august])

        model.setProjectDeadline(december.id, to: Self.deadline(2026, 12, 1))
        model.setProjectDeadline(september1.id, to: Self.deadline(2026, 9, 1))
        model.setProjectDeadline(september2.id, to: Self.deadline(2026, 9, 1))
        model.setProjectDeadline(august.id, to: Self.deadline(2026, 8, 20))

        // Nearest first, unset last; the two same-day projects keep their
        // current relative order (september1 before september2).
        #expect(model.deadlineOrderedProjectIDs()
                == [august.id, september1.id, september2.id, december.id, unset.id])
    }

    @Test func sortOrderingsCoverAllRowsAndMutateNothing() throws {
        let visibleLow = Self.makeProject(name: "visible-low")
        let visibleHigh = Self.makeProject(name: "visible-high")
        let hiddenHigh = Self.makeProject(name: "hidden-high")
        let model = try Self.makeModel(
            visible: [visibleLow, visibleHigh], hidden: [hiddenHigh])

        model.setProjectPriority(visibleLow.id, to: .low)
        model.setProjectPriority(visibleHigh.id, to: .high)
        model.setProjectPriority(hiddenHigh.id, to: .high)
        model.setProjectDeadline(hiddenHigh.id, to: Self.deadline(2026, 1, 1))
        let orderBefore = model.state.projectOrder

        // The orderings cover every row — hidden ones included (SPEC §24.3) —
        // and are pure judgments: the ledger and the hidden set are untouched.
        #expect(model.priorityOrderedProjectIDs()
                == [visibleHigh.id, hiddenHigh.id, visibleLow.id])
        #expect(model.deadlineOrderedProjectIDs()
                == [hiddenHigh.id, visibleLow.id, visibleHigh.id])
        #expect(model.state.projectOrder == orderBefore)
        #expect(model.state.hiddenProjectIDs == [hiddenHigh.id])
        #expect(model.projectPriority(of: hiddenHigh.id) == .high)
    }

    // MARK: Sort state application (SPEC §24.4–24.5)

    @Test func prioritySortStateReordersTheRealLayout() throws {
        let unset = Self.makeProject(name: "unset")
        let low = Self.makeProject(name: "low")
        let medium1 = Self.makeProject(name: "medium-1")
        let high = Self.makeProject(name: "high")
        let medium2 = Self.makeProject(name: "medium-2")
        let model = try Self.makeModel(visible: [unset, low, medium1, high, medium2])

        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(medium1.id, to: .medium)
        model.setProjectPriority(high.id, to: .high)
        model.setProjectPriority(medium2.id, to: .medium)

        // Selecting the priority state applies its ordering to the real
        // layout — including the stable tie (medium1 stays before medium2
        // through the actual reorder), and the ordinals (Cmd+1–9) follow the
        // new traversal order.
        #expect(model.setProjectSortState(.priority))
        #expect(model.projectSortState == .priority)
        #expect(model.state.visibleProjectIDs
                == [high.id, medium1.id, medium2.id, low.id, unset.id])
        #expect(model.state.ordinal(of: high.id) == 1)
        #expect(model.state.visibleProjectID(ordinal: 5) == unset.id)
    }

    @Test func deadlineSortStateReordersTheRealLayout() throws {
        let unset = Self.makeProject(name: "unset")
        let december = Self.makeProject(name: "december")
        let september1 = Self.makeProject(name: "september-1")
        let september2 = Self.makeProject(name: "september-2")
        let august = Self.makeProject(name: "august")
        let model = try Self.makeModel(
            visible: [unset, december, september1, september2, august])

        model.setProjectDeadline(december.id, to: Self.deadline(2026, 12, 1))
        model.setProjectDeadline(september1.id, to: Self.deadline(2026, 9, 1))
        model.setProjectDeadline(september2.id, to: Self.deadline(2026, 9, 1))
        model.setProjectDeadline(august.id, to: Self.deadline(2026, 8, 20))

        // Nearest first, unset last, the same-day tie stable through the
        // actual reorder.
        #expect(model.setProjectSortState(.deadline))
        #expect(model.state.visibleProjectIDs
                == [august.id, september1.id, september2.id, december.id, unset.id])
        #expect(model.state.ordinal(of: august.id) == 1)
    }

    @Test func sortStateLeavesHiddenSetAndFocusUntouched() throws {
        let low = Self.makeProject(name: "low")
        let high = Self.makeProject(name: "high")
        let hiddenHigh = Self.makeProject(name: "hidden-high")
        let model = try Self.makeModel(visible: [low, high], hidden: [hiddenHigh])

        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(high.id, to: .high)
        model.setProjectPriority(hiddenHigh.id, to: .high)

        // The sort reorders rows, never visibility: the hidden project stays
        // hidden (gaining no canonical leaf), and focus is id-keyed so it
        // stays on the same project in its new slot.
        let focusedBefore = model.state.focusedProject
        #expect(model.setProjectSortState(.priority))
        #expect(model.state.visibleProjectIDs == [high.id, low.id])
        #expect(model.state.hiddenProjectIDs == [hiddenHigh.id])
        #expect(model.state.focusedProject == focusedBefore)
    }

    @Test func sortStateWorksWhileTheProjectListIsOpen() throws {
        let low = Self.makeProject(name: "low")
        let high = Self.makeProject(name: "high")
        let model = try Self.makeModel(visible: [low, high])
        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(high.id, to: .high)
        model.beginProjectList()

        // The sort state governs the order with or without the list open.
        // The list session stays up and re-renders the reordered rows live.
        #expect(model.setProjectSortState(.priority))
        #expect(model.state.visibleProjectIDs == [high.id, low.id])
        #expect(model.projectListActive)
        #expect(model.projectListRows.map(\.id) == [high.id, low.id])
    }

    @Test func postSortOrdinalsCountVisibleRowsSkippingHidden() throws {
        let visibleLow = Self.makeProject(name: "visible-low")
        let visibleMedium = Self.makeProject(name: "visible-medium")
        let hiddenHigh = Self.makeProject(name: "hidden-high")
        let model = try Self.makeModel(
            visible: [visibleLow, visibleMedium], hidden: [hiddenHigh])
        model.setProjectPriority(visibleLow.id, to: .low)
        model.setProjectPriority(visibleMedium.id, to: .medium)
        model.setProjectPriority(hiddenHigh.id, to: .high)

        #expect(model.setProjectSortState(.priority))

        // The hidden row sorts to the top of the ledger, but the ordinals
        // (Cmd+1–9) are the *visible* rows counted from the top, skipping it
        // (SPEC §24.4): the first visible row is ordinal 1.
        #expect(model.state.projectOrder
                == [hiddenHigh.id, visibleMedium.id, visibleLow.id])
        #expect(model.state.visibleProjectIDs == [visibleMedium.id, visibleLow.id])
        #expect(model.state.ordinal(of: visibleMedium.id) == 1)
        #expect(model.state.ordinal(of: visibleLow.id) == 2)
        #expect(model.state.ordinal(of: hiddenHigh.id) == nil)
        #expect(model.state.visibleProjectID(ordinal: 1) == visibleMedium.id)
        #expect(model.state.visibleProjectID(ordinal: 2) == visibleLow.id)
    }

    // MARK: Editor commit point (SPEC §24.1, §27.2)

    @Test func noteEditingSavesTheNoteOnlyKeepingPriorityAndDeadline() throws {
        // Priority and deadline entry lives in the project list's cells; the
        // note editor's commit touches the note and nothing else.
        let project = Self.makeProject(name: "alpha")
        let model = try Self.makeModel(visible: [project])
        model.setProjectPriority(project.id, to: .medium)
        model.setProjectDeadline(project.id, to: Self.deadline(2026, 8, 15))
        model.beginNoteEditing(project.id)

        model.endNoteEditing(saving: "note only")

        #expect(model.noteEditingProject == nil)
        #expect(model.state.projects[project.id]?.note == "note only")
        #expect(model.projectPriority(of: project.id) == .medium)
        #expect(model.projectDeadline(of: project.id) == Self.deadline(2026, 8, 15))
    }

    @Test func settersOnUnknownProjectAreNoOps() throws {
        let project = Self.makeProject(name: "alpha")
        let model = try Self.makeModel(visible: [project])
        let unknown = ProjectID()

        model.setProjectPriority(unknown, to: .high)
        model.setProjectDeadline(unknown, parsing: "2026-08-15")
        #expect(model.projectPriority(of: unknown) == nil)
        #expect(model.projectDeadline(of: unknown) == nil)
        #expect(model.projectPriority(of: project.id) == nil)
    }
}
