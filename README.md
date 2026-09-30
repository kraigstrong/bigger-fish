# Bigger Fish

There's always a bigger fish.

V0 prototype: a one-touch iPhone game (landscape, SwiftUI + SpriteKit, iOS 17+).
Hold to rise. Release to fall. Eat fish smaller than you. Avoid fish larger than you. Become the last fish swimming.

## Running

Open `BiggerFish.xcodeproj` in Xcode, pick your iPhone or a simulator, and Run.
Signing uses automatic signing with team `MKACSCQ588`.

Unit tests (wrapping, size rules, growth, win detection):

```bash
xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Layout

This repo builds two separate apps from one Xcode project (`BiggerFish.xcodeproj`), each with its own scheme:

- `BiggerFish/` — **Bigger Fish**, the arcade game: campaign rules, levels, tuning, and scene.
- `MathReef/` — **Math Reef** (`com.kraigstrong.mathreef`), the education app for grades 1–5. Pick a
  world (Addition, Subtraction, Multiplication, Division, Exponents), then a level,
  and swim into the right answer. Addition and subtraction climb in small strategy steps (+1/+2, make 10,
  doubles, near doubles, past 10, then 2-digit up to carrying/borrowing). A round asks every question in
  the level plus 3 review questions from earlier levels (none in Exponents, where squares in a Cubes round
  would read as mistakes). Stars come from accuracy (right answers out of
  tries): 60% ★, 80% ★★, 100% ★★★; two stars unlocks the next level.
  Checkpoint levels are skip tests: always playable, and passing one passes everything before it.
  Worlds sit on a reef map and levels along a scrolling path. A world earns a silver crown when every
  level is passed and a gold crown for three stars everywhere. Progress is saved on the device.
  - `MathFacts.swift` — facts, solutions, and plausible wrong answers
  - `Curriculum.swift` — worlds, levels, and fact decks
  - `Progress.swift` — stars, passing, and saved progress
  - `PracticeSession.swift` — dealing and requeueing within a round
  - `ReefMaps.swift` — the reef (world) map and the level path
  - `ReefUI.swift` — shared labels, stars, crowns, and world colors
  - `ParentalGate.swift` — the grown-ups-only question guarding the privacy and support links and the unlock
  - `ReefUnlock.swift` — the free sample (first 3 levels per world, 1 in Exponents) and the one-time StoreKit unlock; `MathReef.storekit` at the repo root backs it when running from Xcode
  - `PracticeScene.swift` — screen flow and gameplay; tuning is `ReefTuning` at the top
  - `ReefAnalytics.swift` — anonymous first-party counts (milestones and round outcomes), queued on the device and sent in batches to brightbench.app (off during test runs)
- `Packages/FishKit/` — shared fish engine used by both apps:
  the fish model and drawing, hold/release movement (`PlayerMotion` + `MotionTuning`), wrapped world,
  seeded RNG, swallow timing, and water textures.

FishKit tests:

```bash
cd Packages/FishKit && xcodebuild test -scheme FishKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Tuning

Every feel constant — movement, growth, swallow timing, AI behavior, spawn distribution,
and the `aiFishCanEatEachOther` flag — lives in `BiggerFish/GameTuning.swift`.
The five levels are defined in `GameTuning.levels`; each sets the spawn mix, fish speeds,
player speed, and how much a meal grows you.
