//
//  GhosttyTitleUITests.swift
//  XGhosttyUITests
//
//  Created by luca on 13.10.2025.
//

import XCTest

final class GhosttyTitleUITests: GhosttyCustomConfigCase {
    override func setUp() async throws {
        try await super.setUp()
        try updateConfig(#"title = "XGhosttyUITestsLaunchTests""#)
    }

    @MainActor
    func testTitle() throws {
        let app = try ghosttyApplication()
        app.launch()

        XCTAssertEqual(app.windows.firstMatch.title, "XGhosttyUITestsLaunchTests", "Oops, `title=` doesn't work!")
    }
}
