# Bigger Fish on TestFlight

How to ship a Bigger Fish beta to friends, and what each build was. Tracked in #54 (first external
build), #58 (privacy), #59 (smoke test), and #61 (feedback).

## What the build already has

- Bundle ID `com.kraigstrong.biggerfish`, team `MKACSCQ588`, automatic signing.
- Version 1.0.0 (see the build log at the end). iPhone and iPad (full screen), landscape.
- App icon (no alpha), loading screen, and launch color.
- `ITSAppUsesNonExemptEncryption = NO`: the only encryption is the system's HTTPS, so App Store
  Connect won't ask the export-compliance question on each upload.
- Category: Arcade games.
- Privacy manifest (`BiggerFish/PrivacyInfo.xcprivacy`): UserDefaults for saved progress and
  settings, and anonymous gameplay counts (product interaction, not linked to the player, not
  tracking).
- iCloud key-value storage (`BiggerFish/BiggerFish.entitlements`): progress is backed up to the player's own
  iCloud, which we can't read, so it isn't collected data and the privacy label doesn't change. Automatic signing
  adds the capability to the App ID on the first device build or archive after it was added. Both privacy pages
  (biggerfish.app/privacy and brightbench.app/bigger-fish/privacy, word for word the same) describe the iCloud copy
  (kraigstrong/BrightBench#63).
- Anonymous gameplay counts are on (`ArcadeAnalytics.isEnabled`), sent to
  `brightbench.app/api/bigger-fish/events` and tagged `testflight` for beta installs.
- Privacy policy: https://biggerfish.app/privacy
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
- Every world is open from the start (the unlock isn't sold yet, so everyone plays as if they'd bought it), five
  of them: Sunset Cove fourth, Midnight Zone fifth. Riptide Reef isn't there (it's an Xcode-only prototype).
- Sunset Cove: boats and their lines show before their hooks; touching a bait reels you up out of the water to
  "Caught on a hook."; a hook you've passed reels up near the surface; no hooked fish hangs behind you at a
  level's start.
- Each level starts on a short card: its name, the world's progress pips, and "Tap to start". A world's rules
  show only on its first level, until it's cleared. Retry skips the card.
- The world map rings and the level map's bar fill in as you clear levels; the card after a win shows the pips
  filling. Beating a world's level 10 shows its conquered screen with The Deep End.
- The world map's gear opens Settings: Sound effects, Music, and Vibration (remembered, and in the pause menu
  too), Replay tutorial, Privacy Policy and Support (biggerfish.app), Credits, and the version.
- Meals, close calls, bounces, stings, being eaten, and wins are felt (with Vibration on). Vibration off stops them.
- The screen sleeps on the maps, cards, and pause menu as it normally would, but not while you play.

### Progress in iCloud

Progress is backed up to iCloud key-value storage (#96). Sync usually takes seconds and sometimes minutes, so
give each step a minute before calling it a failure. Use a phone signed in to iCloud. Note what you've cleared
and one or two best times before each step.

- **Update over the last build:** progress, best times, and Deep End rings are kept, as before.
- **Delete and reinstall:** clear a level or two, wait a minute, then force-quit and delete the app. Reinstall it
  from TestFlight and open it: the cleared levels, best times, and seen conquered screens come back, with no
  tutorial. If the world map first shows a fresh game (the download hadn't arrived), stay on it: the levels fill in
  without relaunching. If the tutorial starts, skip it; the progress still arrives.
- **A second device** on the same Apple ID (an iPad or another iPhone): install and open it, and the first device's
  progress appears. Clear a different level on each: within a minute or two (or on reopening), both show both.
  Clear the same level on both with different times: both keep the faster one. Nothing cleared on either device is
  ever un-cleared.
- **Offline:** in Airplane Mode, clear a level, then go back online: it reaches the other device.
- **iCloud turned off:** turn Bigger Fish off under Settings > [your name] > iCloud (Saved to iCloud, See All), or
  sign out of iCloud on a test device. The game plays and saves exactly as before, and progress survives a
  force-quit. Turn it back on (or sign back in): the device keeps its progress and merges with iCloud's.
- **Different Apple ID** (a test device only): signing in to another account never removes the device's progress;
  it merges into that account's.

## The unlock

Bigger Fish is free to try: all ten of Shallow Reef's levels and the first two of every other world
(`GameTuning.freeLevelsPerWorld`). A one-time purchase opens every world from the start and every Deep End; a
world's Deep End still opens when its level 10 is beaten. It's on sale from 1.0 (`ArcadeUnlock.isSelling`), with the
paywall analytics on in the same release (`ArcadeAnalytics.sendsPaywallEvents`, #156). Xcode builds sell it against
`BiggerFish.storekit`, and TestFlight testers buy it free in the sandbox.

The in-app purchase in App Store Connect: a **Non-Consumable**, product ID `com.kraigstrong.biggerfish.allworlds`
(permanent once created), reference name "Unlock every world", $4.99, Family Sharing on, with the unlock screen as its
review screenshot. Its display name and description are in `appstore/bigger-fish/iap/allworlds/` (`push.py` sends
them), and `BiggerFish.storekit` matches them. Submit it with the first App Store version, 1.0.0.

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
> swimming. This beta has five worlds of ten levels each: Shallow Reef; Jelly Bloom, where
> jellyfish domes bounce you and their tentacles sting; Kelp Forest, where kelp slows you down and
> hides what's inside it; Sunset Cove, where boats pass overhead dangling baited hooks, so the
> easiest meal in the water is a trap; and Midnight Zone, where it's dark but for your headlamp, and
> every other fish carries the same little light, so you can't tell how big one is until your beam
> lands on it. Play the worlds in any order, and beat a world's tenth level to open its Deep End:
> five extra-hard levels for when you can't get enough.

**What to Test**

> Thanks for playing! This is Bigger Fish 1.0, the version going on the App Store on November 3.
>
> New in 1.0:
> - The unlock is on sale. All of Shallow Reef and the first two levels of every other world are free, and one
>   purchase opens the rest of every world: levels still open in order, and each world's Deep End opens once
>   you beat its level 10. In TestFlight, buying is free, so please try it: tap a padlocked level or Unlock
>   all, buy, and check the padlocks are gone. Then delete the app and reinstall it: your progress and the
>   unlock should come back on their own, with nothing to restore.
> - Kelp Forest: deep in the kelp, fish hide. Only their bubbles show until you get close.
> - Midnight Zone: your fish carries a lure, and your light shines from it.
>
> If you'd cleared levels past the free ones, they're padlocked until you unlock. Your progress is still
> there. We'd love to hear:
> - Whether buying works, whether the unlock comes back after a reinstall, and whether the unlock screen makes
>   sense.
> - Whether Kelp Forest's hidden fish feel fair: do the bubbles tell you enough?
> - Bugs, crashes, or sound problems.
>
> To send feedback, take a screenshot while playing and share it with TestFlight, or use Send Beta Feedback in
> the TestFlight app. The beta sends anonymous gameplay counts, like which levels were cleared, with no names
> or device IDs.

**Feedback Email:** the address you want testers' feedback to reach.

**Privacy Policy URL:** https://biggerfish.app/privacy

**Beta App Review:** your name, phone, and email as the contact. Sign-in isn't required. Notes:

> No account or sign-in. Tap a world, then a level, and hold anywhere to rise. From 1.0, a one-time
> in-app purchase opens the rest of every world (free in TestFlight); levels still open in order, and a
> world's Deep End opens once its level 10 is beaten. To reach the purchase, tap Unlock all on the world
> map, or a padlocked level such as Jelly Bloom 3. Restore purchase is on the same screen.

## Build log

| Build | Date | Source commit | Notes |
|---|---|---|---|
| 0.1 (1) | | `9385ced` (`bigger-fish-v0.1-beta.1`) | First external build. |
| 0.2 (1) | 2026-10-09 | `f98f340` (`bigger-fish-v0.2-beta.1`) | Kelp Forest, The Deep End, worlds unlock in order, unlock screens. |
| 0.3 (1) | 2026-10-09 | `6526c7c` (`bigger-fish-v0.3-beta.1`) | Midnight Zone (world four: a headlamp in the dark, anglerfish lures); Shallow Reef reordered from 0.1 testers' numbers; beating a level 10 goes straight to the conquered screen; players who'd beaten Kelp Forest are told once that Midnight Zone is open. |
| 0.4.0 (1) | 2026-10-12 | `19a652f` (`bigger-fish-v0.4-beta.1`) | Sunset Cove (world four of five: boats, baited hooks), every level frozen; progress backed up to iCloud; full-screen iPad; the credits game; the pause menu in Settings' style; a touch shows on the frame it lands; 60 fps while the screen is recorded. The unlock still isn't on sale. |
| 0.4.1 (1) | 2026-10-13 | `fd163a8` (`bigger-fish-v0.4.1-beta.1`) | Sunset Cove 12's green gate fish (16) a little smaller, 32.2 to 30.9, so the six meals you can reach before it eat it (in 0.4.0 only a glitch got past it). |
| 1.0.0 (1) | 2026-10-14 | `6fc9a83` (`bigger-fish-v1.0.0-rc.1`) | The first 1.0 candidate. The unlock on sale (free in TestFlight) with the paywall analytics on (#192); Kelp Forest hides fish deep in the kelp but for their bubbles (#196); the unlock screen's Kelp Forest and Midnight Zone clips re-recorded (#197); Midnight Zone's beam shines from your own lure (#195). Internal testers first; external once 0.4.1 is out of Beta App Review. |
