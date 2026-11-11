# Memory (facts learned while building; keep it short and current)

## Pins in use (added 2026-11-11, each release >= 14 days old that day)
- Xcode 26.0.1 on `macos-15` (`/Applications/Xcode_26.0.1.app`; 26.3 is also on the image).
- XcodeGen 2.46.0 (released 2026-07-16), `xcodegen.zip` SHA-256 `4d9e34b6…0196806`.
- SwiftLint 0.65.1 (2026-08-21), `portable_swiftlint.zip` SHA-256 `c1e429b0…ff694d0`.
- swift-snapshot-testing 1.19.7 (2026-10-21), `exact:`. Transitive pins in `Package.resolved`:
  swift-custom-dump 1.7.3 (2026-08-28), swift-issue-reporting 2.1.2 (2026-10-13), swift-syntax 604.0.0 (2026-09-15;
  resolved but never built: only InlineSnapshotTesting uses it), xctest-dynamic-overlay 1.13.1 (2026-08-27).
- `Package.resolved` holds BOTH swift-issue-reporting and xctest-dynamic-overlay (separate repos): swift-custom-dump
  1.7.3's `Package.swift` (read by local Swift 6.4) uses swift-issue-reporting, its `Package@swift-6.1.swift`
  (read by Xcode 26.0.1 / Swift 6.2) uses xctest-dynamic-overlay. With only one pin, CI's
  `-onlyUsePackageVersionsFromResolvedFile` fails ("out-of-date resolved file ... dependencies were added").
  Re-resolving locally drops nothing, but check both pins survive any `swift package update`.
- Actions: the web repo's SHAs (checkout v4.4.0, upload-artifact v4.6.2, setup-python v5.6.0, cache v4.3.0,
  setup-node v4.4.0). pytest 8.3.5 in the `tools` job.
- Web sources: `upstream.lock` WEB_SHA `5fed4454f2b948b7fc70501514692c9fd3fb6238` (travel-planner main, 2026-11-11):
  7 languages x 13 namespaces.

## Local toolchain (no Xcode; Command Line Tools, Swift 6.4)
- `swift test` needs `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
  (otherwise "plugin for module 'TestingMacros' not found"). `--build-system native` can't find `Testing` at all.
- The CLT have no actool/xcstringstool (asset and String Catalogs fail to build) and no XCTest (SnapshotTesting
  fails). `VOYAGERKIT_LOCAL=1` drops those resources, TestSupport and the view-level test targets.
- The snapshot dependency stays declared in local mode: with no dependencies SwiftPM deletes `Package.resolved`.
- SwiftLint runs locally with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` (sourcekitdInProc lives there).
- XcodeGen runs locally (inspect the generated pbxproj); XcodeGen's iOS preset puts `CODE_SIGN_IDENTITY` at target
  level, so per-SDK overrides must be target settings in `project.yml`, not only in the xcconfig.

## Behaviour notes
- `JSONEncoder` does not keep a keyed container's insertion order: deterministic JSON needs `.sortedKeys`
  (`JSONValue.jsonData()` / `jsonString()`).
- `gen_golden.mjs` loads web modules through the checkout's Vite SSR loader: web utils import `../i18n`, which uses
  Vite-only `import.meta.glob`, and use extensionless imports, so plain Node `import()` fails.

## Runner (macos-15)
- `iPhone 16` and `iPad Pro 13-inch (M4)` exist on the iOS 26.0 runtime with Xcode 26.0.1.
- A UI test run can hang after the build, before the first test case (runner/simulator launch); xcodebuild's
  test timeouts don't cover that. `test-ui.sh` pre-boots the simulator, runs `test-without-building` under a
  hard per-attempt limit and retries once on an erased simulator; the ui-smoke job has `timeout-minutes: 25`.
- A unit run (build + 44 tests + app build) takes about 9 min on `build-test`; iPad ui-smoke about 4.5 min.
