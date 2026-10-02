# Player-favored ties

Player encounters now award the existing near-equal radius band to the player. If the radii differ by less than 1% of the larger radius, the player swallows the other fish, even if it is fractionally larger. NPC-on-NPC encounters retain the previous bump rule. Clearly larger opponents still eat the player.

This changes both Bigger Fish worlds. Math Reef and FishKit are untouched. No spawn mix, layout, seed, movement speed, hazard, or growth-efficiency setting was changed.

For a target of radius `B`, player feeding is now possible when the player is larger or equal, or strictly greater than `0.99 × B` on the smaller side. The equality at that smaller boundary still belongs to the larger fish. This replaces the historical study's requirement to exceed the opponent by the full near-equality margin.

## Level 5 comparison

At 874 × 402, the opportunist and cautious controllers still capture fish 1, 8, 18, and 7 at approximately 0.18, 0.24, 0.41, and 0.78 world circuits. Those opening contacts match the baseline trace.

The updated route then captures fish 21 at about 0.96 circuits. The baseline route missed that meal and needed more circuits to finish. Updated completion is approximately **16.2 seconds**, compared with **34.6 seconds** previously; four completed meals still have prey/predator radius ratios of at least 0.8. This is a demonstrated simulation improvement, not a guarantee for human attempts.

## Validation

[The updated tables](jelly-bloom-player-ties-results.md) contain 60 rollouts: each of five shipped levels at three phone sizes, with three controllers and one ecological probe per level/size. Every level has a winning route at each size and all configured fish were spawned. The compact Level 3 opportunist loses under the new rule, while the collector and cautious controllers win; the regression route uses cautious there.

Rule tests cover exact equality, both sides of the near-equal band, both collision orders, clear size differences, and unchanged NPC ties. Scene integration checks verify that those encounters actually start the player swallowing the other fish in both orders.

New local recordings include `playerWinsTies: true`. Offline analysis uses that flag for growth paths and keeps the original rule for older recordings. The simulator's feeding choices, collision interventions, threat measurements, and growth checks use the same updated player rule as gameplay.
