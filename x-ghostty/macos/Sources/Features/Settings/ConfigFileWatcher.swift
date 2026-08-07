#if os(macOS)
import Foundation

/// Watches the configuration files on disk and invokes a callback when any
/// of them changes externally.
///
/// The primary motivation is that `open_config` hands the raw config file to
/// a GUI editor whose autosave can silently persist accidental keystrokes.
/// The running app keeps its in-memory config, so without a watcher such
/// corruption only surfaces at the next launch (typically a reboot), long
/// after the user has lost context. Reloading on every external change makes
/// both intentional edits and corruption visible within a second, and lets
/// the existing configuration-errors window point at the exact bad line.
class ConfigFileWatcher {
    /// The file paths being watched. Files don't need to exist; their parent
    /// directories are watched so creations and atomic-rename saves are seen.
    let paths: [String]

    private let onChange: () -> Void
    private let queue: DispatchQueue
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounce: DispatchWorkItem?

    /// Last observed (mtime, size) per path. Used to ignore directory events
    /// that don't actually touch a watched file (e.g. unrelated files in the
    /// same directory).
    private var states: [String: FileState] = [:]

    private struct FileState: Equatable {
        var mtime: Date?
        var size: Int64?

        init(path: String) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            mtime = attrs?[.modificationDate] as? Date
            size = (attrs?[.size] as? NSNumber)?.int64Value
        }
    }

    init(
        paths: [String],
        queue: DispatchQueue = .main,
        onChange: @escaping () -> Void
    ) {
        self.paths = paths
        self.queue = queue
        self.onChange = onChange
        for path in paths {
            states[path] = FileState(path: path)
        }
        arm()
    }

    deinit {
        debounce?.cancel()
        disarm()
    }

    /// The default configuration file paths for this app, mirroring the load
    /// order in `src/config/file_load.zig` (XDG and Application Support, each
    /// with the legacy extensionless name and the current name).
    static func defaultPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let fm = FileManager.default
        var result: [String] = []

        let xdgBase: URL = if let env = environment["XDG_CONFIG_HOME"], !env.isEmpty {
            URL(fileURLWithPath: NSString(string: env).expandingTildeInPath)
        } else {
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let xdgDir = xdgBase.appendingPathComponent("xghostty")
        result.append(xdgDir.appendingPathComponent("config").path)
        result.append(xdgDir.appendingPathComponent("config.xghostty").path)

        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleId = Bundle.main.bundleIdentifier ?? "com.mitchellh.xghostty"
            let dir = appSupport.appendingPathComponent(bundleId)
            result.append(dir.appendingPathComponent("config").path)
            result.append(dir.appendingPathComponent("config.xghostty").path)
        }

        return result
    }

    private func arm() {
        // Watch every existing watched file directly, plus each unique parent
        // directory. The directory watch is what catches atomic-rename saves
        // (most editors) and file creation/deletion, after which the stale
        // file descriptor for the old inode is useless — hence full re-arm
        // on every event.
        var watchPaths = Set(paths.filter { FileManager.default.fileExists(atPath: $0) })
        for path in paths {
            let dir = (path as NSString).deletingLastPathComponent
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                watchPaths.insert(dir)
            }
        }

        for path in watchPaths {
            let fd = open(path, O_EVTONLY)
            if fd < 0 { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleCheck()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func disarm() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    private func scheduleCheck() {
        // Debounced so editor save sequences (truncate + write + rename +
        // attribute changes) produce a single reload.
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.check()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(500), execute: work)
    }

    private func check() {
        disarm()
        arm()

        var changed = false
        for path in paths {
            let state = FileState(path: path)
            if state != states[path] {
                states[path] = state
                changed = true
            }
        }
        if changed { onChange() }
    }
}
#endif
