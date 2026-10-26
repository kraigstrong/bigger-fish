# Meeting planner

Plans when and where you meet each fish, so a level's slack is designed rather than inherited from a
seed. Fish still swim freely: each one spawns wherever its own normal swim brings it across your path
at its planned moment. It plans every world: Shallow Reef's fish, Jelly Bloom's drifting jellies, and Kelp
Forest's kelp, where (as in Midnight Zone) each fish appears just off screen right before you meet it.

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
you; how sharply meals change height; speeds; and the world's width. An open-water threat never crosses
between a fork's lanes and the gate right after them: you're still swallowing a lane's meal high or low
when you need mid-water for the gate, so a big fish there walls off both lanes (it did on Shallow Reef's
Heavyweights).

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

`GameTuning.reefLabSpecs` is a planned Shallow Reef. Its levels 2, 6, and 10 are the playtested Easy, Medium,
and Hard (their names seed their layouts); the levels between step every setting from one to the next, with
speeds following Shallow Reef's authoring curve. Level 1 introduces gates with a couple of big fish to avoid;
level 8 is Hard's shape without walls; walls arrive at level 9.

**Reef Lab levels vs. Shallow Reef levels.** "Reef Lab level N" below means `reefLabSpecs[N - 1]`, the order
the settings step in (Kelp Forest and Midnight Zone borrow them by this index). Shallow Reef plays them in
`GameTuning.shallowReefOrder`, reordered from testers' 0.1 numbers (2026-10-09): Reef Lab 5 and 6 (Medium)
play as Shallow Reef 3 and 4, Reef Lab 3 and 4 as 5 and 6, Hard (Reef Lab 10) as 8, and Reef Lab 8 as the
finale, Shallow Reef 10. Levels 1, 2, 7, 9, and the bonus levels play in their own slots. Saves, the beta
report's level numbers, `-arcadePlaytest`, `-arcadePlanner`, and the tuner's buttons all use Shallow Reef's
numbers.

Every level places all the big fish its settings ask for: one that can't be sized where it was asked for
(an open-water slot, or a meal late in the lap), or whose slot another threat already took, moves to the
latest earlier slot or meal where it can be.

**Frozen levels.** A playtested level keeps its shipped plan exactly as played (`GameTuning.reefLabFrozen`):
regenerating the data file leaves it alone, so later planner changes can't reshuffle it. All ten are frozen
as first played; remove a name to re-plan that level. As played, Easy, Medium, and Hard have one fewer big
fish than their settings ask for, level 8 has two big fish crossing together, and level 9 has one fish
slightly off its planned height.

| Reef Lab level | Plays as Shallow Reef | Fish | Forks | Misses survived per gate | First playtest (an experienced player) | Testers, 0.1 (win rate, median tries to a first clear) |
|---|---|---:|---:|---|---|---|
| 1 | 1 | 12 | 2 | 3+, 2 | first try | 68%, 1 |
| 2 (Easy) | 2 | 17 | 3 | 3+, 2, 2 | first try | 37%, 2 |
| 3 | 5 | 19 | 3 | 1–2 | 5 tries: a spike above 4–8 | 12%, 4–5 |
| 4 | 6 | 21 | 3 | 1–2 | 2 tries | 18%, 6–10 |
| 5 | 3 | 23 | 3 | 1–2 | 2 tries | 50%, 2 |
| 6 (Medium) | 4 | 22 | 3 | 1, 1, 1 | 2 tries | 36%, 1 |
| 7 | 7 | 25 | 4 | 1 | 3 tries | 7%, 6–10 |
| 8 | 10 | 26 | 4 | 1 | first try; "about perfect" | 1%, 21+ |
| 9 | 9 | 30 | 4 | 1 | 20 tries; "about perfect" | 3%, 21+ |
| 10 (Hard) | 8 | 29 | 4 | 0, 0, 0 on the short lanes | 17 tries; "about perfect" | 20%, 4–5 |

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
Levels 1–10 are frozen as played (`GameTuning.jellyLabFrozen`); regenerating keeps them.

### Bonus levels 11–15

Five more at the difficulty of 8–10, unlocking in order after level 10. Three bring Shallow Reef's
favorite bonus levels into the bells; two are jelly feels of their own. They aren't frozen until they've
been played, and `bonusLevelsFishDontBumpOnTheWayToTheirMeetings` checks them in the real scene.

| Level | Name | Feel | Fish | Bells | Misses survived per gate |
|---|---|---|---:|---:|---|
| 11 | Bell Field | lots of jellies: dome and sting meals, a split fork, a bounce-only meal; fewer big fish; unwalled | 25 | 8 | 2, 2, 2 |
| 12 | Jelly Frenzy | Frenzy with meals on domes: quick meals, four walled gates, a burst opening | 34 | 3 | 1, 1, 1, 1 |
| 13 | Jelly Gauntlet | Gauntlet with four slightly smaller big fish threading between bells; unwalled | 31 | 2 | 1, 1, 1, 0 |
| 14 | Night Heavyweights | Heavyweights with meals on domes and tentacle-walled gates | 26 | 6 | 2, 1, 1, 1 |
| 15 | Curtain | most meals just under hanging tentacles; tentacle-walled gates; night | 26 | 6 | 2, 2, 1 |

Bell Field and Night Heavyweights each have one fish slightly off its planned height. Two tries didn't
make it: a level of forks split by jellies everywhere left no room for its big fish and bounce meals, and
Gauntlet's six full-size big fish steered around bells into about 130 bumps.

## Just-in-time jellies (Open Water)

The Open Water (Xcode builds only, `OpenWater.swift`) plans each level as the run reaches it, so Jelly Bloom's levels
there can't wait minutes for the searching solver. `MeetingPlanner.kelpPlan` plans them like Kelp Forest's, fish
appearing just off screen before their meetings, and keeps the bells where the designer puts them (pockets, stings,
split forks, open water), with the route's passes by them in the analysis, so bounce meals and close calls check as in
Jelly Bloom's own levels. A fish held to its way in can't bounce or steer round a bell without missing its meeting, so
it passes bells by (`GameScene.plannedFishMeetsJellies`), and the plan keeps every way in clear of them: a fish whose
usual way in would touch one glides in from higher or lower instead (`plannerJellyDetours`), or swims straight, while a
meal placed by a bell keeps its straight way in. `MeetingPlanner.kelpLayoutFits` turns down a layout whose design or
ways in don't fit in milliseconds, before the analyzer's second or so, so a run can try many. Planned this way, a
jelly level takes up to about 3 seconds in a Debug build, planned while the level before it plays.

## Shipped as data

Plans are deterministic, so every world's are made on the Mac and shipped as data: `ReefLabPlans.json`,
`JellyLabPlans.json`, `KelpPlans.json`, and `MidnightPlans.json` in `BiggerFish/`. Every device plays the same
level, and no device plans: the planner is in Xcode builds only (the tuner's other variations plan there), and a
Release build with a level missing from its file stops at launch. To regenerate a file, create its marker
(`build/arcade-development/reef-lab-plans.request`, `jelly-lab-plans.request`, `kelp-plans.request`, or
`midnight-plans.request`) and run `MeetingPlannerTests`; the writer deletes the marker once it's done.
`bundledReefLabPlansMatchThePlanner` fails until Reef Lab's file is current. Frozen levels are kept as they
are, and `FrozenLevelTests` pins each one's fingerprint, so changing a frozen level means editing its line there.
The files are written one field to a line, keys sorted, so a change to one fish reads as a small diff.

## Playing them

Reef Lab and Jelly Bloom 2 were A/B tested as Shallow Reef 2 and Jelly Bloom 2 against the seeded
campaigns, won, and now are **Shallow Reef** and **Jelly Bloom**, under the original `shallow-reef` and
`jelly-bloom` IDs (progress and anonymous analytics). The seeded campaigns are retired; git history has
them. In Debug builds, **Tuning > Players** resets a world's progress for a new player.

**Tuning > Shallow Reef variations** (Debug) plays other layouts of the same settings as practice runs, or launch with
`-arcadePlanner 10.3` (Shallow Reef level 10, variation 3); `-arcadePlaytest shallow-reef.10` plays the level
itself. Both use Shallow Reef's level numbers, as played.
Recordings include each fish's role, fork lane, gate meals, routes, and slack.

`MeetingPlannerTests` checks the presets, and its marker-gated studies report them
(`build/arcade-development/meeting-study.request`) and the shipped campaign (`campaign-study.request`).

## The wall report

The planner checks each meeting as an instant on one route, and most of the walls found in play came from what that
misses: fish knocked off their plans where only a fuller route's zoom shows them (Gauntlet), a giant crossing between a
fork and a walled gate (Heavyweights), a slowly overtaken giant beside a head-on one (Kelp Forest 8 and 13), a hook
plugging the one gap the threats left (Sunset Cove 15), a gate whose meals nobody could reach (Sunset Cove 12), fish
that ate their way past anything you could eat (Kelp Forest 9), and an opening narrower than you could cross in time
(Riptide Reef 3). The wall report (`WallReport.swift`, Xcode builds only) measures a level in the real scene instead,
so a wall shows before anyone plays it.

**How it measures.** A ghost run of a route records where every fish, hook and bell is at every step
(`GameScene.debugWallFrame`). `WallSweep` then sweeps the heights you could be at forward through those frames: each
step it widens the stretches of water you could reach by as far as you can rise or fall in a step (at the zoom then,
slower in kelp, faster for a moment after landing on a dome), and cuts out everything that would end your run as it
comes within reach: any bigger fish (its collision reach), a hook's bait and bend, and a bell's curtain of tentacles.
The widest stretch left, as a share of the water, is the opening at that step; the smallest over the lap is the
level's **tightest squeeze**, and the report names what bounds it. A sweep **pinned to a route** also eats the route's
meals: the first moment a meal is edible and in reach you're within reach of its body, then safe from fish for the
swallow (as in play) and growing afterward on the game's own clock. A food that goes by before you could get to it is skipped, growth and all,
and the report says why: still swallowing, still bigger than you, or where you could be instead and what cut you
off; a gate that goes by **closes** the route, as does the water closing. Swept **freely**, with no route, it's the 2026-10-12 measure, whose table
counted all the open water rather than the widest lane; the report shows both.

**What it runs.** Every level of the campaign and the prototypes, on the reference route, the fullest, every mix of
lanes (every single and gate, one lane per fork) and each mix's fewest-meal route; and it flags any fish that grows in
play (eating what you passed) past what the fullest route's player could eat when it comes back round (Kelp
Forest 9's snowball). Create `build/arcade-development/wall-report.request` (optionally naming world ids and level
numbers) and run `WallReportTests`: wall-report.md and wall-report.json are written beside it in about five minutes.
`wall-history.request` reports the known walls as they were before their fixes and after (plans from the past are read
from `wall-history/*.json`, taken from the plans files' git history).

**Checked against history.** The free sweep's all-water number reproduces the 2026-10-12 table where that table
decided something: Frenzy 10.4% (10.5% then), Riptide Reef 3's first layout 7.2% (7.3%), Kelp Forest 10 17.5%
(17.8%), Jelly Bloom 8 26% (23%). Gauntlet's three fixes read 0.5% as first planned, 1.9% with its first gap opened, and
9.4% once its giants stopped bumping; Kelp Forest 13's first layout closes outright (fish 13, 14 and 16, the wall of
giants) where the shipped one is 16%; Sunset Cove 15 reads 6.9% with hook 4 named at its wall before #176 and 9.8%
after; Sunset Cove 12 isn't a squeeze (11%) and reads instead as its gate 16 out of reach on the route through 13: the
reach check's blind spot. The levels with walled gates read tighter than the old table (Heavyweights closes, Kelp
Forest 14 reads 0.7% against 8%): a gate a hair bigger than you for the frames you're still growing from the lane meal
shuts the water with its two walls, which the old bot, eating at its own pace, didn't see.

**A report, never a gate.** No test fails on a level's squeeze: the route bot loses some of the best levels, and
Heavyweights is 5.7% and a favorite. What counts as a wall is a product call.

### The campaign (2026-10-25)

| world | level | name | fish | danger | free (fish): lane / all water | free (all hazards) | routes open | best route | reference route | outgrown |
|---|---|---|---|---|---|---|---|---|---|---|
| shallow-reef | 1 | Reef Lab 1 | 12 | 0 | 68.2% / 68.2% | 68.2% / 68.2% | 6 / 6 | fewest LS: 75.0% | 68.2% at 5.1 s: fish 7 (threat, r 30) / the surface |  |
| shallow-reef | 2 | Easy | 17 | 2 | 29.1% / 54.5% | 29.1% / 54.5% | 12 / 12 | fewest SLL: 31.4% | 29.1% at 5.4 s: the floor / fish 10 (threat, r 40) |  |
| shallow-reef | 3 | Reef Lab 5 | 23 | 6 | 33.8% / 48.8% | 33.8% / 48.8% | 10 / 16 | fewest SLS: 27.8% | closed at 7.7 s: gate 16 is out of reach (bigger than you: r 29.9 vs 28.4) (−1 meals) |  |
| shallow-reef | 4 | Medium | 22 | 4 | 24.5% / 30.4% | 24.5% / 30.4% | 8 / 16 | lanes SLS: 23.9% | 18.8% at 3.0 s: fish 5 (threat, r 27) / the surface |  |
| shallow-reef | 5 | Reef Lab 3 | 19 | 5 | 21.3% / 31.9% | 21.3% / 31.9% | 16 / 16 | lanes SSS: 22.0% | 20.3% at 5.1 s: the floor / fish 11 (threat, r 39) |  |
| shallow-reef | 6 | Reef Lab 4 | 21 | 6 | 34.4% / 49.3% | 34.4% / 49.3% | 15 / 15 | lanes SSS: 21.2% | 17.2% at 6.3 s: fish 13 (threat, r 51) / the surface |  |
| shallow-reef | 7 | Reef Lab 7 | 25 | 7 | 16.1% / 31.6% | 16.1% / 31.6% | 16 / 30 | lanes SLSS: 14.1% | closed at 6.7 s: gate 17 is out of reach (bigger than you: r 32.0 vs 31.7) (−1 meals) |  |
| shallow-reef | 8 | Hard | 29 | 9 | 8.3% / 9.1% | 8.3% / 9.1% | 26 / 30 | lanes SLSS: 12.8% (−1 meals) | 12.4% at 4.9 s: fish 14 (threat, r 45) / the surface |  |
| shallow-reef | 9 | Reef Lab 9 | 30 | 8 | 11.5% / 21.5% | 11.5% / 21.5% | 30 / 30 | reference: 14.7% | 14.7% at 5.4 s: fish 15 (threat, r 41) / the surface | fish 18 65→80 (you 77, lap 2) |
| shallow-reef | 10 | Reef Lab 8 | 26 | 8 | 25.2% / 40.4% | 25.2% / 40.4% | 14 / 30 | fewest SLSS: 22.7% | 21.7% at 2.9 s: the floor / fish 5 (threat, r 26) |  |
| shallow-reef | 11 | Crossroads | 31 | 10 | 20.2% / 40.3% | 20.2% / 40.3% | 108 / 108 | fewest LSLSSS: 14.1% | 13.0% at 6.8 s: the floor / fish 18 (threat, r 59) |  |
| shallow-reef | 12 | Frenzy | 34 | 12 | 5.5% / 10.4% | 5.5% / 10.4% | 32 / 32 | lanes LSLS: 6.4% (−1 meals) | 5.5% at 5.7 s: the floor / fish 16 (threat, r 44) |  |
| shallow-reef | 13 | Gauntlet | 33 | 12 | 9.4% / 9.4% | 9.4% / 9.4% | 24 / 32 | lanes SLSS: 10.6% (−1 meals) | closed at 6.6 s: gate 17 is out of reach (bigger than you: r 33.1 vs 30.4; then …; then bigger than you: r 33.1 vs 30.9) (−1 meals) |  |
| shallow-reef | 14 | Heavyweights | 29 | 9 | closed | closed | 18 / 32 | fewest LSLS: 14.4% | closed at 7.5 s: the water closed (fish 21 273–443, fish 23 -27–166; water -26–426, you r 40) | fish 20 80→94 (you 93, lap 2) |
| shallow-reef | 15 | Needle | 31 | 10 | 12.3% / 24.6% | 12.3% / 24.6% | 16 / 30 | fewest SLLS: 21.7% | closed at 6.4 s: gate 20 is out of reach (bigger than you: r 33.6 vs 31.3) (−1 meals) |  |
| jelly-bloom | 1 | Jelly Lab 1 | 12 | 1 | 35.3% / 59.4% | 35.3% / 39.6% | 5 / 5 | fewest LL: 30.1% | 21.4% at 5.5 s: jelly 2 / the surface |  |
| jelly-bloom | 2 | Jelly Lab 2 | 18 | 2 | 31.8% / 55.0% | 31.8% / 48.4% | 16 / 16 | fewest SSL: 19.8% | 15.2% at 7.0 s: jelly 2 / the surface |  |
| jelly-bloom | 3 | Jelly Lab 3 | 19 | 3 | 32.0% / 56.5% | 32.0% / 47.5% | 12 / 16 | reference: 18.6% (−1 meals) | 18.6% at 4.2 s: the floor / jelly 1 (−1 meals) |  |
| jelly-bloom | 4 | Jelly Lab 4 | 21 | 5 | 23.5% / 35.2% | 23.5% / 35.2% | 15 / 15 | fewest SLL: 19.3% | 14.7% at 6.6 s: the floor / jelly 2 |  |
| jelly-bloom | 5 | Jelly Lab 5 | 25 | 6 | 23.2% / 26.3% | 23.2% / 26.3% | 9 / 17 | fewest SLS: 18.8% | closed at 7.9 s: gate 18 is out of reach (at y 273 you could be at -17–210) (−1 meals) |  |
| jelly-bloom | 6 | Jelly Lab 6 | 25 | 5 | 13.5% / 32.4% | 13.5% / 31.5% | 17 / 17 | lanes SSS: 12.9% | 12.9% at 4.9 s: the floor / jelly 1 |  |
| jelly-bloom | 7 | Jelly Lab 7 | 27 | 9 | 12.5% / 21.1% | 5.5% / 5.5% | 25 / 33 | lanes SSLS: 22.2% (−2 meals) | 8.2% at 6.1 s: the floor / fish 17 (threat, r 46) (−1 meals) |  |
| jelly-bloom | 8 | Jelly Lab 8 | 26 | 8 | 15.6% / 26.0% | 6.8% / 6.8% | 0 / 30 | none | closed at 6.2 s: the water closed (fish 15 201–371, fish 16 106–238, jelly 5 -7–114; water 0–400, you r 31) | fish 13 64→97 (you 74, lap 2) |
| jelly-bloom | 9 | Jelly Lab 9 | 28 | 9 | 8.6% / 20.0% | 6.8% / 12.4% | 26 / 30 | lanes LLSS: 8.1% | 6.8% at 5.7 s: fish 16 (threat, r 48) / the surface |  |
| jelly-bloom | 10 | Jelly Lab 10 | 28 | 9 | 20.4% / 39.5% | 14.1% / 22.4% | 12 / 26 | lanes SSSS: 14.5% | closed at 9.4 s: gate 28 is out of reach (bigger than you: r 57.5 vs 53.5) (−1 meals) | fish 8 67→79 (you 77, lap 2) |
| jelly-bloom | 11 | Bell Field | 25 | 10 | 40.6% / 46.0% | 21.8% / 26.7% | 13 / 17 | reference: 18.4% | 18.4% at 10.4 s: jelly 4 / the surface |  |
| jelly-bloom | 12 | Jelly Frenzy | 34 | 12 | 14.6% / 21.1% | 14.6% / 19.1% | 17 / 33 | fewest SLSS: 13.6% | 13.5% at 3.2 s: the floor / jelly 1 | fish 11 83→118 (you 94, lap 2) |
| jelly-bloom | 13 | Jelly Gauntlet | 31 | 13 | 16.3% / 28.9% | 16.3% / 28.9% | 17 / 33 | fewest LSLS: 13.8% | closed at 9.5 s: gate 25 is out of reach (bigger than you: r 55.5 vs 51.8; then …; then bigger than you: r 55.5 vs 52.2) (−1 meals) |  |
| jelly-bloom | 14 | Night Heavyweights | 25 | 6 | 23.0% / 32.8% | 13.5% / 21.5% | 24 / 24 | fewest LLLS: 18.3% | 14.3% at 8.0 s: the floor / jelly 4 |  |
| jelly-bloom | 15 | Curtain | 26 | 10 | 11.3% / 20.4% | 11.3% / 20.4% | 24 / 28 | fewest LLSS: 12.9% | 5.6% at 8.8 s: fish 22 (threat, r 65) / the surface | fish 10 71→78 (you 77, lap 2); fish 15 70→79 (you 77, lap 2) |
| kelp-forest | 1 | Kelp Forest 1 | 12 | 0 | 62.9% / 64.2% | 62.9% / 64.2% | 6 / 6 | fewest LS: 64.2% | 29.5% at 3.5 s: fish 4 (threat, r 26) / the surface |  |
| kelp-forest | 2 | Kelp Forest 2 | 18 | 0 | 25.8% / 31.8% | 25.8% / 31.8% | 16 / 16 | reference: 25.8% | 25.8% at 5.0 s: fish 9 (threat, r 36) / the surface |  |
| kelp-forest | 3 | Kelp Forest 3 | 19 | 2 | 35.0% / 58.3% | 35.0% / 58.3% | 16 / 16 | reference: 35.1% | 35.1% at 5.2 s: the floor / fish 11 (threat, r 32) |  |
| kelp-forest | 4 | Kelp Forest 4 | 21 | 5 | 28.9% / 28.9% | 28.9% / 28.9% | 8 / 15 | lanes SLS: 28.6% | 26.2% at 3.2 s: the floor / fish 5 (threat, r 27) |  |
| kelp-forest | 5 | Kelp Forest 5 | 23 | 4 | 27.4% / 42.4% | 27.4% / 42.4% | 16 / 16 | fewest SLS: 19.2% | 15.3% at 8.5 s: the floor / fish 18 (threat, r 52) |  |
| kelp-forest | 6 | Kelp Forest 6 | 23 | 4 | 26.4% / 37.4% | 26.4% / 37.4% | 10 / 16 | fewest LLS: 25.1% | 4.5% at 6.2 s: the floor / fish 13 (threat, r 51) (−1 meals) |  |
| kelp-forest | 7 | Kelp Forest 7 | 25 | 5 | 16.5% / 25.2% | 16.5% / 25.2% | 10 / 26 | fewest LLSS: 7.4% | closed at 6.8 s: gate 17 is out of reach (bigger than you: r 32.5 vs 30.9) (−1 meals) |  |
| kelp-forest | 8 | Kelp Forest 8 | 26 | 8 | 14.1% / 30.0% | 14.1% / 30.0% | 9 / 27 | lanes SLSS: 8.6% (−1 meals) | closed at 6.7 s: gate 17 is out of reach (bigger than you: r 33.0 vs 31.0) (−1 meals) |  |
| kelp-forest | 9 | Kelp Forest 9 | 30 | 10 | 15.6% / 16.0% | 15.6% / 16.0% | 16 / 30 | lanes LLSS: 14.4% | 13.2% at 5.1 s: fish 14 (threat, r 46) / the surface | fish 16 66→82 (you 76, lap 2); fish 26 62→78 (you 76, lap 2) |
| kelp-forest | 10 | Kelp Forest 10 | 30 | 9 | 14.7% / 17.5% | 14.7% / 17.5% | 8 / 30 | lanes SLSS: 17.1% (−1 meals) | closed at 6.0 s: the water closed (fish 18 3–160, fish 20 178–261, fish 19 260–426; water -10–410, you r 32) (−1 meals) |  |
| kelp-forest | 11 | Kelp Forest 11 | 31 | 8 | 21.7% / 28.6% | 21.7% / 28.6% | 54 / 108 | lanes LLSSSS: 24.0% (−1 meals) | 23.9% at 6.1 s: fish 17 (threat, r 68) / the surface |  |
| kelp-forest | 12 | Kelp Forest 12 | 34 | 12 | 17.0% / 20.4% | 17.0% / 20.4% | 17 / 33 | fullest: 17.6% | 16.8% at 3.5 s: fish 6 (threat, r 26) / the surface | fish 11 81→105 (you 98, lap 2); fish 24 81→99 (you 98, lap 2) |
| kelp-forest | 13 | Kelp Forest 13 | 33 | 13 | 16.2% / 21.8% | 16.2% / 21.8% | 10 / 32 | fewest SLLS: 17.1% | closed at 3.8 s: gate 7 is out of reach (bigger than you: r 19.6 vs 18.1) (−1 meals) | fish 24 96→122 (you 115, lap 2); fish 10 92→135 (you 115, lap 3) |
| kelp-forest | 14 | Kelp Forest 14 | 29 | 9 | 0.7% / 0.7% | 0.7% / 0.7% | 12 / 32 | lanes SLSS: 14.4% | 9.0% at 7.4 s: fish 23 (threat, r 59) / the surface |  |
| kelp-forest | 15 | Kelp Forest 15 | 31 | 7 | 5.3% / 5.3% | 5.3% / 5.3% | 9 / 30 | lanes LSSL: 7.8% (−1 meals) | closed at 6.5 s: gate 21 is out of reach (at y 185 you could be at 326–421) | fish 25 61→78 (you 71, lap 2) |
| sunset-cove | 1 | Sunset Cove 1 | 12 | 0 | 63.2% / 63.2% | 49.4% / 63.2% | 8 / 8 | fewest SL: 52.3% | 39.8% at 3.9 s: the floor / fish 5 (threat, r 28) |  |
| sunset-cove | 2 | Sunset Cove 2 | 18 | 1 | 24.2% / 31.4% | 24.2% / 31.4% | 10 / 12 | fewest LLL: 24.6% | 24.2% at 4.9 s: the floor / fish 9 (threat, r 37) |  |
| sunset-cove | 3 | Sunset Cove 3 | 19 | 4 | 33.0% / 58.7% | 33.0% / 55.3% | 16 / 16 | lanes SSS: 33.2% | 24.2% at 3.0 s: fish 5 (threat, r 29) / the surface |  |
| sunset-cove | 4 | Sunset Cove 4 | 21 | 4 | 31.2% / 50.9% | 26.5% / 46.2% | 15 / 15 | lanes SLL: 21.9% | 21.4% at 3.2 s: the floor / fish 5 (threat, r 25) |  |
| sunset-cove | 5 | Sunset Cove 5 | 23 | 7 | 21.2% / 32.9% | 21.2% / 32.9% | 8 / 16 | fewest LLL: 20.0% | closed at 7.4 s: gate 16 is out of reach (bigger than you: r 30.9 vs 30.4) (−1 meals) | fish 17 48→66 (you 63, lap 2) |
| sunset-cove | 6 | Sunset Cove 6 | 23 | 5 | 19.3% / 24.2% | 19.3% / 24.2% | 8 / 16 | fewest LLS: 6.4% | closed at 7.5 s: gate 16 is out of reach (bigger than you: r 31.1 vs 29.8) (−1 meals) |  |
| sunset-cove | 7 | Sunset Cove 7 | 25 | 7 | 17.3% / 17.3% | 14.8% / 17.3% | 22 / 30 | fewest LLSS: 14.4% | closed at 6.6 s: gate 17 is out of reach (bigger than you: r 33.8 vs 33.3) (−1 meals) | fish 16 65→79 (you 77, lap 2) |
| sunset-cove | 8 | Sunset Cove 8 | 26 | 10 | 19.7% / 32.3% | 19.7% / 32.3% | 30 / 30 | reference: 19.3% | 19.3% at 5.2 s: the floor / fish 12 (threat, r 48) | fish 8 65→79 (you 74, lap 2); fish 16 64→78 (you 74, lap 2) |
| sunset-cove | 9 | Sunset Cove 9 | 30 | 10 | 12.8% / 12.8% | 12.8% / 12.8% | 26 / 30 | reference: 12.6% | 12.6% at 2.9 s: the floor / fish 5 (threat, r 27) | fish 17 66→84 (you 77, lap 2) |
| sunset-cove | 10 | Sunset Cove 10 | 30 | 9 | 13.5% / 17.0% | 13.5% / 17.0% | 15 / 30 | lanes SLSS: 15.7% | 13.5% at 4.3 s: fish 11 (threat, r 36) / the surface | fish 26 60→84 (you 79, lap 2) |
| sunset-cove | 11 | Sunset Cove 11 | 31 | 8 | 21.7% / 21.7% | 17.4% / 21.7% | 54 / 124 | lanes LSLLLS: 17.2% (−2 meals) | closed at 7.9 s: gate 21 is out of reach (bigger than you: r 36.5 vs 33.9) (−1 meals) |  |
| sunset-cove | 12 | Sunset Cove 12 | 34 | 10 | 12.7% / 20.3% | 11.2% / 18.1% | 8 / 24 | lanes SSLS: 10.2% (−1 meals) | closed at 5.9 s: gate 16 is out of reach (at y 191 you could be at 342–407) |  |
| sunset-cove | 13 | Sunset Cove 13 | 33 | 13 | 14.8% / 14.8% | 14.8% / 14.8% | 16 / 32 | fewest SLLS: 14.2% | closed at 8.3 s: the water closed (fish 24 -54–235, fish 23 81–332; water -52–452, you r 51) | fish 18 95→128 (you 117, lap 2); fish 31 95→127 (you 117, lap 3) |
| sunset-cove | 14 | Sunset Cove 14 | 29 | 8 | 1.9% / 1.9% | 1.9% / 1.9% | 8 / 32 | lanes SLSS: 16.2% | closed at 7.4 s: the water closed (fish 21 279–476, fish 23 16–157, fish 22 153–310; water -27–427, you r 38) |  |
| sunset-cove | 15 | Sunset Cove 15 | 31 | 10 | 9.8% / 19.2% | 9.8% / 12.0% | 8 / 30 | lanes LLSS: 8.7% (−1 meals) | closed at 6.4 s: gate 20 is out of reach (bigger than you: r 33.1 vs 30.8) (−1 meals) | fish 10 67→79 (you 75, lap 2); fish 16 67→78 (you 75, lap 2); fish 27 62→78 (you 75, lap 2); fish 10 67→79 (you 75, lap 3) |
| midnight-zone | 1 | Midnight Zone 1 | 12 | 0 | 69.2% / 69.2% | 69.2% / 69.2% | 6 / 6 | fewest LS: 70.7% | 41.4% at 4.0 s: the floor / fish 5 (threat, r 25) |  |
| midnight-zone | 2 | Midnight Zone 2 | 18 | 0 | 30.3% / 54.0% | 30.3% / 54.0% | 16 / 16 | fewest SLS: 31.1% | 21.7% at 5.3 s: fish 11 (threat, r 42) / the surface |  |
| midnight-zone | 3 | Midnight Zone 3 | 19 | 5 | 12.5% / 19.9% | 12.5% / 19.9% | 14 / 16 | fewest SSS: 39.7% | 27.5% at 5.2 s: fish 11 (threat, r 39) / the surface |  |
| midnight-zone | 4 | Midnight Zone 4 | 21 | 6 | 19.5% / 29.7% | 19.5% / 29.7% | 8 / 15 | reference: 19.3% | 19.3% at 6.2 s: the floor / fish 12 (threat, r 43) |  |
| midnight-zone | 5 | Midnight Zone 5 | 23 | 5 | 27.1% / 48.6% | 27.1% / 48.6% | 16 / 16 | lanes SLS: 26.4% | 14.5% at 6.1 s: the floor / fish 13 (threat, r 48) |  |
| midnight-zone | 6 | Midnight Zone 6 | 25 | 8 | 15.5% / 19.2% | 15.5% / 19.2% | 20 / 30 | reference: 15.8% (−1 meals) | 15.8% at 5.5 s: fish 14 (threat, r 38) / the surface (−1 meals) |  |
| midnight-zone | 7 | Midnight Zone 7 | 26 | 7 | 17.6% / 29.7% | 17.6% / 29.7% | 16 / 30 | fewest SLSS: 17.8% | closed at 6.7 s: gate 17 is out of reach (bigger than you: r 32.4 vs 30.0) (−1 meals) | fish 9 62→75 (you 72, lap 2); fish 9 62→77 (you 72, lap 3) |
| midnight-zone | 8 | Midnight Zone 8 | 30 | 9 | 16.5% / 17.4% | 16.5% / 17.4% | 30 / 30 | fewest LLSS: 17.5% | 17.4% at 6.3 s: fish 18 (threat, r 69) / fish 19 (threat, r 43) | fish 9 68→90 (you 78, lap 2); fish 26 64→83 (you 78, lap 2) |
| midnight-zone | 9 | Midnight Zone 9 | 30 | 11 | 8.7% / 8.7% | 8.7% / 8.7% | 18 / 30 | lanes SLSS: 25.5% (−1 meals) | closed at 6.2 s: gate 20 is out of reach (bigger than you: r 35.2 vs 33.0) (−1 meals) | fish 11 73→88 (you 81, lap 2); fish 11 73→88 (you 81, lap 2) |
| midnight-zone | 10 | Midnight Zone 10 | 30 | 10 | 15.7% / 18.6% | 15.7% / 18.6% | 15 / 26 | fewest SLSS: 15.5% | closed at 5.9 s: the water closed (fish 20 134–240, fish 18 -1–121, fish 19 229–404; water -12–412, you r 33) (−1 meals) |  |
| midnight-zone | 11 | Midnight Zone 11 | 31 | 9 | 22.5% / 36.1% | 22.5% / 36.1% | 72 / 108 | lanes SLLSSS: 22.3% (−1 meals) | closed at 8.0 s: gate 21 is out of reach (bigger than you: r 35.6 vs 33.3) (−1 meals) |  |
| midnight-zone | 12 | Midnight Zone 12 | 34 | 10 | 13.7% / 17.9% | 13.7% / 17.9% | 17 / 33 | lanes LLLS: 14.3% | 13.8% at 7.9 s: the floor / fish 23 (threat, r 66) |  |
| midnight-zone | 13 | Midnight Zone 13 | 33 | 15 | 9.8% / 10.2% | 9.8% / 10.2% | 19 / 32 | lanes LSSL: 9.4% (−3 meals) | 4.8% at 8.9 s: the floor / fish 26 (threat, r 91) | fish 8 94→122 (you 115, lap 2) |
| midnight-zone | 14 | Midnight Zone 14 | 29 | 8 | 0.4% / 0.4% | 0.4% / 0.4% | 24 / 32 | fewest LSLS: 29.1% | 11.2% at 7.4 s: fish 23 (threat, r 54) / the surface |  |
| midnight-zone | 15 | Midnight Zone 15 | 31 | 11 | 11.2% / 11.2% | 11.2% / 11.2% | 16 / 30 | fewest LLSS: 19.7% | closed at 6.6 s: gate 21 is out of reach (bigger than you: r 33.9 vs 31.4) (−1 meals) | fish 17 66→110 (you 76, lap 2) |
| riptide-reef | 1 | Riptide Reef 1 | 12 | 0 | 60.1% / 63.4% | 60.1% / 63.4% | 8 / 8 | fewest LS: 62.0% | 60.1% at 3.6 s: fish 4 (threat, r 29) / the surface |  |
| riptide-reef | 2 | Riptide Reef 2 | 23 | 6 | 35.6% / 50.7% | 35.6% / 50.7% | 16 / 16 | lanes SSS: 35.5% | 27.5% at 3.2 s: the floor / fish 5 (threat, r 28) |  |
| riptide-reef | 3 | Riptide Reef 3 | 34 | 12 | 9.6% / 12.5% | 9.6% / 12.5% | 12 / 32 | fewest SSLS: 9.9% | 9.6% at 7.0 s: the floor / fish 21 (threat, r 54) | fish 18 86→101 (you 96, lap 2) |

Shares of the water open at the tightest moment. "Free" sweeps the water with nothing eaten (the widest lane, then all
the open water: the 2026-10-12 measure); "routes open" counts the routes a sweep got through, foods skipped where it
had to (and the route recorded again without them, so its growth, zoom and speed are the player's who skipped them); "best route" is the open route with the widest lane at its tightest; "reference route" is the one the meetings
were timed against. Every route's line is in `build/arcade-development/wall-report.md` after a run.
