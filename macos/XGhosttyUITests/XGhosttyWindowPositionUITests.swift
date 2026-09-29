//
//  GhosttyWindowPositionUITests.swift
//  XGhosttyUITests
//
//  Created by Claude on 2026-03-11.
//

import XCTest

/// XGhostty is a single-window app, so every round-trip here is
/// launch → observe → terminate → relaunch rather than open/close windows.
final class GhosttyWindowPositionUITests: GhosttyCustomConfigCase {
    // MARK: - Restore round-trip per titlebar style

    @MainActor func testRestoredNative() throws { try runRestoreTest(titlebarStyle: "native") }
    @MainActor func testRestoredHidden() throws { try runRestoreTest(titlebarStyle: "hidden") }
    @MainActor func testRestoredTransparent() throws { try runRestoreTest(titlebarStyle: "transparent") }

    // MARK: - Config overrides cached position/size

    @MainActor
    func testConfigOverridesCachedPositionAndSize() async throws {
        // Launch maximized so the cached frame is fullscreen-sized.
        try updateConfig(
            """
            maximize = true
            title = "GhosttyWindowPositionUITests"
            """
        )

        let app = try ghosttyApplication()
        app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Window should appear")

        let maximizedFrame = window.frame
        app.terminate()

        // Relaunch with a small explicit size and position. It should respect the
        // config, not the cached frame.
        try updateConfig(
            """
            window-position-x = 50
            window-position-y = 50
            window-width = 30
            window-height = 30
            title = "GhosttyWindowPositionUITests"
            """
        )

        let app2 = try ghosttyApplication()
        app2.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        app2.launch()

        let newWindow = app2.windows.firstMatch
        XCTAssertTrue(newWindow.waitForExistence(timeout: 5), "Window should appear")
        let newFrame = newWindow.frame

        // The new window should be smaller than the maximized one.
        XCTAssertLessThan(newFrame.size.width, maximizedFrame.size.width,
                          "30 columns should be narrower than maximized")
        XCTAssertLessThan(newFrame.size.height, maximizedFrame.size.height,
                          "30 rows should be shorter than maximized")

        app2.terminate()
    }

    // MARK: - Size-only config change preserves position

    @MainActor
    func testSizeOnlyConfigPreservesPosition() async throws {
        // Launch maximized so the window has a known position (top-left of visible frame).
        try updateConfig(
            """
            maximize = true
            title = "GhosttyWindowPositionUITests"
            """
        )

        let app = try ghosttyApplication()
        app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Window should appear")

        let initialFrame = window.frame
        app.terminate()

        // Relaunch with only size changed. Position should be restored from cache.
        try updateConfig(
            """
            window-width = 30
            window-height = 30
            title = "GhosttyWindowPositionUITests"
            """
        )

        let app2 = try ghosttyApplication()
        app2.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        app2.launch()

        let newWindow = app2.windows.firstMatch
        XCTAssertTrue(newWindow.waitForExistence(timeout: 5), "Window should appear")

        let newFrame = newWindow.frame

        // Position should be preserved from the cached value.
        // Compare x and maxY since the window is anchored at the top-left
        // but AppKit uses bottom-up coordinates (origin.y changes with height).
        XCTAssertEqual(newFrame.origin.x, initialFrame.origin.x, accuracy: 2,
                        "x position should not change with size-only config")
        XCTAssertEqual(newFrame.maxY, initialFrame.maxY, accuracy: 2,
                        "top edge (maxY) should not change with size-only config")

        app2.terminate()
    }

    // MARK: - Shared round-trip helper

    /// Launches the app, records the window frame, quits, and relaunches to
    /// verify the frame is restored consistently.
    private func runRestoreTest(titlebarStyle: String) throws {
        try updateConfig(
            """
            macos-titlebar-style = \(titlebarStyle)
            title = "GhosttyWindowPositionUITests"
            """
        )

        let app = try ghosttyApplication()
        // Suppress Restoration
        app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        // Clean run
        app.launchEnvironment["XGHOSTTY_CLEAR_USER_DEFAULTS"] = "YES"
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Window should appear")

        let firstFrame = window.frame
        let screenFrame = NSScreen.main?.frame ?? .zero

        XCTAssertEqual(firstFrame.midX, screenFrame.midX, accuracy: 5.0, "First window should be centered horizontally")

        app.terminate()

        // Relaunch — the window should come back with the same frame.
        let app2 = try ghosttyApplication()
        app2.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        app2.launch()

        let window2 = app2.windows.firstMatch
        XCTAssertTrue(window2.waitForExistence(timeout: 5), "Window should appear")

        let restoredFrame = window2.frame

        XCTAssertEqual(restoredFrame.origin.x, firstFrame.origin.x, accuracy: 2,
                        "[\(titlebarStyle)] x position should be restored")
        XCTAssertEqual(restoredFrame.origin.y, firstFrame.origin.y, accuracy: 2,
                        "[\(titlebarStyle)] y position should be restored")
        XCTAssertEqual(restoredFrame.size.width, firstFrame.size.width, accuracy: 2,
                        "[\(titlebarStyle)] width should be restored")
        XCTAssertEqual(restoredFrame.size.height, firstFrame.size.height, accuracy: 2,
                        "[\(titlebarStyle)] height should be restored")

        app2.terminate()
    }
}
