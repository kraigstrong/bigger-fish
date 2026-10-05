# Meeting planner (prototype)

Plans when and where you meet each fish, so a level's slack is designed rather than inherited from a
seed. Fish still swim freely: each one spawns wherever its own normal swim brings it across your path
at its planned moment. Fish-only (Shallow Reef rules) for now; Jelly Bloom's jellyfish steering isn't
modeled yet.

## What we keep from today's game

These are why the current campaign is fun, and the planner leaves them alone:

- **Free-roaming fish.** Same steering, speeds, turns, and vertical wandering (`FreeSwim.swift`, shared
  with gameplay). No patrols or pockets.
- **The first-pass food race.** Fish are protected from AI eating until you pass them; a fish you miss
  is fair game for bigger fish, which grow into threats.
- **Near-size gates.** A gate is a fish about your size that's only edible after enough meals ("eat
  1 and 2, then the orange one"). Planned gates land 1–10% under your size, so close-call slow motion
  and the struggle still happen.
- **Memorizable routes.** Fixed seeds, fixed steps, and per-fish streams make every retry identical,
  and neighboring meetings get different colors.
- **Area growth, player-favored ties, last-fish-swimming wins, second-lap cleanup.**

The shipped campaign through the same analysis (a ghost run, then a replay eating the fullest route):
you meet 15–20 fish on the first lap but can eat only 6–12 of them, and every level has at least one
gate with no misses to spare. The favorites (Jelly Bloom 8 and 9, Shallow Reef 10) are full of
single-route, zero-slack gates: memorized paths. What the seed decided, and the planner now sets, is
how many of those a level has and where.

## How a level is planned

A `MeetingSpec` (presets in `GameTuning.plannerPresets`) describes a lap as segments. Each has single
meals, forks, and a gate that needs `needed` meals. A fork is a high lane and a low lane crossing at about
the same moment, too far apart to take both: the long lane has more meals, and any danger in the fork
crosses beside it. When the short lanes still reach `needed`, both lanes are real options and the long
lane buys margin for later; playtesting showed zero slack leaves only one obvious route. On top of that:
threats beside chosen foods (eat near danger); open-water threats that come back on lap two near the
size you should have reached (`lapTwoSize`), so lap two tests lap one; the share of fish swimming at
you; how sharply meals change height; speeds; and the world's width.

All planned meetings happen on the first lap: a fish's first crossing can't wait for lap two, and as you
grow the camera zooms out and the lap speeds by (about ten seconds). A wider world buys a little more
room; the rest of a level's length comes from lap two.

1. **Sizes** follow the fewest-meal route: whichever lanes you take, any `needed` meals make the gate
   edible, and no `needed - 1` do.
2. **Times** are evenly spaced on screen: a fork's lanes a beat apart, extra room to reach either
   lane and come back, a short beat beside danger, and room after a gate's long swallow. Distances follow from a reference route's growth (`PlayerTimeline` mirrors the
   scene's zoom and swallow order).
3. **Heights**: single meals step by a share of the farthest you can swim between them, so they stay
   reachable and harder levels demand sharper dives. Fork lanes sit near the top and bottom; the meals
   either side of a fork stay mid-water so both lanes are in reach.
4. **Spawns** are solved backward (`MeetingSolver`): simulate the fish's own free swim to the meeting
   time, then start it that far back, trying movement streams until it arrives at the planned height.
   A head-on fish met late in the lap starts out swimming your way and makes one ordinary turn while
   it's far off screen. Fish you overtake come from the slow end of the speed range: a fish swimming
   your way near your speed creeps toward you for seconds, as if fleeing.
5. **Checks** (`EncounterAnalyzer`): for every fish, the fewest earlier meals that reach it, how many
   routes do, and how many misses it survives. A design is kept only if each gate needs its designed
   meals, has more than one route when it has slack, and every food is reachable.

Two rules apply only to planned levels, so fish you haven't met stay on schedule. A fish you've passed
gives way to one you haven't (it turns away). Two unmet fish separate only on screen; off screen they
pass each other.

## Presets

| | Fish | Forks | Misses survived per gate | Routes into gates | Danger meals | Bot wins |
|---|---:|---:|---|---|---:|---|
| Easy | 17 | 3 | 3+, 2, 2 | 4, 60, 34 | 3 | 3/3, about 14 s |
| Medium | 22 | 3 | 1, 1, 1 | 4, 31, 28 | 5 | 1/3, 18 s |
| Hard | 29 | 4 | 0, 0, 0 on the short lanes | 3, 16, 99 | 10 | 0/3 |

Hard's meals are 76–90% of your size and its gates barely edible, so every catch is a close call. Its
gates are walled (`walledGates`): a big fish crosses a tenth of a second before and after each gate,
just above and below it, too tight to slip between and too quick to swim around, so a gate can't be
dodged and saved for lap two. Starting a swallow makes you safe, so a big-enough player eats the gate
and the walls pass by. The last gate goes unwalled when its walls couldn't be outgrown by lap two.
Returning fish come back at 94–99% of the size you should be. Playtested: 17 attempts to the first win,
deaths spread from 2.8 to 7.5 s, in line with Shallow Reef 10 (18 attempts). Because near-size meals grow routes apart quickly, Hard times its meetings against
the player who barely makes each gate (`timesTheEdge`).

Lanes are exclusive in every fork: the most anyone can eat on lap one is every single, every gate, and
one lane per fork. In the real scene every fish crosses within 0.05 s and 3 points of its plan on the
reference route, and every fish still arrives on the fewest-meal and fullest routes. Bots are poor at
choosing lanes; playtesting decides difficulty (an earlier, linear Hard was beaten on the second try).

## Playing them

Debug builds show **Reef Lab** as the third world on the map: Easy, Medium, and Hard, all open, with
clears and best times saved like any world (`reef-lab.1`–`.3`). These are new levels, not remakes. For
an A/B comparison, their speeds match Shallow Reef 2, 6, and 10. Reef Lab is hidden from Release and
TestFlight builds (`ArcadeWorld.mapWorlds`).

**Tuning > Meeting planner** plays other variations of the same presets as practice runs, or launch
with `-arcadePlanner hard` (`hard.3` for variation 3). Recordings include each fish's role, gate
meals, routes, and slack.

`MeetingPlannerTests` checks the presets, and its marker-gated studies report them
(`build/arcade-development/meeting-study.request`) and the shipped campaign (`campaign-study.request`).
