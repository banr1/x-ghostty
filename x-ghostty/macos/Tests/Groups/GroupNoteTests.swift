import Foundation
import Testing
@testable import XGhostty

/// Tests for the per-group note model: normalization (the 10-line cap),
/// the `WorkspaceModel.setGroupNote` mutation path, and persistence via the
/// `WorkspaceState` Codable round trip. Pane trees stay empty, matching the
/// other group-model tests.
struct GroupNoteTests {
    // MARK: Normalization (line cap)

    @Test func noteDefaultsToEmpty() throws {
        let group = GroupState(id: GroupID(), name: "g", paneTree: .init(), createdAt: Date())
        #expect(group.note == "")
    }

    @Test func normalizedNoteKeepsShortTextVerbatim() throws {
        let text = "line 1\nline 2\nline 3"
        #expect(GroupState.normalizedNote(text) == text)
    }

    @Test func normalizedNoteKeepsExactlyTenLines() throws {
        let ten = (1...10).map { "line \($0)" }.joined(separator: "\n")
        #expect(GroupState.normalizedNote(ten) == ten)
    }

    @Test func normalizedNoteDropsLinesBeyondTen() throws {
        let twelve = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let expected = (1...10).map { "line \($0)" }.joined(separator: "\n")
        #expect(GroupState.normalizedNote(twelve) == expected)
    }

    @Test func normalizedNoteUnifiesLineEndings() throws {
        #expect(GroupState.normalizedNote("a\r\nb\rc") == "a\nb\nc")
    }

    @Test func initCapsOversizedNote() throws {
        let twelve = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let group = GroupState(
            id: GroupID(), name: "g", paneTree: .init(), note: twelve, createdAt: Date())
        #expect(group.note.components(separatedBy: "\n").count == GroupState.maxNoteLines)
    }

    @Test func setNoteCapsOversizedNote() throws {
        var group = GroupState(id: GroupID(), name: "g", paneTree: .init(), createdAt: Date())
        group.setNote((1...15).map { "line \($0)" }.joined(separator: "\n"))
        #expect(group.note.components(separatedBy: "\n").count == GroupState.maxNoteLines)
    }

    // MARK: WorkspaceModel.setGroupNote

    @Test func setGroupNoteStoresText() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.setGroupNote(ids.0, to: "remember: fix the build\nthen ship")

        #expect(model.state.groups[ids.0]?.note == "remember: fix the build\nthen ship")
        #expect(model.state.groups[ids.1]?.note == "")
    }

    @Test func setGroupNoteCapsAtTenLines() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.setGroupNote(ids.0, to: (1...20).map { "line \($0)" }.joined(separator: "\n"))

        let stored = try #require(model.state.groups[ids.0]?.note)
        #expect(stored.components(separatedBy: "\n").count == GroupState.maxNoteLines)
        #expect(stored.hasSuffix("line 10"))
    }

    @Test func setGroupNoteUnknownGroupIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.setGroupNote(GroupID(), to: "should go nowhere")

        #expect(model.state.groups[ids.0]?.note == "")
        #expect(model.state.groups[ids.1]?.note == "")
    }

    @Test func setGroupNoteCanClearNote() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.setGroupNote(ids.0, to: "something")
        model.setGroupNote(ids.0, to: "")

        #expect(model.state.groups[ids.0]?.note == "")
    }

    // MARK: Persistence (Codable round trip)

    @Test func codableRoundTripRestoresNoteText() throws {
        var (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        state.groups[ids.0]?.setNote("project A\nwaiting on review")
        state.groups[ids.1]?.setNote("project B")

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(decoded.groups[ids.0]?.note == "project A\nwaiting on review")
        #expect(decoded.groups[ids.1]?.note == "project B")
    }

    @Test func decodeWithoutNoteKeyDefaultsToEmpty() throws {
        // A save written before notes existed has no `note` key. Simulate it by
        // stripping the key from a freshly encoded state.
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let data = try JSONEncoder().encode(state)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var groups = try #require(object["groups"] as? [String: [String: Any]])
        for key in groups.keys { groups[key]?.removeValue(forKey: "note") }
        object["groups"] = groups

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: legacy)

        #expect(decoded.groups[ids.0]?.note == "")
        #expect(decoded.groups[ids.1]?.note == "")
    }

    @Test func decodeCapsOversizedNote() throws {
        // A hand-edited or corrupted save must not smuggle in an over-long
        // note: decode re-normalizes.
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let data = try JSONEncoder().encode(state)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var groups = try #require(object["groups"] as? [String: [String: Any]])
        let oversized = (1...30).map { "line \($0)" }.joined(separator: "\n")
        groups[ids.0.rawValue.uuidString]?["note"] = oversized
        object["groups"] = groups

        let tampered = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: tampered)

        let restored = try #require(decoded.groups[ids.0]?.note)
        #expect(restored.components(separatedBy: "\n").count == GroupState.maxNoteLines)
        #expect(restored.hasSuffix("line 10"))
    }

    // MARK: Note editing session (edit_group_note, SPEC §21.2)

    @Test func beginNoteEditingFocusedGroupTargetsFocusedGroup() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.beginNoteEditingFocusedGroup()

        #expect(model.noteEditingGroup == ids.0)
    }

    @Test func beginNoteEditingUnknownGroupIsNoOp() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.beginNoteEditing(GroupID())

        #expect(model.noteEditingGroup == nil)
    }

    @Test func beginNoteEditingWithoutFocusIsNoOp() throws {
        let model = WorkspaceModel()

        model.beginNoteEditingFocusedGroup()

        #expect(model.noteEditingGroup == nil)
    }

    @Test func beginNoteEditingNonFocusedGroupOpensItWithoutMovingFocus() throws {
        // The header-band mouse affordance (SPEC §21.2) opens any visible
        // group's note editor directly — the group focus must stay put.
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.beginNoteEditing(ids.1)

        #expect(model.noteEditingGroup == ids.1)
        #expect(model.state.focusedGroup == ids.0)
    }

    @Test func endNoteEditingSavesDraftAndCloses() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.1)

        model.endNoteEditing(saving: "deploy after review\nping the team")

        #expect(model.state.groups[ids.1]?.note == "deploy after review\nping the team")
        #expect(model.noteEditingGroup == nil)
    }

    @Test func endNoteEditingCapsAtTenLines() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.endNoteEditing(saving: (1...25).map { "line \($0)" }.joined(separator: "\n"))

        let stored = try #require(model.state.groups[ids.0]?.note)
        #expect(stored.components(separatedBy: "\n").count == GroupState.maxNoteLines)
        #expect(model.noteEditingGroup == nil)
    }

    @Test func endNoteEditingWithoutSessionIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.endNoteEditing(saving: "orphan text")

        #expect(model.state.groups[ids.0]?.note == "")
        #expect(model.state.groups[ids.1]?.note == "")
    }

    @Test func cancelNoteEditingKeepsPreOpenTextAndCloses() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.setGroupNote(ids.1, to: "original line 1\noriginal line 2")
        model.beginNoteEditing(ids.1)

        model.cancelNoteEditing()

        #expect(model.state.groups[ids.1]?.note == "original line 1\noriginal line 2")
        #expect(model.noteEditingGroup == nil)
    }

    @Test func cancelNoteEditingWithoutSessionIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.setGroupNote(ids.0, to: "keep me")

        model.cancelNoteEditing()

        #expect(model.state.groups[ids.0]?.note == "keep me")
        #expect(model.noteEditingGroup == nil)
    }

    @Test func restoreStateClearsNoteEditingForVanishedGroup() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.1)

        // A snapshot in which the edited group no longer exists.
        let solo = GroupID()
        let snapshot = WorkspaceState(
            canonicalGroupTree: .init(view: GroupRef(id: solo)),
            groups: [solo: GroupState(
                id: solo, name: "solo", paneTree: .init(), createdAt: Date())],
            focusedGroup: solo)

        model.restoreState(snapshot)

        #expect(model.noteEditingGroup == nil)
    }

    @Test func restoreStateKeepsNoteEditingForSurvivingGroup() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.restoreState(state)

        #expect(model.noteEditingGroup == ids.0)
    }

    @Test func removeAllGroupsClearsNoteEditing() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.removeAllGroups()

        #expect(model.noteEditingGroup == nil)
    }

    // MARK: Note overview (toggle_note_overview)

    @Test func overviewStartsInactiveWithEmptyDisplaySet() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        #expect(!model.noteOverviewActive)
        #expect(model.noteOverviewGroupIDs.isEmpty)
    }

    @Test func overviewDisplaySetIsExactlyTheVisibleGroups() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.toggleNoteOverview()

        #expect(model.noteOverviewGroupIDs == [ids.0, ids.1])
    }

    @Test func overviewDisplaySetExcludesHiddenGroups() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        // Hide the focused group (ids.0); ids.1 stays the only visible group.
        let hidden = try #require(model.hideFocusedGroup(savingOutgoingPaneTree: .init()))
        #expect(hidden.target == ids.1)

        model.toggleNoteOverview()

        #expect(model.noteOverviewGroupIDs == [ids.1])
        #expect(!model.noteOverviewGroupIDs.contains(ids.0))
    }

    @Test func enteringOverviewReleasesZoom() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleGroupZoom()
        #expect(model.state.zoomedGroup == ids.0)

        model.toggleNoteOverview()

        #expect(model.state.zoomedGroup == nil)
        #expect(model.noteOverviewActive)
        // With the zoom released, the display set is all visible groups again.
        #expect(model.noteOverviewGroupIDs == [ids.0, ids.1])
    }

    @Test func enteringOverviewKeepsFocusedGroup() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        model.toggleNoteOverview()

        #expect(model.state.focusedGroup == ids.0)
    }

    @Test func togglingTwiceLeavesOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)

        #expect(model.toggleNoteOverview())
        #expect(!model.toggleNoteOverview())
        #expect(!model.noteOverviewActive)
    }

    @Test func endNoteOverviewLeavesOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.endNoteOverview()

        #expect(!model.noteOverviewActive)
    }

    @Test func overviewBlocksNoteEditing() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.beginNoteEditing(ids.1)
        model.beginNoteEditingFocusedGroup()

        #expect(model.noteEditingGroup == nil)
    }

    @Test func overviewBlocksDirectionalFocusMoves() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        // Sanity: the move resolves while the overview is inactive.
        #expect(model.gotoGroupTarget(.spatial(.right)) != nil)

        model.toggleNoteOverview()

        #expect(model.gotoGroupTarget(.spatial(.right)) == nil)
    }

    @Test func overviewBlocksIndexFocusMoves() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        // Sanity: the jump resolves while the overview is inactive.
        #expect(model.gotoGroupIndexTarget(2) != nil)

        model.toggleNoteOverview()

        #expect(model.gotoGroupIndexTarget(2) == nil)
    }

    @Test func overviewBlocksFocusSwitch() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        let result = model.switchFocusedGroup(
            to: ids.1, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedGroup == ids.0)
    }

    @Test func toggleOverviewWhileNoteEditingIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        #expect(!model.toggleNoteOverview())
        #expect(!model.noteOverviewActive)
        #expect(model.noteEditingGroup == ids.0)
    }

    @Test func restoreStateEndsOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.restoreState(state)

        #expect(!model.noteOverviewActive)
    }

    @Test func removeAllGroupsEndsOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoGroupState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.removeAllGroups()

        #expect(!model.noteOverviewActive)
    }
}
