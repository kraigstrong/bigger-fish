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
folder as shown. CI runs all three on every pull request (`.github/workflows/ci.yml`).

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Unit-test the game logic
(curriculum, facts, sessions, progress, rules); the SpriteKit scenes are checked by running the app.

## Conventions

- **Xcode picks up new files automatically.** The project uses folder-synced groups, so add files under
  `MathReef/` or `BiggerFish/` without editing `project.pbxproj`.
- **Never rename Math Reef level IDs.** They're the keys for saved progress. Generated fact decks use
  fixed seeds so they never change between launches.
- **Never lose Bigger Fish progress.** World IDs (`shallow-reef`, `jelly-bloom`, `kelp-forest`) and the
  numbering of a released world's levels are the keys for saved progress: don't rename, reorder, or
  renumber them. A new field in `ArcadeSave` must load when a save doesn't have it (decode it with a
  default), and `ArcadeCampaignTests` loads a real 0.1 save to prove old saves still work.
- **Tuning constants stay in one place per app:** `ReefTuning` at the top of
  `MathReef/PracticeScene.swift` and `BiggerFish/GameTuning.swift`.
- **Debug-only tools go behind `#if DEBUG`.** Math Reef's Settings has crown previews and
  Multiplication progress shortcuts in Xcode builds only. Anything a kid or parent shouldn't see
  follows the same pattern.
- **Audio:** every sound's source and license goes in its app's credits file:
  `MathReef/Sounds/CREDITS.md` or `BiggerFish/Sounds/CREDITS.md`. Mixkit's
  *sound effects* license covers games; Mixkit's *music* license does not, so no Mixkit music in
  the apps.
- **Privacy:** Math Reef is a kids' app. Don't add third-party analytics, ads, or tracking SDKs.
- **Analytics are first-party, anonymous counts only** (`MathReef/ReefAnalytics.swift`): no
  identifiers, timestamps, or device details. Any new event field must be added to the payload
  allowlist test in `MathReefTests/ReefAnalyticsTests.swift`, the brightbench.app privacy policy
  (kraigstrong/BrightBench, `apps/marketing/app/math-reef/privacy/page.tsx`), and
  `MathReef/PrivacyInfo.xcprivacy` before sending is enabled.
- **Purchases go behind the parental gate too.** Math Reef is free to try (`FreeSample` in
  `MathReef/ReefUnlock.swift`) with a one-time unlock; the unlock screen is only reachable through the
  gate. StoreKit test sessions can't run under `xcodebuild test`, so the purchase flow is checked by
  hand in Xcode against `MathReef.storekit`.
- **Links out of Math Reef go behind the parental gate** (`MathReef/ParentalGate.swift`), as the
  App Store's Kids category requires: web pages, email, and App Store links alike. Today that's the
  privacy policy and support pages on brightbench.app, reached from Settings > For grown-ups.

## Pull requests

- **Base:** branch from the latest `origin/main` and open PRs against `main`. Don't stack PRs on other
  PR branches.
- **Check before pushing:** PRs often merge quickly. Confirm a PR is still open before pushing more
  commits to its branch, and open a new PR if it has merged.
- **Commit messages:** Math Reef commits start with `Math Reef:` and a short summary, then explain the
  why in the body.
