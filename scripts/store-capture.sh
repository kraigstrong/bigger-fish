#!/bin/bash
# App Store screenshots and preview footage for Math Reef, from the simulator.
#
#   scripts/store-capture.sh screenshots [scene ...]   # default: every scene
#   scripts/store-capture.sh video
#
# Builds a debug build and launches it with `-storeCapture <scene>` (see MathReef/StoreCapture.swift),
# which stages believable progress in its own saved state and lets an autopilot swim. Everything is
# drawn by the app itself, so nothing has the simulator's Dynamic Island over it.
# Output goes to build/store-capture/:
#   screenshots/<scene>[-NN].png  landscape PNGs at the screen's full size: 2868x1320 on the iPhone
#                                 17 Pro Max (6.9"), 2752x2064 on a 13-inch iPad. Play scenes and the
#                                 crown are a burst of frames to pick from.
#   video/frames/                 the frames the app drew, 30 a second, and when it drew each
#   video/soundtrack.wav          the game's own sounds and music, rebuilt from the app's cue log
#   video/full.mp4                30 fps, H.264 + stereo AAC at Apple's app preview size: 1920x886 on
#                                 an iPhone, 1600x1200 on an iPad; trim it to 15-30 seconds with
#                                 scripts/store-preview.py
#
# STORE_CAPTURE_DEVICE picks the simulator (default iPhone 17 Pro Max; 'iPad Pro 13-inch (M5)' for the
# iPad), STORE_CAPTURE_OUT the output folder, and STORE_CAPTURE_SECONDS the video's length (default 86).
# The video plays frame by frame, a 60th of a second of play each however long the simulator takes to
# save one (about 15 minutes for 86 seconds), so it comes out smooth. Screenshots play in real time unless
# STORE_CAPTURE_FRAME_BY_FRAME=1: on an iPad, where saving a full-size frame holds the game up, set it so
# a burst keeps pace with the game.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${STORE_CAPTURE_OUT:-$ROOT/build/store-capture}"
DERIVED="$ROOT/build/store-capture/DerivedData"
DEVICE="${STORE_CAPTURE_DEVICE:-iPhone 17 Pro Max}"
BUNDLE=com.kraigstrong.mathreef
STATIC_SCENES=(home world crown)
PLAY_SCENES=(play wrong addition exponents)

build() {
    xcodebuild build -quiet -project BiggerFish.xcodeproj -scheme MathReef -configuration Debug \
        -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED"
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/MathReef.app"
}

pause() { perl -e "select(undef, undef, undef, $1)"; }

launch() {
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    local steady=()
    [ "${STORE_CAPTURE_FRAME_BY_FRAME:-0}" = 1 ] && steady=(-storeCaptureFrameByFrame)
    xcrun simctl launch "$DEVICE" "$BUNDLE" -storeCapture "$1" "${steady[@]}" >/dev/null
}

# Screenshot scenes save the frames the app draws (no Dynamic Island over them) in its Documents
# folder: one for a still scene, a burst for play and the crown. Wait for the last, then collect.
screenshots() {
    mkdir -p "$OUT/screenshots"
    local scenes=("$@")
    [ ${#scenes[@]} -eq 0 ] && scenes=("${STATIC_SCENES[@]}" "${PLAY_SCENES[@]}")
    for scene in "${scenes[@]}"; do
        local last="$scene"
        [[ " ${STATIC_SCENES[*]} " == *" $scene "* && $scene != crown ]] || last="$scene-60"
        local frames
        frames="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Documents/StoreCapture"
        xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
        rm -rf "$frames"
        launch "$scene"
        local waited=0
        until [ -f "$frames/$last.png" ] || [ $waited -gt 6000 ]; do
            pause 0.1
            waited=$((waited + 1))
        done
        pause 0.5
        rm -f "$OUT/screenshots/$scene"*.png
        for frame in "$frames/$scene"*.png; do
            # App Store Connect rejects PNGs with an alpha channel.
            ffmpeg -v error -y -i "$frame" -pix_fmt rgb24 "$OUT/screenshots/$(basename "$frame")"
        done
        echo "captured $scene"
    done
}

video() {
    local dir="$OUT/video" seconds="${STORE_CAPTURE_SECONDS:-86}"
    mkdir -p "$dir"
    rm -rf "$dir/frames" "$dir/cues.log"
    local frames
    frames="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Documents/StoreCapture/video"
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    rm -rf "$frames"
    # The console carries the audio cues: the simulator plays no sound into a capture.
    xcrun simctl launch --console-pty "$DEVICE" "$BUNDLE" -storeCapture video -storeCaptureSeconds "$seconds" \
        >"$dir/cues.log" 2>&1 &
    local app=$! waited=0 limit=$(( seconds * 30 + 300 ))
    until [ -f "$frames/done.txt" ]; do
        [ $waited -gt $(( limit * 10 )) ] && { echo "video: not done after ${limit}s" >&2; exit 1; }
        pause 0.1
        waited=$((waited + 1))
    done
    kill "$app" 2>/dev/null || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    mv "$frames" "$dir/frames"

    # Frame by frame, the frames are exactly a 30th of a second of play apart; the soundtrack starts with the first.
    local start length size
    start=$(head -1 "$dir/frames/times.txt")
    length=$(awk 'NR == 1 { first = $1 } { last = $1 } END { printf "%.3f", last - first + 1 / 30 }' "$dir/frames/times.txt")
    python3 scripts/store-soundtrack.py "$dir/cues.log" "$start" "$length" MathReef/Sounds "$dir/soundtrack.wav"
    # Apple's app preview size: wider than 2:1 is an iPhone, anything else an iPad.
    size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$dir/frames/00000.jpg" |
        awk -F, '{ print ($1 > 2 * $2) ? "1920:886" : "1600:1200" }')
    ffmpeg -v error -y -framerate 30 -i "$dir/frames/%05d.jpg" -i "$dir/soundtrack.wav" \
        -vf "scale=$size:flags=lanczos,format=yuv420p" \
        -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M \
        -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "$dir/full.mp4"
    echo "wrote $dir/full.mp4 ($(cat "$dir/frames/done.txt"), ${size/:/x})"
}

# Check the tools up front, not after the build or a minute and a half of recording.
need_ffmpeg() {
    command -v ffmpeg >/dev/null || { echo "needs ffmpeg: brew install ffmpeg" >&2; exit 1; }
}
need_numpy() {
    python3 -c "import numpy" 2>/dev/null || { echo "video needs NumPy: python3 -m pip install numpy" >&2; exit 1; }
}

case "${1:-}" in
    screenshots) shift; need_ffmpeg; build; screenshots "$@" ;;
    video) need_ffmpeg; need_numpy; build; video ;;
    *) sed -n '2,6p' "$0"; exit 1 ;;
esac
