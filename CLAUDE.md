# Voyager iOS

Native SwiftUI app (iPhone + iPad, iOS 17.0+) for the AI travel planner. Web repo (source of truth for API,
strings, colours, telemetry): `rupakc/travel-planner`. Android parity reference: `rupakc/travel-planner-android`.
Plan: `docs/superpowers/plans/2026-11-11-ios-app.md`. Bundle id `io.github.rupakc.travelplanner`, display name
"Voyager", URL scheme `voyager`. MIT.

## Layout

- `project.yml`: XcodeGen spec (app `Voyager`, `VoyagerUITests`; schemes `Voyager`, `VoyagerUI`). The app links only
  the `AppShell` product. `Voyager.xcodeproj` and `App/Info.plist` are generated, never committed.
- `Config/{Base,Debug,Release}.xcconfig`: bundle id, versions, Swift 6 settings, `VOYAGER_BASE_URL`,
  `VOYAGER_TRUSTED_HOSTS` (read at runtime from Info.plist keys `VoyagerBaseURL`, `VoyagerTrustedHosts`).
- `App/`: `VoyagerApp.swift`, entitlements, `PrivacyInfo.xcprivacy`, `Resources/Assets.xcassets`.
- `Packages/VoyagerKit/`: all code. `Package.swift` declares every target, test target and dependency edge; later
  work only adds files inside its own target. Features never import each other (navigation goes through
  `env.router.open(Route)`). A new edge is a manifest change in its own small PR.
  - Test-only libraries: `TestFixtures` (Foundation only; `Fixtures.url/data/string/sseDataLines` read
    `Tests/Fixtures/` via `#filePath`) and `TestSupport` (fakes, snapshot helpers; re-exports TestFixtures).
    Neither is reachable from `AppShell`, so neither (nor swift-snapshot-testing) is ever linked into the app.
  - Every test target depends on `TestFixtures`. View-level test targets (`SharedUITests`, `SectionsUITests`,
    `VoyagerEnvTests`, `AppShellTests`, every `Feature*Tests`) also get `TestSupport` + `SnapshotTesting` and keep
    snapshots in their `__Snapshots__/` (excluded from sources).
  - Shared fixtures: `Tests/Fixtures/sse/*.sse` (from Android), `Tests/Fixtures/golden/<name>/<case>.json`.
- `Upstream/`: vendored web files at `upstream.lock` (`locales/<lang>/<ns>.json`, `tokens.json`, `registry.py`,
  exported `telemetry_registry.json`, `SOURCE`). Never edit by hand.
- `tools/`: Python 3.12 stdlib generators + `tools/tests` (pytest); `tools/golden/gen_golden.mjs`.
- `scripts/ci/`: what CI runs; `scripts/upstream/sync.sh`; `scripts/fonts/fetch.sh`.
- `docs/reference/`: API contract and web UI inventory (`docs/API-Reference.md` in travel-planner wins on conflict).

## How things are verified (no local Xcode)

Everything Xcode-shaped runs on GitHub Actions `macos-15` with Xcode 26.0.1 (`.github/workflows/ios-ci.yml`):

- Pull request: `tools` (ubuntu: pytest, shellcheck, upstream drift, generator `--check`, golden `--check` when
  there are cases) then one macOS job `build-test`: bootstrap → select Xcode → `swiftlint lint --strict` →
  generate → unit tests on the iPhone simulator → "Test summary" → app build for the simulator.
- Push to `main`, or `workflow_dispatch` with `full=true`: also `ui-smoke` (iPhone + iPad); `archive` on main only.
- Filtered run / snapshot recording:
  `gh workflow run ios-ci.yml --ref <branch> -f only_testing=DomainTests` (comma-separated `-only-testing:` values),
  add `-f record_snapshots=true` to record, then `gh run download <id> -n snapshots -D Packages/VoyagerKit/Tests`.
- Prefer the PR run. Batch commits: every push costs macOS minutes (max ~5 concurrent macOS jobs).
- Zero warnings: the app sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`; `test-unit.sh` fails on any `warning:` from a file
  under `Packages/VoyagerKit/Sources` or `App`.

## Local checks

- Python: `python3 -m pytest -q tools/tests`; `shellcheck -x scripts/**/*.sh`.
- Swift (Command Line Tools, Swift 6.4, Swift Testing): `Package.swift` also declares `.macOS(.v14)` only so
  Foundation-level targets can be compiled and tested locally:
  ```bash
  cd Packages/VoyagerKit
  VOYAGERKIT_LOCAL=1 swift test --filter VoyagerModelTests \
    -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
  ```
  (Without the plugin path the CLT fail with "plugin for module 'TestingMacros' not found"; `--build-system
  native` cannot find `Testing` at all.)
  `VOYAGERKIT_LOCAL=1` drops what the CLT cannot build (asset/String Catalog resources, XCTest-based
  SnapshotTesting, TestSupport and the view-level test targets). Never set it on CI. Local failures caused only
  by macOS (Keychain entitlements, UIKit) are fine; the simulator run is the authority. Do not add macOS code
  paths beyond `#if canImport(UIKit)` guards.
- SwiftLint: `eval "$(scripts/ci/bootstrap.sh)" && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools scripts/ci/lint.sh`.
- XcodeGen also runs locally (`xcodegen generate`) to inspect the generated project; it cannot build.

## Generators (outputs are committed; CI fails on drift)

- `scripts/upstream/sync.sh [sha]`: sparse, shallow fetch of the web repo at a SHA → `Upstream/`, exports the
  telemetry registry (`tools/export_registry.py`, also copied to `Tests/TelemetryTests/Resources/`), updates
  `upstream.lock`. Bump the SHA only with this script.
- `tools/gen_tokens.py [--check]` (Task 2): `Upstream/tokens.json` → `Colors.xcassets` + `Generated/Palette.swift`.
- `tools/gen_catalog.py [--check]` (Task 3): `Upstream/locales` + `i18n/pending/en` → `Localizable.xcstrings`,
  `Generated/Keys.swift`, `App/Resources/InfoPlist.xcstrings`.
- `TZ=UTC node tools/golden/gen_golden.mjs <travel-planner checkout> [--check]`: runs web utils on
  `tools/golden/cases/<name>.json` and writes `Tests/Fixtures/golden/<name>/<case>.json`. Needs `npm ci` in the
  checkout's `frontend/` (it uses that checkout's Vite to load the modules). Use a checkout at `WEB_SHA`.
- `scripts/ci/generate.sh`: runs the generators that exist, then XcodeGen, and copies `Package.resolved` into the
  generated project so the app resolves the same package versions.
- `scripts/fonts/fetch.sh`: fonts from `font:*` lines in `tools.lock` (SHA-256 checked) into DesignSystem.

## Conventions

- Swift 6 language mode, complete strict concurrency, zero warnings, in every target.
- Strings only through `L10n`; `Text(verbatim:)` for brand names and backend data. SwiftLint's `no_literal_text`
  bans `Text("…")` in sources; previews with literal text go in `*Previews.swift` files. Colours only from
  generated tokens (`no_raw_color`). Also banned: `print(`, `DispatchQueue.main.sync`, `try!` outside tests.
- Pins: actions by commit SHA (the ones the web repo uses), tools in `tools.lock` (version, URL, SHA-256), the
  only third-party package `swift-snapshot-testing` `exact: "1.19.7"` (test targets only), XcodeGen 2.46.0,
  SwiftLint 0.65.1, Xcode 26.0.1. A new pin must be a release at least 14 days old when added.
- CI shape (R1): PRs get `tools` + one macOS `build-test`; no iPad unit job (unit tests are device-agnostic; iPad
  layouts are covered by iPad snapshot configs and `ui-smoke (ipad)`).
- Fixtures (R4): shared files under `Packages/VoyagerKit/Tests/Fixtures/`, read through `TestFixtures`.
- Base URL (R5): Debug `http://127.0.0.1:8001`; Release `$(VOYAGER_PROD_BASE_URL)` =
  `https://35-207-18-35.sslip.io`, trusted hosts `35-207-18-35.sslip.io`. CI's archive overrides each only when
  the repo variable of the same name is non-empty. A custom domain later is a config change.
- Two-way compatibility with the backend: feature-detect every endpoint newer than today's API (`/api/config`,
  `/api/auth/providers`, `/api/telemetry`, `POST /api/devices` for `ios` may 404/422) and degrade silently.
- Git: commits as `rupakc` (noreply); never commit `.superpowers/` or `.worktrees/`; PRs via `~/.local/bin/gh`.
