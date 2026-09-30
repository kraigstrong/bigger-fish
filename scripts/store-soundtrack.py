#!/usr/bin/env python3
"""Rebuilds Math Reef's audio for a simulator recording, which captures no sound.

    store-soundtrack.py cues.log <recording start epoch> <length seconds> <Sounds dir> <out.wav>

In a store capture the app logs every cue (`STORE-CAPTURE-AUDIO <epoch> sound <name>` and
`... music <name|none> <delay> <fade>`). This mixes the same files the app plays, the way ReefAudio
plays them: effects at full volume, music at ReefAudio.musicVolume, each track fading in and out
and resuming where it left off.
"""
import subprocess
import sys

import numpy as np

RATE = 48000
MUSIC_VOLUME = 0.45  # ReefAudio.musicVolume


def load(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def main():
    cues_path, start, length, sounds, out = sys.argv[1:6]
    start, length = float(start), float(length)
    mix = np.zeros((int(length * RATE) + RATE, 2), dtype=np.float32)
    cache = {}

    def clip(name, ext):
        if name not in cache:
            cache[name] = load(f"{sounds}/{name}.{ext}")
        return cache[name]

    cues = []
    for line in open(cues_path, errors="replace"):
        parts = line.split()
        if len(parts) >= 4 and parts[0] == "STORE-CAPTURE-AUDIO":
            cues.append((float(parts[1]) - start, parts[2], parts[3:]))

    # Effects.
    for t, kind, args in cues:
        if kind != "sound" or t < 0:
            continue
        audio = clip(args[0], "caf")
        i = int(t * RATE)
        n = min(len(audio), len(mix) - i)
        if n > 0:
            mix[i:i + n] += audio[:n]

    # Music: one volume envelope per track, built from the switches.
    tracks = {"menu-music": [], "game-music": []}  # (time, target volume, fade seconds)
    current = None
    for t, kind, args in cues:
        if kind != "music":
            continue
        name, delay, fade = args[0], float(args[1]), float(args[2])
        if current:
            tracks[current].append((t, 0.0, fade))
        current = None if name == "none" else name
        if current:
            tracks[current].append((t + delay, MUSIC_VOLUME, fade))

    frames = len(mix)
    for name, changes in tracks.items():
        if not changes:
            continue
        audio = clip(name, "m4a")
        envelope = np.zeros(frames, dtype=np.float32)
        volume, last = 0.0, 0
        for t, target, fade in changes + [(frames / RATE, None, 0)]:
            i = max(0, min(frames, int(t * RATE)))
            envelope[last:i] = volume
            if target is None:
                break
            ramp = max(1, int(fade * RATE))
            j = min(frames, i + ramp)
            envelope[i:j] = np.linspace(volume, target, ramp, dtype=np.float32)[: j - i]
            volume, last = target, j
        # The track only advances while it's audible (it pauses after fading out).
        playing = envelope > 0
        position = np.cumsum(playing) - 1
        track = audio[np.mod(np.maximum(position, 0), len(audio))]
        mix += track * (envelope * playing)[:, None]

    peak = np.abs(mix).max()
    if peak > 0.98:
        mix *= 0.98 / peak
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-i", "-",
         "-t", str(length), out],
        input=mix.astype(np.float32).tobytes(), check=True,
    )
    print(f"soundtrack: {len(cues)} cues, peak {peak:.2f}")


if __name__ == "__main__":
    main()
