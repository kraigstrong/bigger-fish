# Sound credits

The sound effects are from Mixkit's free **sound effects** library, whose license allows use in video
games and commercial projects with no attribution required. The music is from Pixabay, whose Content
License allows music inside a new work such as a game, also with no attribution required. It bans
only redistributing a track on its own. The details below are for our own traceability, not a
license obligation.

Mixkit's **stock music** license is different: it does not allow use in video games. Don't add Mixkit
music tracks to this app.

## Sound effects

Each file is trimmed to just past its audible end (measured at a -45 dB floor), peak-normalized, and
stored as 16-bit PCM `.caf` so it plays without decoding delay. Source URLs take the form
`https://assets.mixkit.co/active_storage/sfx/<id>/<id>-preview.mp3`.

- `gulp.caf` (the fish swallows a right answer)
  - Mixkit 2925, "Soap bubble sound"
  - Trimmed 1.14s → 0.26s: 40ms of leading silence removed, fade from 0.20s. Peak -1.5 dBFS.
- `wrong.caf` (a wrong answer is spat out)
  - Mixkit 240, "Failure arcade alert notification"
  - Trimmed 1.27s → 0.70s, fade from 0.60s. Peak -3.0 dBFS, a little under the gulp so a miss
    doesn't sound louder than a hit.
- `map-jingle.caf` (arriving at the reef map, at launch or back from a level)
  - Mixkit 2831, "Magic potion music and fx"
  - Trimmed 4.27s → 3.70s, fade from 3.40s. Peak -3.0 dBFS.
- `star.caf` (rings once per star on the results panel)
  - Mixkit 600, "Achievement bell"
  - Same file as Time Tutor's `star-ding.mp3`: 2.40s source → 1.40s. Peak -1.5 dBFS.
- `crown.caf` (a round earns a new or better crown)
  - Mixkit 2633, "Sweeping sparkle presentation intro"
  - Same file as Time Tutor's `crown.mp3`: 3.00s source → 2.80s. Peak -1.3 dBFS.

## Music

Neither track is registered with YouTube Content ID, so videos of the game won't draw
copyright claims. Each is loudness-normalized to -18 LUFS, gets a 50ms fade-in and a 300ms fade-out so
the loop doesn't click, and is encoded as 128 kbps AAC with `afconvert`. Playback volume is
`ReefAudio.musicVolume`.

- `menu-music.m4a` (loops under the reef map, level paths, and a level's instructions)
  - Pixabay 578468, "Kids Playground Giggles Parade" by alex-morgan
  - https://pixabay.com/music/happy-childrens-tunes-kids-playground-giggles-parade-578468/
  - 55.7s, turned down 8.2 dB.
- `game-music.m4a` (loops while the fish swims)
  - Pixabay 214978, "Puppy Love Waltz" by GoldenSoundLabs
  - https://pixabay.com/music/cartoons-puppy-love-waltz-214978/
  - 4:00; the source's 150ms of leading silence is removed, then it's turned down 1.9 dB.
