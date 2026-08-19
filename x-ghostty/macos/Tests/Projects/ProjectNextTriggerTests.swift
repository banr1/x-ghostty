import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real next-trigger judgment logic (SPEC §24.6) with real leaves.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the next trigger (SPEC §24.6, success condition 24's model
/// half): the four-valued who-moves-this-next field — unset by default,
/// persisted and restored like the priority, shown by the note overview's
/// content, untouched by the daily priority reset, and migrating the
/// abolished "team member" value to "external" on load.
struct ProjectNextTriggerTests {
    private static func makeProject(
        name: String,
        note: String = "",
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        nextTrigger: ProjectNextTrigger? = nil
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: note,
            priority: priority,
            deadline: deadline,
            nextTrigger: nextTrigger,
            createdAt: Date())
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

    // MARK: Default & mutation (SPEC §24.6)

    @Test func nextTriggerDefaultsToUnset() throws {
        let project = Self.makeProject(name: "fresh")
        #expect(project.nextTrigger == nil)

        let model = try Self.makeModel(visible: [project])
        #expect(model.projectNextTrigger(of: project.id) == nil)
    }

    @Test func setNextTriggerStoresAndClearsThroughTheModel() throws {
        let project = Self.makeProject(name: "alpha")
        let model = try Self.makeModel(visible: [project])

        model.setProjectNextTrigger(project.id, to: .externalPerson)
        #expect(model.projectNextTrigger(of: project.id) == .externalPerson)

        model.setProjectNextTrigger(project.id, to: nil)
        #expect(model.projectNextTrigger(of: project.id) == nil)

        // Unknown projects are a no-op, mirroring the priority setter.
        model.setProjectNextTrigger(ProjectID(), to: .event)
        #expect(model.state.projects.count == 1)
    }

    // MARK: Persistence (SPEC §24.6 — same record as the priority)

    @Test func nextTriggerSurvivesASaveAndRestoreForEveryValue() throws {
        for value in ProjectNextTrigger.allCases {
            let project = Self.makeProject(name: "p", nextTrigger: value)
            let model = try Self.makeModel(visible: [project])

            let data = try JSONEncoder().encode(model.state)
            let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

            #expect(decoded.projects[project.id]?.nextTrigger == value)
        }
    }

    @Test func aSaveWithoutTheKeyOrWithAnUnknownValueDecodesAsUnset() throws {
        // Pre-next-trigger saves carry no key at all.
        let bare = Self.makeProject(name: "bare")
        let bareData = try JSONEncoder().encode(bare)
        let bareObject = try #require(
            try JSONSerialization.jsonObject(with: bareData) as? [String: Any])
        #expect(bareObject["nextTrigger"] == nil)
        #expect(try JSONDecoder().decode(TestProjectState.self, from: bareData).nextTrigger == nil)

        // A save carrying an unknown value follows the invalid-to-unset rule
        // instead of rejecting the whole project record.
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(
                    Self.makeProject(name: "odd", nextTrigger: .event))) as? [String: Any])
        object["nextTrigger"] = "committee"
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TestProjectState.self, from: corrupted)
        #expect(decoded.nextTrigger == nil)
        #expect(decoded.name == "odd")
    }

    @Test func nextTriggerIsFourValuedAndASavedTeamMemberMigratesToExternal() throws {
        // Success condition 20: the value set is exactly self / external /
        // event (unset is the optional's absence)...
        #expect(ProjectNextTrigger.allCases == [.myself, .externalPerson, .event])

        // ...and a save written before "team member" was abolished migrates
        // to "external" on load instead of falling back to unset.
        var object = try #require(
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(
                    Self.makeProject(name: "legacy", nextTrigger: .event))) as? [String: Any])
        object["nextTrigger"] = "teamMember"
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TestProjectState.self, from: legacy)
        #expect(decoded.nextTrigger == .externalPerson)
        #expect(decoded.name == "legacy")
    }

    // MARK: Overview content (SPEC §21.3, §24 — success condition 24)

    @Test func overviewContentIncludesTheNextTrigger() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 9, day: 1))
        let project = Self.makeProject(
            name: "alpha", note: "ship it",
            priority: .high, deadline: deadline, nextTrigger: .externalPerson)

        // The overview's display content is one model judgment: the note
        // together with priority, deadline, and next trigger.
        #expect(project.overviewContent == ProjectOverviewContent(
            note: "ship it",
            priority: .high,
            deadline: deadline,
            nextTrigger: .externalPerson))

        // Unset stays unset in the content — the panel then shows nothing
        // for it.
        #expect(Self.makeProject(name: "plain").overviewContent
                == ProjectOverviewContent(
                    note: "", priority: nil, deadline: nil, nextTrigger: nil))
    }

    // MARK: The daily reset never touches it (SPEC §28.2)

    @Test func dailyPriorityResetLeavesNextTriggersUntouched() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 15; components.hour = 21
        let evening = try #require(calendar.date(from: components))
        components.day = 16; components.hour = 7
        let nextMorning = try #require(calendar.date(from: components))

        let visible = Self.makeProject(
            name: "a", priority: .high, nextTrigger: .myself)
        let hidden = Self.makeProject(
            name: "h", priority: .medium, nextTrigger: .event)
        let model = try Self.makeModel(
            visible: [visible], hidden: [hidden],
            lastReset: Workday(containing: evening, calendar: calendar))

        #expect(model.applyDailyPriorityReset(now: nextMorning, calendar: calendar) == true)

        // Priorities are gone; the next triggers survive, hidden included.
        #expect(model.state.projects.values.allSatisfy { $0.priority == nil })
        #expect(model.state.projects[visible.id]?.nextTrigger == .myself)
        #expect(model.state.projects[hidden.id]?.nextTrigger == .event)
    }
}
