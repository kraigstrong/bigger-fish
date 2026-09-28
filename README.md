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
- `MathReef/` — **Math Reef** (`com.kraigstrong.mathreef`), the education app. Pick a world (Addition,
  Subtraction, Mixed + −, Multiplication, Division, Mixed × ÷, Exponents; Fractions coming soon), then a
  level, and swim into the right answer. A round asks every fact in the level (at least 10 questions);
  get 90% right to pass and unlock the next level. Progress is saved on the device.
  - `MathFacts.swift` — facts, solutions, and plausible wrong answers
  - `Curriculum.swift` — worlds, levels, and fact decks
  - `Progress.swift` — the 90% pass rule and saved progress
  - `PracticeSession.swift` — dealing and requeueing within a round
  - `PracticeScene.swift` — menus and gameplay; tuning is `ReefTuning` at the top
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
