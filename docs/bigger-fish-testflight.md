# Bigger Fish on TestFlight

How to ship a Bigger Fish beta to friends, and what each build was. Tracked in #54 (first external
build), #58 (privacy), #59 (smoke test), and #61 (feedback).

## What the build already has

- Bundle ID `com.kraigstrong.biggerfish`, team `MKACSCQ588`, automatic signing.
- Version 0.3 (see the build log at the end). iPhone only, landscape.
- App icon (no alpha), loading screen, and launch color.
- `ITSAppUsesNonExemptEncryption = NO`: the only encryption is the system's HTTPS, so App Store
  Connect won't ask the export-compliance question on each upload.
- Category: Arcade games.
- Privacy manifest (`BiggerFish/PrivacyInfo.xcprivacy`): UserDefaults for saved progress and
  settings, and anonymous gameplay counts (product interaction, not linked to the player, not
  tracking).
- Anonymous gameplay counts are on (`ArcadeAnalytics.isEnabled`), sent to
  `brightbench.app/api/bigger-fish/events` and tagged `testflight` for beta installs.
- Privacy policy: https://brightbench.app/bigger-fish/privacy
- The Release build has none of the debug tools: no tuner, run recorder, playtest shortcuts, planner,
  or progress reset.

## Uploading a build

1. **App record (first time only).** In App Store Connect, go to Apps, then + New App. Choose iOS,
   name it Bigger Fish, pick the `com.kraigstrong.biggerfish` bundle ID, and use `biggerfish` as the
   SKU. If the bundle ID isn't in the list, archiving once with automatic signing registers it.
2. **Archive.** Check out `main` at the commit you want and tag it (`bigger-fish-v0.4-beta.1`). In Xcode,
   choose the BiggerFish scheme and Any iOS Device (arm64), then Product > Archive.
3. **Upload.** In the Organizer, choose Distribute App > App Store Connect > Upload. Leave "Manage
   Version and Build Number" on so each upload gets a new build number.
4. **Internal test.** When the build finishes processing, add yourself to an internal group (Apple
   requires one before any external group), install it from TestFlight, and run the smoke check below.
5. **External test.** Create an external group (Friends, say), fill in Test Information (below), add
   the build, and submit it for beta review. The first build of a version is reviewed by Apple. Once
   it's approved, invite friends by email or with a public link.
6. **Record it** in the build log at the end of this file.

## Smoke check on the TestFlight build

On a physical iPhone, with a fresh install and again as an update over the last build:

- The loading screen shows, then the world map. No black screen.
- Play a level in each world, win one, and lose one, both eaten and stung.
- Progress is kept after force-quitting and reopening.
- Sound plays with the phone on silent. The Sound effects and Music switches work on the map and in
  the pause menu, and are remembered.
- Background the app mid-level: the game pauses and the music stops, then resumes on return.
- A phone call or alarm during a level doesn't break the game or its sound.

Since 0.3:

- **Fresh install:** the tutorial plays first: hold to rise, let go to fall, eat a smaller fish, dodge a bigger
  one, watch a missed fish grow and catch it back, then eat through the wall to be the last fish swimming. Missing
  a wall meal gets you eaten, and Retry starts the wall again. It ends on the world map. Settings > Replay
  tutorial plays it again.
- **Update over 0.3:** no tutorial (you have cleared levels); progress, Deep End rings, and best times are kept.
- Every world is open from the start (the unlock isn't sold yet, so everyone plays as if they'd bought it).
- Each level starts on a short card: its name, the world's progress pips, and "Tap to start". A world's rules
  show only on its first level, until it's cleared. Retry skips the card.
- The world map rings and the level map's bar fill in as you clear levels; the card after a win shows the pips
  filling. Beating a world's level 10 shows its conquered screen with The Deep End.
- The world map's gear opens Settings: Sound effects, Music, and Vibration (remembered, and in the pause menu
  too), Replay tutorial, Privacy Policy and Support (biggerfish.app), Credits, and the version.
- Meals, close calls, bounces, stings, being eaten, and wins are felt (with Vibration on). Vibration off stops them.
- The screen sleeps on the maps, cards, and pause menu as it normally would, but not while you play.

## Turning on the unlock

Bigger Fish is free to try: all ten of Shallow Reef's levels and the first two of every other world
(`GameTuning.freeLevelsPerWorld`). A one-time purchase opens every world from the start and every Deep End; a
world's Deep End still opens when its level 10 is beaten. Xcode builds sell it against `BiggerFish.storekit`.
Release builds don't sell it until `ArcadeUnlock.isSelling` is turned on, and until then everyone plays
as if they'd bought it. To turn it on:

1. In App Store Connect, under the app's Monetization > In-App Purchases, create a **Non-Consumable** with
   product ID `com.kraigstrong.biggerfish.allworlds` (permanent once created), reference name "Unlock every
   world", price $4.99, display name "Every World", and description "Every world and every Deep End, for
   good." Turn on Family Sharing. Add the review screenshot (the unlock screen) so it reaches Ready to Submit.
2. Set `ArcadeUnlock.isSelling` to `true` for Release, and archive. TestFlight testers buy it free in the sandbox.
3. Submit the in-app purchase with the first App Store version that sells it.

In Xcode, Debug > StoreKit > Manage Transactions deletes a test purchase to play as a new player again.
Launching with `-arcadeUnlocked YES` (or `NO`) skips StoreKit and plays with (or without) the unlock.

Smoke check, without the unlock:

- Every world on the map is open. Shallow Reef plays levels 1–10; every other world plays levels 1 and 2,
  and levels 3–10 show a gold padlock and "Unlock". Every Deep End says "Unlock every world to dive in."
- "Unlock all" on the world map, a padlocked level, and Next level after a world's level 2 each show the unlock
  screen: a looping clip of Jelly Bloom, Kelp Forest, and Midnight Zone, the price, Restore purchase, and Not now.
- Beating Shallow Reef's level 10 shows "Shallow Reef conquered!" with the same offer.
- Buying (or Restore purchase after buying on another device) shows "Every world is open!" and removes every
  padlock. Beating a world's level 10 then shows its conquered screen with just The Deep End.

## Test Information (paste into App Store Connect)

**Beta App Description**

> Bigger Fish is an arcade game about working your way up the food chain. Hold to rise, release to
> fall. Eat fish smaller than you, avoid the bigger ones, and grow until you're the last fish
> swimming. This beta has four worlds of ten levels each: Shallow Reef; Jelly Bloom, where
> jellyfish domes bounce you and their tentacles sting; Kelp Forest, where kelp slows you down and
> hides what's inside it; and Midnight Zone, where it's dark but for your headlamp, and every other
> fish carries the same little light, so you can't tell how big one is until your beam lands on it.
> Play the worlds in any order, and beat a world's tenth level to open its Deep End: five extra-hard
> levels for when you can't get enough.

**What to Test**

> Thanks for playing! New in this build: Midnight Zone, a fourth world. Beat Kelp Forest's level 10 to
> open it; if you already have, you'll be shown the way in once. Shallow Reef's levels are also
> reordered to ramp up more smoothly, and your cleared levels stay cleared. We'd love to hear:
> - How Midnight Zone's dark feels: is not knowing a fish's size until your light lands on it fair?
> - Which levels felt too hard or too easy, and roughly how many tries they took.
> - Whether Shallow Reef's new order feels like a steady climb.
> - Whether The Deep End is a fun challenge or just frustrating.
> - Anything about how to play that was confusing.
> - Bugs, crashes, or sound problems.
>
> To send feedback, take a screenshot while playing and share it with TestFlight, or use Send Beta
> Feedback in the TestFlight app. The beta sends anonymous gameplay counts, like which levels were
> cleared, with no names or device IDs.

**Feedback Email:** the address you want testers' feedback to reach.

**Privacy Policy URL:** https://brightbench.app/bigger-fish/privacy

**Beta App Review:** your name, phone, and email as the contact. Sign-in isn't required. Notes:

> No account or sign-in. Tap a world, then a level, and hold anywhere to rise.

## Build log

| Build | Date | Source commit | Notes |
|---|---|---|---|
| 0.1 (1) | | `9385ced` (`bigger-fish-v0.1-beta.1`) | First external build. |
| 0.2 (1) | 2026-10-09 | `f98f340` (`bigger-fish-v0.2-beta.1`) | Kelp Forest, The Deep End, worlds unlock in order, unlock screens. |
| 0.3 (1) | 2026-10-09 | `6526c7c` (`bigger-fish-v0.3-beta.1`) | Midnight Zone (world four: a headlamp in the dark, anglerfish lures); Shallow Reef reordered from 0.1 testers' numbers; beating a level 10 goes straight to the conquered screen; players who'd beaten Kelp Forest are told once that Midnight Zone is open. |
