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
}
