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

## Phase 3 rulings
- Ruling: `AlertsV2Service.quickWatch` is a watch create path and fires `watchesChanged()` itself (not the view); `existing: true` and failures do not. Why: TripReminderScheduler.refresh and the poll must follow every create. Cost if wrong: a stale poll until the next launch.
- Ruling: an advice 503 maps to `ai_limit` (the 5xx body is dropped by `ErrorMapping`); `ai_billing` shows the same copy. Cost: none visible.

## Task 3.3 rulings
- Ruling: the drop moment is an inline card in the inbox row (via `InboxRowSlot`), not a modal; the row's own tap opens the watch's story. Game wording uses `GameVisibility` with `features.game` and an account `hide_game` that the app cannot read yet (no account-settings sync), so it counts as hidden and the XP / badge line stays off until that sync exists. Why: plan R4 and "an unreadable setting counts as hidden". Cost if wrong: owners with the game on see no XP line until the sync lands.
- Ruling: `DigestWatch` also reads `currency` (sent by `alert_digest`, absent from the frozen contract); without it prices show as plain numbers, never a guessed symbol. A digest row tap opens the Alerts page and sends `alert_digest_open` (`via: in_app`). Cost if wrong: none (additive).
- Ruling: the "Share savings" button shows only with `features.sharing >= 1` and something caught; it calls `router.open(.shareSheet(.savings))`, wired for real in 4.4.

## Phase 6 rulings (Task 6.1)
- Ruling: a failed settings save (a `422 notification_settings_invalid` included) undoes the change and shows the web's "It was undone" copy; the plan's `test_invalidKeepsDraft` is `test_invalidIsUndoneWithAMessage`. Why: the web copy says "undone", toggles and a stepper have no draft to fix. Cost if wrong: none visible.
- Ruling: the quiz switch is shown only when `GameVisibility.showsGame`. The account's `hide_game` is not read anywhere yet, so `NotificationSettingsModel.defaultGameVisibility(env:)` reports it unreadable (= hidden) until the account/Play work injects a reader. Why: global rule, an unreadable setting counts as hidden. Cost: quiz switch missing until then.
- Ruling: no new strings; every label comes from the web `notifications` namespace and `mobile:notifSettings.*` / `mobile:permissions.*` (all 7 languages already vendored). The registered-device count is shown only as the `noDevices` note (0 devices with a live APNs key), not as a number: no catalogue string for a count exists.
- Ruling: `NotificationGate.decide` has no clock or counters of its own: the caller (6.2's poller) passes `now` and the bucket's `deliveredToday` (price kind for price rows, `daily_cap` bucket otherwise). Unknown kinds and `quiz_*` while the game is hidden are dropped locally (the inbox row stays). A hold over 12 h is dropped like the server does.
- Ruling: the notification catalog is cached per locale in `Library/Caches` (`notification-catalog-<locale>.json`, 24 h TTL), a failed fetch serves the stale file, then the bundled English subset (`NotificationCatalog.bundledEnglish`); callers use `render`, which returns nil unless every `{placeholder}` can be filled.
- Ruling (owner follow-up "personalized near-you note"): it fits R10, so it is built in Task 6.3, not here. 6.3's `NearYouNotifier` runs on scene-active in an active trip phase with when-in-use permission only, calls the existing non-grounded v1 `POST /nearby` (location stays in memory, no new endpoint, no coordinates in telemetry), fills `nearby_arrival` from the catalog, and falls back to `mobile:nearYou.fallbackTitle/Body` (already vendored) when `/nearby` gives nothing or fails. Task 6.1 owns no location code, so it only supplies the catalog (`NotificationCatalogRepository`, `NotificationCatalog.render`) and the `nearby` switch.

## Phase 4 rulings
- Ruling: `ShareFailure` lives in `VoyagerEnv` (features may not import `VoyagerData`) and reads 404 codes from the envelope's fixed `detail` text, because `ErrorMapping` keeps only `detail` for a 404. Why: no `APIError` change for one feature. Cost if wrong: a reworded backend 404 shows the generic copy.
- Ruling: `ShareCardLoading`, `LiveShareCardLoader` and `ShareCardStore` live in `VoyagerEnv/Phase4` (not `FeatureShare/Create`) so `TestSupport` can fake them. Why: TestSupport cannot import features. Cost: none.
- Ruling: the one new string ("Sharing this again updates the same link...") is a pending English key (`i18n/pending/en/share.json`) until Task 41 translates it; every other string is an existing web `share:` / `mobile:share.*` key in all 7 languages. Cost: one English line in six languages until Task 41.
- Ruling: `FeatureShare` Create is built on main only; T29's `ShareLinkButton` (#47, unmerged) is untouched, so no entry point opens `.shareSheet` yet (Task 4.4).

## Task 4.2 rulings (My shares)
- Ruling: "Stop sharing" confirms inline in the row (the web's `mine.confirm`/`yes`/`no` copy, no Undo, says the loss of access is immediate) instead of a `confirmationDialog`, so the confirmation is snapshot-testable and reads the same at AX5. Cost: not the system action sheet.
- Ruling: legacy plan links are revoked with `DELETE /plans/{id}/share` through `SharesRepository.revokeLegacyPlanShare` (a 404 counts as already gone); "Open" on a legacy row reads the token from its URL.
- Ruling: "Share again" opens `ShareSheetView` over the list, starting from the link's own options (so a second share never resets them to private); only plan, recap and savings rows offer it (quiz and status need a session or active trip the list does not carry).
- Ruling: a pasted link opens only as `voyager://share/<token>` or `https://<trusted host>/share/<token>` (`ShareLinkParser`, the `DeepLinks` allow-list; 8-64 URL-safe characters); anything else shows `mobile:share.openLinkInvalid`.
- Ruling: one new string, `share:mine.shareAgain` ("Share again"), is a pending English key until Task 41.

## Task 5.1 rulings (Social and Play core)
- Ruling: `SocialFailure` / `PlayFailure` live in `VoyagerData` (beside the repositories) and read 409/410/422 codes from the envelope but 403/404 codes from the backend's fixed `detail` texts, because `ErrorMapping` keeps only `detail` for 403 and 404 (as for `ShareFailure`). A plain `Not found` (ours for `social_disabled` / `play_disabled`, FastAPI's `Not Found` for a missing route) turns that feature off for the session; every other 404 (`Profile not found.` ...) keeps it on. Cost: a reworded backend text degrades to the backend `detail`; the lasting fix is an additive `code` on `APIError.forbidden/notFound` (follow-up).
- Ruling: `SocialService` / `PlayService` (`VoyagerEnv/Phase5`) expose one `call { repo in ... }` door instead of 30 forwarding methods; both reset on every user switch (`observeAuth`). Play gates on `features.play` alone (the server already folds `GAME_ENABLED` into it), then on `hideGameSetting` (nil today: the account setting is not readable yet, so the server's `403 game_hidden` hides Play for the session) and `PlayService.isHiddenByServer`. Cost: one wasted call for a hide_game user until the setting sync exists.
- Ruling: the contract does not spell the elements of `answers` (resumed session) or the `GET /play/history` wrapper. `GivenAnswer` needs only `index`; `QuizHistory` accepts a bare array or `history|sessions|entries|items` (stub uses `history`). Gap logged per R17: ask web to freeze both.
- Ruling: a question is supported only with a known `prompt.template` and at least two options; an unknown template degrades to "update the app" for that question (5.4). `H2HMatch` drops `them` and `winner` unless the state is `done`, even if the server sent them.
- Ruling: the AppShell composition of R12 (Ideas segment in Discover, Play and Profile rows in You) lands with the screens in 5.2-5.5; 5.1 only wires `env.social`, `env.play`, `Repositories.social|play` and the fakes. No upstream sync was needed (the vendored SHA already has the social, play, socialShare, playYou and game catalogues and the registry events). The four notification templates (`idea_saved`, `new_follower`, `h2h_invite`, `h2h_result`) are added to the Phase 6 stub catalog; kinds, categories and links were already handled by 6.1/6.2.
- Task 5.3 (Ideas feed): Ideas is a segment of the Discover tab (`router.showsIdeas`), detail is `Route.ideaDetail`, publishing is the new `Route.publishIdea` sheet opened from the share sheet ("Share to Ideas"; waits for the share sheet to close). Support row URL comes from `VOYAGER_SUPPORT_URL` (empty hides it). No avatars (privacy, offline snapshots); no "forget save" UI (no catalogue string; model call exists). Rules acceptance (R13) belongs to 5.2's profile editor.
