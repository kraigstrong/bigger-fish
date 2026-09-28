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
- `MathReef/` — **Math Reef** (`com.kraigstrong.mathreef`), the education app: exponent practice
  (squares, cubes, mixed) where you swim into the right answer. Question and session logic is in
  `Exponents.swift`, the scene in `ExponentScene.swift`, and tuning in `ReefTuning` at the top of that file.
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
