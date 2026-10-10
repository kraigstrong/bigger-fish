# Jelly Bloom: free-moving campaign playtest

This replaces the bounded-patrol experiment in all ten Jelly Bloom levels. Shallow Reef's layouts remain unchanged; the global 10% meal-growth reduction applies to both arcade worlds, AI meals, and saved tuning overrides.

The accepted Level 2 movement and starting-wave plan remain the reference: 40–175 point/second fish, unrestricted roaming for most fish, broad lingering areas for one in four fish, high/low food, and individually released AI-eating protection. Bell bounces apply to AI and player; tentacles only kill the player.

## Phone playtest

The user played all ten levels and reported that the campaign was fun, especially Levels 8, 9, and 10. These settings are the accepted baseline for further tuning.

After the protected-contact and bell-bounce changes, the user won every level except 7. Levels 8 and 9 have especially good encounters; Level 10 now feels too easy. Preserve 8 and 9 as references when revisiting 7 and 10. The fixed-playfield conversion keeps every seed and balance setting unchanged.

## Difficulty targets

The campaign has been reordered from phone playtesting. Complete setups move together, including speeds, growth budgets, seeded movement, and hazard layouts:

| Current level | Original setup | Spawn seed |
|---|---|---:|
| 3 | Original Level 6 | 20261033 |
| 6 | Original Level 7, accepted reroll | 20261477 |
| 7 | Original Level 3 | 20261033 |

Other campaign slots are unchanged. The accepted Level 7 reroll was described as hard but fair and winnable; its seed variation is 444. Saved debug tuning overrides migrate once with these setups. Gameplay headers now show only the world and level number, without totals or dots. The following difficulty targets and seed-study results describe the original authoring order, not the reordered campaign.

Targets describe expected growth, not human win probabilities. A starting wave's edible share is calculated relative to expected arrival size. Sizes then advance using the expected catch percentage and the effective absorption rate (0.55 × 0.90 = 0.495). Missing catches can leave you behind that curve. AI eating resumes for each fish after you pass its starting location; protected fish remain protected against already-released predators. During protected contacts, fish physically separate and an approaching fish turns away, so they do not swim through one another. In head-on contacts the faster swimmer yields; stable IDs break ties without consuming extra randomness.

| Level | Expected edible catches | Intent |
|---|---:|---|
| 1 | 45% | Spare food and alternate catches; learn the movement |
| 2 | 59% | Preserve the accepted high/low interception feel |
| 3 | 63% | More consistent catches across encounters |
| 4 | 67% | Tighter growth budget |
| 5 | 71% | Increasing pressure to take risky food |
| 6 | 74% | Fewer missed opportunities |
| 7 | 78% | Strong first-pass food race |
| 8 | 82% | Tight late growth budget |
| 9 | 86% | Few spare catches |
| 10 | 90% | Near-complete catches; missed food can cost the run |

Most levels shuffle 3-, 4-, 4-, and 5-fish starting groups and vary their edible shares, heights, and spacing with the seed. Level 2 keeps its accepted 4/3/5/4 groups and 3/2/3/3 edible plan. Later levels lower the edible share and raise fish speed, alongside the higher expected catch percentage. Fish are never kept in staged wave formations during play.

Jellyfish bell heights vary vertically and their horizontal gaps vary. Food and danger can create swoop-and-bounce opportunities; no mandatory bounce sequence is imposed. Individual movement streams and starting seeds repeat; player and AI interactions can change later paths.

## Validation and playtesting

Gameplay now uses one fixed 874×402 logical playfield. Displays fit it uniformly with an ocean border where needed; resizing cannot restart or reshape a run. Route checks use that single playfield; display tests separately check fitting and identical simulation state across view sizes. No seeds or level settings were changed for this conversion.

Seed comparisons use the real scene and multiple bot policies. A bot win establishes a reachable route under those inputs. Failed bots do not prove impossibility, and selected winning seeds do not prove a level fun or a linear human difficulty curve. Human playtesting remains decisive.

Fixed-playfield verification before reordering: 78 non-route tests passed, including matching gameplay state across display sizes, resizing without a reset, protected contacts, and bell bounces; device and Release builds passed. The automatic winning-route regression remains in the code but was excluded from verification at the user's request. Before reordering, its default policies missed Levels 3, 5, and 7; this is not a claim that those levels are impossible.

Load shipped settings and Apply & Play for each level to clear old saved overrides. Seed re-roll and effective growth controls remain available in the tuner; recordings include expected catch fraction, starting wave budgets, per-fish release events, meal ratios, and actual effective growth.

## Selected seed results

The seed search evaluated 1,368 rollouts, followed by 120 validation runs of the selected seeds after the spawn-clearance fix. These numerical measurements precede the protected-contact separation follow-up; that follow-up is checked by the current route regression. At the time of that study, every selected seed had a winning route on each tested screen size, no missing initial fish, and a viable initial growth chain. Bot win counts and uncontested food-race deadlines are **not monotonic**: these do not establish a linear human difficulty curve. The catch-percentage model is the first design pass.

| Level | Seed offset | Displayed spawn seed | Bot wins | Close meals in wins (mean) | No-meal growth stall (laps) |
|---|---:|---:|---:|---:|---:|
| 1 | 1 | 20261028 | 9/9 | 4.44 | 0.95–1.50 |
| 2 | 0 | 20261028 | 7/9 | 4.43 | 0.85–1.57 |
| 3 | 4 | 20261033 | 6/9 | 4.33 | 1.00–1.32 |
| 4 | 4 | 20261034 | 6/9 | 5.17 | 1.00–1.88 |
| 5 | 6 | 20261037 | 5/9 | 5.0 | 1.09–1.29 |
| 6 | 1 | 20261033 | 6/9 | 5.33 | 1.17–1.44 |
| 7 | 3 | 20261036 | 3/9 | 6.0 | 0.76–1.24 |
| 8 | 12 | 20261046 | 6/9 | 5.67 | 0.87–1.16 |
| 9 | 26 | 20261061 | 4/9 | 3.75 | 0.88–1.17 |
| 10 | 38 | 20261074 | 8/9 | 5.25 | 0.74–1.14 |

The last column is a ghost-player probe: when the optimistic food chain first becomes impossible if the player eats nothing. It excludes navigation and does not describe a mandatory catch sequence or a player's win probability. Early levels aim for more spare food; they can still become unwinnable after losing the food race.

Machine-readable results: [selected seed summary](jelly-bloom-free-campaign-seeds.json). Full local searches and selected runs are saved under `build/arcade-development/free-campaign-search.json`, `free-campaign-nine-search.json`, and `free-campaign-selected.json`.
