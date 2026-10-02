# Bigger Fish

There's always a bigger fish.

Arcade prototype: a one-touch iPhone game (landscape, SwiftUI + SpriteKit, iOS 17+).
Hold to rise. Release to fall. Eat fish smaller than you. Avoid fish larger than you. Become the last fish swimming.

The world map opens **Shallow Reef** (the original five levels) and **Jelly Bloom** (five new levels).
Each world unlocks its levels sequentially; clears and fastest times stay on the device. Jelly Bloom
adds safe dome bounces and lethal tentacles, with food pockets above stepped and chained bounce routes.
A few larger fish become edible through growth; no chasing, fleeing, or urchins. Shallow Reef keeps
the original drift behavior and tuning. Both worlds use numbered levels.

This playable slice has no purchases, endless mode, pearls, or shop yet. See
[`docs/bigger-fish-playable-scope.md`](docs/bigger-fish-playable-scope.md) for the accepted scope and deferred vision.

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
  - `ArcadeMaps.swift` — world selection and the five-stop level paths
  - `ArcadeCampaign.swift` / `ArcadeProgress.swift` — stable level IDs and local campaign saves
  - `Jellyfish.swift` / `ArcadeArt.swift` — arcade-only hazard rules and procedural artwork
  - `ArcadeAudio.swift` / `Sounds/` — copied sound effects; source credits stay alongside them
  - `ArcadePlaytest.swift` — debug-only isolated level launches for playtesting
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
  - `ReefReview.swift` — queues a native App Store review request after a successful round with a crown;
    presents on the next Settings > For grown-ups gate pass, with one more opportunity after a
    successful round at least 90 days later (two requests total). Timing stays on-device. TestFlight
    and Xcode builds don't consume requests; Xcode has a gated review-sheet preview.
  - `ReefUnlock.swift` — the free sample (first 3 levels per world, 1 in Exponents) and the one-time StoreKit unlock; `MathReef.storekit` at the repo root backs it when running from Xcode
  - `PracticeScene.swift` — screen flow and gameplay; tuning is `ReefTuning` at the top
  - `ReefAnalytics.swift` — anonymous first-party counts (milestones and round outcomes), queued on the device and sent in batches to brightbench.app (off during test runs)
  - `StoreCapture.swift` — debug-only staged scenes and an autopilot for App Store screenshots and the preview video
- `Packages/FishKit/` — shared fish engine used by both apps:
  the fish model and drawing, hold/release movement (`PlayerMotion` + `MotionTuning`), wrapped world,
  seeded RNG, swallow timing, and water textures.

FishKit tests:

```bash
cd Packages/FishKit && xcodebuild test -scheme FishKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## App Store screenshots and preview

`scripts/store-capture.sh` builds Math Reef in Debug, then launches it on the iPhone 17 Pro Max
simulator with `-storeCapture <scene>`. That stages believable progress in its own saved state,
leaving real progress, purchases, and analytics alone, and lets an autopilot play. Output goes to
`build/store-capture/` (ignored by git). It needs ffmpeg (`brew install ffmpeg`), and the video
also needs NumPy (`python3 -m pip install numpy`).

```bash
scripts/store-capture.sh screenshots
STORE_CAPTURE_DEVICE='iPhone 13 Pro Max' STORE_CAPTURE_OUT="$PWD/build/store-capture-6.5" scripts/store-capture.sh screenshots
scripts/store-capture.sh video
python3 scripts/store-preview.py build/store-capture/video/full.mp4 build/store-capture/video/preview.mp4 1.8-3.8 4.0-6.0 6.1-7.3 7.3-12.8 19.8-25.3 67.7-78.0
```

- **Screenshots** are 2868×1320 PNGs (the 6.9" size) with no alpha, saved by the app itself
  (simulator screenshots have the Dynamic Island drawn over them). Play scenes and the crown save
  a burst of frames to pick from. Rounds use a fixed shuffle, so a retake shows the same questions.
  For the 6.5" upload slot, the iPhone 13 Pro Max command above captures native 2778×1284 PNGs
  in a separate output directory, preserving the original set.
- **Video:** `video` records a full scripted run and rebuilds its soundtrack from the game's own
  sounds (the simulator records no audio). `store-preview.py` cuts the chosen clips (in seconds)
  into Apple's app preview format: 1920×886, 30 fps, H.264, stereo AAC, 15–30 seconds. The clip
  times shift a little between runs, so check them against the full recording.
- **Framed versions:** `scripts/store-frames.py` puts each chosen shot (from
  `build/store-capture/picks/`) on a world-color background under a caption in the game's font,
  matching the selected captures' dimensions. The shots, their order, and the captions are the
  `SHOTS` list at its top. Pass the picks and output directories to frame an alternate device set.
- **Dynamic Island:** the simulator draws it into its video, so the video fills it in from the
  surrounding water and slides the level path so no stop sits under it.
- **Autopilot:** it drifts around mid-water, sometimes eyes a wrong answer first, and heads for
  the right one as the wave gets close, so it plays like a kid rather than a bot.

## Tuning

Every feel constant — movement, growth, swallow timing, AI behavior, spawn distribution,
and the `aiFishCanEatEachOther` flag — lives in `BiggerFish/GameTuning.swift`.
Shallow Reef's five levels are defined in `GameTuning.levels`; Jelly Bloom's five are in
`GameTuning.bloomLevels`. Each sets the spawn mix, fish speeds, player speed, and meal growth;
Bloom also sets jelly count, tentacle length, sway, urchin beds, and its night palette.

For a specific Debug level, add launch arguments `-arcadePlaytest jelly-bloom.4` in Xcode (world ID
plus one-based level). This bypasses the level lock and uses a separate `biggerFish.playtest` save.
Add `-arcadeResult passed` or `-arcadeResult failed` to preview its result panel without recording a
clear. Remove the arguments to return to the normal world map and real campaign progress.

## Debug playtest recordings

Bigger Fish Xcode Debug builds automatically record runs locally in `Documents/ArcadeRuns`.
Release/TestFlight builds contain no recorder. Play normally, then pause or finish and keep your
phone unlocked and connected. Xcode's console prints `[ArcadeRun]` start/outcome lines.

Ask Codex to pull your runs, or run:

```bash
python3 scripts/pull-arcade-runs.py
```

The script selects a single connected device and copies only Bigger Fish's run directory to
ignored `build/arcade-runs`. Use `--device 'Your iPhone name'` if several devices are connected.
`--summarize-only` summarizes downloaded files; `--simulator booted` supports local verification.
If device transfer is unavailable, Xcode > Window > Devices and Simulators > installed Bigger Fish >
Download Container contains the same Documents/ArcadeRuns folder.

JSONL includes configuration and seeded starts, tap/release transitions, player and AI meals,
interrupted-swallow hazard deaths, bounces, pause/resume, outcomes, and full world/camera snapshots
at five per second plus event-time snapshots. Times are elapsed wall and simulation seconds;
fish positions are wrapped world coordinates. Recordings stream on a background queue, flush
periodically and on pause, and keep the latest 30 files. An interrupted run remains readable;
an abrupt process kill may lose the most recent queued records. Nothing is uploaded automatically.
Add `-arcadeDisableRunRecording` to Xcode's launch arguments to disable recording temporarily.


### Tune on your phone (Debug only)

Tap **Tuning** on a map or during a run. During play this pauses and flushes the recording.
Choose a world/level, edit fish counts and size ranges, growth, AI/player speed, food-pocket
release, jelly count/radius/tentacles, bounce strength, or layout/seed variation. **Apply & Play**
saves a per-level override and starts a fresh practice run immediately, without rebuilding.
Practice runs and overridden levels do not write campaign progress. Closing the panel leaves
an existing run paused. Overrides persist across launches and restarts.

Save named presets for comparisons. **Load shipped settings** loads the checked-in configuration;
**Load before-roaming experiment** restores the prior slow AI, bounded food pockets, and authored
jelly layout. Those buttons edit the draft; Apply saves it. **Remove override for this level**
clears its saved settings and starts a practice run with the checked-in configuration.
Presets are local, hold at most ten names, and can be applied to another level. Level geometry and
starting fish cannot always fit extreme combinations; the run analysis flags spawn shortfalls.
These tools and overrides are absent in Release/TestFlight.

### Automatic run diagnostics

Pulling recordings also writes `build/arcade-runs/analysis/report.md` and `metrics.json`.
For already pulled files, run `python3 scripts/analyze-arcade-runs.py`.
The report groups identical recorded configurations and measures completed close-size meals,
time with larger fish, nearby threats, gaps between meals, fish-cleanup tails, early deaths,
spawn shortfalls, and growth stalls. Simulation time excludes pauses and accounts for slow motion.

The growth check repeatedly consumes edible fish using the game's area-growth and near-equal
rules. It optimistically ignores geometry and future AI competition and checks stable snapshots
without active swallows. If it still cannot eat all remaining fish, the current food chain needs
an AI/hazard change to progress. This does not prove the whole level impossible: hazards can kill
fish. Threat/cleanup metrics concern fish danger, not jelly danger. Thresholds such as five-second
early deaths are descriptive; fast deaths can be desirable opening tension. Cleanup tails are
review signals, not a validated universal fun score.
Compare them with player feedback, especially the favorite Shallow Reef level 4 recordings.
Diagnostics are offline and do not alter gameplay. New recordings include the effective tuning
and both seeds, so changes on the phone remain attributable.

Player encounters within the 1% near-equal radius band favor the player, including a
fractionally larger opponent. NPC ties still bump apart. New run headers include
`playerWinsTies`; the offline analyzer preserves the old rule for older recordings.

### Simulate food races locally (Debug only)

The five Jelly Bloom profiles were selected with 1,642 real-scene rollouts. Read
[the balance study](docs/jelly-bloom-balance.md) for the growth-area calculation, pass-based
recovery measurements, selected seeds, and limits of bot-based evaluation. Three phone sizes
have demonstrated winning routes for every shipped level. Horizontal AI speeds are eased on
smaller Bloom viewports; tuning controls specify the nominal reference-width speeds.

To repeat the final validation:

```sh
python3 scripts/study-arcade-balance.py \
  --profiles docs/jelly-bloom-study-profiles.json --seeds 0,7,13,23 --passes 0 \
  --sizes 874x402,852x393,667x375 --limit 90 --run \
  --output build/arcade-development/studies/validation
```

Use `--passes 0,1,2` to test skipped circuits or `--meal-limits=-1,0,1,2,3,4,5,6`
for first-pass meal caps. Requests, raw results, summaries, and logs stay under ignored `build/`.
The study uses simulator tests, does not render or record runs, and cannot write campaign
progress. Its activation marker is removed by the command afterward. Normal test runs skip
large studies unless that marker was explicitly prepared. Shut down the simulator after a batch
if you are done testing.
