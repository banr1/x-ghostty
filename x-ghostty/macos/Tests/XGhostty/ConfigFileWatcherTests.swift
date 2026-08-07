#if os(macOS)
import Foundation
import Testing
@testable import XGhostty

/// Tests for `ConfigFileWatcher`. These are timing-based (the watcher
/// debounces kqueue events by 500ms) so waits are generous to stay
/// deterministic on slow CI machines.
struct ConfigFileWatcherTests {
    /// Wraps a watcher on a fresh temporary directory and counts callbacks.
    private final class Harness {
        let dir: URL
        let configPath: String
        let watcher: ConfigFileWatcher
        private let lock = NSLock()
        private var count = 0

        var changeCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        init(initialContents: String?) throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("xghostty-watcher-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("config.xghostty")
            configPath = url.path
            if let initialContents {
                try initialContents.write(to: url, atomically: true, encoding: .utf8)
            }

            var onChange: (() -> Void)?
            watcher = ConfigFileWatcher(
                paths: [configPath],
                queue: DispatchQueue(label: "watcher-test")
            ) { onChange?() }
            onChange = { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.count += 1
                self.lock.unlock()
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: dir)
        }

        /// Waits until at least `count` changes were observed or the timeout
        /// elapses. Returns the final observed count.
        func wait(for target: Int, timeout: TimeInterval = 5) async -> Int {
            let deadline = Date().addingTimeInterval(timeout)
            while changeCount < target && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return changeCount
        }
    }

    @Test func detectsInPlaceWrite() async throws {
        let harness = try Harness(initialContents: "theme = A\n")
        defer { harness.cleanup() }

        try "hatheme = A\n".write(
            toFile: harness.configPath,
            atomically: false,
            encoding: .utf8
        )
        #expect(await harness.wait(for: 1) >= 1)
    }

    @Test func detectsAtomicRenameSave() async throws {
        let harness = try Harness(initialContents: "theme = A\n")
        defer { harness.cleanup() }

        // atomically:true replaces the file via rename, like most editors.
        try "theme = B\n".write(
            toFile: harness.configPath,
            atomically: true,
            encoding: .utf8
        )
        #expect(await harness.wait(for: 1) >= 1)
    }

    @Test func detectsCreationOfMissingFile() async throws {
        let harness = try Harness(initialContents: nil)
        defer { harness.cleanup() }

        try "theme = A\n".write(
            toFile: harness.configPath,
            atomically: true,
            encoding: .utf8
        )
        #expect(await harness.wait(for: 1) >= 1)
    }

    @Test func keepsWatchingAcrossReplacements() async throws {
        let harness = try Harness(initialContents: "theme = A\n")
        defer { harness.cleanup() }

        try "theme = B\n".write(
            toFile: harness.configPath,
            atomically: true,
            encoding: .utf8
        )
        #expect(await harness.wait(for: 1) >= 1)

        // The rename above invalidated the original file descriptor; a
        // subsequent write must still be seen via the re-armed watcher.
        try "theme = C\n".write(
            toFile: harness.configPath,
            atomically: true,
            encoding: .utf8
        )
        #expect(await harness.wait(for: 2) >= 2)
    }

    @Test func ignoresUnrelatedFilesInSameDirectory() async throws {
        let harness = try Harness(initialContents: "theme = A\n")
        defer { harness.cleanup() }

        let unrelated = harness.dir.appendingPathComponent("other.txt")
        try "hello\n".write(to: unrelated, atomically: true, encoding: .utf8)

        // Give the debounce ample time to fire if it (incorrectly) would.
        try await Task.sleep(for: .seconds(2))
        #expect(harness.changeCount == 0)
    }
}
#endif
