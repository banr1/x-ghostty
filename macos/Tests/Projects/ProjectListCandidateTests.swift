import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real candidate-menu judgment logic (SPEC §27.6) with real leaves.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the value-candidate menus (SPEC §27.6): the priority and
/// next-trigger menus enumerating every real value and never unset, the
/// deadline menu's 10 date candidates with the month-end clamp, the menu's
/// selection movement, and a selection committing through the model.
struct ProjectListCandidateTests {
    private static func makeProject(
        name: String,
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        nextTrigger: ProjectNextTrigger? = nil
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: "",
            priority: priority,
            deadline: deadline,
            nextTrigger: nextTrigger,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeListModel(_ projects: [TestProjectState]) -> TestWorkspaceModel {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            focusedProject: projects.first?.id)
        state.relayout()
        let model = TestWorkspaceModel(state)
        model.beginProjectList()
        return model
    }

    private static func makeRow(_ project: TestProjectState) -> ProjectListRow {
        ProjectListRow(
            id: project.id,
            title: project.name,
            ordinal: 1,
            isHidden: false,
            priority: project.priority,
            deadline: project.deadline,
            nextTrigger: project.nextTrigger,
            note: project.note)
    }

    private static let today = ProjectDeadline(parsing: "2026-08-19")!

    // MARK: Menu content (SPEC §27.6)

    @Test func priorityMenuListsEveryRealValueAndNeverUnset() {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        let menu = ProjectListCandidateMenu.opened(
            on: row, column: .priority, today: Self.today)

        // All three real values, in the fixed high → medium → low order —
        // and nothing standing for "unset" (clearing is Delete's job).
        #expect(menu?.items == [
            .priority(.high), .priority(.medium), .priority(.low),
        ])
        #expect(menu?.selection == 0)
    }

    @Test func nextTriggerMenuListsEveryRealValueAndNeverUnset() {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        let menu = ProjectListCandidateMenu.opened(
            on: row, column: .nextTrigger, today: Self.today)

        #expect(menu?.items == [
            .nextTrigger(.myself), .nextTrigger(.externalPerson), .nextTrigger(.event),
        ])
    }

    @Test func menusOpenOnlyOnCandidateColumns() {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        for column: ProjectListColumn in [.visibility, .title, .note] {
            #expect(ProjectListCandidateMenu.opened(
                on: row, column: column, today: Self.today) == nil)
        }
        #expect(ProjectListCandidateMenu.opened(
            on: row, column: .deadline, today: Self.today) != nil)
    }

    // MARK: Date candidates (SPEC §27.6)

    @Test func dateCandidatesAreTodayThroughSevenDaysPlusTheMonthEchoes() {
        // The 10 choices from 2026-08-19: today .. +7 days, the same day
        // next month, and the same day in 3 months.
        let dates = ProjectDeadline.dateCandidates(from: Self.today)
        #expect(dates.map(\.displayText) == [
            "2026-08-19", "2026-08-20", "2026-08-21", "2026-08-22",
            "2026-08-23", "2026-08-24", "2026-08-25", "2026-08-26",
            "2026-09-19", "2026-11-19",
        ])

        // Shown as real dates in the Aug 19 spelling.
        #expect(dates.first?.monthDayText == "Aug 19")
        #expect(dates.last?.monthDayText == "Nov 19")
    }

    @Test func nonexistentSameDaysClampToTheMonthEnd() {
        // Jan 31 has no same day next month: Feb clamps to its last day —
        // 28 in a common year, 29 in a leap year — and +3 months lands on
        // Apr 30.
        let jan31 = ProjectDeadline(parsing: "2026-01-31")!
        #expect(jan31.sameDayAddingMonths(1)?.displayText == "2026-02-28")
        #expect(jan31.sameDayAddingMonths(3)?.displayText == "2026-04-30")
        let leapJan31 = ProjectDeadline(parsing: "2028-01-31")!
        #expect(leapJan31.sameDayAddingMonths(1)?.displayText == "2028-02-29")

        // A year boundary rolls over; Dec 31's echoes both exist.
        let dec31 = ProjectDeadline(parsing: "2026-12-31")!
        #expect(dec31.sameDayAddingMonths(1)?.displayText == "2027-01-31")
        #expect(dec31.sameDayAddingMonths(3)?.displayText == "2027-03-31")

        // An existing same day passes through unclamped.
        #expect(Self.today.sameDayAddingMonths(1)?.displayText == "2026-09-19")
    }

    // MARK: Selection movement (SPEC §27.6)

    @Test func selectionMovesWithUpDownAndClampsAtTheEnds() {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        var menu = ProjectListCandidateMenu.opened(
            on: row, column: .priority, today: Self.today)!

        // Up on the first entry is absorbed.
        #expect(menu.moved(by: -1).selection == 0)

        menu = menu.moved(by: 1)
        #expect(menu.selectedValue == .priority(.medium))
        menu = menu.moved(by: 1)
        #expect(menu.selectedValue == .priority(.low))

        // Down on the last entry is absorbed.
        #expect(menu.moved(by: 1).selection == menu.selection)
    }

    // MARK: Selection commits (SPEC §27.6)

    @Test func committingASelectionSetsTheValueThroughTheModel() {
        let project = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([project])

        #expect(model.commitProjectListCandidate(
            .priority(.medium), for: project.id))
        #expect(model.projectPriority(of: project.id) == .medium)

        #expect(model.commitProjectListCandidate(
            .nextTrigger(.event), for: project.id))
        #expect(model.projectNextTrigger(of: project.id) == .event)

        let deadline = ProjectDeadline(parsing: "2026-09-19")!
        #expect(model.commitProjectListCandidate(
            .deadline(deadline), for: project.id))
        #expect(model.projectDeadline(of: project.id) == deadline)
    }

    @Test func commitRequiresTheListSessionAndResortsUnderAnActiveSort() {
        let early = Self.makeProject(name: "early", deadline: ProjectDeadline(parsing: "2026-08-01"))
        let late = Self.makeProject(name: "late")
        let model = Self.makeListModel([late, early])
        model.setProjectSortState(.deadline)
        #expect(model.state.projectOrder == [early.id, late.id])

        // A committed date candidate re-sorts immediately (SPEC §24.4):
        // "late" gains the earlier deadline and moves to the top.
        let sooner = ProjectDeadline(parsing: "2026-07-01")!
        #expect(model.commitProjectListCandidate(.deadline(sooner), for: late.id))
        #expect(model.state.projectOrder == [late.id, early.id])

        // Without the list session up, the commit is refused untouched.
        model.endProjectList()
        #expect(!model.commitProjectListCandidate(.priority(.high), for: late.id))
        #expect(model.projectPriority(of: late.id) == nil)
    }
}
