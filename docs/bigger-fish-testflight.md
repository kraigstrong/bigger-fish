# Bigger Fish on TestFlight

How to ship a Bigger Fish beta to friends, and what each build was. Tracked in #54 (first external
build), #58 (privacy), #59 (smoke test), and #61 (feedback).

## What the build already has

- Bundle ID `com.kraigstrong.biggerfish`, team `MKACSCQ588`, automatic signing.
- Version 0.1, build 1. iPhone only, landscape.
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

## Test Information (paste into App Store Connect)

**Beta App Description**

> Bigger Fish is an arcade game about working your way up the food chain. Hold to rise, release to
> fall. Eat fish smaller than you, avoid the bigger ones, and grow until you're the last fish
> swimming. This beta has two worlds of ten levels each: Shallow Reef, and Jelly Bloom, where
> jellyfish domes bounce you and their tentacles sting.

**What to Test**

> Thanks for playing! Play as far as you can in both worlds. We'd love to hear:
> - Which levels felt too hard or too easy, and where you got stuck.
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
| 0.1 (1) | | | First external build. |
