# Encounter difficulty system

**Superseded campaign:** all ten levels now use the freely moving encounter model. See [the current playtest report](jelly-bloom-free-campaign.md). The measurements below describe earlier prototypes.


## Historical first trial: freely moving Level 2

The October 3 playtest changes **only Level 2's encounter generation and movement tuning**. The earlier uniform protected-patrol campaign below is historical for this level; it did not deliver the speed, variety, or food-race tension the player wanted. Levels 1 and 3–10 retain their geometry/tuning while we test the replacement.

- Most fish roam the world immediately with speeds 40–175 points/second; one in four lingers within a broad horizontal area. Protection no longer cages their movement.
- Starting authoring groups contain 4, 3, 5, and 4 fish, with 3, 2, 3, and 3 edible at the expected arrival size. They are an internal budget, not visible wave boundaries. Seeded placement alternates high/low food and puts some predators near the upper side.
- Later starting sizes use expected player growth from catching 55–90% of edible fish, controlled by the existing difficulty slider (about 59% at Level 2's default). Edible radii vary from 65–100% of expected size; threats vary from 115–135%. Actual catches and subsequent AI meals can change which fish are edible.
- Level 2 uses base absorption 0.55. After player feedback, a global 0.90 meal-growth multiplier applies throughout both arcade worlds, including AI meals and saved overrides (Level 2 effective absorption: 0.495). Expected-growth budgets and tuner displays use the effective rate. A 10% reduction removed bot winning routes for Levels 9–10 at width 667. These are untuned prototypes, so their settings and seeds remain unchanged; current route validation focuses on Levels 1–5 as requested. Historical opening and catch-cap comparisons explicitly retain their original effective growth rate, while current route checks use shipped growth. Jelly heights vary from roughly 32% to 67% of water height, subject to the existing floor-lane clearance.
- Each fish's protection expires 0.18 screen widths after its own starting x position. No extra recovery laps apply to the prototype. AI eating is blocked if either participant is protected; passing one fish does not unlock its entire group.
- **Across Jelly Bloom, AI fish are never killed by tentacles.** They steer around stingers and can bounce on bells even while protected. Player tentacle contact remains lethal. This shared arcade rule also affects the older levels; their balance needs later human playtesting.
- Retries use the same initial seed and per-fish movement generators. Physical interactions can change later trajectories. Re-roll remains available in the tuner.

Load shipped settings for Jelly Bloom Level 2 and Apply & Play to clear the old tuning experiment. Legacy presets with encounter difficulty disabled retain the original reference mode. Automated route checks establish reachability, not fun or a reliable human difficulty curve.


Jelly Bloom now has ten generated levels. Shallow Reef, Math Reef, and FishKit
retain their existing gameplay. The original five Bloom profiles remain available
through **Load original five-level reference** in the debug tuner, including the
accepted original Level 5 opening and its regression checks.

## Design model

Each level uses four encounters: three edible fish around a jellyfish and one
larger return threat nearby. The difficulty value advances uniformly from 0 to 1
over ten levels. Three quantities vary continuously:

- Equivalent food budget: 3.5 to 10.5 opening meals.
- Extra protection after the first opportunity: one circuit to zero circuits.
- Nominal clearance between food and threats: 32 to 10 world points.

Opening food has radius 0.85 relative to the player's starting radius. Return
threat radius is `sqrt(1 + budget × absorption × foodRadius²)`, using the game's
actual area growth rule. Integer catch requirements also account for player-favored
near-equal encounters. With the default absorption of 0.82, the endpoints require
4 and 11 catches respectively to eat an unchanged return threat; there are 12
opening food fish. These are growth requirements, not guaranteed first-pass quotas.
Other threats remain edible only after reaching that threshold, then contribute
growth themselves.

Fish hold bounded positions around their encounter until the player has passed
its exit plus the extra recovery distance. Both prey and threats are protected:
neither can eat another NPC while either participant remains protected. A released
fish cannot raid an encounter the player has not reached. Player eating and lethal
player collisions remain active throughout. After release, normal movement,
AI eating, and jellyfish interactions resume. Protection is based on accumulated
forward world distance, so slowdown and changing camera zoom cannot prematurely
start competition in an unseen area.

Protected NPCs do not take jellyfish contacts; their positions are kept clear of
the initial bells. Player jellyfish bouncing and tentacle danger remain active.
Each encounter uses visible bounded swimming while protected, with seeded vertical
retargeting, anticipation of nearby swimmers, and tentacle steering. Slow movement
keeps the fish broadside; an actual turn briefly narrows the silhouette. The
no-eating guard remains as a budget guarantee if separation steering misses. Fish
use their independent movement stream both before and after release. Seeded horizontal and vertical layout variation
stays within constrained bounds; it does not randomize the food growth budget.

## Wave variety in levels 1–5

The opening formation remains unchanged. The following three encounters use a
seeded permutation of descending, ascending, and raised-middle formations. Food
heights and horizontal spacing differ; the ascending wave places its larger fish
on the leading side instead of the trailing side. All waves still have three
0.85-radius food fish and one unchanged return threat. Catch targets, absorption,
protection deadlines, and growth budgets remain unchanged. Levels 6–10 retain
their previous formation while balance work focuses on 1–5.

Formations have regression coverage for repeatable ordering, distinct shapes,
full food counts, and initial clearance from fish and tentacles on compact and
wide phones. The three-size winning-route and recovery checks remain required.
New run headers identify these layouts with `encounterFormationVersion: 1`.

## Seed selection and route evidence

696 real-scene rollouts searched candidates, including baseline ecology probes.
The original selected offsets were **0, 0, 0, 3, 0, 1, 0, 1, 0, 16**.
The October 3 natural-swimming fix changes the final offset to **33** to preserve
the existing food-race regression; the other nine offsets and all difficulty
targets stay unchanged. The earlier selection JSON is a historical measurement.
A further 450 rollouts checked normal routes and capped-meal behavior for the
motion change. Ongoing balance work focuses on levels 1–5. Every selected level has
at least one winning controller route at each of 874×402, 852×393, and 667×375,
with the full fish population and a viable initial growth chain.

The reproducible selection report is [jelly-bloom-validated-seeds.json](jelly-bloom-validated-seeds.json).
`scripts/validate-arcade-candidates.py` selects the lowest tested offset satisfying
these conditions. It rejects candidates without route evidence; it does not prove
those candidates impossible for humans. Required campaign tests retain winning
route checks for every generated level at all three sizes.

An additional 240 rollouts capped first-pass meals at 4, 6, 8, or 10 on the widest
and smallest sizes. Four first-pass meals still allow demonstrated recovery in
Level 1. They produce no Level 10 wins for any of the three controllers at either size.
At the widest size all three develop persistent growth stalls; on the smallest
size some die before a stall can be measured. This endpoint distinction is covered
by a regression.
Intermediate controller results are **not monotonically ordered**: seed geometry,
bounces, later recovered meals, and AI interactions still matter. A linear design
target is not yet a proven linear curve in human difficulty. More calibration and
phone playtesting are needed before making that claim.

The first-pass cap counts all player meals, including any early return threats.
It is a counterfactual experiment, not a production quota or a perfect measure of
missed opening food. AI meals and hazard deaths can change the original growth
requirements after protection expires. Some late levels remain recoverable after
missing several first-pass catches; the system does not force a loss by deleting
food or scripting a predator meal.

## Tuning and playing

Use **Load shipped settings** on levels with old saved overrides to enter the new
system. Existing overrides and presets still decode and preserve legacy behavior.
The difficulty slider displays the catch target, spare catches, extra recovery,
and clearance. The original group editor remains available in legacy mode.

**Re-roll seed** changes the candidate while retaining other settings. The full
seed is visible and copyable. **Check winning routes** runs the real scene at all
three sizes and reports route evidence for the current settings; changing settings
invalidates the result. It is an advisory tool during experimentation. **Apply &
Play** remains available for human testing even when bots find no route. Save a
preset to preserve both settings and seed.

Run recordings include difficulty, food budget, recovery allowance, forward
distance, and local `encounter_release` events. The existing meal size-ratio and
food-race diagnostics remain available. All tools and recordings are debug-only.

The map, HUD, progression, and tuner use each world's actual level count. Level
IDs 1–5 remain stable and existing clears persist; levels 6–10 extend Bloom's
sequential progression. For local map captures, launch with `-arcadeMap jelly-bloom`.

Raw requests/results are local under ignored `build/arcade-development/`:
`difficulty-first*`, `difficulty-seeds*`, `difficulty-final-seeds*`, and
`difficulty-misses*`.
