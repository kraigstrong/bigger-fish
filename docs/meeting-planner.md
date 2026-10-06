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

## Reef Lab's ten levels

`GameTuning.reefLabSpecs` is a planned Shallow Reef, slot for slot with the campaign. Levels 2, 6, and 10
are the playtested Easy, Medium, and Hard (their names seed their layouts); the levels between step every
setting from one to the next, with speeds following Shallow Reef's authoring curve. Level 1 introduces gates
with a couple of big fish to avoid; level 8 is Hard's shape without walls; walls arrive at level 9.

Every level places all the big fish its settings ask for: one that can't be sized where it was asked for
(an open-water slot, or a meal late in the lap), or whose slot another threat already took, moves to the
latest earlier slot or meal where it can be.

**Frozen levels.** A playtested level keeps its shipped plan exactly as played (`GameTuning.reefLabFrozen`):
regenerating the data file leaves it alone, so later planner changes can't reshuffle it. All ten are frozen
as first played; remove a name to re-plan that level. As played, Easy, Medium, and Hard have one fewer big
fish than their settings ask for, level 8 has two big fish crossing together, and level 9 has one fish
slightly off its planned height.

| Level | Fish | Forks | Misses survived per gate | First playtest (an experienced player) |
|---|---:|---:|---|---|
| 1 | 12 | 2 | 3+, 2 | first try |
| 2 (Easy) | 17 | 3 | 3+, 2, 2 | first try |
| 3 | 19 | 3 | 1–2 | 5 tries: a spike above 4–8 |
| 4–5 | 21–23 | 3 | 1–2 | 2 tries each |
| 6 (Medium) | 22 | 3 | 1, 1, 1 | 2 tries |
| 7 | 25 | 4 | 1 | 3 tries |
| 8 | 26 | 4 | 1 | first try; "about perfect" |
| 9 | 30 | 4 | 1 | 20 tries; "about perfect" |
| 10 (Hard) | 29 | 4 | 0, 0, 0 on the short lanes | 17 tries; "about perfect" |

Hard's meals are 76–90% of your size and its gates barely edible, so every catch is a close call. Its
gates are walled (`walledGates`): a big fish crosses a tenth of a second before and after each gate,
just above and below it, too tight to slip between and too quick to swim around, so a gate can't be
dodged and saved for lap two. Starting a swallow makes you safe, so a big-enough player eats the gate
and the walls pass by. The last gate goes unwalled when its walls couldn't be outgrown by lap two.
Returning fish come back at 94–99% of the size you should be. Its first playtest took 17 attempts, deaths
spread from 2.8 to 7.5 s, in line with Shallow Reef 10 (18 attempts). Because near-size meals
grow routes apart quickly, Hard times its meetings against the player who barely makes each gate
(`timesTheEdge`).

Lanes are exclusive in every fork: the most anyone can eat on lap one is every single, every gate, and
one lane per fork. In the real scene every fish crosses within 0.05 s and 3 points of its plan on the
reference route, and every fish still arrives on the fewest-meal and fullest routes. Bots are poor at
choosing lanes; playtesting decides difficulty.

### Bonus levels 11–15

Five more levels at the difficulty of 8–10, each with its own feel. They unlock in order after level 10,
like any other level. All five are frozen as played.

| Level | Name | Feel | Fish | Misses survived per gate | First playtest |
|---|---|---|---:|---|---|
| 11 | Crossroads | two forks before every gate, one of them three meals high or one low; unwalled | 31 | 1, 1, 2 | 3 tries; "pretty easy" |
| 12 | Frenzy | quick meals, four walled gates; opens with a burst (three of the first four) | 34 | 1, 1, 1, 1 | 6 tries; "really fun" |
| 13 | Gauntlet | six big fish in open water, all back on lap two a little smaller than you; unwalled | 33 | 2, 2, 2, 1 | 27 tries; "the perfect level" |
| 14 | Heavyweights | few meals, each 85–93% of your size; one or two open each walled gate | 29 | 2, 1, 1, 1 | 53 tries across its fixes (3 on the last); "a great level" |
| 15 | Needle | most meals a beat from a big fish with little room; walled gates | 31 | 1, 1, 1 | 28 tries, most deaths in the first 5 s; "really fun" |

Fish only keep their plans if they don't touch where you could see it, and a player who eats more than the
reference route zooms out and sees further. Gauntlet's giants first came back at 92–98% of your size and
bumped each other off schedule, lining two of them up into an impassable wall; at 86–93% they pass clear,
and `bonusLevelsFishDontBumpOnTheWayToTheirMeetings` checks every bonus level in the real scene on the
fewest-meal, reference, and fullest routes. Heavyweights failed that check in a five-screen world and
passed in a 5.5-screen one, before anyone played it.

As first planned, Gauntlet's first giant (fish 9) also crossed over the high lane just as a big fish
guarded the low one, too tight to get through in 20 tries; it starts 380 points closer than planned, so it
crosses just after the first gate, above the swim to the next meal.

Heavyweights' giant fish 20 crossed between its second fork and the walled gate after it, filling mid-water:
from the high lane you'd swim through it, and from the low lane you'd have to wait under it and then climb
faster than you can to reach the gate between its walls. It starts 420 points farther than planned, so it
crosses a third of a second after the gate on every route, while you're swallowing it. That gate is also
smaller than planned (38.8 points, not 42): you keep growing for 0.35 s after a meal, and Kraig, one meal
short on the low lane, met it as little as a frame after swallowing the lane's meal, still growing, and lost
after a run that felt perfect. At 38.8 that meal makes the gate edible from the first frame after its
swallow; without it the gate still wins.

A swarm of small fish doesn't fit the planner yet. A gate must be edible after `needed` meals and not
after one fewer, with a few percent of margin either side, and a meal half your size grows you less than
that margin.

## Jelly Bloom 2

Jelly Bloom 2, now Jelly Bloom (ID `jelly-bloom`), plans Jelly Bloom the same way, with Shallow Reef 2's
ten fish curves and drifting jellyfish. A jelly wanders a tenth of a screen around its home and bobs, as a
pure function of time (`JellyDrift`), so the planner knows where every bell is at every step.

- **Jellies sit beside meetings.** A *pocket* meal crosses just above a dome, so you bounce as you eat it.
  A *bounce* meal (`Segment.bounceMeals`) crosses high above a pocket half a second later: out of
  swimming reach, inside the bounce's. A fork can be *split* by a jelly (`Fork.bounce`): its long lane
  starts on the dome and climbs with the bounce, its short lane passes under the tentacles. A *sting*
  meal crosses just under hanging tentacles; on levels 9–10 tentacles are a walled gate's upper wall
  wherever the bell fits over the gate with the gate still in mid-water (elsewhere, early in the level
  before the camera zooms out, the gate keeps both wall fish).
  *Open* jellies sit clear of the swim between two meals. Level 1's second plain meal is a *demo* fish
  that bounces off the first jelly while it's ahead of you on screen; the solver places that jelly
  under its swim.
- **Fish swim around them exactly as the game does.** `JellySwim` holds the steering and bounce the scene
  and the solver share. Like other unmet fish, a planned fish you haven't met ignores jellies while it's
  off screen, so bells can't knock its meeting off schedule; on screen and after you meet it, it steers
  and bounces as usual.
- **Routes know about bells.** The analyzer gets each jelly's pass: you must be above its dome or below
  its tentacles while it's in your column, or land on the dome and ride the bounce (`JellyRoutes`).
  `check` confirms bounce meals need their bounce and sting meals are close calls.
- **Bells keep apart and below the surface.** A fish with no room to rise above a dome slides over it
  instead of bouncing (Jelly Bloom 2 only), so nothing rattles between a dome and the surface.
- **Big fish in open water only have to stay clear of your path,** at any height that keeps their
  clearance: near drifting bells they rarely swim to one exact height.

The ramp: levels 1–2 have bells to bounce on if you like; from 3, sting meals; from 5, bounce meals,
then split forks; 9–10 wall gates with tentacles. Plans ship in `BiggerFish/JellyLabPlans.json`; create
`build/arcade-development/jelly-lab-plans.request` and run `MeetingPlannerTests` to regenerate it
(several minutes: replanning ten jelly levels is slow, so CI only checks the file matches the specs).
Levels 1–8 are frozen as played (`GameTuning.jellyLabFrozen`); regenerating keeps them.

## Shipped as data

Plans are deterministic, so Reef Lab's are made on the Mac and shipped in `BiggerFish/ReefLabPlans.json`:
no device plans while you play, and every device plays the same level. After changing `reefLabSpecs` or
the planner, regenerate the file by creating `build/arcade-development/reef-lab-plans.request` and running
`MeetingPlannerTests`; `bundledReefLabPlansMatchThePlanner` fails until you do. Frozen levels are kept. The tuner's other
variations still plan on the device.

## Playing them

Reef Lab and Jelly Bloom 2 were A/B tested as Shallow Reef 2 and Jelly Bloom 2 against the seeded
campaigns, won, and now are **Shallow Reef** and **Jelly Bloom**, under the original `shallow-reef` and
`jelly-bloom` IDs (progress and anonymous analytics). The seeded levels stay in `GameTuning` for the
debug tuner and the generator's tests (`GameScene(seeded: true)`). In Debug builds, **Tuning > Players**
resets a world's progress for a new player.

**Tuning > Shallow Reef variations** (Debug) plays other layouts of the same settings as practice runs, or launch with
`-arcadePlanner 10.3` (level 10, variation 3); `-arcadePlaytest shallow-reef.10` plays the level itself.
Recordings include each fish's role, fork lane, gate meals, routes, and slack.

`MeetingPlannerTests` checks the presets, and its marker-gated studies report them
(`build/arcade-development/meeting-study.request`) and the shipped campaign (`campaign-study.request`).
