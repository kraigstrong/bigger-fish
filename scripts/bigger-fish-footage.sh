#!/bin/bash
# Gameplay footage of Bigger Fish for the trailer and App Store previews, from the simulator.
#
#   scripts/bigger-fish-footage.sh <world>.<level> <policy> [from to]   # 60 fps at full size, from and to in seconds
#   scripts/bigger-fish-footage.sh --look <world>.<level> <policy>      # a contact sheet of the whole run
#
# Builds a Debug build and launches it with `-arcadePlaytest <world>.<level> -storeFootage <policy>` (see
# BiggerFish/StoreFootage.swift). The app plays the level with the diagnostics bot (collector, opportunist, or
# cautious) one frame at a time and saves each frame with the interface hidden; this script waits for them and
# encodes them. Footage never stutters, and a rerun gives the same frames: runs are deterministic. So a --look at the
# whole run, then a recording of just the seconds that are wanted, gives exactly what the look showed.
#
# Output goes to build/footage/ (ignored by git):
#   <world>.<level>-<policy>[-<from>-<to>].mp4   60 fps H.264, silent, at the simulator's screen size
#   <world>.<level>-<policy>-look.jpg            with --look: a frame every half second, ten to a row
#   <name>.txt                                   how the run went, and every bite: when, and the meal's size against
#                                                yours then and at its biggest, for finding moments to record
#
# Needs ffmpeg (brew install ffmpeg). FOOTAGE_DEVICE picks the simulator (default iPhone 17 Pro Max, 2868x1320, the
# App Store's 6.9" size). FOOTAGE_NO_BUILD=1 reuses the last build, already installed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/footage"
DERIVED="$ROOT/build/store-capture/DerivedData"
DEVICE="${FOOTAGE_DEVICE:-iPhone 17 Pro Max}"
BUNDLE=com.kraigstrong.biggerfish

usage() { sed -n '2,5p' "$0"; exit 1; }

LOOK=0
if [ "${1:-}" = --look ]; then LOOK=1; shift; fi
[ $# -eq 2 ] || [ $# -eq 4 ] || usage
LEVEL="$1" POLICY="$2" FROM="${3:-}" TO="${4:-}"
[[ $LEVEL =~ ^[a-z-]+\.[0-9]+$ ]] || { echo "not a level: $LEVEL (like sunset-cove.10)" >&2; usage; }
[[ " collector opportunist cautious " == *" $POLICY "* ]] || { echo "not a bot policy: $POLICY" >&2; usage; }
command -v ffmpeg >/dev/null || { echo "needs ffmpeg: brew install ffmpeg" >&2; exit 1; }

if [ "${FOOTAGE_NO_BUILD:-0}" != 1 ]; then
    destination="name=$DEVICE"
    [[ $DEVICE =~ ^[0-9A-Fa-f-]{36}$ ]] && destination="id=$DEVICE"
    xcodebuild build -quiet -project BiggerFish.xcodeproj -scheme BiggerFish -configuration Debug \
        -destination "platform=iOS Simulator,$destination" -derivedDataPath "$DERIVED"
fi
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
# Installing takes longer than a short recording, so only after a build, or when the app isn't there.
if [ "${FOOTAGE_NO_BUILD:-0}" != 1 ] || ! xcrun simctl get_app_container "$DEVICE" "$BUNDLE" >/dev/null 2>&1; then
    xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/BiggerFish.app"
fi

args=(-arcadePlaytest "$LEVEL" -storeFootage "$POLICY" -arcadeDisableRunRecording)
name="$LEVEL-$POLICY"
if [ $LOOK = 1 ]; then
    args+=(-storeFootageEvery 30 -storeFootageScale 0.25)
    name="$name-look"
elif [ -n "$FROM" ]; then
    args+=(-storeFootageFrom "$FROM" -storeFootageTo "$TO")
    name="$name-$FROM-$TO"
fi

frames="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Documents/StoreFootage"
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
rm -rf "$frames"
xcrun simctl launch "$DEVICE" "$BUNDLE" "${args[@]}" >/dev/null
waited=0
until [ -f "$frames/done.txt" ] || [ -f "$frames/failed.txt" ]; do
    [ $waited -gt 18000 ] && { echo "$name: not done after half an hour" >&2; exit 1; }
    perl -e "select(undef, undef, undef, 0.1)"
    waited=$((waited + 1))
done
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
[ -f "$frames/failed.txt" ] && { echo "$name failed: $(cat "$frames/failed.txt")" >&2; exit 1; }

mkdir -p "$OUT"
if [ $LOOK = 1 ]; then
    count=$(find "$frames" -name '*.jpg' | wc -l | tr -d ' ')
    ffmpeg -v error -y -framerate 1 -i "$frames/%05d.jpg" \
        -vf "tile=10x$(( (count + 9) / 10 )):padding=4" -frames:v 1 "$OUT/$name.jpg"
    cp "$frames/done.txt" "$OUT/$name.txt"
    echo "$OUT/$name.jpg (a frame every half second): $(head -1 "$frames/done.txt")"
else
    ffmpeg -v error -y -framerate 60 -i "$frames/%05d.jpg" -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p \
        -movflags +faststart "$OUT/$name.mp4"
    cp "$frames/done.txt" "$OUT/$name.txt"
    echo "$OUT/$name.mp4: $(head -1 "$frames/done.txt")"
fi
