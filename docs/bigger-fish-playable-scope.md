# Bigger Fish: two-world playable

Based on Kraig's Bigger Fish design draft dated September 29, 2026, with decisions made during
implementation and family playtesting through October 4. The draft is a longer-term vision, not the
scope of this build.

## Accepted decisions

- Keep continuous area-based growth and relative-size eating. Ignore the draft's fixed tiers.
- Two worlds, **Shallow Reef** (fish only) and **Jelly Bloom** (jellyfish), with ten numbered
  levels each. Both worlds are open; levels unlock sequentially within each world.
- Jellyfish domes bounce the player and AI fish; tentacles kill only the player. No urchins,
  chasing, or fleeing.
- AI-on-AI eating is essential: take a risky meal before another fish eats it and grows into a
  threat. Each fish is protected from AI eating until the player has passed its starting area.
- Near-equal encounters (within 1% radius) go to the player; NPC ties still bump apart.
- One global 0.90 meal-growth multiplier applies to both worlds (effective absorption 0.495).
- Gameplay runs at fixed 1/60-second steps on one 874 × 402 logical playfield, and every NPC has
  its own seeded movement stream, so retries start identically on every device.
- Campaign order comes from phone playtesting, not the authoring difficulty targets. Level IDs
  are campaign slots; a reorder moves whole setups (seed, speeds, growth) between slots.
- Save level clears and fastest clear times locally, with stable IDs and a Bigger Fish-only key.
- Map art and layout are shared with Math Reef through FishKit (`OceanMapArt`, `OceanMapLayout`);
  game code and assets stay in `BiggerFish/`.

## Playable slice

World map -> level path -> instructions -> play -> win/retry/next level/level map.
Results use Math Reef's choices: Next level / Play again / Levels after a clear, or Try again / Levels
after a loss. The final level offers Play again / Levels. Only buttons advance the game.
Pausing offers Resume, Restart, and Level map. Cleared levels remain replayable. World completion
returns to its map with the final level focused rather than restarting the campaign.

A clear means becoming the last fish swimming, with no meal quota or replenishment. Meal counters
and HUD code remain dormant for a future endless mode. All tuning lives in `GameTuning`; the
current campaigns are described in [shallow-reef-ten-level-campaign.md](shallow-reef-ten-level-campaign.md)
and [jelly-bloom-free-campaign.md](jelly-bloom-free-campaign.md).

## Privacy

No ads or third-party SDKs. The app sends anonymous first-party gameplay summaries
(`ArcadeAnalytics.swift`) to brightbench.app: no identifiers, timestamps, device details, or
trajectories. The policy is at brightbench.app/bigger-fish/privacy; keep it,
`BiggerFish/PrivacyInfo.xcprivacy`, and the endpoint's validator in step with any payload change.
Debug builds record full runs locally only.

## Deferred vision

- Endless / The Open Water: timed difficulty director, continuous spawning, predator caps, hooks,
  grazing combos, scoring, and local top-ten runs.
- Earned pearls, cosmetic-only shop (hats, trails, skins), achievement unlocks, and settings.
- Full Dive non-consumable unlock and Restore Purchases; no paid gate in this development build.
- A dedicated, skippable World 1 tutorial and fuller sound/music treatment.
- Future worlds: Kelp Forest (ambush), The Deep (limited information), Riptide Reef (currents after
  controls are validated), Frozen Trench (space management).
- Fishpedia, daily seeded runs, expanded cosmetics, and a later decision about Game Center.
- Whether player growth (camera zoom) should keep widening every NPC's swimming area.

Size readability remains the priority. Cosmetics must never change the fish's apparent body size.

## Branches

Development integrates on `codex/bigger-fish-integration`; feature branches open PRs into it, and
it merges to `main` when ready. Math Reef releases are tagged (`math-reef-v1.0.0`); a Math Reef
hotfix branches from its tag, then merges back into `main` and from there into the integration branch.
