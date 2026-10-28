#!/bin/bash
# App Store screenshots for Bigger Fish, from the simulator.
#
#   scripts/bigger-fish-store-capture.sh [moment ...]          # default: every moment, in the listing's order
#   scripts/bigger-fish-store-capture.sh --ipad [moment ...]   # the same moments on a 13-inch iPad
#   scripts/bigger-fish-store-capture.sh --duo [moment ...]    # on an iPhone Duo, open (its inside screen)
#
# Builds a Debug build and launches it once per moment with `-storeCapture <moment>` (see
# BiggerFish/StoreCapture.swift). The app plays the moment's real level with the diagnostics bot until the
# moment comes (or opens a screen), waits for the frame to settle, and saves the frame it draws, with the
# interface hidden; this script waits for that file. Progress is staged in the capture's own saved state,
# so real progress, purchases, and analytics are untouched. A rerun gives the same frames: runs are
# deterministic.
#
# Output goes to build/store-capture/bigger-fish/ (ignored by git):
#   screenshots/NN-<moment>.png      2868x1320 landscape PNGs with no alpha: the 6.9" size, which
#                                    App Store Connect scales down for smaller iPhones
#   screenshots-6.5/NN-<moment>.png  2778x1284, scaled and trimmed from those, for the 6.5" slot
#   screenshots-ipad-13/NN-<moment>.png  with --ipad: 2752x2064, the 13-inch iPad size, which App Store
#                                    Connect scales down for smaller iPads
#   screenshots-duo/NN-<moment>.png  with --duo: 2853x2007, an iPhone Duo's inside screen, open
#
# STORE_CAPTURE_DEVICE picks the simulator (a name or UDID; default iPhone 17 Pro Max, whose screen is
# the 6.9" size, with --ipad iPad Pro 13-inch (M5), or with --duo iPhone Duo). STORE_CAPTURE_OUT moves the
# output. An iPad simulator held upright shows the game shrunk to fit, but the app saves what it draws at
# full size. A Duo simulator has to be open first: its pose is a button in Xcode's Device Hub, not a
# simctl command.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${STORE_CAPTURE_OUT:-$ROOT/build/store-capture/bigger-fish}"
DERIVED="$ROOT/build/store-capture/DerivedData"
IPAD=0 DUO=0
if [ "${1:-}" = --ipad ]; then IPAD=1; shift; elif [ "${1:-}" = --duo ]; then DUO=1; shift; fi
if [ $IPAD = 1 ]; then
    DEVICE="${STORE_CAPTURE_DEVICE:-iPad Pro 13-inch (M5)}"
    SHOTS=screenshots-ipad-13 SIZE=2752x2064 SIZE_NAME='13-inch iPad'
elif [ $DUO = 1 ]; then
    DEVICE="${STORE_CAPTURE_DEVICE:-iPhone Duo}"
    SHOTS=screenshots-duo SIZE=2853x2007 SIZE_NAME='iPhone Duo (open)'
else
    DEVICE="${STORE_CAPTURE_DEVICE:-iPhone 17 Pro Max}"
    SHOTS=screenshots SIZE=2868x1320 SIZE_NAME='6.9" iPhone'
fi
BUNDLE=com.kraigstrong.biggerfish
# The listing's order (StoreCapture.Moment.listing): the dodge, the two ways to play, each world's idea, the
# shop, then where it goes.
MOMENTS=(dodge home open-water eat jelly-tops kelp-shadows sunset-hooks midnight-light shop deep-end)

usage() { sed -n '2,7p' "$0"; exit 1; }

build() {
    local destination="name=$DEVICE"
    [[ $DEVICE =~ ^[0-9A-Fa-f-]{36}$ ]] && destination="id=$DEVICE"
    xcodebuild build -quiet -project BiggerFish.xcodeproj -scheme BiggerFish -configuration Debug \
        -destination "platform=iOS Simulator,$destination" -derivedDataPath "$DERIVED"
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl bootstatus "$DEVICE" -b >/dev/null
    xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/BiggerFish.app"
}

pause() { perl -e "select(undef, undef, undef, $1)"; }

# Each moment's frame lands in the app's Documents/StoreCapture as <moment>.png, or <moment>.failed
# with the reason. Wait for one, then collect it.
capture() {
    local moment="$1" number="$2"
    local frames
    frames="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)/Documents/StoreCapture"
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    rm -rf "$frames"
    xcrun simctl launch "$DEVICE" "$BUNDLE" -storeCapture "$moment" -arcadeDisableRunRecording >/dev/null
    local waited=0
    until [ -f "$frames/$moment.png" ] || [ -f "$frames/$moment.failed" ]; do
        [ $waited -gt 1200 ] && { echo "$moment: no frame after two minutes" >&2; return 1; }
        pause 0.1
        waited=$((waited + 1))
    done
    xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
    if [ -f "$frames/$moment.failed" ]; then
        echo "$moment failed: $(cat "$frames/$moment.failed")" >&2
        return 1
    fi
    local name
    name="$(printf '%02d' "$number")-$moment.png"
    rm -f "$OUT/$SHOTS"/??-"$moment".png
    cp "$frames/$moment.png" "$OUT/$SHOTS/$name"
    local size
    size="$(sips -g pixelWidth -g pixelHeight "$OUT/$SHOTS/$name" | awk '/pixel/ { printf "%s%s", sep, $2; sep = "x" }')"
    [ "$size" = "$SIZE" ] || echo "$moment: $size, not the $SIZE_NAME size ($SIZE); is $DEVICE the right simulator?" >&2
    if [ $IPAD = 0 ] && [ $DUO = 0 ]; then
        # 6.5": scaled to its height, then trimmed to its width (a few points off each side).
        rm -f "$OUT"/screenshots-6.5/??-"$moment".png
        sips --resampleHeight 1284 "$OUT/$SHOTS/$name" --out "$OUT/screenshots-6.5/$name" >/dev/null
        sips --cropToHeightWidth 1284 2778 "$OUT/screenshots-6.5/$name" >/dev/null
    fi
    echo "captured $SHOTS/$name ($size)"
}

moments=("$@")
[ ${#moments[@]} -eq 0 ] && moments=("${MOMENTS[@]}")
for moment in "${moments[@]}"; do
    [[ " ${MOMENTS[*]} " == *" $moment "* ]] || { echo "unknown moment: $moment (one of: ${MOMENTS[*]})" >&2; usage; }
done
mkdir -p "$OUT/$SHOTS"
[ $IPAD = 1 ] || [ $DUO = 1 ] || mkdir -p "$OUT/screenshots-6.5"
build
failed=0
for moment in "${moments[@]}"; do
    for index in "${!MOMENTS[@]}"; do [ "${MOMENTS[$index]}" = "$moment" ] && number=$((index + 1)); done
    capture "$moment" "$number" || failed=1
done
exit $failed
