# Bigger Fish on TestFlight

How to ship a Bigger Fish beta to friends, and what each build was. Tracked in #54 (first external
build), #58 (privacy), #59 (smoke test), and #61 (feedback).

## What the build already has

- Bundle ID `com.kraigstrong.biggerfish`, team `MKACSCQ588`, automatic signing.
- Version 1.1.0 (see the build log at the end). iPhone and iPad (full screen), landscape.
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
- The Release build has none of the debug tools: no tuner, run recorder, playtest shortcuts, or progress reset.
  From 1.1 it has the planner, for the Open Water alone: its levels are new every run, so they're planned on the
  device. The campaign still plays only its frozen plans.

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

- The loading screen shows, then the home screen. No black screen.
- Play a level in each world, win one, and lose one, both eaten and stung.
- Progress is kept after force-quitting and reopening.
- Sound plays with the phone on silent. The Sound effects and Music switches work on the map and in
  the pause menu, and are remembered.
- Background the app mid-level: the game pauses and the music stops, then resumes on return.
- A phone call or alarm during a level doesn't break the game or its sound.

Since 0.3:

- **Fresh install:** the home screen first. Adventure's first tap plays its tutorial, opening on "Hold anywhere to rise": hold
  to rise, let go to fall, eat a smaller fish, dodge a bigger one, watch a missed fish grow and catch it back, then
  eat through the wall and catch the last two ("2 fish left"). Missing a wall meal gets you eaten, and Retry starts
  the wall again. It ends on the world map. Open Water's first tap plays its own (eat smaller, avoid bigger, gather a
  pearl; rising and falling only if Adventure's hasn't taught them), then the run starts. The Shop's first open shows
  arrows to your pearls, the kinds, and the shelf; a tap clears them. Settings > How to play plays any of them again,
  then goes home.
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
- The home screen's gear opens Settings: Sound effects, Music, and Vibration (remembered, and in the pause menu
  too), How to play (Adventure, Open Water, Shop), Privacy Policy and Support (biggerfish.app), Credits, and the version.
- Meals, close calls, bounces, stings, being eaten, and wins are felt (with Vibration on). Vibration off stops them.
- The screen sleeps on the maps, cards, and pause menu as it normally would, but not while you play.

Since 1.1:

- **Open Water** (on the home screen): a run goes round all five worlds, a new level each time; eating a level's
  last gate shrinks you for the next world, and being eaten ends the run. The card shows the fish eaten, the pearls,
  the best, and Shop.
- **Pearls** sit beside big fish: touching one takes it (no growth) and it's kept at once. The home screen's Shop and
  the card's Shop show the total.
- **The pearl shop:** buying puts a look on, and it shows everywhere (the maps, the campaign, the credits). The
  Christmas looks (Dec 1 – Jan 6) and the Valentine's ones (Feb 1 – 15) show dimmed out of season, to try on only.
  Earned looks show what earns them.
- **Without the unlock:** Open Water on the home screen says "5 runs left today"; a run counts once it takes its
  first pearl; with none left it says "More runs tomorrow", the card offers Unlock all in place of Retry, and both open the unlock
  screen. Buying makes Open Water unlimited.
- **The home screen** (from 1.1.0 (2)): your fish in its look with Shop under it on the left (tapping the fish opens
  the shop too); Adventure and Open Water on the right. Adventure shows a crown per world (outlined, silver, gold),
  and until Shallow Reef 1 is beaten, "Start here" and "Eat every fish to win". It opens the world map (Back and
  "Adventure" along the top), scrolled to your fish; Back comes home. Open Water says "How far can you get?" until a
  run, then your best. In Open Water and the tutorial, the pause menu's way out and a run card's say Home; a level's
  say Level map and Levels. Check an iPhone SE and the iPhone Duo's outer screen: every name on one line.

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
- "Unlock all" on the home screen or the world map, a padlocked level, Next level after a world's level 2, beating Shallow
  Reef's level 10, and the Open Water with the day's runs used up all show the same unlock screen (from 1.1.0 (4)): "Unlock
  it all", a looping clip of each locked world with its name, The Deep End's line and the Open Water's, the price, Restore
  purchase, and Not now.
- Buying (or Restore purchase after buying on another device) shows "Every world is open!" and removes every
  padlock. Beating a world's level 10 then shows its conquered screen with just The Deep End.

## Test Information (paste into App Store Connect)

**Beta App Description** (as App Store Connect has it from 1.1.0)

> Bigger Fish is an arcade game about working your way up the food chain. Hold to rise, release to fall. Eat fish smaller than you, avoid the bigger ones, and grow until you’re the last fish swimming. This beta has the full game, all five worlds: Shallow Reef; Jelly Bloom, where jellyfish domes bounce you and their tentacles sting; Kelp Forest; Sunset Cove, with fishing hooks to dodge; and Midnight Zone, where your headlamp is the only light. Then take on the Open Water: an endless run round all five worlds, with pearls to collect for looks in the pearl shop. Bigger Fish launches on the App Store on November 3.

**What to Test** (1.1.0 (2); build 1 had the same without the home screen)

> Thanks for playing! This is Bigger Fish 1.1, a beta of what's coming after the App Store launch.
>
> New in 1.1:
> - A new home screen with two ways to play. Adventure is the five worlds, with a crown for each one you conquer. Open Water is the new endless run. Your fish sits on the left in whatever it's wearing, with the Shop under it.
> - Open Water: you go round all five worlds, a brand-new level each time, until a bigger fish eats you. Eat a level's last big fish to move on. Your score is how many fish you eat.
> - Pearls sit right beside the big fish. Swim close enough to take one. They're only earned by playing, never sold.
> - The Shop: on the home screen (or tap your fish), or Shop after a run. It has colors, patterns, hats, faces and trails for your fish, and your fish wears them everywhere. A few looks are earned instead, like reaching Kelp Forest in a run or conquering a world. Some are seasonal: the Christmas looks are on sale Dec 1 – Jan 6, and the Valentine's ones Feb 1 – 15.
> - Without the unlock, Open Water has 5 runs a day. A run counts once it takes its first pearl. The unlock makes it unlimited. Buying is free in TestFlight, so if you can, play a day or two without buying first and tell us how the limit feels.
>
> We'd love to hear: Is it clear where to start? Is Open Water fun, and how far do you get? Did anything feel unfair? Do pearls and the shop make you want to keep playing? How do 5 runs a day feel? And any bugs, crashes or slowdowns, especially on older or smaller iPhones and on the iPhone Duo.
>
> To send feedback, take a screenshot while playing and share it with TestFlight, or use Send Beta Feedback in the TestFlight app. The beta sends anonymous counts, like how far a run got and which looks were bought, with no names or device IDs.

**Feedback Email:** the address you want testers' feedback to reach.

**Privacy Policy URL:** https://biggerfish.app/privacy

**Beta App Review:** your name, phone, and email as the contact. Sign-in isn't required. Notes (1.1.0 (2); list every
limited-edition look and its dates whenever they change, App Review guideline 2.5.19):

> No account or sign-in. Hold anywhere to rise, release to fall. New in 1.1: a home screen with two modes, Adventure (the campaign's worlds) and Open Water, an endless mode.
>
> Pearls are earned only by playing. They can't be bought and have no real-money value. They buy cosmetic looks for your fish in the pearl shop, from Shop on the home screen or Shop after a run.
>
> Six looks are limited editions. Outside their dates they're shown dimmed with their dates, and can be tried on but not bought:
> - Santa hat, Reindeer antlers and Red nose: Dec 1 – Jan 6.
> - Heart glasses, Polka hearts and the Hearts trail: Feb 1 – 15.
>
> Without the one-time in-app purchase (free in TestFlight), Open Water allows 5 runs a day, and the purchase removes the limit. The purchase screen opens from Unlock all on the home screen or the world map, from a padlocked level such as Jelly Bloom 3, or from Open Water once the day's runs are used up.

## Build log

| Build | Date | Source commit | Notes |
|---|---|---|---|
| 0.1 (1) | | `9385ced` (`bigger-fish-v0.1-beta.1`) | First external build. |
| 0.2 (1) | 2026-10-09 | `f98f340` (`bigger-fish-v0.2-beta.1`) | Kelp Forest, The Deep End, worlds unlock in order, unlock screens. |
| 0.3 (1) | 2026-10-09 | `6526c7c` (`bigger-fish-v0.3-beta.1`) | Midnight Zone (world four: a headlamp in the dark, anglerfish lures); Shallow Reef reordered from 0.1 testers' numbers; beating a level 10 goes straight to the conquered screen; players who'd beaten Kelp Forest are told once that Midnight Zone is open. |
| 0.4.0 (1) | 2026-10-12 | `19a652f` (`bigger-fish-v0.4-beta.1`) | Sunset Cove (world four of five: boats, baited hooks), every level frozen; progress backed up to iCloud; full-screen iPad; the credits game; the pause menu in Settings' style; a touch shows on the frame it lands; 60 fps while the screen is recorded. The unlock still isn't on sale. |
| 0.4.1 (1) | 2026-10-13 | `fd163a8` (`bigger-fish-v0.4.1-beta.1`) | Sunset Cove 12's green gate fish (16) a little smaller, 32.2 to 30.9, so the six meals you can reach before it eat it (in 0.4.0 only a glitch got past it). |
| 1.0.0 (1) | 2026-10-14 | `6fc9a83` (`bigger-fish-v1.0.0-rc.1`) | The first 1.0 candidate. The unlock on sale (free in TestFlight) with the paywall analytics on (#192); Kelp Forest hides fish deep in the kelp but for their bubbles (#196); the unlock screen's Kelp Forest and Midnight Zone clips re-recorded (#197); Midnight Zone's beam shines from your own lure (#195). Internal testers first; external once 0.4.1 is out of Beta App Review. |
| 1.0.1 (1) | 2026-10-25 | `aa91cee` (`bigger-fish-v1.0.1-rc.1`) | The first build from Xcode 27.1, filling an iPhone Duo's screens (#226). Friends and Family only, for a friend's Duo smoke test. |
| 1.1.0 (1) | 2026-10-26 | `9088a9c` (`bigger-fish-v1.1.0-beta.1`) | Open Water and the pearl shop in the shipped game, planned on the device (#237); 5 free runs a day without the unlock, counted at a run's first pearl (#239); Valentine's looks, earned looks kept, retired looks (#236); a level that won't plan cleanly deals again (#237); the world map's title in the bottom corner and its stops without their detail line (#240). Soaked 10 minutes on an iPhone 16 Pro: 120 fps, memory flat. Friends and Family only: "Marketing site" gets no more builds (Kraig, 2026-10-26). |
| 1.1.0 (2) | 2026-10-26 | `64dd1e1` (`bigger-fish-v1.1.0-beta.2`) | The home screen (#242): your fish and Shop on the left, Adventure (a crown per world; opens the world map) and Open Water on the right; "Start here" and "Eat every fish to win" for a new player; Home, not Level map, to leave the Open Water and the tutorial; new Adventure and Open Water pictures. In Family (internal, every build) at once. Apple takes no build of a version for beta review while another is waiting (`ANOTHER_BUILD_IN_REVIEW`), so 1.1.0 (1), still waiting, was expired (Kraig's call) and build 2 submitted for Friends and Family. The 1.0.0 App Store review wasn't touched. |
| 1.1.0 (3) | 2026-10-27 | `08be316` (`bigger-fish-v1.1.0-rc.1`) | The launch candidate, if 1.1.0 replaces 1.0.0 in App Review (the SE and the Duo checked out on build 2). Three tutorials, one for each part of the home screen (#246); Adventure levels count down their last 10 fish (#249); buying a look plays a sound and buzzes (#250); a droopy starfish and a pirate hat the right way up (#251); Zebra is a color, Polka hearts is a Valentine's look, and the shop's button says Buy (#252). In Family (internal) at once, and in Friends and Family with build 2's What to Test, approved in beta review the same night; the Beta App Review notes now list Polka hearts with the Valentine's looks. 1.0.0 is still waiting for App Review. |
| 1.1.0 (4) | 2026-10-27 | `79475b0` (`bigger-fish-v1.1.0-rc.2`) | The launch candidate in place of build 3. Each tutorial opens on "Hold anywhere to rise", with no goal over it (#254); one unlock screen every way in, "Unlock it all", naming the Open Water as well as the worlds, without the worlds' one-liners (#255). Kraig played both as a new player first (a Debug build with `-arcadeScreen new-player`). In Family at once, and in Friends and Family with build 2's What to Test, for beta review; build 3 had been approved by then, so it wasn't expired. 1.0.0 is still waiting for App Review. |
