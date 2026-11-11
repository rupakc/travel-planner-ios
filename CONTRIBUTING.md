# Contributing

1. Branch from `main`; one change per pull request. Commits are by `rupakc` (noreply) with conventional prefixes
   (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
2. Write the tests first. Python tools: `python3 -m pytest -q tools/tests`. Swift: see "Local checks" in
   [CLAUDE.md](CLAUDE.md); CI on the iOS simulator is the authority.
3. Keep to the module graph in `Packages/VoyagerKit/Package.swift`. Features never import each other. A new
   dependency edge is its own small pull request.
4. No literal UI strings (`L10n` only), no raw colours (generated tokens only), no third-party runtime code.
   SwiftLint (`.swiftlint.yml`) enforces these with `--strict`.
5. Never hand-edit generated files (`Upstream/`, `**/Generated/`, `Localizable.xcstrings`, `Colors.xcassets`,
   golden fixtures); change the input and regenerate.
6. Open the pull request and get the `ios-ci` checks green. Don't push every small commit: each run costs macOS minutes.

Pins: GitHub Actions by commit SHA, tools in `tools.lock` with SHA-256, the web sources in `upstream.lock`. A new
pin must be a release at least 14 days old on the day it is added.
