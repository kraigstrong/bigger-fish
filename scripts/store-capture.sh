#!/bin/bash
# App Store screenshots and preview footage for Math Reef, from the simulator.
#
#   scripts/store-capture.sh screenshots [scene ...]   # default: every scene
#   scripts/store-capture.sh video
#
# Builds a debug build and launches it with `-storeCapture <scene>` (see MathReef/StoreCapture.swift),
# which stages believable progress in its own saved state and lets an autopilot swim.
# Output goes to build/store-capture/:
#   screenshots/<scene>[-NN].png  2868x1320 landscape PNGs (the 6.9" size). Play scenes are a burst of
#                                 frames to pick from.
#   video/raw.mov                 the simulator recording, as captured
#   video/soundtrack.wav          the game's own sounds and music, rebuilt from the app's cue log
#   video/full.mp4                1920x886, 30 fps, H.264 + stereo AAC: Apple's app preview format,
#                                 before trimming to 15-30 seconds (scripts/store-preview.sh)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/store-capture"
DERIVED="$ROOT/build/store-capture/DerivedData"
DEVICE="${STORE_CAPTURE_DEVICE:-iPhone 17 Pro Max}"
BUNDLE=com.kraigstrong.mathreef
STATIC_SCENES=(home world crown)
# The simulator draws the Dynamic Island into its frames (a device screenshot doesn't), so fill it in
# from the water around it. Measured on the 17 Pro Max in landscape: x 2716-2825, y 472-847.
TO_LANDSCAPE="transpose=1,delogo=x=2708:y=464:w=126:h=392"
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
    xcrun simctl launch "$DEVICE" "$BUNDLE" -storeCapture "$1" >/dev/null
}

# The simulator saves the portrait framebuffer; turn it to landscape and drop any alpha.
shoot() {
    local raw="$OUT/screenshots/.raw.png"
    xcrun simctl io "$DEVICE" screenshot --mask=ignored "$raw" >/dev/null 2>&1
    ffmpeg -v error -y -i "$raw" -vf "$TO_LANDSCAPE" -pix_fmt rgb24 "$1"
}

screenshots() {
    mkdir -p "$OUT/screenshots"
    local scenes=("$@")
    [ ${#scenes[@]} -eq 0 ] && scenes=("${STATIC_SCENES[@]}" "${PLAY_SCENES[@]}")
    for scene in "${scenes[@]}"; do
        launch "$scene"
        if [[ " ${PLAY_SCENES[*]} " == *" $scene "* ]]; then
            pause 2
            for i in $(seq -w 1 40); do shoot "$OUT/screenshots/$scene-$i.png"; pause 0.3; done
        elif [ "$scene" = crown ]; then
            # The crown lands about 3 seconds in, then flies onto the fish.
            for i in $(seq -w 1 12); do pause 0.5; shoot "$OUT/screenshots/$scene-$i.png"; done
        else
            pause 4
            shoot "$OUT/screenshots/$scene.png"
        fi
        echo "captured $scene"
    done
    rm -f "$OUT/screenshots/.raw.png"
}

video() {
    local dir="$OUT/video"
    mkdir -p "$dir"
    rm -f "$dir/raw.mov" "$dir/cues.log"
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --mask=ignored --force "$dir/raw.mov" 2>"$dir/record.log" &
    local recorder=$!
    # recordVideo prints when the first frame is written; that's time zero for the soundtrack.
    until grep -q "Recording started" "$dir/record.log" 2>/dev/null; do pause 0.05; done
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time' >"$dir/start.txt"
    xcrun simctl launch --console-pty "$DEVICE" "$BUNDLE" -storeCapture video >"$dir/cues.log" 2>&1 &
    local app=$!
    # The reef, the path, the instructions, a full round, then the results and crown.
    pause "${STORE_CAPTURE_SECONDS:-86}"
    kill -INT "$recorder"
    wait "$recorder" || true
    kill "$app" 2>/dev/null || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true

    local length
    length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/raw.mov")
    python3 scripts/store-soundtrack.py "$dir/cues.log" "$(cat "$dir/start.txt")" "$length" \
        MathReef/Sounds "$dir/soundtrack.wav"
    # Landscape (the recording is portrait), 1920x886, a constant 30 fps, and the soundtrack.
    ffmpeg -v error -y -i "$dir/raw.mov" -i "$dir/soundtrack.wav" \
        -vf "$TO_LANDSCAPE,scale=1920:886:flags=lanczos,fps=30,format=yuv420p" \
        -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M \
        -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart "$dir/full.mp4"
    echo "wrote $dir/full.mp4"
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
