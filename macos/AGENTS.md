# macOS XGhostty Application

- Use `swiftlint` for formatting and linting Swift code.
- If code outside of `macos/` directory is modified, use
  `zig build -Demit-macos-app=false` before building the macOS app to update
  the underlying Ghostty library.
- Use `macos/build.sh` to build the macOS app, do not use `zig build`
  (except to build the underlying library as mentioned above).
  - Build: `macos/build.sh [--scheme XGhostty] [--configuration Debug] [--action build]`
  - Output: `macos/build/<configuration>/XGhostty.app` (e.g. `macos/build/Debug/XGhostty.app`)
- Run unit tests directly with `macos/build.sh --action test`
