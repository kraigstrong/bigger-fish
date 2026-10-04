# Latest phone tuning comparison — October 2, 2026

The user requested the latest saved settings for each adjusted level. The phone's
preferences contained overrides for Jelly Bloom level 4 and Shallow Reef level 5.
These settings were compared with the source defaults using the real scene,
seed 0, three controllers, three landscape sizes, and a 90-second limit.
The 48 rollouts include 36 playable runs and 12 untouched-player ecology probes.
No shipped defaults were changed for this comparison.

## User-authored fish groups

Ranges are fish radius multipliers relative to the player's starting radius.
Slider floating-point artifacts are rounded here for readability.

| Level | Current groups: count × range | Latest phone groups: count × range |
|---|---|---|
| Jelly Bloom 4 | 3 × .42–.62; 5 × .66–.90; 5 × .92–1.08; 4 × 1.20–1.60; 2 × 2.00–2.60 | 7 × .42–.85; 5 × .66–1.15; 5 × .92–1.08; 5 × .95–1.60; 2 × 1.45–2.30 |
| Shallow Reef 5 | 3 × .45–.65; 4 × .70–.92; 6 × .94–1.06; 4 × 1.15–1.50; 3 × 1.90–2.80 | 4 × .45–.65; 5 × .70–.92; 7 × .80–1.15; 6 × .70–1.50; 3 × 1.90–2.80 |

Other effective tuning settings match the current defaults. Fish counts increase
from 19 to 24 in Bloom 4 and from 20 to 25 in Shallow 5. Adding fish also changes
spawn random draws and placements, so this is not an isolated food-budget experiment.

## Demonstrated routes

| Level | Landscape size | Default bot wins / 3 | Latest phone bot wins / 3 |
|---|---:|---:|---:|
| Jelly Bloom 4 | 874 × 402 | 0 | 2 |
| Jelly Bloom 4 | 852 × 393 | 1 | 3 |
| Jelly Bloom 4 | 667 × 375 | 3 | 3 |
| Shallow Reef 5 | 874 × 402 | 0 | 1 |
| Shallow Reef 5 | 852 × 393 | 0 | 1 |
| Shallow Reef 5 | 667 × 375 | 3 | 0 |

Latest Bloom 4 settings demonstrate a winning route at every tested size.
This resolves the wide-phone route gap in the comparison, but the settings have
not been promoted to defaults. The user's latest Bloom 4 settings also produced
a physical-phone win in 20.75 simulation seconds, with 14 player meals.

Latest Shallow 5 settings demonstrate routes on the two larger sizes. The user
also won twice on the phone, with 13 player meals in each run. On the smallest
size, all three controllers time out after losing their optimistic growth path
near the end of the first circuit (0.94–1.01 passes), with no subsequent recovery.
This is evidence of a food-race problem for those routes, not proof that no human
route exists. Those settings should receive compact-phone testing before adoption.

Bot wins establish reachable routes, not subjective enjoyment or a difficulty
ranking. No new gameplay changes or CI policy changes were made. Bloom level 5's
existing small-phone CI route failure remains separate from these two adjustments.

Raw settings, requests, results, and recordings remain local in ignored `build/`:
`arcade-runs/phone-tuning.plist`,
`arcade-development/phone-latest-comparison.request.json`,
`arcade-development/phone-latest-comparison.json`, and
`arcade-development/phone-latest-comparison.md`.
The opt-in simulation study now accepts an optional world and optional tuning;
omitting them retains Jelly Bloom and uses the selected level's source defaults.
