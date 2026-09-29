import Foundation
import Testing
@testable import XGhostty

/// Tests for `ShortcutCatalog` (`SPEC.md` §30): the shortcut-list overlay's
/// grouped enumeration of the effective shortcuts. The catalog is the model's
/// judgment of what the overlay shows, so its shape — scene coverage, the
/// upstream-derived entries, the removed defaults staying absent, the
/// everywhere-reachable toggle — is pinned here.
struct ShortcutCatalogTests {
    /// The overlay groups by scene, one group per scene, in the scene
    /// declaration order (overall view, zoom, project list, note editor,
    /// overview) — the four on-device scenes of success criterion 28 plus
    /// the overview.
    @Test func groupsCoverEverySceneInOrder() {
        #expect(ShortcutCatalog.groups.map(\.scene) == ShortcutScene.allCases)
        #expect(ShortcutScene.allCases == [
            .overallView, .zoom, .projectList, .noteEditor, .noteOverview,
        ])
    }

    /// Every group lists Cmd+/ — the list toggles from any scene.
    @Test func shortcutListChordIsListedInEveryScene() {
        for group in ShortcutCatalog.groups {
            #expect(
                group.items.contains { $0.chord == "⌘/" },
                "missing ⌘/ in \(group.scene)")
        }
    }

    /// Upstream-derived chords appear (the enumeration is not fork-only):
    /// copy/paste and find in the overall view, splits and pane moves in
    /// the zoom scene.
    @Test func upstreamDerivedShortcutsAreListed() {
        let overall = ShortcutCatalog.groups[0].items.map(\.chord)
        #expect(overall.contains("⌘C · ⌘V"))
        #expect(overall.contains("⌘F"))

        let zoom = ShortcutCatalog.groups[1].items.map(\.chord)
        #expect(zoom.contains("⌘D · ⌘⇧D"))
        #expect(zoom.contains("⌘[ · ⌘]"))
    }

    /// The fork's project-layer chords appear in their scenes.
    @Test func forkShortcutsAreListed() {
        let overall = ShortcutCatalog.groups[0].items.map(\.chord)
        #expect(overall.contains("⌘L"))
        #expect(overall.contains("⌘E"))
        #expect(overall.contains("⌘⌥E"))
        #expect(overall.contains("⌘1–9"))

        let zoom = ShortcutCatalog.groups[1].items.map(\.chord)
        #expect(zoom.contains("⌘P"))

        let noteEditor = ShortcutCatalog.groups[3].items.map(\.chord)
        #expect(noteEditor.contains("⌘↩"))
        #expect(noteEditor.contains("⌘Z · ⌘⇧Z"))
    }

    /// The defaults this fork removed must not be listed: Cmd+K
    /// (clear_screen, must 82) nowhere, and no fullscreen or
    /// search-selection entry on Cmd+Enter / Cmd+E.
    @Test func removedDefaultsAreAbsent() {
        for group in ShortcutCatalog.groups {
            for item in group.items {
                #expect(!item.chord.contains("⌘K"), "⌘K listed in \(group.scene)")
                #expect(
                    !item.label.lowercased().contains("fullscreen"),
                    "fullscreen listed in \(group.scene)")
                #expect(
                    !item.label.lowercased().contains("clear screen"),
                    "clear-screen listed in \(group.scene)")
            }
        }
    }

    /// Display hygiene: no empty chord or label, and no duplicate chord
    /// within a group (chords are the overlay's row identity).
    @Test func entriesAreWellFormed() {
        for group in ShortcutCatalog.groups {
            #expect(!group.items.isEmpty)
            var seen = Set<String>()
            for item in group.items {
                #expect(!item.chord.isEmpty)
                #expect(!item.label.isEmpty)
                #expect(seen.insert(item.chord).inserted,
                        "duplicate chord \(item.chord) in \(group.scene)")
            }
        }
    }

    /// Every scene carries a non-empty display name for the group header.
    @Test func sceneDisplayNames() {
        for scene in ShortcutScene.allCases {
            #expect(!scene.displayName.isEmpty)
        }
    }
}

/// Tests for the shortcut-list session on `WorkspaceModel` (`SPEC.md` §30):
/// a stacking toggle that locks nothing underneath.
struct ShortcutListSessionTests {
    @Test func togglesAndCloses() {
        let model = WorkspaceModel(wrapping: .init(), name: "amber-owl")
        #expect(!model.shortcutListActive)
        model.toggleShortcutList()
        #expect(model.shortcutListActive)
        model.toggleShortcutList()
        #expect(!model.shortcutListActive)
        model.toggleShortcutList()
        model.endShortcutList()
        #expect(!model.shortcutListActive)
    }

    /// The shortcut list stacks: opened over an active project-list session
    /// it neither closes that session nor is blocked by it, and closing it
    /// leaves the session as it was.
    @Test func stacksOverAnOverlaySession() {
        let model = WorkspaceModel(wrapping: .init(), name: "amber-owl")
        model.beginProjectList()
        #expect(model.projectListActive)

        model.toggleShortcutList()
        #expect(model.shortcutListActive)
        #expect(model.projectListActive)

        model.endShortcutList()
        #expect(!model.shortcutListActive)
        #expect(model.projectListActive)
    }
}
