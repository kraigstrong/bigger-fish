# Jelly Bloom: five-level food-race study

> Historical baseline: the 1,642-rollout study below used the original rule where every near-equal encounter bumped apart. The current game awards player ties to the player; NPC ties still bump. See [the player-tie follow-up](jelly-bloom-player-ties.md) for the updated growth boundary and validation. The baseline numbers below are retained for comparison.

The initial campaign established a deliberate recovery curve. Level 1 remains the simple bouncing introduction. Level 2 gives time to miss food and recover. Levels 3 and 4 demand earlier feeding. Level 5 has four timely first-pass catches in the demonstrated winning route, with near-equal meals and dangerous competitors persisting late into the run.

AI-on-AI eating remains enabled. There is no chasing, fleeing, food replenishment, automatic loss for a blocked growth path, or new objective. Tentacles remain lethal, uneven layouts repeat on retries, and the lower passage expands with player growth. Math Reef and FishKit were not changed.

## What the mathematics describes

Growth follows the actual area rule:

`newRadius² = oldRadius² + absorptionEfficiency × preyRadius²`

To become large enough to eat a target of radius `B`, the required radius is at least `B / (1 − 0.01)`, with the existing near-equal rule deciding the boundary. The approximate food-area deficit is:

`requiredFoodArea = ((B / 0.99)² − playerRadius²) / absorptionEfficiency`

For a snapshot, consume the smallest currently edible fish, recompute growth, and repeat. If the smallest remaining fish cannot be eaten, that snapshot has no complete player feeding chain. This is an optimistic check: it assumes every reachable meal can be collected without collision or interruption. Future AI meals or hazard deaths can change the answer, so the study also counts reopened paths.

Difficulty is described with several measurements rather than a single “fun score”:

- **Recovery window:** full world circuits before leaving all food to the AI first blocks the starting fish's growth path.
- **Early food demand:** catches before the first circuit ends in winning runs; delayed-feeding and capped-feeding experiments test recovery.
- **Meal sensitivity:** skip a particular fish on the first circuit and rerun the controllers.
- **Size tension:** completed meals with a prey/predator radius ratio of at least 0.8, nearby larger fish, and when the final threat disappears.

A useful urgency estimate is `timely meals / available passes`, not their product: the same required food spread over more passes is easier. Keep the two measurements visible because spatial routes and competitor growth can give the same estimate very different play.

Fast opening deaths are descriptive data, not an automatic reason to soften a level. The desired opening includes a risky meal ahead of a larger fish.

## Selected campaign

These measurements use the fixed shipped seeds at 874 × 402 points, matching the recent phone logs. A pass means one complete four-screen world circuit.

| Level | Starting AI fish | First blocked path if player takes nothing | Early demand demonstrated | Intended character |
|---|---:|---:|---|---|
| 1 | 14 | None within the 90-second probe | Winning runs after a foodless first pass | Learn falling and bouncing; recover freely |
| 2 | 22 | 2.00 passes | A winning route after a foodless first pass; multiple-pass recovery | Risky opening with extra food and one giant |
| 3 | 19 | 1.43 passes | A winning capped run with 3 first-pass meals | Start racing for food, with some recovery time |
| 4 | 19 | 1.05 passes | Winning routes with 4 first-pass catches | Tighter food race; larger fish remain dangerous longer |
| 5 | 23 | 0.50 passes | 4 first-pass catches in the winning trace | Food must be secured early; repeated close-size meals late |

The final-level winning trace starts catches at approximately 0.18, 0.24, 0.41, and 0.78 passes (fish IDs 1, 8, 18, and 7). A fifth catch begins just into the second pass, at 1.05. Skipping any one of those four first-pass fish produced no wins among the three controllers; skipping the fifth also eliminated wins. These are measured sensitivities, not a proof that every possible human strategy requires the same fish.

The final winning run took about 34.6 seconds, completed five close-size meals, and retained a larger-fish threat until about 89% of the run. That addresses the earlier pattern of a risky start followed by long, harmless cleanup.

Meal caps change the controller's subsequent steering. Their results can therefore be nonmonotonic: a cap of five can produce a winning run with four actual first-pass catches, while a cap of four sends the controller away from its next intercept and loses. We do not label the cap alone as a mathematically necessary meal count.

## How the study ran

**1,642 rollouts**, including ecological probes, candidate selection, delayed feeding, meal caps, individual meal omissions, and screen-size validation. The initial search varied easy-food counts, competitor speeds, giant counts, growth efficiency, and hazard density. Seeds 0–2 were used for candidate selection. Final validation perturbed the selected seeds by 7, 13, and 23 and also reran the shipped seed.

Rollouts instantiate `GameScene` and advance its real movement, AI steering, swallowing, growth, jelly contact, and victory logic at 60 simulation steps per second. No rendered view, sound, run recording, or campaign progress is needed. Three controllers make different food/risk choices from nearby fish and jelly observations. Their short trajectory prediction is approximate; the actual rollout is the game's code.

A separate ecological probe uses an untouchable player that never eats, leaving the actual AI ecosystem running. Delay and meal-cap experiments suppress only player meals that the experiment forbids; NPC interactions remain active. These interventions exist only in debug simulation, never normal gameplay.

The results at three landscape sizes are recorded in [the final validation tables](jelly-bloom-simulation-results.md). Every shipped level has at least one demonstrated winning route at **874 × 402, 852 × 393, and 667 × 375**. All 240 final validation runs spawned their full configured ecosystem and began with an optimistic growth path.

Smaller worlds compress encounters while AI speed was previously constant. Each race profile now eases horizontal AI speed by viewport width, using tested compact and intermediate adjustments in `GameTuning`. Level 1's settings and Shallow Reef's speed rules remain unchanged. The recovery timings are measurements of the reference layout, not universal guarantees across every viewport.

Holdout results also show an important limit: Level 4's three new seeds produced no bot wins at the reference size, while the selected fixed seed has winning routes. This campaign uses curated fixed seeds; the generator is **not** yet validated for unrestricted random levels. Neither controller win rates nor these proxies establish human enjoyment.

Osmos used procedural level creation and difficulty curves driven by level parameters, alongside iteration and feedback. This approach follows that pattern without assuming procedural generation alone guarantees balance. See [Hemisphere's GDC slides](https://www.hemispheregames.com/misc/GrowingOsmos_IGS2010_final_print.pdf) and [Towards Minimalist Game Design](https://www.nealen.net/papers/tmgd.pdf).

## Repeat the study

From the repository root:

```sh
python3 scripts/study-arcade-balance.py \
  --profiles docs/jelly-bloom-study-profiles.json \
  --seeds 0,7,13,23 --passes 0 \
  --sizes 874x402,852x393,667x375 --limit 90 --run \
  --output build/arcade-development/studies/validation
```

Use `--passes 0,1,2` to compare recovery after skipped circuits, or `--meal-limits=-1,0,1,2,3,4,5,6` for first-pass food caps (`-1` means unrestricted). For individual food omissions, use `--skip-fish '1;8;18;7'` with a profile file containing only the final level. Seed values perturb each profile's selected seed; results contain the actual offset used.

The command writes request JSON, full result JSON, a Markdown summary, and the test log under ignored `build/`. It removes its activation marker on completion so normal tests do not accidentally rerun a large batch. Without `--run`, it prepares the marker for a manual test run; remove that marker afterward. The preset JSON contains nominal settings; viewport speed adjustments come from the checked-in level profile.

For the next phone playtest, focus on whether Level 2 still invites the risky opening, whether the transition through Levels 3 and 4 feels fair, and whether Level 5's four early catches feel urgent rather than obscure. Local run logs can compare meal sizes and timings against these simulation traces.
