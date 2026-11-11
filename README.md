# travel-planner-ios

Voyager, the native iOS app (SwiftUI, iPhone and iPad) for the AI travel planner
[rupakc/travel-planner](https://github.com/rupakc/travel-planner). It has parity with the web app and the
Android app ([rupakc/travel-planner-android](https://github.com/rupakc/travel-planner-android)).

- iOS 17.0+, iPhone and iPad (all iPad orientations, Split View, Slide Over, Stage Manager)
- Swift 6 (strict concurrency), SwiftUI, Observation, `URLSession` async/await, no third-party runtime code
- Colours, strings (7 languages) and the telemetry registry are vendored from the web repo at one pinned commit
  (`upstream.lock`) and generated into an asset catalog and String Catalogs, so the web stays the single source

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec for the `Voyager` app and `VoyagerUITests` (the `.xcodeproj` is generated, never committed) |
| `Config/` | `Base`/`Debug`/`Release.xcconfig`: bundle id, base URL, trusted hosts |
| `App/` | The app target: entry point, entitlements, privacy manifest, assets |
| `Packages/VoyagerKit/` | All code: one Swift package with a target per layer and per feature |
| `UITests/` | XCUITest smoke tests |
| `Upstream/` | Files vendored from `travel-planner` (`scripts/upstream/sync.sh`) |
| `tools/` | Python generators and tests, the golden-fixture generator |
| `scripts/ci/` | Everything CI runs (bootstrap, generate, lint, tests, builds) |
| `docs/` | Developer docs; `docs/reference/` holds the API contract and the web UI inventory |

## Building

There is no Xcode in the development setup: GitHub Actions (`macos-15`, Xcode 26.0.1) builds, lints and tests
every pull request. See [CLAUDE.md](CLAUDE.md) for the commands, and [CONTRIBUTING.md](CONTRIBUTING.md).

With Xcode installed you can also build locally:

```bash
eval "$(scripts/ci/bootstrap.sh)"   # pinned XcodeGen + SwiftLint
scripts/ci/generate.sh              # Voyager.xcodeproj
open Voyager.xcodeproj
```

## License

MIT, see [LICENSE](LICENSE). Bundled fonts (Inter, Sora) are under the SIL Open Font License.
