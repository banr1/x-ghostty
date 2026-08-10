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

private typealias TestGroupState = GroupStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the priority/deadline model layer (SPEC §24): unset defaults,
/// persistence, the invalid-to-unset deadline boundary, the overdue judgment,
/// and the stable visible-only sort orderings.
struct GroupPriorityDeadlineTests {
    private static func makeGroup(name: String) -> TestGroupState {
        TestGroupState(
            id: GroupID(), name: name, paneTree: .init(view: TestPane()), createdAt: Date())
    }

    /// A model whose visible groups are `visible`, in exactly that layout
    /// order, plus `hidden` groups on the shelf (no canonical leaf,
    /// SPEC §11.7).
    private static func makeModel(
        visible: [TestGroupState], hidden: [TestGroupState] = []
    ) throws -> TestWorkspaceModel {
        var tree = SplitTree<GroupRef>(view: GroupRef(id: visible[0].id))
        for (previous, next) in zip(visible, visible.dropFirst()) {
            tree = try tree.inserting(
                view: GroupRef(id: next.id), at: GroupRef(id: previous.id), direction: .right)
        }
        var groups: [GroupID: TestGroupState] = [:]
        for group in visible + hidden { groups[group.id] = group }
        return TestWorkspaceModel(TestWorkspaceState(
            canonicalGroupTree: tree,
            groups: groups,
            hiddenGroupIDs: Set(hidden.map(\.id)),
            focusedGroup: visible[0].id))
    }

    private static func deadline(_ year: Int, _ month: Int, _ day: Int) -> GroupDeadline {
        GroupDeadline(year: year, month: month, day: day)!
    }

    // MARK: Defaults (SPEC §24.1)

    @Test func newGroupDefaultsToUnsetPriorityAndDeadline() {
        let group = Self.makeGroup(name: "fresh")
        #expect(group.priority == nil)
        #expect(group.deadline == nil)
    }

    // MARK: Persistence (SPEC §24.1)

    @Test func priorityAndDeadlineRoundTripThroughSaveRestore() throws {
        let groupA = Self.makeGroup(name: "alpha")
        let groupB = Self.makeGroup(name: "beta")
        let model = try Self.makeModel(visible: [groupA, groupB])

        model.setGroupPriority(groupA.id, to: .high)
        #expect(model.setGroupDeadline(groupA.id, parsing: "2026-12-31"))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        let restoredA = try #require(decoded.groups[groupA.id])
        #expect(restoredA.priority == .high)
        #expect(restoredA.deadline == Self.deadline(2026, 12, 31))
        let restoredB = try #require(decoded.groups[groupB.id])
        #expect(restoredB.priority == nil)
        #expect(restoredB.deadline == nil)
    }

    @Test func corruptStoredPriorityAndDeadlineDecodeAsUnset() throws {
        // The invalid-to-unset rule holds on the restore path too: a save
        // carrying an unknown priority value or an impossible date comes back
        // unset instead of rejecting the whole group record.
        var group = Self.makeGroup(name: "alpha")
        group.priority = .high
        group.deadline = Self.deadline(2026, 12, 31)

        let json = String(decoding: try JSONEncoder().encode(group), as: UTF8.self)
            .replacingOccurrences(of: "\"high\"", with: "\"urgent\"")
            .replacingOccurrences(of: "2026-12-31", with: "2026-02-30")
        let decoded = try JSONDecoder().decode(TestGroupState.self, from: Data(json.utf8))

        #expect(decoded.priority == nil)
        #expect(decoded.deadline == nil)
        #expect(decoded.name == "alpha")
    }

    // MARK: Deadline input boundary (SPEC §24.1)

    @Test func invalidDeadlineInputIsRejectedToUnset() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        #expect(model.setGroupDeadline(group.id, parsing: "2026-08-15"))
        #expect(model.groupDeadline(of: group.id) == Self.deadline(2026, 8, 15))

        // An impossible date is rejected — and the stored value is unset, not
        // the previous deadline.
        #expect(!model.setGroupDeadline(group.id, parsing: "2026-02-30"))
        #expect(model.groupDeadline(of: group.id) == nil)
    }

    @Test func emptyDeadlineInputClearsDeliberately() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        model.setGroupDeadline(group.id, to: Self.deadline(2026, 8, 15))

        // Empty input is a deliberate clear, not a rejection.
        #expect(model.setGroupDeadline(group.id, parsing: "  "))
        #expect(model.groupDeadline(of: group.id) == nil)
    }

    @Test func deadlineParserAcceptsOnlyRealDates() {
        #expect(GroupDeadline(parsing: "2026-08-15") == Self.deadline(2026, 8, 15))
        #expect(GroupDeadline(parsing: "2026/8/5") == Self.deadline(2026, 8, 5))
        #expect(GroupDeadline(parsing: " 2026-01-01 ") == Self.deadline(2026, 1, 1))
        #expect(GroupDeadline(parsing: "2024-02-29") == Self.deadline(2024, 2, 29))

        #expect(GroupDeadline(parsing: "2023-02-29") == nil)
        #expect(GroupDeadline(parsing: "2026-13-01") == nil)
        #expect(GroupDeadline(parsing: "2026-00-10") == nil)
        #expect(GroupDeadline(parsing: "26-01-01") == nil)
        #expect(GroupDeadline(parsing: "2026-01") == nil)
        #expect(GroupDeadline(parsing: "2026-01-01-01") == nil)
        #expect(GroupDeadline(parsing: "not-a-date") == nil)
        #expect(GroupDeadline(parsing: "") == nil)
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
        #expect(GroupDeadline(from: date, calendar: calendar) == Self.deadline(2026, 8, 10))
    }

    // MARK: Overdue judgment (SPEC §24.2)

    @Test func overdueIsStrictlyPastTheDeadlineDay() throws {
        let past = Self.makeGroup(name: "past")
        let today = Self.makeGroup(name: "today")
        let future = Self.makeGroup(name: "future")
        let unset = Self.makeGroup(name: "unset")
        let hiddenPast = Self.makeGroup(name: "hidden-past")
        let model = try Self.makeModel(
            visible: [past, today, future, unset], hidden: [hiddenPast])

        let now = Self.deadline(2026, 8, 10)
        model.setGroupDeadline(past.id, to: Self.deadline(2026, 8, 9))
        model.setGroupDeadline(today.id, to: now)
        model.setGroupDeadline(future.id, to: Self.deadline(2026, 8, 11))
        model.setGroupDeadline(hiddenPast.id, to: Self.deadline(2025, 12, 31))

        #expect(model.isGroupOverdue(past.id, today: now))
        #expect(!model.isGroupOverdue(today.id, today: now))
        #expect(!model.isGroupOverdue(future.id, today: now))
        #expect(!model.isGroupOverdue(unset.id, today: now))
        // The judgment covers hidden groups too: overdue-ness survives hiding;
        // the display layers are already visibility-scoped.
        #expect(model.overdueGroupIDs(today: now) == [past.id, hiddenPast.id])
    }

    // MARK: Sort orderings (SPEC §24.3)

    @Test func prioritySortOrdersHighMediumLowUnsetWithStableTies() throws {
        let unset1 = Self.makeGroup(name: "unset-1")
        let low = Self.makeGroup(name: "low")
        let medium1 = Self.makeGroup(name: "medium-1")
        let high = Self.makeGroup(name: "high")
        let medium2 = Self.makeGroup(name: "medium-2")
        let model = try Self.makeModel(visible: [unset1, low, medium1, high, medium2])

        model.setGroupPriority(low.id, to: .low)
        model.setGroupPriority(medium1.id, to: .medium)
        model.setGroupPriority(high.id, to: .high)
        model.setGroupPriority(medium2.id, to: .medium)

        // high → medium → low → unset; the two mediums keep their current
        // relative order (medium1 before medium2).
        #expect(model.priorityOrderedVisibleGroupIDs()
                == [high.id, medium1.id, medium2.id, low.id, unset1.id])
    }

    @Test func deadlineSortOrdersNearestFirstUnsetLastWithStableTies() throws {
        let unset = Self.makeGroup(name: "unset")
        let december = Self.makeGroup(name: "december")
        let september1 = Self.makeGroup(name: "september-1")
        let september2 = Self.makeGroup(name: "september-2")
        let august = Self.makeGroup(name: "august")
        let model = try Self.makeModel(
            visible: [unset, december, september1, september2, august])

        model.setGroupDeadline(december.id, to: Self.deadline(2026, 12, 1))
        model.setGroupDeadline(september1.id, to: Self.deadline(2026, 9, 1))
        model.setGroupDeadline(september2.id, to: Self.deadline(2026, 9, 1))
        model.setGroupDeadline(august.id, to: Self.deadline(2026, 8, 20))

        // Nearest first, unset last; the two same-day groups keep their
        // current relative order (september1 before september2).
        #expect(model.deadlineOrderedVisibleGroupIDs()
                == [august.id, september1.id, september2.id, december.id, unset.id])
    }

    @Test func sortOrderingsCoverVisibleGroupsOnlyAndMutateNothing() throws {
        let visibleLow = Self.makeGroup(name: "visible-low")
        let visibleHigh = Self.makeGroup(name: "visible-high")
        let hiddenHigh = Self.makeGroup(name: "hidden-high")
        let model = try Self.makeModel(
            visible: [visibleLow, visibleHigh], hidden: [hiddenHigh])

        model.setGroupPriority(visibleLow.id, to: .low)
        model.setGroupPriority(visibleHigh.id, to: .high)
        model.setGroupPriority(hiddenHigh.id, to: .high)
        model.setGroupDeadline(hiddenHigh.id, to: Self.deadline(2026, 1, 1))
        let layoutBefore = model.state.visibleGroupIDs

        // Hidden groups appear in neither ordering, and the orderings are
        // pure judgments: the real layout and the hidden shelf are untouched.
        #expect(model.priorityOrderedVisibleGroupIDs() == [visibleHigh.id, visibleLow.id])
        #expect(model.deadlineOrderedVisibleGroupIDs() == [visibleLow.id, visibleHigh.id])
        #expect(model.state.visibleGroupIDs == layoutBefore)
        #expect(model.state.hiddenGroupIDs == [hiddenHigh.id])
        #expect(model.groupPriority(of: hiddenHigh.id) == .high)
    }

    // MARK: Editor commit point (SPEC §24.1)

    @Test func endNoteEditingSavesNotePriorityAndDeadlineTogether() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        model.beginNoteEditing(group.id)

        model.endNoteEditing(
            saving: "ship it", priority: .high, deadlineInput: "2026-09-01")

        #expect(model.noteEditingGroup == nil)
        #expect(model.state.groups[group.id]?.note == "ship it")
        #expect(model.groupPriority(of: group.id) == .high)
        #expect(model.groupDeadline(of: group.id) == Self.deadline(2026, 9, 1))
    }

    @Test func endNoteEditingRejectsInvalidDeadlineInputToUnset() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        model.setGroupDeadline(group.id, to: Self.deadline(2026, 8, 15))
        model.beginNoteEditing(group.id)

        // The commit goes through the same parsing boundary as the direct
        // setter: an impossible date is rejected — to unset, not to the
        // previous value.
        model.endNoteEditing(saving: "", priority: nil, deadlineInput: "2026-02-30")

        #expect(model.noteEditingGroup == nil)
        #expect(model.groupDeadline(of: group.id) == nil)
    }

    @Test func noteOnlyEndNoteEditingKeepsPriorityAndDeadline() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        model.setGroupPriority(group.id, to: .medium)
        model.setGroupDeadline(group.id, to: Self.deadline(2026, 8, 15))
        model.beginNoteEditing(group.id)

        model.endNoteEditing(saving: "note only")

        #expect(model.state.groups[group.id]?.note == "note only")
        #expect(model.groupPriority(of: group.id) == .medium)
        #expect(model.groupDeadline(of: group.id) == Self.deadline(2026, 8, 15))
    }

    @Test func fullEndNoteEditingWithoutSessionIsNoOp() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])

        model.endNoteEditing(saving: "stray", priority: .high, deadlineInput: "2026-09-01")

        #expect(model.state.groups[group.id]?.note == "")
        #expect(model.groupPriority(of: group.id) == nil)
        #expect(model.groupDeadline(of: group.id) == nil)
    }

    @Test func settersOnUnknownGroupAreNoOps() throws {
        let group = Self.makeGroup(name: "alpha")
        let model = try Self.makeModel(visible: [group])
        let unknown = GroupID()

        model.setGroupPriority(unknown, to: .high)
        model.setGroupDeadline(unknown, parsing: "2026-08-15")
        #expect(model.groupPriority(of: unknown) == nil)
        #expect(model.groupDeadline(of: unknown) == nil)
        #expect(model.groupPriority(of: group.id) == nil)
    }
}
