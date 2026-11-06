# Agent notes

Two iOS games share one Xcode project, `BiggerFish.xcodeproj`:

- **Bigger Fish** (`BiggerFish/`): the arcade game.
- **Math Reef** (`MathReef/`): the math practice app for kids, grades 1–5. This is where most work happens.
- **FishKit** (`Packages/FishKit/`): the shared fish engine both apps use. A change here affects both
  apps, so build and test both.

`README.md` has the fuller tour of each app's files.

## Build and test

Everything is iOS-only (FishKit imports UIKit), so tests run on a simulator. Use any available iPhone
simulator; `iPhone 17` is an example.

```bash
xcodebuild test -project BiggerFish.xcodeproj -scheme MathReef -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish -destination 'platform=iOS Simulator,name=iPhone 17'
cd Packages/FishKit && xcodebuild test -scheme FishKit -destination 'platform=iOS Simulator,name=iPhone 17'
```

The FishKit scheme inside the Xcode project can't run tests; run the package's tests from its own
folder as shown.

**Shut down every simulator you boot as soon as you're done with it** (`xcrun simctl shutdown <udid>`):
test runs, app runs, and screenshots alike. Simulators left running cost Kraig money: in October 2026
they ran up his Upstash bill. Leave alone any simulator you didn't boot.

CI (`.github/workflows/ci.yml`) tests only the app a pull request changes: the project tests both apps,
FishKit or CI changes test all three, and docs, scripts, and App Store listing text alone test nothing. A
pull request tests an optimized build (`-O`), so don't rely on `assert()`: use `precondition()` or a test.
A push to main runs nothing, since its pull request tested the merge; the nightly run tests all three in
Debug with coverage. CI uses the Xcode in `.xcode-version` and treats warnings as errors, so keep the build
warning-free.

The Bigger Fish planner tests re-plan a sample of Shallow Reef specs; CI re-plans every spec nightly. To
re-plan them all locally, put `TEST_RUNNER_BIGGER_FISH_FULL_PLANNER_TESTS=1` in xcodebuild's environment.

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Unit-test the game logic
(curriculum, facts, sessions, progress, rules); the SpriteKit scenes are checked by running the app.

## Conventions

- **Xcode picks up new files automatically.** The project uses folder-synced groups, so add files under
  `MathReef/` or `BiggerFish/` without editing `project.pbxproj`.
- **Never rename Math Reef level IDs.** They're the keys for saved progress. Generated fact decks use
  fixed seeds so they never change between launches.
- **Never lose Bigger Fish progress.** World IDs (`shallow-reef`, `jelly-bloom`, `kelp-forest`, `sunset-cove`, `midnight-zone`) and level
  numbers (`shallow-reef.8`) are the keys for saved progress: never rename them or renumber a released
  world's levels. Which layout plays in a numbered slot can change with Kraig's OK, since a cleared level
  stays cleared by its number (Shallow Reef's play order is `GameTuning.shallowReefOrder`). A new field in `ArcadeSave` must load when a save doesn't have it (decode it with a
  default), and `ArcadeCampaignTests` loads a real 0.1 save to prove old saves still work. Never change a
  field's type; add a new key instead.
  - **Progress is backed up to the player's iCloud** (key-value storage, `ArcadeProgress`) and merged at launch
    and on every iCloud change, so syncing only ever adds: cleared levels and seen screens are united, the faster
    best time wins, and a lesson or tutorial seen anywhere stays seen. A new `ArcadeSave` field needs a key in
    `ArcadeSave.CodingKeys` and a merge rule in `merged(withCloud:)` (the compiler asks for both), and fields a
    version doesn't know are kept as they were. Only the real save (standard defaults) syncs: never a save of
    its own, like the Debug playtest's or a store capture's. Anything that removes progress (Tuning > Players)
    must replace iCloud's copy, not merge with it. `ArcadeCloudSaveTests` covers all of this with a fake iCloud;
    tests never touch the real one.
- **Bigger Fish level design: iterate in code, freeze before publishing.** While a world's levels are being
  playtested, plan them in code at launch (Kelp Forest: `MeetingPlanner.kelpPlan`, milliseconds per level),
  so a fix is a one-line change Kraig can rebuild and play: a re-roll to another variation
  (`GameTuning.kelpRerolls`), a fish made a different size (`kelpFishRadius`), or turned to swim at you
  (`kelpSwimsAtYou`). Once a level is played and approved, freeze it: add it to the world's frozen set
  (`kelpFrozen`, `reefLabFrozen`, `jellyLabFrozen`, `midnightFrozen`, `sunsetFrozen`), regenerate the world's plans file with its marker (for Kelp
  Forest, `touch build/arcade-development/kelp-plans.request`, then run
  `MeetingPlannerTests/manualWriteKelpPlans()`), and commit the JSON. **Freeze every level before
  publishing (TestFlight or the App Store):** the shipped game loads saved plans and never plans a campaign level
  on the device, and a planner change can't alter a level players have. (The Open Water's levels are new every run,
  so they alone are planned on the device, just in time: `OpenWater.plan`.) To change a frozen level, take it out of the frozen
  set with Kraig's OK, tune it in code, and freeze it again.
- **Tuning constants stay in one place per app:** `ReefTuning` at the top of
  `MathReef/PracticeScene.swift` and `BiggerFish/GameTuning.swift`.
- **Debug-only tools go behind `#if DEBUG`.** Math Reef's Settings has crown previews and
  Multiplication progress shortcuts in Xcode builds only. Anything a kid or parent shouldn't see
  follows the same pattern.
- **Audio:** every sound's source and license goes in its app's credits file:
  `MathReef/Sounds/CREDITS.md` or `BiggerFish/Sounds/CREDITS.md`. Mixkit's
  *sound effects* license covers games; Mixkit's *music* license does not, so no Mixkit music in
  the apps. Bigger Fish's credits game also names the music's creators and the sound library in
  `BiggerFish/Credits.json` (with its play-testers); a test fails until the two files agree.
- **Privacy:** Math Reef is a kids' app. Don't add third-party analytics, ads, or tracking SDKs.
- **Analytics are first-party, anonymous counts only** (`MathReef/ReefAnalytics.swift`): no
  identifiers, timestamps, or device details. Any new event field must be added to the payload
  allowlist test in `MathReefTests/ReefAnalyticsTests.swift`, the brightbench.app privacy policy
  (kraigstrong/BrightBench, `apps/marketing/app/math-reef/privacy/page.tsx`), and
  `MathReef/PrivacyInfo.xcprivacy` before sending is enabled.
- **App Store listing text lives in `appstore/<app>/`** as plain files, pushed with `appstore/push.py` (see its
  README). The API key is in the 1Password Environment "App Store Connect", mounted at `~/.appstoreconnect/.env`:
  never copy it into a file or into chat, and dry-run every push before writing.
- **Purchases go behind the parental gate too.** Math Reef is free to try (`FreeSample` in
  `MathReef/ReefUnlock.swift`) with a one-time unlock; the unlock screen is only reachable through the
  gate. StoreKit test sessions can't run under `xcodebuild test`, so the purchase flow is checked by
  hand in Xcode against `MathReef.storekit`.
- **Links out of Math Reef go behind the parental gate** (`MathReef/ParentalGate.swift`), as the
  App Store's Kids category requires: web pages, email, and App Store links alike. Today that's the
  privacy policy and support pages on brightbench.app, reached from Settings > For grown-ups.

## Pull requests

- **Base:** branch from the latest `origin/main` and open PRs against `main`, for both apps and FishKit.
  (The old `codex/bigger-fish-integration` branch is retired.) Don't stack PRs on other PR branches.
- **Check before pushing:** PRs often merge quickly. Confirm a PR is still open before pushing more
  commits to its branch, and open a new PR if it has merged.
- **Commit messages:** start with the app (`Math Reef:` or `Bigger Fish:`) and a short summary, then
  explain the why in the body.
- **Releases:** each app archives from `main` at a tagged commit (`math-reef-v1.0.1`,
  `bigger-fish-v0.4-beta.1`). Unreleased work for one app can sit on `main` while the other ships: they're
  separate targets. From 1.0, Bigger Fish sells its unlock in every build (`ArcadeUnlock.isSelling`), TestFlight
  in the sandbox. Archive with the Xcode in `.xcode-version` or newer: only a build with the iOS 27.1 SDK fills an
  iPhone Duo's screens, and an older one runs there in a small 667×375 window.
