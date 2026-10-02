# Why Bigger Fish retries diverge

The starting ecosystem repeats, but its later evolution does not necessarily repeat. Three independent couplings were confirmed in the real `GameScene` logic. Gameplay was not changed by this investigation; additions are debug-only audit tools and a local test runner.

## 1. Every NPC shares one random sequence

`moveAI` draws a new turn interval, vertical target, and retarget interval from the scene's `rng`. The next swimmer consumes the next values. A fish being removed, reaching a target sooner, or turning at a different moment therefore changes random choices received by otherwise unrelated fish.

The arrival check also requests a new target whenever a fish is within six points of its existing target. If the new target is nearby, another request can happen on the next frame. This makes random-number consumption sensitive to both movement and frame frequency.

A controlled experiment advanced only AI movement: no player movement, no collisions, no hazards, no growth, and no camera updates. Every fish remained present. Skipping fish 1's updates changed the targets of **20 of the other 22 fish on the first step**. Fish 22's target changed from approximately **137.13 to 90.45**, despite no physical interaction. After eight seconds, all 22 other fish had different positions.

This is an unintended nonlocal dependency, distinct from legitimate consequences such as losing a prey fish to another predator.

## 2. Rendering frequency changes the simulation

Normal gameplay passes elapsed rendering-frame time directly into `simulate`, capped at 1/30 second. AI movement, random target arrival checks, collision checks, swallowing, growth, and camera easing all run at that variable interval. The offline balance harness instead uses a regular 60-step schedule.

An identical seeded ecosystem was advanced for eight simulation seconds with a ghost player that never touched or ate anything:

| Steps per second | NPC fish remaining at eight seconds |
|---|---:|
| 30 | 13 |
| 60 | 8 |
| 120 | 11 |

Different survivors and sizes appeared without different player decisions. Even with every collision disabled, all 23 NPC positions differed across frame schedules. Repeating the exact 60-step schedule produced identical internal fish state, confirming that the setup itself was reproducible.

Wrapped-world displacement, measured against the 60-step isolated control:

| Comparison | Common fish | Fish with different positions | Largest displacement |
|---|---:|---:|---:|
| 30 steps/second | 23 | 23 | 1,095.70 points |
| 120 steps/second | 23 | 23 | 1,218.44 points |
| Alternating 1/120 and 3/120 second frames | 23 | 23 | 1,035.64 points |
| Skip fish 1's AI updates | 22 | 22 | 734.95 points |

These comparisons combine integration and random-sequence effects. They demonstrate that frame scheduling changes gameplay, not that each numerical difference has a separate physical cause.

## 3. Player growth changes the world everywhere

`waterBottom` and `waterTop` derive from camera zoom. NPC target ranges, steering limits, boundary contacts, and jelly avoidance use those bounds. Player growth therefore enlarges the swimming area for every fish, including distant fish.

The jelly update additionally raises every jelly to maintain a floor passage based on the player's radius. Bounce impulses are divided by zoom for NPCs as well as the player. These are current design couplings rather than just randomness bugs.

In the isolated first-step experiment, changing only zoom from 1 to 0.8 changed ten NPC targets. Fish 22 received the same retarget timer and random fraction, but its target shifted from **137.13 to 117.82** because its allowed vertical range changed.

In the complete eight-second ecosystem probe, starting the untouchable player at radius 32 instead of 16 left **12 NPCs rather than 8**. The water boundaries expanded from `[10, 390]` to approximately `[-51.40, 451.40]`. No player meal or contact was needed to affect the ecology.

## Relation to the recorded win

The phone recordings around the Level 5 win had identical settings, seeds, and initial fish positions and velocities. Opening catches were nearly identical. In the preceding long loss, NPC 22 ate fish 20 at about 10.36 simulation seconds, and NPC 23 ate NPC 22 at about 14.03 seconds. In the winning run, fish 20 remained available for the player around 12.09 seconds, followed by NPCs 22 and 23.

The controlled experiments establish mechanisms that can change that opportunity. The recordings do not include every frame interval or internal random state, so they cannot uniquely assign that particular divergence to one mechanism or to a specific input difference. Similar-looking openings are not necessarily identical inputs.

## Phase 1: fixed stepping

The investigation above describes the pre-refactor build. Gameplay now advances in
fixed 1/60-second simulation steps. Display frames contribute elapsed time to an
accumulator; a separate fixed real-time tick advances slowdown and its recovery,
then releases whole gameplay steps. Normal play and offline studies use the same
stepping path. Presentation still renders on each display frame.

Pause/resume and resets discard pending time. Catch-up is bounded to 0.25 seconds
per display frame; longer stalls intentionally discard the excess rather than
running an unbounded backlog. Consequently equal inputs at equal simulation ticks
repeat across frame schedules within that bound, while long stalls and different
input timing can still change a run. Drawing now interpolates between the previous and current gameplay states, including fractional real-time ticks. Fish poses, camera zoom, jelly positions, swallowing, and growth are smoothed without writing back into the simulation. Previous drawing state is synchronized on pause/resume and reset. Like standard interpolation, this presents motion up to one gameplay step behind the simulation (about 17 ms normally, longer during slow motion).

Regression checks compare complete fish state, player state, camera zoom, and world
bounds after eight seconds at 10, 30, 60, and 120 FPS and alternating short/long
frames, including close-meal slowdown and scripted hold/release input. They also
check fractional ticks, pause/resume timestamps, bounded hitches, and reset debt.

All five Bloom levels retain a winning simulated route at three phone sizes.
Level 3 at width 852 now uses the cautious controller rather than the opportunist
for that check; no level tuning changed. At width 874, Level 5's cautious route
still catches fish 1, 8, 18, and 7 at approximately 0.180, 0.237, 0.406, and 0.775
circuits, preserving the reference opening. Its finish changes from approximately
16.2 to 21.3 simulation seconds, so later human gameplay still needs checking.

NPCs still share randomness and camera growth still changes physical world bounds.
Neither dependency is addressed here. Historical isolated audit modes intentionally
retain raw variable steps to reproduce the original findings; the new fixed-step
regressions exercise the production accumulator instead.

## Recommended next work

1. Advance gameplay at a fixed simulation interval independent of display frequency. Use the same stepping path for normal play and offline studies, and validate close-meal slowdown, pause/resume, and touch latency.
2. Give each NPC an independent reproducible movement sequence. Keep the initial spawning sequence intact, and test that skipping or removing one noninteracting fish does not alter another fish's movement choices.
3. Decide separately whether camera zoom and the growing-fish passage should change distant NPC ecology. Separating visual camera bounds from physical world bounds affects feel and navigation, so this needs a product discussion rather than an incidental refactor.

AI eating remains essential. Repeatability should remove incidental dependencies while retaining consequences of consuming or losing food. Different player inputs can still produce different food races.

Both timing and random-stream fixes can change the current Level 5 opening trajectories. Before applying them, retain the present build and winning/losing reference logs, replay the opening, and compare the first food encounters. A fixed seed alone cannot guarantee the favorite opening is preserved under a new movement model.

## Reproduce

The local test activates only while this marker exists:

```sh
mkdir -p build/arcade-development
touch build/arcade-development/repeatability-investigation.request
xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' \
  -derivedDataPath build/arcade-development/DerivedData \
  -only-testing:BiggerFishTests/ArcadeSimulationTests
rm build/arcade-development/repeatability-investigation.request
xcrun simctl shutdown all
```

It writes `build/arcade-development/repeatability-investigation.json` with complete endpoint positions, velocities, radii, steering targets, timers, states, and bounds. All data and tools are local and debug-only. The full Bigger Fish suite passed **54 tests**, including the exact-schedule control. The marker was removed and simulators were shut down after the investigation.
