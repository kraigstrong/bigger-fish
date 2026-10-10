# Bigger Fish on TestFlight

How to ship a Bigger Fish beta to friends, and what each build was. Tracked in #54 (first external
build), #58 (privacy), #59 (smoke test), and #61 (feedback).

## What the build already has

- Bundle ID `com.kraigstrong.biggerfish`, team `MKACSCQ588`, automatic signing.
- Version 0.2 (0.1 was the first build). iPhone only, landscape.
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
2. **Archive.** Check out the integration branch at the commit you want. In Xcode, choose the
   BiggerFish scheme and Any iOS Device (arm64), then Product > Archive.
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

New in 0.2, worlds unlock in order:

- **Fresh install:** only Shallow Reef is open. Jelly Bloom and Kelp Forest show a lock and "Beat ...
  to unlock". Beating Shallow Reef's level 10 shows the "Shallow Reef conquered!" screen once, with
  Jelly Bloom and The Deep End; Swim there, Dive in, and Maybe later each go where they say.
- **Update over 0.1** (with Shallow Reef's level 10 beaten): every world played before stays open.
  On first launch the unlock screen for the furthest beaten world shows once, then never again.
- Each world's level map shows The Deep End past level 10, locked until level 10 is beaten.
- Kelp Forest: kelp slows you, fish inside it are silhouettes, and your whole fish stays in front of
  the kelp.

New in 0.3, Midnight Zone and a reordered Shallow Reef:

- **Update over 0.2 with Kelp Forest's level 10 beaten:** your progress, Deep End rings, and best times
  are all still there. On first launch, Kelp Forest's conquered screen shows once more, now with the
  "Midnight Zone is open" card, then never again. It doesn't show if you've already played Midnight Zone.
- **Fresh install:** Midnight Zone shows a lock and "Beat Kelp Forest to unlock". Beating Kelp Forest's
  level 10 opens it, and its conquered screen points to it.
- Midnight Zone: the water is dark except your headlamp's beam, which tilts as you rise or dive; every
  other fish carries the same small lure light, and its body only shows in your beam. Your whole fish
  stays bright.
- Beating any world's level 10 for the first time goes straight to its conquered screen, with no
  result card first. Replaying it shows the card.
- Shallow Reef plays its levels in the new order; levels cleared before stay cleared by number.

## Test Information (paste into App Store Connect)

**Beta App Description**

> Bigger Fish is an arcade game about working your way up the food chain. Hold to rise, release to
> fall. Eat fish smaller than you, avoid the bigger ones, and grow until you're the last fish
> swimming. This beta has four worlds of ten levels each: Shallow Reef; Jelly Bloom, where
> jellyfish domes bounce you and their tentacles sting; Kelp Forest, where kelp slows you down and
> hides what's inside it; and Midnight Zone, where it's dark but for your headlamp, and every other
> fish carries the same little light, so you can't tell how big one is until your beam lands on it.
> Beat a world's tenth level to open the next, and The Deep End: five extra-hard levels for when you
> can't get enough.

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
