# Bigger Fish sound credits

The sound effects are from Mixkit's free **sound effects** library, whose license allows use in video
games and commercial projects with no attribution required. The music is from Pixabay, whose Content
License allows music inside a new work such as a game, also with no attribution required. It bans
only redistributing a track on its own. The details below are for our own traceability, not a
license obligation.

Mixkit's **stock music** license is different: it does not allow use in video games. Don't add Mixkit
music tracks to this app.

## Sound effects

Each file is trimmed to just past its audible end (measured at a -45 dB floor) with any leading
silence removed so it fires on time, faded over its last 60ms, peak-normalized, and stored as 16-bit
PCM `.caf` so it plays without decoding delay. Source URLs take the form
`https://assets.mixkit.co/active_storage/sfx/<id>/<id>-preview.mp3`. Playback volumes are in
`GameTuning` (Sound).

- `pop.caf` (the player swallows a fish)
  - Mixkit 3192, "Egg bubble pop"
  - Trimmed 0.75s → 0.16s: 68ms of leading silence removed. Peak -1.5 dBFS.
- `gulp.caf` (a bounce off a jellyfish dome, played sped up)
  - Mixkit 2925, "Soap bubble sound"; the same file as Math Reef's `gulp.caf`
  - Trimmed 1.14s → 0.26s: 40ms of leading silence removed, fade from 0.20s. Peak -1.5 dBFS.
- `zap.caf` (the player is stung, with the jolt and sparks)
  - Mixkit 2967, "Electric fence buzzing"
  - Trimmed 1.12s → 0.52s. Peak -3.0 dBFS.
- `wrong.caf` (a run is lost; after a sting, when the result appears)
  - Mixkit 240, "Failure arcade alert notification"; the same file as Math Reef's `wrong.caf`
  - Trimmed 1.27s → 0.70s, fade from 0.60s. Peak -3.0 dBFS.
- `win.caf` (the player is the last fish swimming)
  - Mixkit 2018, "Winning notification"
  - Trimmed 1.75s → 1.39s. Peak -1.5 dBFS.
- `start.caf` (the tap that begins a level)
  - Mixkit 2830, "Video game magic potion"
  - Trimmed 2.81s → 2.27s. Peak -3.0 dBFS.

## Music

Each track is loudness-normalized to -18 LUFS with a plain gain change, has its leading and trailing
silence removed, gets a 50ms fade-in and a 300ms fade-out so the loop doesn't click, and is encoded
as 128 kbps AAC with `afconvert`. Playback volume is `GameTuning.musicVolume`.

- `menu-music.m4a` (loops under the world map and level maps)
  - Pixabay 560238, "Tidal Groove [Chill Pop Instrumental]" by tideblue (marked AI-generated)
  - https://pixabay.com/music/lofi-tidal-groove-chill-pop-instrumental-560238/
  - 1:17, turned down 3.4 dB. Not registered with YouTube Content ID.
- `game-music.m4a` (loops under a level, from its ready screen to its result)
  - Pixabay 132518, "Aquarium Fish" by Magiksolo
  - https://pixabay.com/music/beats-aquarium-fish-132518/
  - 2:26, turned down 7.5 dB. **Registered with YouTube Content ID**: videos of the game can draw
    copyright claims, cleared by disputing with the Pixabay license.
