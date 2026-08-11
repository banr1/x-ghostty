import Foundation
import Testing
@testable import XGhostty

/// Tests for the per-project note model: normalization (the 10-line cap),
/// the `WorkspaceModel.setProjectNote` mutation path, and persistence via the
/// `WorkspaceState` Codable round trip. Pane trees stay empty, matching the
/// other project-model tests.
struct ProjectNoteTests {
    // MARK: Normalization (line cap)

    @Test func noteDefaultsToEmpty() throws {
        let project = ProjectState(id: ProjectID(), name: "g", paneTree: .init(), createdAt: Date())
        #expect(project.note == "")
    }

    @Test func normalizedNoteKeepsShortTextVerbatim() throws {
        let text = "line 1\nline 2\nline 3"
        #expect(ProjectState.normalizedNote(text) == text)
    }

    @Test func normalizedNoteKeepsExactlyTenLines() throws {
        let ten = (1...10).map { "line \($0)" }.joined(separator: "\n")
        #expect(ProjectState.normalizedNote(ten) == ten)
    }

    @Test func normalizedNoteDropsLinesBeyondTen() throws {
        let twelve = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let expected = (1...10).map { "line \($0)" }.joined(separator: "\n")
        #expect(ProjectState.normalizedNote(twelve) == expected)
    }

    @Test func normalizedNoteUnifiesLineEndings() throws {
        #expect(ProjectState.normalizedNote("a\r\nb\rc") == "a\nb\nc")
    }

    @Test func initCapsOversizedNote() throws {
        let twelve = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let project = ProjectState(
            id: ProjectID(), name: "g", paneTree: .init(), note: twelve, createdAt: Date())
        #expect(project.note.components(separatedBy: "\n").count == ProjectState.maxNoteLines)
    }

    @Test func setNoteCapsOversizedNote() throws {
        var project = ProjectState(id: ProjectID(), name: "g", paneTree: .init(), createdAt: Date())
        project.setNote((1...15).map { "line \($0)" }.joined(separator: "\n"))
        #expect(project.note.components(separatedBy: "\n").count == ProjectState.maxNoteLines)
    }

    // MARK: WorkspaceModel.setProjectNote

    @Test func setProjectNoteStoresText() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.setProjectNote(ids.0, to: "remember: fix the build\nthen ship")

        #expect(model.state.projects[ids.0]?.note == "remember: fix the build\nthen ship")
        #expect(model.state.projects[ids.1]?.note == "")
    }

    @Test func setProjectNoteCapsAtTenLines() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.setProjectNote(ids.0, to: (1...20).map { "line \($0)" }.joined(separator: "\n"))

        let stored = try #require(model.state.projects[ids.0]?.note)
        #expect(stored.components(separatedBy: "\n").count == ProjectState.maxNoteLines)
        #expect(stored.hasSuffix("line 10"))
    }

    @Test func setProjectNoteUnknownProjectIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.setProjectNote(ProjectID(), to: "should go nowhere")

        #expect(model.state.projects[ids.0]?.note == "")
        #expect(model.state.projects[ids.1]?.note == "")
    }

    @Test func setProjectNoteCanClearNote() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.setProjectNote(ids.0, to: "something")
        model.setProjectNote(ids.0, to: "")

        #expect(model.state.projects[ids.0]?.note == "")
    }

    // MARK: Persistence (Codable round trip)

    @Test func codableRoundTripRestoresNoteText() throws {
        var (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        state.projects[ids.0]?.setNote("project A\nwaiting on review")
        state.projects[ids.1]?.setNote("project B")

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        #expect(decoded.projects[ids.0]?.note == "project A\nwaiting on review")
        #expect(decoded.projects[ids.1]?.note == "project B")
    }

    @Test func decodeWithoutNoteKeyDefaultsToEmpty() throws {
        // A save written before notes existed has no `note` key. Simulate it by
        // stripping the key from a freshly encoded state.
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let data = try JSONEncoder().encode(state)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var projects = try #require(object["projects"] as? [String: [String: Any]])
        for key in projects.keys { projects[key]?.removeValue(forKey: "note") }
        object["projects"] = projects

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: legacy)

        #expect(decoded.projects[ids.0]?.note == "")
        #expect(decoded.projects[ids.1]?.note == "")
    }

    @Test func decodeCapsOversizedNote() throws {
        // A hand-edited or corrupted save must not smuggle in an over-long
        // note: decode re-normalizes.
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let data = try JSONEncoder().encode(state)
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var projects = try #require(object["projects"] as? [String: [String: Any]])
        let oversized = (1...30).map { "line \($0)" }.joined(separator: "\n")
        projects[ids.0.rawValue.uuidString]?["note"] = oversized
        object["projects"] = projects

        let tampered = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: tampered)

        let restored = try #require(decoded.projects[ids.0]?.note)
        #expect(restored.components(separatedBy: "\n").count == ProjectState.maxNoteLines)
        #expect(restored.hasSuffix("line 10"))
    }

    // MARK: Note editing session (edit_project_note, SPEC §21.2)

    @Test func beginNoteEditingFocusedProjectTargetsFocusedProject() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.beginNoteEditingFocusedProject()

        #expect(model.noteEditingProject == ids.0)
    }

    @Test func beginNoteEditingUnknownProjectIsNoOp() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.beginNoteEditing(ProjectID())

        #expect(model.noteEditingProject == nil)
    }

    @Test func beginNoteEditingWithoutFocusIsNoOp() throws {
        let model = WorkspaceModel()

        model.beginNoteEditingFocusedProject()

        #expect(model.noteEditingProject == nil)
    }

    @Test func beginNoteEditingNonFocusedProjectOpensItWithoutMovingFocus() throws {
        // The header-band mouse affordance (SPEC §21.2) opens any visible
        // project's note editor directly — the project focus must stay put.
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.beginNoteEditing(ids.1)

        #expect(model.noteEditingProject == ids.1)
        #expect(model.state.focusedProject == ids.0)
    }

    @Test func endNoteEditingSavesDraftAndCloses() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.1)

        model.endNoteEditing(saving: "deploy after review\nping the team")

        #expect(model.state.projects[ids.1]?.note == "deploy after review\nping the team")
        #expect(model.noteEditingProject == nil)
    }

    @Test func endNoteEditingCapsAtTenLines() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.endNoteEditing(saving: (1...25).map { "line \($0)" }.joined(separator: "\n"))

        let stored = try #require(model.state.projects[ids.0]?.note)
        #expect(stored.components(separatedBy: "\n").count == ProjectState.maxNoteLines)
        #expect(model.noteEditingProject == nil)
    }

    /// A paste that pushes the draft past the cap behaves like manual input
    /// (SPEC §21.2): the save truncates to the first `maxNoteLines` lines.
    /// Pasteboard payloads may carry CRLF/CR endings, which the normalization
    /// unifies before capping, so a CRLF paste cannot evade the line cap.
    @Test func endNoteEditingTruncatesOversizedPasteToFirstTenLines() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        let pasted = (1...14).map { "pasted \($0)" }.joined(separator: "\r\n")
        model.endNoteEditing(saving: pasted)

        let stored = try #require(model.state.projects[ids.0]?.note)
        let expected = (1...ProjectState.maxNoteLines)
            .map { "pasted \($0)" }
            .joined(separator: "\n")
        #expect(stored == expected)
        #expect(model.noteEditingProject == nil)
    }

    @Test func endNoteEditingWithoutSessionIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.endNoteEditing(saving: "orphan text")

        #expect(model.state.projects[ids.0]?.note == "")
        #expect(model.state.projects[ids.1]?.note == "")
    }

    @Test func cancelNoteEditingKeepsPreOpenTextAndCloses() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.setProjectNote(ids.1, to: "original line 1\noriginal line 2")
        model.beginNoteEditing(ids.1)

        model.cancelNoteEditing()

        #expect(model.state.projects[ids.1]?.note == "original line 1\noriginal line 2")
        #expect(model.noteEditingProject == nil)
    }

    @Test func cancelNoteEditingWithoutSessionIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.setProjectNote(ids.0, to: "keep me")

        model.cancelNoteEditing()

        #expect(model.state.projects[ids.0]?.note == "keep me")
        #expect(model.noteEditingProject == nil)
    }

    @Test func restoreStateClearsNoteEditingForVanishedProject() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.1)

        // A snapshot in which the edited project no longer exists.
        let solo = ProjectID()
        let snapshot = WorkspaceState(
            canonicalProjectTree: .init(view: ProjectRef(id: solo)),
            projects: [solo: ProjectState(
                id: solo, name: "solo", paneTree: .init(), createdAt: Date())],
            focusedProject: solo)

        model.restoreState(snapshot)

        #expect(model.noteEditingProject == nil)
    }

    @Test func restoreStateKeepsNoteEditingForSurvivingProject() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.restoreState(state)

        #expect(model.noteEditingProject == ids.0)
    }

    @Test func removeAllProjectsClearsNoteEditing() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        model.removeAllProjects()

        #expect(model.noteEditingProject == nil)
    }

    // MARK: Note overview (toggle_note_overview)

    @Test func overviewStartsInactiveWithEmptyDisplaySet() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        #expect(!model.noteOverviewActive)
        #expect(model.noteOverviewProjectIDs.isEmpty)
    }

    @Test func overviewDisplaySetIsExactlyTheVisibleProjects() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.toggleNoteOverview()

        #expect(model.noteOverviewProjectIDs == [ids.0, ids.1])
    }

    @Test func overviewDisplaySetExcludesHiddenProjects() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        // Hide the focused project (ids.0); ids.1 stays the only visible project.
        let hidden = try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(hidden.target == ids.1)

        model.toggleNoteOverview()

        #expect(model.noteOverviewProjectIDs == [ids.1])
        #expect(!model.noteOverviewProjectIDs.contains(ids.0))
    }

    @Test func enteringOverviewReleasesZoom() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == ids.0)

        model.toggleNoteOverview()

        #expect(model.state.zoomedProject == nil)
        #expect(model.noteOverviewActive)
        // With the zoom released, the display set is all visible projects again.
        #expect(model.noteOverviewProjectIDs == [ids.0, ids.1])
    }

    @Test func enteringOverviewKeepsFocusedProject() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        model.toggleNoteOverview()

        #expect(model.state.focusedProject == ids.0)
    }

    @Test func togglingTwiceLeavesOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)

        #expect(model.toggleNoteOverview())
        #expect(!model.toggleNoteOverview())
        #expect(!model.noteOverviewActive)
    }

    @Test func endNoteOverviewLeavesOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.endNoteOverview()

        #expect(!model.noteOverviewActive)
    }

    @Test func overviewBlocksNoteEditing() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.beginNoteEditing(ids.1)
        model.beginNoteEditingFocusedProject()

        #expect(model.noteEditingProject == nil)
    }

    @Test func overviewBlocksDirectionalFocusMoves() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        // Sanity: the move resolves while the overview is inactive.
        #expect(model.gotoProjectTarget(.spatial(.right)) != nil)

        model.toggleNoteOverview()

        #expect(model.gotoProjectTarget(.spatial(.right)) == nil)
    }

    @Test func overviewBlocksIndexFocusMoves() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        // Sanity: the jump resolves while the overview is inactive.
        #expect(model.gotoProjectIndexTarget(2) != nil)

        model.toggleNoteOverview()

        #expect(model.gotoProjectIndexTarget(2) == nil)
    }

    @Test func overviewBlocksFocusSwitch() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        let result = model.switchFocusedProject(
            to: ids.1, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedProject == ids.0)
    }

    @Test func toggleOverviewWhileNoteEditingIsNoOp() throws {
        let (state, ids) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.beginNoteEditing(ids.0)

        #expect(!model.toggleNoteOverview())
        #expect(!model.noteOverviewActive)
        #expect(model.noteEditingProject == ids.0)
    }

    @Test func restoreStateEndsOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.restoreState(state)

        #expect(!model.noteOverviewActive)
    }

    @Test func removeAllProjectsEndsOverview() throws {
        let (state, _) = try WorkspaceStateTests.makeTwoProjectState()
        let model = WorkspaceModel(state)
        model.toggleNoteOverview()

        model.removeAllProjects()

        #expect(!model.noteOverviewActive)
    }
}
