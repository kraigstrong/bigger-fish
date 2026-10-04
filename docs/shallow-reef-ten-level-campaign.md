# Shallow Reef: ten-level encounter campaign

This is a first playable tuning pass, based on the Jelly Bloom family playtests. Shallow Reef stays fish-only: no jellyfish, urchins, chase AI, or prey fleeing. Its original five configurations remain available through the debug tuner's original-reference button, including the favorite original Level 4.

Both worlds now add 49.5% of a meal's area to the predator's area (base absorption 0.55 × the global 0.90 growth multiplier). Player ties still favor the player. AI-on-AI eating remains critical: before each fish's first opportunity, protected contacts separate and turn away; after the player passes its starting area, it can participate in the food race. Most fish roam, and a minority linger. Retry seeds and per-fish movement streams are fixed.

Four internal starting areas each contain a seeded mix of high/low food and larger fish. Twenty fish start in every level; the 5/4/6/5 area sizes are shuffled by seed. Edible shares vary by area, and their target declines from 88% to 64%. Each area always has at least one larger fish. These labels are generation budgets, not visible waves or movement cages.

Later fish are sized relative to expected arrival growth. The original authoring targets rise by five percentage points per setup. Human playtesting now determines campaign order: the original Level 3 moves to Level 8, and original Levels 4–8 shift forward one slot. Each setup retains its seed, speeds, growth, and catch targets. This controls the amount of missed food the authoring model budgets for; it is not a verified minimum catch count, a human win probability, or a guarantee of linear felt difficulty.

| Level | Expected edible catches | AI horizontal speed | Seconds across the playfield |
|---|---:|---:|---:|
| 1 | 45% | 45–120 | 2.90 |
| 2 | 50% | 48–129 | 2.86 |
| 3 | 60% | 53–147 | 2.77 |
| 4 | 65% | 56–156 | 2.72 |
| 5 | 70% | 59–164 | 2.68 |
| 6 | 75% | 62–173 | 2.63 |
| 7 | 80% | 64–182 | 2.59 |
| 8 | 55% | 51–138 | 2.81 |
| 9 | 85% | 67–191 | 2.54 |
| 10 | 90% | 70–200 | 2.50 |

AI vertical speed rises from 60 to 100. Early levels budget spare food; late levels reward taking near-equal catches before competing fish outgrow the player. Food and predator sizes, positions, direction, and speed still interact, so seed selection and human playtesting remain decisive. Jelly Bloom proved that nominal speed and catch targets alone cannot rank every generated layout.

The debug tuner exposes difficulty, speed, effective growth, seed re-roll, and the actual edible budget for both worlds. Old Shallow Reef debug overrides are backed up locally and retired once so they cannot silently restore the former faster-growth campaign. New overrides persist normally. Campaign progress is retained.

## Initial seed evidence

The study ran 72 diagnostic rollouts: 40 initial runs, 24 alternate-seed runs for Levels 7 and 9, and eight checks of the selected alternates. Each current seed has at least one demonstrated route among three bot policies, a full initial spawn, and an optimistic initial growth path. Current per-level bot wins are 3, 3, 3, 2, 3, 1, 2, 3, 2, and 2 out of three attempts. These are not a monotonic human difficulty curve.

In ghost-player probes that eat nothing, the first growth stall occurs around 1.84 circuits in Level 1 and 1.55 in Level 2, versus roughly one circuit in most later levels. The selected Level 9 seed is an exception at 1.85 circuits. The deadline varies by seed and is not strictly ordered. These measurements do not establish how many mistakes a human can recover from; check Level 9's pressure in the phone playtest rather than assuming its target makes it harder.

The selected seed offsets are 2, 7, 13, 23, 31, 47, 60, 71, 92, and 101. Levels 7 and 9 use the first small-sample alternatives with demonstrated routes; their speed and budget settings were unchanged. See [the machine-readable seed summary](shallow-reef-selected-seeds.json). Raw local diagnostics remain in `build/arcade-development/shallow-ten-level-*.json`.

Validation checks full spawn counts, no initial overlaps, an optimistic initial growth path, deterministic movement, protection/release behavior, matching tuner budgets, and migration. Bot-route studies remain optional diagnostics; their failures do not prove impossibility. This campaign still needs a phone playtest to judge route variety, recovery from missed catches, and the final difficulty order.

## Verification-only follow-up

While the family continued playtesting, no gameplay constants, seeds, or layout rules were changed. A new scene test confirms advancement from Level 9 to 10, final-level replay without looping to Level 1, correct clear callbacks, and returning to the map. All seven targeted tests (the six Shallow Reef checks and the diagnostic runner) passed.

An additional 18 diagnostic runs deliberately skipped the first one or two opening food fish until the second circuit:

| Level | Skip first food: wins | Skip first two foods: wins |
|---|---:|---:|
| 1 | 3/3 | 3/3 |
| 5 | 2/3 | 1/3 |
| 10 | 1/3 | 0/3 |

This demonstrates recovery routes in the first level and less tolerance in the sampled later levels. Zero bot wins does not establish mathematical impossibility or the human difficulty order. The Level 10 two-miss sample included one death and two timeouts. Raw results are saved locally in `build/arcade-development/shallow-missed-food-audit.json`. The phone was not accessed or reinstalled during this follow-up.

## Phone playtest and campaign order

The latest 50 recordings included 43 Shallow Reef runs. Every level was beaten. Original Level 3 had two wins in eight attempts; the latest replay session had six losses before a win, including three deaths within five seconds and one run with no food and a larger final opponent. Level 10 took 18 attempts and was explicitly praised for its difficulty.

Move original Level 3 to slot 8, shifting original Levels 4–8 to slots 3–7. Levels 1, 2, 9, and 10 stay in place. Saved debug tuning follows its setup through a one-time migration; progress stays attached to campaign slots. The seed and diagnostic summary reflects this new order. Historical diagnostic counts above refer to the original authoring order, not the reordered slots.
