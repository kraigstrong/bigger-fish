# Bigger Fish

There's always a bigger fish.

Arcade game: a one-touch game for iPhone and iPad (landscape, SwiftUI + SpriteKit, iOS 17+).
Hold to rise. Release to fall. Eat fish smaller than you. Avoid fish larger than you. Become the last fish swimming.

A new player starts with the tutorial (`ArcadeTutorial.swift`), which teaches the rules by playing them. The world
map then has five worlds, each with ten levels to conquer and then The Deep End, five more at its hardest:
**Shallow Reef** (fish only), **Jelly Bloom** (drifting jellyfish: bounce off their domes, dodge their tentacles),
**Kelp Forest** (kelp slows you, and fish in it are shadows), **Sunset Cove** (boats lower baited hooks: leave the
bait; `FishHooks.swift`, its knobs under `// MARK: Sunset Cove` in `GameTuning`), and **Midnight Zone** (dark water
lit by your headlamp, and anglerfish lures). Xcode builds add a prototype world after them
(`ArcadeWorld.prototypes`): **Riptide Reef**, whose currents carry you faster, being developed for 2.0. Every level is planned (see
Meeting planner below), and each world opens its levels in order. Clears and fastest times are saved on the device
and backed up to the player's own iCloud, so they come back after a reinstall and follow the player to another
device; the two copies merge so that syncing never un-clears a level.

Free to try: all of Shallow Reef, plus two levels of each other world; a one-time purchase opens every world
from the start and every Deep End (`ArcadeUnlock.swift`). No endless mode, pearls, or shop yet. See
[`docs/bigger-fish-playable-scope.md`](docs/bigger-fish-playable-scope.md) for the accepted scope and deferred vision.

## Running

Open `BiggerFish.xcodeproj` in Xcode, pick your iPhone, iPad, or a simulator, and Run.
Signing uses automatic signing with team `MKACSCQ588`. The Bigger Fish target has the iCloud key-value storage
capability (`BiggerFish/BiggerFish.entitlements`), which automatic signing adds to the App ID.

Unit tests (wrapping, size rules, growth, win detection):

```bash
xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Draw order.** Every SpriteView draws with `ignoresSiblingOrder`, so nodes at the same global depth come out in any
order on a phone, though the simulator keeps the order they were added. Anything drawn over something else needs its own
zPosition. `DrawOrderTests` walks every scene at the moments that matter (cards, play, pause, the result, the tutorial,
the credits, the maps) with `DrawOrderAudit`, which reports overlapping nodes that share a depth. To check that a change
of depths keeps the look, render the key moments before and after and compare:

```bash
TEST_RUNNER_DRAW_ORDER_RENDERS=before xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:BiggerFishTests/DrawOrderTests/manualRenderDrawOrderMoments()'
# change the depths, render again as `after`, then:
diff -rq build/draw-order/before build/draw-order/after
```

## Layout

This repo builds two separate apps from one Xcode project (`BiggerFish.xcodeproj`), each with its own scheme:

- `BiggerFish/` — **Bigger Fish**, the arcade game: campaign rules, levels, tuning, and scene.
  - `ArcadeMaps.swift` — world selection and the level paths (one stop per level)
  - `ScreenFit.swift` — the iPad: every level plays at the same fixed playfield (`GameTuning.playfieldSize`),
    fitted to the screen's width with its world's water in a band above and below (a touch in a band still
    steers), and the menus are laid out as on the biggest iPhone and scaled up to fill the screen (`ScreenScaled`).
    Every iPhone draws exactly as before. On an iPad the app takes the whole screen in landscape
    (`UIRequiresFullScreen`), so it doesn't join Split View or resize in Stage Manager
  - `SettingsView.swift` — Settings from the world map's gear: sound, music, vibration, replaying the tutorial,
    restoring the unlock, the privacy policy and support (biggerfish.app), the credits, and the version
  - `CreditsScene.swift` / `ArcadeCredits.swift` / `Credits.json` — the credits, played: from Settings, a calm swim
    where every name is a fish to eat (design, the play-testers, then the music and sound credits), with a thank-you for each
    and a card at the end. Nothing can eat you, and it saves nothing. Add a name by editing `Credits.json`
  - `ArcadeCampaign.swift` / `ArcadeProgress.swift` — stable level IDs and campaign saves, kept on the device and
    backed up to iCloud key-value storage. At launch and whenever iCloud's copy changes (another device, a reinstall's
    first download, a new Apple ID), the two merge so progress only ever grows: cleared levels and seen screens are
    united, the faster best time wins, and fields from a later version are kept. Without iCloud it plays exactly as
    before. Debug playtest, store-capture and footage saves never sync
  - `ArcadeUnlock.swift` / `UnlockView.swift` / `WorldClips/` — free to try (all of Shallow Reef, two levels of
    each other world) and the one-time unlock that opens every world and Deep End; its screen loops a clip of each
    world. `BiggerFish.storekit` is the scheme's StoreKit test file
  - `Jellyfish.swift` / `ArcadeArt.swift` — arcade-only hazard rules and procedural artwork
  - `WorldProgress.swift` — how far through a world you are: pips and a crown on the cards before and after each
    level, a bar on the level map, and a ring on the world map
  - `ArcadeAudio.swift` / `Sounds/` — copied sound effects; source credits stay alongside them
  - `ArcadePlaytest.swift` — debug-only isolated level launches for playtesting
  - `StoreCapture.swift` — debug-only App Store screenshots: the bot plays each moment's level to its best frame
  - `StoreFootage.swift` — debug-only gameplay footage for the trailer and App Store previews: the bot plays a level
    one frame at a time, so it never stutters, with the interface hidden (`scripts/bigger-fish-footage.sh`)
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
  - `Tutorial.swift` — the first-launch tutorial (Hold, Let go, Eat the answer with 1 + 1), played with the
    real movement before the reef map on a fresh install. It never fails or times out; a stuck kid
    sees the hint again. The first catch gets "Yes!", then "Ready to play!", then a fade to the map
    (Skip just fades). Saved as done the moment the 2 is eaten or Skip is tapped, and skipped for
    players who already have progress. Xcode builds can replay it from Settings.
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

### Bigger Fish screenshots

`scripts/bigger-fish-store-capture.sh` builds Bigger Fish in Debug and launches it on the iPhone 17 Pro Max
simulator once per moment with `-storeCapture <moment>` (`BiggerFish/StoreCapture.swift`). For a moment in
play, the diagnostics bot plays a real level as shipped; runs are deterministic, so the app plays it once with
each bot policy to score every frame, then again to stop on the best one. The other two moments are the game's
own screens. The app saves what it draws with the interface hidden (no Dynamic Island either), in staged
progress of its own, silently, leaving real progress, purchases, and analytics alone. It needs only Xcode.

```bash
scripts/bigger-fish-store-capture.sh                 # every moment, about a minute
scripts/bigger-fish-store-capture.sh dodge missed    # just these
scripts/bigger-fish-store-capture.sh --ipad          # every moment on the iPad Pro 13-inch (M5) simulator
```

Output goes to `build/store-capture/bigger-fish/` (ignored by git): `screenshots/NN-<moment>.png` at
2868×1320 (6.9", no alpha) in the listing's order, and `screenshots-6.5/` scaled and trimmed to 2778×1284.
With `--ipad`, `screenshots-ipad-13/NN-<moment>.png` at 2752×2064, App Store Connect's 13-inch iPad size,
bands of water above and below the playfield included, as an iPad shows them.
The moments: `eat` (Shallow Reef 5), `dodge` (Shallow Reef 9), `missed` (Shallow Reef 10: a fish that kept
eating), `jelly-tops` (Jelly Bloom 2), `kelp-shadows` (Kelp Forest 8), `sunset-hooks` (Sunset Cove 7: a baited hook
ahead, under its boat), `midnight-light` (Midnight Zone 5),
`conquered` (Shallow Reef's map, conquered), and `deep-end` (the screen that opens its Deep End). The levels
are `StoreCapture.Moment.level`; to try another in Xcode, add `-arcadePlaytest world.N` beside
`-storeCapture <moment>`.

### Bigger Fish trailer and footage

`scripts/bigger-fish-footage.sh` records gameplay for the trailer and App Store previews
(`BiggerFish/StoreFootage.swift`). The diagnostics bot plays a level and the app saves every frame at 60 fps with the
interface hidden, one frame at a time, so the footage never stutters and the same launch gives the same footage. A
`--look` is a contact sheet of a whole run, a frame every half second; then record just the seconds wanted. Each
recording writes a report beside it listing every bite: yours, with the meal's size then and at its biggest (a fish
that had been three times your size is a "turn the tables" moment), and the other fish's on screen, with where.

```bash
scripts/bigger-fish-footage.sh --look sunset-cove.7 opportunist    # the whole run, to pick from
scripts/bigger-fish-footage.sh sunset-cove.7 opportunist 1.5 10    # 1.5-10 s of it, 60 fps
scripts/bigger-fish-trailer.sh                                     # the trailer and App Store preview
```

`scripts/bigger-fish-trailer.sh` rebuilds the trailer from `scripts/trailer/edl.json`: it records whatever footage
the cut needs that isn't in `build/footage/` yet, renders the captions in Avenir Next, and composes each shot with a
slow camera move over the game's music (cut to its 120 BPM bars, the world montage on its drop). It writes
`build/trailer/bigger-fish-trailer.mp4` (60 fps, with the release line, for biggerfish.app) and
`bigger-fish-app-preview.mp4` (30 fps, no dates, 29.5 s: the App Store preview at the 6.9" iPhone size, 1920×886). A
level that isn't frozen can play differently after a change, so delete its recording to record it again. It needs
ffmpeg and Python with Pillow and NumPy.

## Tuning

Every feel constant — movement, growth, swallow timing, AI behavior, and the `aiFishCanEatEachOther`
flag — lives in `BiggerFish/GameTuning.swift`. So do each world's levels: specs the meeting planner lays out,
shipped as saved plans in the app.

| World | Specs in `GameTuning` | Saved plans | Frozen set |
|---|---|---|---|
| Shallow Reef | `reefLabSpecs`, played in `shallowReefOrder` | `ReefLabPlans.json` | `reefLabFrozen` |
| Jelly Bloom | `jellyLabSpecs` | `JellyLabPlans.json` | `jellyLabFrozen` |
| Kelp Forest | `kelpSpecs` | `KelpPlans.json` | `kelpFrozen` |
| Midnight Zone | `midnightSpecs` | `MidnightPlans.json` | `midnightFrozen` |

The shipped game plays the saved plans and never plans on the device: the planner is in Xcode builds only, and a
Release build with a level missing from its plans file stops at launch. `FrozenLevelTests` pins every frozen
level, so changing one is never a side effect. AGENTS.md has the workflow: iterate in code, freeze before
publishing.

For a specific Debug level, add launch arguments `-arcadePlaytest jelly-bloom.4` in Xcode (world ID
plus one-based level). This bypasses the level lock and uses a separate `biggerFish.playtest` save, which never
syncs to iCloud.
Add `-arcadeResult passed` or `-arcadeResult failed` to preview its result panel without recording a
clear. Remove the arguments to return to the normal world map and real campaign progress.

To check a screen's layout at a device's size (an iPad, a small phone), `-arcadeScreen <screen>` opens it at launch:
`worlds`, `settings`, `unlock`, `conquered`, `credits`, `tutorial`, or `pause` (with `-arcadePlaytest` for the
level to pause). It plays in a staged save of its own (`biggerFish.screen`: Shallow Reef conquered, the tutorial
seen), which never syncs to iCloud. Add `-arcadeMap <world ID>` for a level map, `-arcadeUnlocked YES` or `NO` for
either side of the unlock, or `-arcadePlaytest` with `-arcadeResult` for a result card. `-arcadeScreenCapture <name>`
saves the screen once it settles, at full resolution, to the app's `Documents/ScreenCheck/<name>.png`: an iPad
simulator held upright shows the landscape-only game shrunk to fit, in its own screenshots too.

## Debug playtest recordings

Bigger Fish Xcode Debug builds automatically record runs locally in `Documents/ArcadeRuns`.
Release/TestFlight builds contain no recorder. Play normally, then pause or finish and keep your
phone unlocked and connected. Xcode's console prints `[ArcadeRun]` start/outcome lines.

To pull your runs:

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
periodically and on pause, and keep the latest 100 files. An interrupted run remains readable;
an abrupt process kill may lose the most recent queued records. Nothing is uploaded automatically.
Add `-arcadeDisableRunRecording` to Xcode's launch arguments to disable recording temporarily.

### Slow frames (the hitch log)

Debug builds also log every slow frame anywhere in the app (`HitchLog.swift`): the maps, Settings, the unlock, a level
in any phase (its card, playing, paused, a death, the result), the tutorial, and the credits. A frame is slow when it
takes at least 1.5 display intervals (12.5 ms at 120 Hz, 25 ms at 60): it missed a refresh. Each one records the screen
and phase, how long the frame took, the main thread's longest stretch of work in it, the scene's own update, and the
last few things that happened before it: a screen or scene appearing, a haptic and its generator, a sound, a swallow, a
death, a card or result shown, an analytics write or send, a pause or resume. A scene times its own frames on
SpriteKit's clock; everywhere else a display link does, paused while a scene is up so it never changes the frame rate
being measured.

1. Play a Debug build from Xcode on the phone, as usual.
2. Pull: `python3 scripts/pull-arcade-runs.py`. Slow frames during a recorded run are in its `run-*.jsonl`; the rest
   are in a `hitches-*.jsonl` beside them (one per launch that had any; the latest 30 are kept).
3. Read the **Hitches** section at the end of `build/arcade-runs/analysis/report.md`: slow frames by screen and phase,
   then by the event just before them, each worst first, then the ten worst with what led up to each.
   `analysis/hitches.json` has every one.

A long frame with little work came late rather than busy: the display or the system held it, not the game's code. At
most 20 slow frames are written a second, and the rest are counted. Release builds have none of it, and
`-arcadeDisableRunRecording` turns it off along with the recordings.

### Meeting planner

Every world plays planned levels: each gate's slack and routes are designed, and every fish still swims
freely into its meeting. Shallow Reef's and Jelly Bloom's won an A/B test as Shallow Reef 2 and Jelly Bloom 2
(internally Reef Lab and Jelly Lab) and replaced the seeded campaigns under the original `shallow-reef` and
`jelly-bloom` IDs; those seeded campaigns are retired, and git history has them. Jelly Bloom's jellyfish drift,
to bounce off and dodge. Kelp Forest and Midnight Zone were planned from the start, with each fish appearing
just off screen right before you meet it. In Debug builds, **Tuning** (on a map or during a run) has
**Players**, to reset a world for a new player (on the device and in iCloud), and **Shallow Reef variations**, to play other layouts. See
[`docs/meeting-planner.md`](docs/meeting-planner.md).

### Automatic run diagnostics

Pulling recordings also writes `build/arcade-runs/analysis/report.md` and `metrics.json`.
For already pulled files, run `python3 scripts/analyze-arcade-runs.py`.
The report groups identical recorded configurations and measures completed close-size meals,
time with larger fish, nearby threats, gaps between meals, fish-cleanup tails, early deaths,
spawn shortfalls, and growth stalls. Simulation time excludes pauses and accounts for slow motion.

The growth check repeatedly consumes edible fish using the game's area-growth and near-equal
rules. It optimistically ignores geometry and future AI competition and checks stable snapshots
without active swallows. If it still cannot eat all remaining fish, the current food chain needs
an AI/hazard change to progress. This does not prove the whole level impossible: future AI interactions can change the
food chain. Jellyfish no longer kill AI fish. Threat/cleanup metrics concern fish danger, not jelly danger. Thresholds such as five-second
early deaths are descriptive; fast deaths can be desirable opening tension. Cleanup tails are
review signals, not a validated universal fun score.
Compare them with player feedback, especially the favorite Shallow Reef level 4 recordings.
Diagnostics are offline and do not alter gameplay. New recordings include the level's settings
and its seed.

Player encounters within the 1% near-equal radius band favor the player, including a
fractionally larger opponent. NPC ties still bump apart. New run headers include
`playerWinsTies`; the offline analyzer preserves the old rule for older recordings.

## Anonymous arcade diagnostics

`ArcadeAnalytics.swift` and `ArcadeMetrics.swift` implement first-party gameplay summaries for
Bigger Fish, separate from Math Reef. `ArcadeAnalytics.isEnabled` controls collection; it is
on for the beta, with the endpoint, policy, and report live on brightbench.app.
No player/install/session IDs, exact play timestamps, device information, or trajectories are sent.
The paywall funnel (where the unlock's screen was shown from, purchase and restore outcomes, a milestone when a
world's ten main levels are beaten, and whether each run had the unlock) is built but stays off behind
`ArcadeAnalytics.sendsPaywallEvents` until brightbench.app accepts it and the privacy policy describes it.

The schema records content identity (world, campaign/endless mode, displayed slot, original setup,
seed, content revision, app version/build/channel), outcomes, local attempts-to-first-clear,
size/count diagnostics, close meals, bounces, growth-budget losses/recoveries, and cleanup time.
The pre-fatal snapshot is taken at the committed collision, before the fatal meal or animation.
Unresolved swallows produce `unknown` growth paths rather than double-counted food. A path is an
optimistic size budget, not proof of safe navigation or future victory.

Summary work is in-memory; growth checks run at ecosystem changes and boundaries. Pausing writes
a checkpoint; a pending run is counted as abandoned on the next cold launch. Run IDs are never
created. Decisions/reports retain their originating build when an update occurs. At-most-once
sending drops failed/uncertain batches rather than introducing identifiers or duplicate retries.
The local queue holds 100 events and sends batches of up to 25. Simulation/capture/tuner runs and
ordinary test launches do not collect. Gameplay counts saturate at 10,000, durations at 3,600
simulation seconds, and circuits at 100; these bounds censor telemetry only, never gameplay.

The companion report is `/bigger-fish/stats` on BrightBench, behind a server-only reporting key.
Its policy is `/bigger-fish/privacy`. Complete the App Store privacy answers before public release. Production retention and provider-log handling remain release audit checks;
successful ingestion alone does not verify them.

New worlds and large/generated campaigns do not require a finite server-side level catalog.
Bump the content revision when seeds, rules, or tuning change so comparisons remain separate.
Additive optional fields require server-first allowlist updates; old schema-1 summaries remain
valid. Incompatible meaning/shape changes require a new schema version. Never add unrestricted
metadata or identifiers under an extension field.

## License

The source code is under the [PolyForm Noncommercial License 1.0.0](LICENSE): free to read, learn from, and use
for noncommercial purposes, but not in anything commercial. (The license also permits any use by charities,
schools, and public and government institutions; see its Noncommercial Organizations section.) The names, icons,
art, and videos are all rights reserved, and the sounds and music are third-party works under their own licenses (see each app's
`Sounds/CREDITS.md`).
