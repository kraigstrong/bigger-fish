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
from the start and every Deep End (`ArcadeUnlock.swift`). No endless mode, pearls, or shop yet in the released game;
Xcode builds have the endless run's prototype, **Open Water** (`OpenWater.swift`, from the world map's button, or launch
with `-openWater <seed>`): round the worlds a stage at a time (`GameTuning.openWaterWorlds`), each a new level dealt like that world's level 5 on stage 1, 6 on stage 2, and on,
planned as the run reaches it. Eating a level's last gate ends it and shrinks you back to your starting size for the
next world; being eaten ends the run. Pearls sit beside the big fish, a few a level (`OpenWater.pearls`): touch one to take it. Fish eaten and pearls count at the top.
A run's score is the fish it ate: the best is kept (`ArcadeProgress.openWaterBest`, synced with progress) and shown on
the run's card and the map's Open Water button.
Pearls are kept (`ArcadeProgress.pearls`, synced with progress) and spent in the **pearl shop** (`PearlShop.swift`,
`PearlShopView.swift`, the list and prices in `GameTuning.pearlShop`), from the map's pearl button or a run's card:
body colors, patterns, hats, faces, and trails for your fish, worn everywhere it swims, never making it look bigger. Limited
editions are on sale only in their season (`PearlSeason`; Christmas's Dec 1 – Jan 6), and kept all year once bought.
Some looks are never sold, only earned (`PearlGoal`): by an Open Water run, or as crowns like the map's (silver for a
world conquered, gold for a Deep End, diamond for every Deep End). The shop's rail down the left has each kind of look
and your saved outfits; looks added since you last looked are marked new. See
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
the credits, the maps) with `DrawOrderAudit`, which reports overlapping nodes that share a depth (Math Reef has a copy;
see Math Reef's draw order below). To check that a change of depths keeps the look, render the key moments before and
after and compare:

```bash
TEST_RUNNER_DRAW_ORDER_RENDERS=before xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:BiggerFishTests/DrawOrderTests/manualRenderDrawOrderMoments()'
# change the depths, render again as `after`, then:
diff -rq build/draw-order/before build/draw-order/after
```

## Layout

This repo builds two separate apps from one Xcode project (`BiggerFish.xcodeproj`), each with its own scheme:

- `BiggerFish/` — **Bigger Fish**, the arcade game: campaign rules, levels, tuning, and scene.
  - `ArcadeMaps.swift` — world selection (scrolling sideways when the worlds don't fit the screen) and the level
    paths (one stop per level)
  - `ScreenFit.swift` — the iPad: every level plays at the same fixed playfield (`GameTuning.playfieldSize`),
    fitted to the screen's width with its world's water in a band above and below (a touch in a band still
    steers), and the menus are laid out as on the biggest iPhone and scaled up to fill the screen (`ScreenScaled`).
    Every iPhone draws exactly as before. On an iPad the app takes the whole screen in landscape
    (`UIRequiresFullScreen`), so it doesn't join Split View or resize in Stage Manager. An iPhone Duo still resizes
    the app as it opens and closes: the same fitting draws a level on either screen, and a level in play pauses
    (`GameScene.screenDidResize`)
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
  It runs on iPhone and iPad, in landscape. An iPad draws the app as the biggest iPhone does, only taller,
  scaled up to fill the screen: the maps and cards use the extra height, and a round plays in a band of
  water as tall as that iPhone's, with darker water above and below, so lanes and reach match every phone.
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
  - `UnlockScreen.swift` — the grown-ups' unlock screen, behind the parental gate: each world in its color and
    symbol with its grades, its first and hardest question, and a pip per level (the free ones white), then the free
    levels against all of them, Family Sharing, and the App Store's price. Debug builds open on it with
    `-unlockScreen`, and `-unlockPrice '$4.99'` stands in for the price outside Xcode, which has no StoreKit config
  - `PracticeScene.swift` — screen flow and gameplay; tuning is `ReefTuning` at the top
  - `ReefScreen.swift` — the iPad: how much bigger the scene draws (`ReefScreen.scale`), the band of water
    a round plays in (`ReefScreen.playfield`), and the scene's view (`ReefView`), which draws it bigger at
    the screen's own resolution. Every iPhone draws exactly as before. On an iPhone Duo, opening or closing the
    phone changes the scene's size mid-play: whatever is showing is drawn again where it was (`PracticeScene.relayout`),
    and a round's next question waits for the kid's next hold. The controls in a top corner move clear of the closed
    phone's camera (`ReefCorners`, from iOS 27.1's reserved regions, so only in a build from the iOS 27.1 SDK)
  - `Tutorial.swift` — the first-launch tutorial (Hold, Let go, Eat the answer with 1 + 1), played with the
    real movement before the reef map on a fresh install. It never fails or times out; a stuck kid
    sees the hint again. The first catch gets "Yes!", then "Ready to play!", then a fade to the map
    (Skip just fades). Saved as done the moment the 2 is eaten or Skip is tapped, and skipped for
    players who already have progress. Settings can replay it.
  - `RoundHint.swift` — the control hint at the start of a round: the tutorial's "Hold" step (finger,
    "Hold to swim up", arrows over the fish and its question), drawn under the answer fish. A kid's first
    3 rounds after install start with it (`ReefTuning.roundHintRounds`), and it goes at their first hold;
    a round only counts once they've held, so a kid who hasn't found the control keeps seeing it.
  - `ReefAudio.swift` / `ReefHaptics.swift` — sound effects, music, and haptics, each with its own
    switch in Settings (Sound, Music, Vibration), saved on the device. A 1.0 install that turned sound
    off keeps the music off too. Sound and music play on their own queue, as Bigger Fish's do, so a slow
    start can't stall a frame
  - `ReefAnalytics.swift` — anonymous first-party counts (milestones and round outcomes), queued on the device and sent in batches to brightbench.app (off during test runs)
  - `StoreCapture.swift` — debug-only staged scenes and an autopilot for App Store screenshots and the preview video
- `Packages/FishKit/` — shared fish engine used by both apps:
  the fish model and drawing, hold/release movement (`PlayerMotion` + `MotionTuning`), wrapped world,
  seeded RNG, swallow timing, and water textures.

FishKit tests:

```bash
cd Packages/FishKit && xcodebuild test -scheme FishKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Math Reef's draw order.** Its view (`ReefView`) draws with `ignoresSiblingOrder` too, and asks for 120 frames a
second, which a ProMotion iPhone allows only with the key in `MathReef-Info.plist` (the rest of its Info.plist is
generated from build settings). `MathReefTests/DrawOrderTests` plays the app's one scene frame by frame, as a store
capture does, through the moments that matter on an iPhone, the iPhone SE, and an iPad: the reef and every level path,
Settings and the parental gate, the unlock, rounds answered right and wrong, a first round's control hint, the results
and a crown, and the tutorial.
It checks each with a copy of Bigger Fish's `DrawOrderAudit` (a fix to one belongs in the other). Its renders hash every
moment the audit looks at, so a change of depths can be checked frame by frame:

```bash
TEST_RUNNER_DRAW_ORDER_RENDERS=before xcodebuild test -project BiggerFish.xcodeproj -scheme MathReef \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:MathReefTests/DrawOrderTests/manualRenderDrawOrderMoments()'
# change the depths, render again as `after`, then:
diff build/math-reef-draw-order/before/hashes.txt build/math-reef-draw-order/after/hashes.txt
```

## App Store screenshots and preview

`scripts/store-capture.sh` builds Math Reef in Debug, then launches it on the iPhone 17 Pro Max
simulator with `-storeCapture <scene>`. That stages believable progress in its own saved state,
leaving real progress, purchases, and analytics alone, and lets an autopilot play. Everything is
drawn by the app itself, so nothing has the simulator's Dynamic Island over it. Output goes to
`build/store-capture/` (ignored by git). It needs ffmpeg (`brew install ffmpeg`), and the video
also needs NumPy (`python3 -m pip install numpy`).

```bash
scripts/store-capture.sh screenshots
STORE_CAPTURE_DEVICE='iPhone 13 Pro Max' STORE_CAPTURE_OUT="$PWD/build/store-capture-6.5" scripts/store-capture.sh screenshots
STORE_CAPTURE_DEVICE='iPad Pro 13-inch (M5)' STORE_CAPTURE_OUT="$PWD/build/store-capture-ipad13" scripts/store-capture.sh screenshots
scripts/store-capture.sh video
python3 scripts/store-preview.py build/store-capture/video/full.mp4 build/store-capture/video/preview.mp4 0.2-2.3 2.6-4.7 5.1-11.0 17.8-23.4 65.6-77.4
```

- **Screenshots** are PNGs at the screen's full size with no alpha: 2868×1320 on the iPhone 17 Pro
  Max (6.9"), 2752×2064 on the 13-inch iPad. Play scenes and the crown save a burst of frames to
  pick from. Rounds use a fixed shuffle, so a retake shows the same questions. For the 6.5" upload
  slot, the iPhone 13 Pro Max command above captures native 2778×1284 PNGs in a separate output
  directory, preserving the original set.
- **Frame by frame:** a capture plays as Bigger Fish's footage does: every frame is exactly a 60th
  of a second of play, the scene's animations included, however long the simulator takes to save
  one (`StoreCapture.Stepper` drives SpriteKit's clock and draws the frames). So the video is
  smooth, and a burst catches the same moments at the same frame numbers on any device.
- **Video:** `video` plays a scripted run (the reef, Multiplication's path, a round of × 7 with a
  wrong answer, the results and silver crown) and saves 30 frames a second of play (about 8
  minutes for the 86 seconds). The soundtrack is rebuilt from the game's own sounds (the simulator
  records no audio), timed on the same clock. It comes out at Apple's app preview size: 1920×886 on an iPhone, 1600×1200 on an iPad.
  `store-preview.py` cuts the chosen clips (in seconds) into the preview: 30 fps, H.264, stereo AAC,
  15–30 seconds. Check the clip times against `full.mp4` after any change to the game or autopilot.
- **Framed versions:** `scripts/store-frames.py` puts each chosen shot (from
  `build/store-capture/picks/`) on a world-color background under a caption in the game's font,
  matching the selected captures' dimensions. The shots, their order, and the captions are the
  `SHOTS` list at its top. Pass the picks and output directories to frame an alternate device set,
  with each pick saved under the iPhone's file name.
- **Autopilot:** it drifts around mid-water, sometimes eyes a wrong answer first, and swoops into
  the right one as the wave gets close (waiting off to one side, then diving or climbing through
  it), so it plays like a kid rather than a bot. It steers clear of the other answers, so the only
  wrong answers are the ones a scene plans.

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

Then caption them and send them to App Store Connect:

```bash
scripts/bigger-fish-store-frames.py build/store-capture/bigger-fish/screenshots build/store-capture/bigger-fish/captioned
scripts/bigger-fish-store-frames.py build/store-capture/bigger-fish/screenshots-ipad-13 build/store-capture/bigger-fish/captioned-ipad-13
python3 appstore/push.py media --app bigger-fish --dry-run \
  --screenshots build/store-capture/bigger-fish/captioned build/store-capture/bigger-fish/captioned-ipad-13 \
  --header build/footage/bigger-fish-header.png --search build/footage/bigger-fish-universal-creative.png
```

The captions are the trailer's: 2–4 words in Avenir Next Heavy over a soft dark band, on full-size gameplay with no
device frame, dodge first (it's the strongest single image, and search often shows only the first). The two app
screens (conquered, The Deep End) have titles where the caption goes, so they're shrunk a little over a blur of
themselves instead. The 6.5" size isn't uploaded: App Store Connect scales the 6.9" set down.

The universal creative (iOS 27's product page header and search results image, 5244×2950) is gameplay drawn big
enough by the footage recorder, then cropped and captioned. The header gets its own, with the game drawn smaller: an
iPhone shows only the middle half of the header and its top 60% or so, which at full size is a close-up of one fish.

```bash
FOOTAGE_SCALE=2.4461 scripts/bigger-fish-footage.sh shallow-reef.9 collector 15.21 15.22
scripts/bigger-fish-creative.py build/footage/shallow-reef.9-collector-15.21-15.22/00000.png \
  build/footage/bigger-fish-universal-creative.png
scripts/bigger-fish-creative.py --scale 0.7 build/footage/shallow-reef.9-collector-15.21-15.22/00000.png \
  build/footage/bigger-fish-header.png
```

That's the dodge screenshot's moment (`[StoreCapture] dodge: collector bot, step 913`, 913/60 seconds in).

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

The App Store cut differs from the site's in two places (shots and captions marked `"only": "store"`). Its "TURN THE
TABLES." shot is a different bite. And it ends on Shallow Reef 11's eating run in slow motion, with "Bigger Fish / Eat fast. Stay alive." landing under it
before the blur. That's for the poster frame, the one frame the App Store shows until the preview plays: it can only
be a frame of the video, so the video has to hold the picture. The poster is 26.67 s in, mouth open with the next
meal just ahead (mid-swallow read as two fish bumping): `appstore/push.py media --preview ... --poster 00:00:26:20`.

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
world's ten main levels are beaten, and whether each run had the unlock) went on with the unlock's sale
(`ArcadeAnalytics.sendsPaywallEvents`).

The Open Water and the pearl shop report behind `ArcadeAnalytics.sendsOpenWaterEvents` (on: brightbench.app accepts
them, kraigstrong/BrightBench#85, and the privacy policy describes them): one `endless` summary per run from its first level
(`ArcadeOpenWaterMetrics`: levels cleared, fish, pearls, game seconds, a new best, levels that waited on the next
plan and for how long, the slowest plan, dressed), with Retry or leaving as its `decision` and once-per-install
milestones for the first run and the first time round the worlds; one `shop` event per visit (door, pearls in hand,
looks bought, and the Open Water runs before an install's first purchase); `earned` once per look; whether each
campaign run was played `dressed`; and, at a launch's first run, the looks worn (`outfit`, counted piece by piece,
never with a run). Every Open Water run shares one context (world `open-water`, seed `"0"`,
`ArcadeAnalytics.openWaterRevision`): a run's own seed would make a stats row per run. Bump the revision when the
run's worlds, ramp, dealing, or the planner change. Headless studies and runs started part-way in don't report.

Events go in batches of `ArcadeAnalytics.batchSize` (25), when the app goes to the background or a level is
interrupted, and at launch, not after every run: each send is a billed Redis write on brightbench.app, and the same
counters in a batch add up into one. Simulator builds never collect.

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
