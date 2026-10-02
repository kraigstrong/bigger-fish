# Independent NPC movement sequences

Phase 2 gives every arcade NPC its own reproducible movement generator, derived from the ecosystem seed and stable fish ID. Spawning still uses the original shared generator, with no added draws: placement, size, initial speed, initial timers, and art selection keep their existing sequence. Both Shallow Reef and Jelly Bloom use the new movement streams.

Turn intervals, vertical targets, and retarget intervals now consume only that fish’s stream. Swallowing or removing another fish cannot shift its random choices. Independent state is recreated on retry and released when a fish is removed. Newly added NPCs receive a stream too. Debug recordings identify the new behavior with `aiMovementRandomVersion: 1`.

Physical interactions remain intentional: losing prey changes food availability, growth changes size, and camera-dependent water bounds can still change distant fish. Phase 2 does not make those interactions independent or remove AI-on-AI eating.

## Mechanical validation

An eight-second isolated movement comparison covers all ten levels across both worlds. Skipping updates for fish 1 or fish 1–3, or removing those fish after spawning, leaves every other fish’s full internal movement state exactly equal to the control. Frame-schedule equivalence and slow-motion checks remain in place. Stream cleanup/retry lifecycle is also tested.

## Campaign comparison

The same three controllers and seed were run before and after at three phone sizes: 60 baseline rollouts and 60 new rollouts, including untouched-player ecology probes. Level tuning, layouts, and initial spawn budgets were unchanged. These controllers demonstrate routes; their failures do not prove a human route is impossible.

| Level | Width | Before wins / 3 | After wins / 3 |
|---|---:|---:|---:|
| 1 | 874 | 3 | 3 |
| 1 | 852 | 3 | 3 |
| 1 | 667 | 3 | 3 |
| 2 | 874 | 3 | 1 |
| 2 | 852 | 2 | 1 |
| 2 | 667 | 2 | 3 |
| 3 | 874 | 3 | 3 |
| 3 | 852 | 1 | 3 |
| 3 | 667 | 2 | 0 |
| 4 | 874 | 2 | 0 |
| 4 | 852 | 1 | 1 |
| 4 | 667 | 3 | 3 |
| 5 | 874 | 2 | 3 |
| 5 | 852 | 2 | 3 |
| 5 | 667 | 3 | 0 |

The new controllers find winning routes in 12 of 15 combinations. They find none for Level 3 at width 667, Level 4 at width 874, or Level 5 at width 667. Level 2 at widths 874 and 852 requires the cautious controller instead of the previous opportunist route.

At width 874, the cautious Level 5 opening changes:

| | First six catches | First six catch laps | Finish |
|---|---|---|---|
| Before | 1, 8, 18, 7, 21, 14 | 0.180, 0.237, 0.406, 0.775, 0.962, 1.047 | 21.3 s |
| After | 1, 8, 10, 18, 4, 13 | 0.180, 0.235, 0.392, 0.410, 0.499, 0.846 | 19.6 s |

The first two catches stay almost identical, but fish 10 becomes available before the old third catch. This new route has three close meals and its last threat occurs at approximately 58% of the run, versus four close meals and 67% before.

## Playtest decision

The user chose to play the new behavior before deciding whether to preserve the old opening. No level balance changes or seed searches were made. The existing campaign-winning-route/opening regression remains enabled and currently fails; the phase 2 PR is a draft pending phone playtesting and balance decisions. It must not be treated as merge-ready merely because stream-independence checks pass.

Raw requests/results and study logs are local under `build/arcade-development/phase2-before*` and `phase2-after*`. The study runner still executes the campaign regression, so the new study exits unsuccessfully despite writing its rollout results. The core suite can be checked separately while keeping that failure visible:

```sh
xcodebuild test -project BiggerFish.xcodeproj -scheme BiggerFish \
  -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' \
  -derivedDataPath build/arcade-development/DerivedData \
  '-skip-testing:BiggerFishTests/ArcadeSimulationTests/everyShippedLevelHasAWinningRouteAtThreePhoneSizes()'
```

Math Reef and FishKit are unchanged.

## Meal hitch follow-up

Phone playtesting reported a stutter at every player meal. `AVAudioPlayer` setup,
voice selection, seeking, and playback previously ran on the gameplay thread.
These now run exclusively on a serial audio worker; initialization is queued before
playback requests. The hidden meal counter is no longer updated during campaign
play. These remove two potential sources of main-thread work, but the physical-phone
cause has not yet been measured or confirmed resolved.

Debug run files now include `frame_hitch` for display gaps or update work longer
than about 41.7 ms, and `meal_hitch` for swallowing completion work longer than
about 8.3 ms. Frame entries include elapsed time, update work time, player meals,
remaining fish, and slowdown factor. These events use the existing asynchronous
local writer; neither diagnostics nor their clock reads are included in Release.
Rebuild on the phone and collect a few meals before concluding the hitch is fixed.
