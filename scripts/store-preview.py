#!/usr/bin/env python3
"""Cuts the store capture's full recording into an App Store app preview.

    store-preview.py full.mp4 preview.mp4 START-END [START-END ...]

Joins the given clips (seconds into full.mp4) with short crossfades, keeping Apple's preview
format: 1920x886, 30 fps, H.264 High 4.0, stereo 256 kbps AAC at 48 kHz, 15-30 seconds.
Pick the clips from a timeline of full.mp4; scripts/store-capture.sh prints how.
"""
import subprocess
import sys

FADE = 0.3


def main():
    src, out, *spans = sys.argv[1:]
    clips = [tuple(float(x) for x in span.split("-")) for span in spans]
    length = sum(end - start for start, end in clips) - FADE * (len(clips) - 1)
    if not 15 <= length <= 30:
        sys.exit(f"preview would be {length:.1f}s; Apple allows 15-30s")

    parts, offset = [], 0.0
    for i, (start, end) in enumerate(clips):
        parts.append(f"[0:v]trim={start}:{end},setpts=PTS-STARTPTS[v{i}]")
        parts.append(f"[0:a]atrim={start}:{end},asetpts=PTS-STARTPTS[a{i}]")
    video, audio = "v0", "a0"
    for i in range(1, len(clips)):
        offset += clips[i - 1][1] - clips[i - 1][0] - FADE
        parts.append(f"[{video}][v{i}]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[vx{i}]")
        parts.append(f"[{audio}][a{i}]acrossfade=d={FADE}[ax{i}]")
        video, audio = f"vx{i}", f"ax{i}"
    # A short fade in from black and out at the end.
    parts.append(f"[{video}]fade=t=in:d=0.3,fade=t=out:st={length - 0.5:.3f}:d=0.5,format=yuv420p[vout]")
    parts.append(f"[{audio}]afade=t=in:d=0.3,afade=t=out:st={length - 0.5:.3f}:d=0.5[aout]")

    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", src, "-filter_complex", ";".join(parts),
         "-map", "[vout]", "-map", "[aout]", "-r", "30",
         "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
         "-b:v", "11M", "-maxrate", "12M", "-bufsize", "24M",
         "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
         "-movflags", "+faststart", out],
        check=True,
    )
    print(f"wrote {out} ({length:.1f}s)")


if __name__ == "__main__":
    main()
