#!/usr/bin/env python3
"""Select reproducible encounter seeds with demonstrated routes at every required phone size.

Only encounter-mode results are eligible. Bot failure is a rejected candidate for
this campaign selection process, not proof that a human cannot win it.
"""
import argparse
import collections
import json
from pathlib import Path


def select(rows, widths):
    groups = collections.defaultdict(list)
    for row in rows:
        if row.get('tuning', {}).get('difficulty') is not None and not row['ecologyProbe']:
            groups[(row['level'], row['seed'])].append(row)
    accepted = {}
    for (level, seed), runs in sorted(groups.items()):
        winners = {r['width'] for r in runs if r['outcome'] == 'won'
                   and r['spawned'] == r['configured'] and r['initialGrowthPath']
                   and r['delayedPasses'] == 0 and r.get('firstPassMealLimit') is None
                   and not r.get('skippedFirstPassFishIDs')}
        if set(widths) <= winners and level not in accepted:
            accepted[level] = dict(level=level, seedOffset=seed,
                difficulty=runs[0]['tuning']['difficulty'],
                wins={str(width): sum(r['width'] == width and r['outcome'] == 'won' for r in runs)
                      for width in widths})
    return accepted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', nargs='+', type=Path)
    parser.add_argument('--widths', default='874,852,667')
    parser.add_argument('--levels', type=int, default=10)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    rows = [row for path in args.results for row in json.loads(path.read_text())]
    accepted = select(rows, [int(w) for w in args.widths.split(',')])
    report = dict(rollouts=len(rows), accepted=list(accepted.values()),
                  missingLevels=sorted(set(range(1, args.levels + 1)) - accepted.keys()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    if report['missingLevels']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
