#!/bin/bash
# App Store screenshots for Bigger Fish, from the simulator.
#
#   scripts/bigger-fish-store-capture.sh [moment ...]   # default: every moment, in the listing's order
#
# Builds a Debug build and launches it once per moment with `-storeCapture <moment>` (see
# BiggerFish/StoreCapture.swift). The app plays the moment's real level with the diagnostics bot until the
# moment comes (or opens a map), waits for the frame to settle, and saves the frame it draws, with the
# interface hidden; this script waits for that file. Progress is staged in the capture's own saved state,
# so real progress, purchases, and analytics are untouched. A rerun gives the same frames: runs are
# deterministic.
#
# Output goes to build/store-capture/bigger-fish/ (ignored by git):
#   screenshots/NN-<moment>.png      2868x1320 landscape PNGs with no alpha: the 6.9" size, which
#                                    App Store Connect scales down for smaller iPhones
#   screenshots-6.5/NN-<moment>.png  2778x1284, scaled and trimmed from those, for the 6.5" slot
#
# STORE_CAPTURE_DEVICE picks the simulator (a name or UDID; default iPhone 17 Pro Max, whose screen is
# the 6.9" size). STORE_CAPTURE_OUT moves the output.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${STORE_CAPTURE_OUT:-$ROOT/build/store-capture/bigger-fish}"
DERIVED="$ROOT/build/store-capture/DerivedData"
DEVICE="${STORE_CAPTURE_DEVICE:-iPhone 17 Pro Max}"
BUNDLE=com.kraigstrong.biggerfish
# The listing's order: the game, each world's idea, then where it goes (kraigstrong/bigger-fish#142).
MOMENTS=(eat dodge missed jelly-tops kelp-shadows midnight-light conquered deep-end)

usage() { sed -n '2,6p' "$0"; exit 1; }

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
    rm -f "$OUT"/screenshots/??-"$moment".png "$OUT"/screenshots-6.5/??-"$moment".png
    cp "$frames/$moment.png" "$OUT/screenshots/$name"
    local size
    size="$(sips -g pixelWidth -g pixelHeight "$OUT/screenshots/$name" | awk '/pixel/ { printf "%s%s", sep, $2; sep = "x" }')"
    [ "$size" = 2868x1320 ] || echo "$moment: $size, not the 6.9\" size (2868x1320); is $DEVICE an iPhone 17 Pro Max?" >&2
    # 6.5": scaled to its height, then trimmed to its width (a few points off each side).
    sips --resampleHeight 1284 "$OUT/screenshots/$name" --out "$OUT/screenshots-6.5/$name" >/dev/null
    sips --cropToHeightWidth 1284 2778 "$OUT/screenshots-6.5/$name" >/dev/null
    echo "captured $name ($size)"
}

moments=("$@")
[ ${#moments[@]} -eq 0 ] && moments=("${MOMENTS[@]}")
for moment in "${moments[@]}"; do
    [[ " ${MOMENTS[*]} " == *" $moment "* ]] || { echo "unknown moment: $moment (one of: ${MOMENTS[*]})" >&2; usage; }
done
mkdir -p "$OUT/screenshots" "$OUT/screenshots-6.5"
build
failed=0
for moment in "${moments[@]}"; do
    for index in "${!MOMENTS[@]}"; do [ "${MOMENTS[$index]}" = "$moment" ] && number=$((index + 1)); done
    capture "$moment" "$number" || failed=1
done
exit $failed
