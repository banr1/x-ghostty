import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise the
/// real daily-reset judgment logic (SPEC §28) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the daily priority reset (SPEC §28): the local 06:00 workday
/// boundary, the once-per-workday rule, the reset's exact blast radius
/// (priority only, every project including hidden ones), and its persistence.
struct ProjectPriorityResetTests {
    /// A fixed calendar and time zone so the boundary arithmetic under test is
    /// not at the mercy of the machine's locale.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

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

    private static func makeModel(
        visible: [TestProjectState],
        hidden: [TestProjectState] = [],
        lastReset: Workday? = nil
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
            focusedProject: visible[0].id,
            lastPriorityResetWorkday: lastReset))
    }

    // MARK: The workday boundary (SPEC §28.1)

    @Test func theWorkdayRunsFromLocalSixToTheNextSix() throws {
        let calendar = Self.calendar
        // 05:59 still belongs to the previous day's workday; 06:00 starts a new
        // one and holds it until the next 05:59.
        let lateNight = Workday(containing: try Self.date(2026, 8, 16, 5, 59), calendar: calendar)
        let earlyMorning = Workday(containing: try Self.date(2026, 8, 16, 6, 0), calendar: calendar)
        let sameEvening = Workday(containing: try Self.date(2026, 8, 16, 23, 30), calendar: calendar)
        let nextNight = Workday(containing: try Self.date(2026, 8, 17, 3, 0), calendar: calendar)

        #expect(lateNight == Workday(containing: try Self.date(2026, 8, 15, 12), calendar: calendar))
        #expect(earlyMorning != lateNight)
        #expect(sameEvening == earlyMorning)
        #expect(nextNight == earlyMorning)
        #expect(earlyMorning.displayText == "2026-08-16")
        #expect(lateNight.displayText == "2026-08-15")
    }

    @Test func boundaryCrossingIsDecidedFromTheLastResetDateAndNow() throws {
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .high)
        let yesterdayEvening = try Self.date(2026, 8, 15, 21)
        let lastReset = Workday(containing: yesterdayEvening, calendar: calendar)
        let model = try Self.makeModel(visible: [a], lastReset: lastReset)

        // Same workday, later that night: not due.
        #expect(model.state.needsPriorityReset(
            at: try Self.date(2026, 8, 16, 2), calendar: calendar) == false)
        // Past the boundary: due.
        #expect(model.state.needsPriorityReset(
            at: try Self.date(2026, 8, 16, 6, 1), calendar: calendar) == true)
        // A state that never reset is always due.
        let fresh = try Self.makeModel(visible: [a], lastReset: nil)
        #expect(fresh.state.needsPriorityReset(
            at: yesterdayEvening, calendar: calendar) == true)
    }

    // MARK: What the reset touches (SPEC §28.2–28.3)

    @Test func resetClearsEveryProjectsPriorityIncludingHiddenOnes() throws {
        let calendar = Self.calendar
        let deadline = try #require(ProjectDeadline(year: 2026, month: 9, day: 1))
        let a = Self.makeProject(name: "a", note: "keep me", priority: .high, deadline: deadline)
        let b = Self.makeProject(name: "b", priority: .low)
        let hidden = Self.makeProject(name: "h", note: "hidden note", priority: .medium)
        let model = try Self.makeModel(
            visible: [a, b],
            hidden: [hidden],
            lastReset: Workday(containing: try Self.date(2026, 8, 15, 21), calendar: calendar))

        let ran = model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 6, 1), calendar: calendar)

        #expect(ran == true)
        #expect(model.state.projects.values.allSatisfy { $0.priority == nil })
        // Deadlines and notes are untouched.
        #expect(model.state.projects[a.id]?.deadline == deadline)
        #expect(model.state.projects[a.id]?.note == "keep me")
        #expect(model.state.projects[hidden.id]?.note == "hidden note")
        #expect(model.state.isProjectHidden(hidden.id))
    }

    @Test func resetDoesNotReorderProjectsInTheManualState() throws {
        let calendar = Self.calendar
        // Priorities that a priority sort would visibly rearrange.
        let a = Self.makeProject(name: "a", priority: .low)
        let b = Self.makeProject(name: "b", priority: .high)
        let c = Self.makeProject(name: "c", priority: .medium)
        let model = try Self.makeModel(
            visible: [a, b, c],
            lastReset: Workday(containing: try Self.date(2026, 8, 15, 21), calendar: calendar))
        #expect(model.projectSortState == .manual)
        let before = model.state.visibleProjectIDs

        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 7), calendar: calendar) == true)

        #expect(model.state.visibleProjectIDs == before)
        #expect(model.state.visibleProjectIDs == [a.id, b.id, c.id])
    }

    @Test func resetResortsAsAConsequenceOfAnActiveSortState() throws {
        // SPEC §28.3: the reset's effect on the order follows the sort state.
        // Under the priority key the cleared priorities all tie, so the
        // stable re-sort keeps the pre-reset display order — and the order
        // keeps being governed by the state afterwards: the next priority
        // set re-sorts immediately.
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .low)
        let b = Self.makeProject(name: "b", priority: .high)
        let c = Self.makeProject(name: "c", priority: .medium)
        let model = try Self.makeModel(
            visible: [a, b, c],
            lastReset: Workday(containing: try Self.date(2026, 8, 15, 21), calendar: calendar))
        model.setProjectSortState(.priority)
        #expect(model.state.visibleProjectIDs == [b.id, c.id, a.id])

        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 7), calendar: calendar) == true)
        #expect(model.state.projects.values.allSatisfy { $0.priority == nil })
        #expect(model.state.visibleProjectIDs == [b.id, c.id, a.id])

        model.setProjectPriority(a.id, to: .high)
        #expect(model.state.visibleProjectIDs == [a.id, b.id, c.id])
    }

    // MARK: Once per workday (SPEC §28.2)

    @Test func resetRunsOnlyOnceWithinTheSameWorkday() throws {
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .high)
        let model = try Self.makeModel(
            visible: [a],
            lastReset: Workday(containing: try Self.date(2026, 8, 15, 21), calendar: calendar))

        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 6, 1), calendar: calendar) == true)

        // A priority set after the morning reset must survive every later check
        // in the same workday — including one past midnight, which is still the
        // same workday.
        model.setProjectPriority(a.id, to: .high)
        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 12), calendar: calendar) == false)
        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 17, 2), calendar: calendar) == false)
        #expect(model.state.projects[a.id]?.priority == .high)

        // The next boundary clears it again.
        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 17, 6, 30), calendar: calendar) == true)
        #expect(model.state.projects[a.id]?.priority == nil)
    }

    // MARK: Persistence (SPEC §28.2)

    @Test func lastResetWorkdaySurvivesASaveAndRestore() throws {
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .high)
        let model = try Self.makeModel(visible: [a], lastReset: nil)
        #expect(model.applyDailyPriorityReset(
            now: try Self.date(2026, 8, 16, 9), calendar: calendar) == true)
        let stamped = try #require(model.state.lastPriorityResetWorkday)

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        #expect(decoded.lastPriorityResetWorkday == stamped)
        // A relaunch inside the same workday must not reset again.
        #expect(decoded.needsPriorityReset(
            at: try Self.date(2026, 8, 16, 22), calendar: calendar) == false)
        // A relaunch after the next boundary must.
        #expect(decoded.needsPriorityReset(
            at: try Self.date(2026, 8, 17, 8), calendar: calendar) == true)
    }

    @Test func aSaveWithoutTheResetKeyDecodesAsNeverReset() throws {
        // Workspaces written before the reset existed carry no key; the reset
        // then runs once at the next check.
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .high)
        let model = try Self.makeModel(visible: [a], lastReset: nil)

        let data = try JSONEncoder().encode(model.state)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["lastPriorityResetWorkday"] == nil)

        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)
        #expect(decoded.lastPriorityResetWorkday == nil)
        #expect(decoded.needsPriorityReset(
            at: try Self.date(2026, 8, 16, 9), calendar: calendar) == true)
    }

    // MARK: The scheduled boundary (SPEC §28.3)

    @Test func theNextBoundaryIsTheComingLocalSixAM() throws {
        let calendar = Self.calendar

        // Mid-morning: the boundary is tomorrow's 06:00.
        #expect(
            Workday.nextBoundary(after: try Self.date(2026, 8, 16, 9), calendar: calendar)
                == (try Self.date(2026, 8, 17, 6)))

        // Before the boundary: it is today's, still ahead.
        #expect(
            Workday.nextBoundary(after: try Self.date(2026, 8, 16, 3), calendar: calendar)
                == (try Self.date(2026, 8, 16, 6)))

        // Exactly on it: the next one is a day away, so a timer armed at the
        // boundary cannot re-fire immediately in a loop.
        #expect(
            Workday.nextBoundary(after: try Self.date(2026, 8, 16, 6), calendar: calendar)
                == (try Self.date(2026, 8, 17, 6)))
    }

    @Test func aRunningAppCrossingTheBoundaryResetsOnce() throws {
        // What the scheduled check does when it fires: the first call at the
        // boundary resets, later calls in the same workday do not — the timer
        // and the reactivation/wake triggers can therefore overlap freely.
        let calendar = Self.calendar
        let a = Self.makeProject(name: "a", priority: .high)
        let model = try Self.makeModel(
            visible: [a],
            lastReset: Workday(containing: try Self.date(2026, 8, 16, 9), calendar: calendar))

        let boundary = try #require(
            Workday.nextBoundary(after: try Self.date(2026, 8, 16, 9), calendar: calendar))
        #expect(model.applyDailyPriorityReset(now: boundary, calendar: calendar) == true)
        #expect(model.state.projects[a.id]?.priority == nil)
        #expect(model.applyDailyPriorityReset(
            now: boundary.addingTimeInterval(3600), calendar: calendar) == false)
    }
}
