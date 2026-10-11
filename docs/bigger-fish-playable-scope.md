# Bigger Fish: playable scope

Based on Kraig's Bigger Fish design draft dated September 29, 2026, with decisions made during
implementation and family playtesting through October 4. The draft is a longer-term vision, not the
scope of this build.

## Accepted decisions

- Keep continuous area-based growth and relative-size eating. Ignore the draft's fixed tiers.
- Four worlds, **Shallow Reef** (fish only), **Jelly Bloom** (jellyfish), **Kelp Forest** (kelp), and
  **Midnight Zone** (a headlamp in the dark), each with ten numbered levels to conquer and then The Deep End,
  five more at its hardest. Levels unlock in order within each world.
- Free to try, with a one-time purchase: all of Shallow Reef and two levels of each other world are free; the
  unlock opens every world from the start and every Deep End (`ArcadeUnlock.swift`).
- Jellyfish domes bounce the player and AI fish; tentacles kill only the player. No urchins,
  chasing, or fleeing.
- AI-on-AI eating is essential: take a risky meal before another fish eats it and grows into a
  threat. Each fish is protected from AI eating until the player has passed its starting area.
- Near-equal encounters (within 1% radius) go to the player; NPC ties still bump apart.
- One global 0.90 meal-growth multiplier applies to both worlds (effective absorption 0.495).
- Gameplay runs at fixed 1/60-second steps on one 874 × 402 logical playfield, and every NPC has
  its own seeded movement stream, so retries start identically on every device.
- Every level is planned by the meeting planner (`docs/meeting-planner.md`) and shipped as saved data,
  frozen once played and approved.
- Campaign order comes from phone playtesting. Level IDs are campaign slots; a reorder moves whole layouts
  between slots (Shallow Reef's is `GameTuning.shallowReefOrder`).
- Save level clears and fastest clear times locally, with stable IDs and a Bigger Fish-only key.
- Map art and layout are shared with Math Reef through FishKit (`OceanMapArt`, `OceanMapLayout`);
  game code and assets stay in `BiggerFish/`.

## Playable slice

First launch: the tutorial. Then world map -> level path -> level card -> play -> win/retry/next level/level map.
Results use Math Reef's choices: Next level / Play again / Levels after a clear, or Try again / Levels
after a loss. The final level offers Play again / Levels. Only buttons advance the game.
Pausing offers Resume, Restart, and Level map. Cleared levels remain replayable. World completion
returns to its map with the final level focused rather than restarting the campaign.

A clear means becoming the last fish swimming, with no meal quota or replenishment. All tuning lives in
`GameTuning`. Beating a world's level 10 conquers it and opens its Deep End.

Settings (the world map's gear) has sound, music, and vibration switches, replaying the tutorial, restoring the
unlock, and the privacy policy and support pages on biggerfish.app.

## Privacy

No ads or third-party SDKs. The app sends anonymous first-party gameplay summaries
(`ArcadeAnalytics.swift`) to brightbench.app: no identifiers, timestamps, device details, or
trajectories. The policy is at biggerfish.app/privacy (word for word the same as
brightbench.app/bigger-fish/privacy); keep it,
`BiggerFish/PrivacyInfo.xcprivacy`, and the endpoint's validator in step with any payload change.
Debug builds record full runs locally only.

## Deferred vision

- Endless / The Open Water: timed difficulty director, continuous spawning, predator caps, hooks,
  grazing combos, scoring, and local top-ten runs.
- Earned pearls, cosmetic-only shop (hats, trails, skins), and achievement unlocks.
- Future worlds: Riptide Reef (currents), Frozen Trench (space management).
- Fishpedia, daily seeded runs, expanded cosmetics, and a later decision about Game Center.
- Whether player growth (camera zoom) should keep widening every NPC's swimming area.

Size readability remains the priority. Cosmetics must never change the fish's apparent body size.

## Branches

Both apps develop on `main`: feature branches open PRs into it. (Bigger Fish used to integrate on
`codex/bigger-fish-integration`; that branch merged into `main` on 2026-10-10 and is retired.) Each app's
releases are tagged (`math-reef-v1.0.0`, `bigger-fish-v0.3-beta.1`); a hotfix branches from its tag and
merges back into `main`.
