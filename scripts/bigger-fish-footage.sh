#!/bin/bash
# Gameplay footage of Bigger Fish for the trailer and App Store previews, from the simulator.
#
#   scripts/bigger-fish-footage.sh <world>.<level> <policy> [from to]   # 60 fps at full size, from and to in seconds
#   scripts/bigger-fish-footage.sh --look <world>.<level> <policy>      # a contact sheet of the whole run
#   scripts/bigger-fish-footage.sh --shop                               # the pearl shop's tour, recorded live
#
# <world>.<level> can be open-water.<seed> for an Open Water run (its levels planned as it reaches them). FOOTAGE_LOOK
# dresses your fish (item IDs, comma separated, like color.galaxy,hat.party): the name gets "-dressed".
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
#   <world>.<level>-<policy>-<from>-<to>/        with FOOTAGE_SCALE above 1: the frames as PNGs that many times the
#                                                screen's size, sharp, for App Store art (2.45 makes 5244 wide)
#   <name>.txt                                   how the run went, and every bite: when, and the meal's size against
#                                                yours then and at its biggest, for finding moments to record (in the
#                                                Open Water, each pearl taken and level reached too)
#   shop-tour.mp4                                with --shop: the shop trying on and buying three looks, 60 fps, the
#                                                same size as the gameplay
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

LOOK=0 SHOP=0
if [ "${1:-}" = --look ]; then LOOK=1; shift; fi
if [ "${1:-}" = --shop ]; then SHOP=1; set -- shop.1 collector; fi
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

if [ $SHOP = 1 ]; then
    # Live: the shop's tour plays on its own (StoreFootage.shopTour) while the simulator's screen is recorded. Its
    # first seconds are the loading screen; the trailer starts the shot after them.
    mkdir -p "$OUT"
    raw="$OUT/shop-tour-raw.mov"
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    xcrun simctl io "$DEVICE" recordVideo --codec=h264 --mask=ignored --force "$raw" >/dev/null 2>&1 &
    recorder=$!
    sleep 1
    xcrun simctl launch "$DEVICE" "$BUNDLE" -storeFootageShop -arcadeDisableRunRecording >/dev/null
    sleep 10
    kill -INT $recorder
    wait $recorder || true
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    # Landscape, at the gameplay's frame size and rate.
    size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$raw")
    turn=""
    [ "${size%,*}" -lt "${size#*,}" ] && turn="transpose=2,"
    ffmpeg -v error -y -i "$raw" -vf "${turn}scale=2622:1206:flags=lanczos,fps=60" -c:v libx264 -preset slow -crf 14 \
        -pix_fmt yuv420p -movflags +faststart "$OUT/shop-tour.mp4"
    rm -f "$raw"
    echo "$OUT/shop-tour.mp4"
    exit 0
fi

if [[ $LEVEL == open-water.* ]]; then
    args=(-openWater "${LEVEL#open-water.}" -storeFootage "$POLICY" -arcadeDisableRunRecording)
else
    args=(-arcadePlaytest "$LEVEL" -storeFootage "$POLICY" -arcadeDisableRunRecording)
fi
name="$LEVEL-$POLICY"
if [ -n "${FOOTAGE_LOOK:-}" ]; then
    args+=(-storeFootageLook "$FOOTAGE_LOOK")
    name="$name-dressed"
fi
if [ $LOOK = 1 ]; then
    args+=(-storeFootageEvery 30 -storeFootageScale 0.25)
    name="$name-look"
elif [ -n "$FROM" ]; then
    args+=(-storeFootageFrom "$FROM" -storeFootageTo "$TO")
    name="$name-$FROM-$TO"
fi
STILLS=0
if [ $LOOK = 0 ] && [ -n "${FOOTAGE_SCALE:-}" ]; then
    args+=(-storeFootageScale "$FOOTAGE_SCALE")
    STILLS=1
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
if [ $STILLS = 1 ]; then
    rm -rf "${OUT:?}/$name" && mkdir -p "$OUT/$name"
    cp "$frames"/*.png "$frames/done.txt" "$OUT/$name/"
    echo "$OUT/$name/: $(head -1 "$frames/done.txt"), PNGs at $FOOTAGE_SCALE times the screen"
elif [ $LOOK = 1 ]; then
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
