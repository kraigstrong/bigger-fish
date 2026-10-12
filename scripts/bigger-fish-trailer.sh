#!/bin/bash
# The Bigger Fish trailer and App Store preview, rebuilt from the game.
#
#   scripts/bigger-fish-trailer.sh
#
# Records the footage scripts/trailer/edl.json needs that isn't in build/footage/ yet (scripts/bigger-fish-footage.sh),
# renders the captions in the game's typeface (scripts/trailer/captions.py), and composes the cut over the game's
# music (scripts/trailer/compose.py). Output goes to build/trailer/ (ignored by git):
#   bigger-fish-trailer.mp4       1920x886, 60 fps, ending on the release line: for biggerfish.app
#   bigger-fish-app-preview.mp4   1920x886, 30 fps, no release line: the App Store preview (the 6.9" iPhone size)
#
# Needs ffmpeg and Python 3 with Pillow and NumPy. Recordings are deterministic, but a level that's replanned (one
# that isn't frozen yet) plays differently: delete its build/footage/<name>.mp4 to record it again, and check the
# shot still shows what it should. To change the cut, edit edl.json: each shot names a recording, where in it to
# start, how long, and a camera move.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
EDL="$ROOT/scripts/trailer/edl.json"
FOOTAGE="$ROOT/build/footage"
OUT="$ROOT/build/trailer"
command -v ffmpeg >/dev/null || { echo "needs ffmpeg: brew install ffmpeg" >&2; exit 1; }
python3 -c 'import PIL, numpy' 2>/dev/null || { echo "needs Pillow and NumPy: python3 -m pip install pillow numpy" >&2; exit 1; }

# Each recording the cut uses, as "<world>.<level> <policy> <from> <to>", for those not recorded yet.
missing=$(python3 - "$EDL" "$FOOTAGE" <<'EOF'
import json, os, re, sys
edl, footage = sys.argv[1:3]
for name in sorted({shot['footage'] for shot in json.load(open(edl))['shots']}):
    match = re.fullmatch(r'([a-z-]+\.\d+)-(collector|opportunist|cautious)-([\d.]+)-([\d.]+)', name)
    if not match:
        sys.exit(f'not a recording name: {name}')
    if not os.path.exists(os.path.join(footage, name + '.mp4')):
        print(' '.join(match.groups()))
EOF
)
built=0
while read -r level policy from to; do
    [ -n "$level" ] || continue
    echo "recording $level ($policy bot, $from-${to}s)"
    FOOTAGE_NO_BUILD=$built scripts/bigger-fish-footage.sh "$level" "$policy" "$from" "$to" >/dev/null
    built=1
done <<< "$missing"

mkdir -p "$OUT/captions"
python3 scripts/trailer/captions.py "$OUT/captions"
python3 scripts/trailer/compose.py "$EDL" "$FOOTAGE" "$OUT/captions" "$OUT/bigger-fish-trailer.mp4" --site
python3 scripts/trailer/compose.py "$EDL" "$FOOTAGE" "$OUT/captions" "$OUT/bigger-fish-app-preview.mp4" --store --fps 30
