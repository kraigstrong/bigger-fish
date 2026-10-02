# Bigger Fish: first two-world playable

Based on Kraig's Bigger Fish design draft dated September 29, 2026, with decisions made during
implementation on October 1. The draft is a longer-term vision, not the scope of this build.

## Accepted decisions

- Keep continuous area-based growth and relative-size eating. Ignore the draft's fixed tiers.
- Keep the original five levels and control tuning as World 1, **Shallow Reef**.
- Both worlds are available during development; levels unlock sequentially within each world.
- Add World 2, **Jelly Bloom**, with five numbered levels; both worlds show Level 1–5, without names.
- Dome tops bounce; tentacles remain lethal. Remove all urchins, chasing, and fleeing.
- Bloom's larger fish swim normally and can be outgrown through eating; baiting is optional.
- Disable AI-on-AI eating in Bloom so larger fish cannot consume the player's growth opportunities.
- Save level clears and fastest clear times locally, with stable IDs and a Bigger Fish-only key.
- Keep new code and copied assets in BiggerFish; defer shared engine consolidation while Math Reef is in review.

## Playable slice

World map -> level path -> instructions -> play -> win/retry/next level/level map.
Results use Math Reef's choices: Next level / Play again / Levels after a clear, or Try again / Levels
after a loss. The final level offers Play again / Levels. Only buttons advance the game.
Pausing offers Resume, Restart, and Level map. Cleared levels remain replayable. World completion
returns to its map rather than immediately restarting the campaign.

Level 1 retains its four-domed, smaller-fish opening. Levels 2–5 place food pockets above authored
bounce routes: alternating stepping stones, an ascending/descending ladder, a night chain, and a
longer playground. Food fish patrol near their pockets rather than dispersing around the whole reef.
There are 1/2/2/3 initially larger fish in Levels 2–5, with separated starts and enough smaller food
to outgrow every larger fish. Bells are broader and tentacles shorter than the former predator layouts.

A clear means becoming the last fish swimming, with no meal quota or replenishment. Meal counters
and HUD code remain dormant for future endless mode. Ordinary Bloom swimmers look ahead and steer
around tentacles. Every level keeps a lower passage sized for the growing player. Same-frame
bouncing and touch controls remain intact.
All physics, hazard dimensions, and speeds live in `GameTuning` and need device playtesting.

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
