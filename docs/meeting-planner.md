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

A `MeetingSpec` (presets in `GameTuning.plannerPresets`) describes a lap as segments. Each has some
foods and a gate that needs `needed` of them, so `foods - needed` is that gate's slack. On top of that:
threats beside chosen foods (eat near danger), open-water threats you outgrow by lap two, the share
of fish swimming at you, how sharply meals change height, and speeds.

1. **Sizes** follow the fewest-meal route: any `needed` foods make the gate edible, any fewer don't.
2. **Times** are evenly spaced on screen, with a short beat beside danger and room after a gate's
   long swallow. Distances follow from a reference route's growth (`PlayerTimeline` mirrors the
   scene's zoom and swallow order).
3. **Heights** step by a share of the farthest you can swim between meals, so designed meals stay
   reachable and harder levels demand sharper dives.
4. **Spawns** are solved backward (`MeetingSolver`): simulate the fish's own free swim to the meeting
   time, then start it that far back, trying movement streams until it arrives at the planned height.
5. **Checks** (`EncounterAnalyzer`): for every fish, the fewest earlier meals that reach it, how many
   routes do, and how many misses it survives. A design is kept only if each gate needs its designed
   meals, has more than one route when it has slack, and every food is reachable.

Two rules apply only to planned levels, so fish you haven't met stay on schedule. A fish you've passed
gives way to one you haven't (it turns away). Two unmet fish separate only on screen; off screen they
pass each other.

## Presets

| | Fish | Gates after | Misses survived | Routes | Bot wins |
|---|---:|---|---|---|---|
| Easy | 19 | 1, 4, 7 meals | 3+, 3+, 3+ | 4, 77, 656 | 3/3 |
| Medium | 21 | 2, 4, 8 | 2, 2, 2 | 6, 8, 8 | 3/3 |
| Hard | 18 | 2, 6, 10 | 1, 0, 0 | 3, 3, 3 | 1/3 |

In the real scene every fish crosses within 0.05 s and 3 points of its plan on the reference route.
Eating only the minimum or everything shifts late meetings by up to about 0.7 s, but every fish still
arrives. Bot wins show a route exists; they aren't a difficulty ranking.

## Playing them

Debug builds: **Tuning > Meeting planner > Play Easy / Medium / Hard**, with a variation stepper for
other layouts of the same settings, or launch with `-arcadePlanner hard` (`hard.3` for variation 3).
These are practice runs: no clears, progress, or analytics. Recordings include each fish's role,
gate meals, routes, and slack.

`MeetingPlannerTests` checks the presets, and its marker-gated studies report them
(`build/arcade-development/meeting-study.request`) and the shipped campaign (`campaign-study.request`).
