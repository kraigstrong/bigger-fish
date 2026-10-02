# Bigger Fish: first two-world playable

Based on Kraig's Bigger Fish design draft dated September 29, 2026, with decisions made during
implementation on October 1. The draft is a longer-term vision, not the scope of this build.

## Accepted decisions

- Keep continuous area-based growth and relative-size eating. Ignore the draft's fixed tiers.
- Keep the original five levels and control tuning as World 1, **Shallow Reef**.
- Both worlds are available during development; levels unlock sequentially within each world.
- Add World 2, **Jelly Bloom**: Bounce House, Threading, Bloom, Night Bloom, Gauntlet.
- Dome tops bounce; tentacles kill player and AI. No health, stuns, or tier drops.
- Bloom adds limited predator chasing and short-range prey fleeing. Chasers warn for 0.45 seconds,
  commit for 1.6 seconds, rest for four seconds, and are capped below player speed. World 1 retains its original AI.
- Save level clears and fastest clear times locally, with stable IDs and a Bigger Fish-only key.
- Keep new code and copied assets in BiggerFish; defer shared engine consolidation while Math Reef is in review.

## Playable slice

World map -> level path -> instructions -> play -> win/retry/next level/level map.
Results use Math Reef's choices: Next level / Play again / Levels after a clear, or Try again / Levels
after a loss. The final level offers Play again / Levels. Only buttons advance the game.
Pausing offers Resume, Restart, and Level map. Cleared levels remain replayable. World completion
returns to its map rather than immediately restarting the campaign.

Bounce House has sparse jellies, only smaller fish, and no AI-on-AI eating so the opening stays safe.
Threading introduces longer curtains and urchin beds. Bloom adds density and predators. Night Bloom
uses darker water while preserving fish and hazard readability. Gauntlet combines the densest field,
predators, and floor hazards. Jelly layouts wrap with the existing finite ecosystem.

A clear still means becoming the last fish swimming. Bloom additionally requires 3/4/5/6/8 completed
player meals across its levels; AI and hazard kills do not count as meals. The HUD shows the goal.
Sparse small prey replenish only when nothing edible remains and the meal goal or larger survivors
still prevent a clear. Hazard density is reduced so the ecosystem lasts longer. All physics, hazard dimensions, and speeds live in `GameTuning` and need device playtesting.

## Deferred vision

- Endless / The Open Water: timed difficulty director, continuous spawning, predator caps, hooks,
  grazing combos, scoring, and local top-ten runs.
- Earned pearls, cosmetic-only shop (hats, trails, skins), achievement unlocks, and settings.
- Full Dive non-consumable unlock and Restore Purchases; no paid gate in this development build.
- A dedicated, skippable World 1 tutorial and fuller sound/music treatment.
- Future worlds: Kelp Forest (ambush), The Deep (limited information), Riptide Reef (currents after
  controls are validated), Frozen Trench (space management).
- Fishpedia, daily seeded runs, expanded cosmetics, and a later decision about Game Center.
- Consolidating map, audio, and reusable art infrastructure with Math Reef through FishKit.

Size readability remains the priority. Cosmetics must never change the fish's apparent body size.
No ads, third-party tracking, or network services are added to this build.

## Release isolation

Development lives on `codex/bigger-fish-arcade`. Math Reef 1.0.0 build 2 stays at
`math-reef-v1.0.0`; if Apple requests a change, branch from that tag and increment its build there.
Merge release fixes back into main and then into the arcade branch rather than cherry-picking.
