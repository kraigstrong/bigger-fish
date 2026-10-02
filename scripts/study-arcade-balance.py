#!/usr/bin/env python3
"""Repeatable, local-only food-race studies using the real iOS scene.

Example:
  python3 scripts/study-arcade-balance.py --profiles docs/jelly-bloom-study-profiles.json \
    --seeds 0,7,13 --passes 0,1,2 --run --output build/arcade-development/validation

A pass is one full world circuit. Delayed runs cannot eat before that circuit;
first-pass meal limits skip further edible contacts until the second circuit.
These are counterfactual experiments, not additional gameplay rules.
"""
import argparse
import collections
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STUDY = ROOT / 'build/arcade-development'


def mean(values):
    return statistics.mean(values) if values else 0


def summarize(results):
    grouped = collections.defaultdict(list)
    for run in results:
        key = (run['candidate'], run['width'], run['delayedPasses'], run.get('firstPassMealLimit'), tuple(run.get('skippedFirstPassFishIDs', [])))
        grouped[key].append(run)
    lines = ['# Simulation results', '',
             'Bot wins demonstrate a reachable route under those inputs. Losses and timeouts do not prove a level impossible.', '',
             '| Candidate | Width | Skipped passes | First-pass cap | Skipped fish | Wins / attempts | Early catches in wins (min–max) | Close meals in wins | Spawn shortfalls |',
             '|---|---:|---:|---:|---|---:|---:|---:|---:|']
    for (name, width, delay, cap, skipped), runs in sorted(grouped.items(), key=lambda item: str(item[0])):
        played = [r for r in runs if not r['ecologyProbe']]
        if not played:
            continue
        wins = [r for r in played if r['outcome'] == 'won']
        meals = [sum(lap < 1 for lap in r['stats'].get('mealStartLaps', r['stats']['mealLaps'])) for r in wins]
        early = f'{min(meals)}–{max(meals)}' if meals else '—'
        close = mean([r['stats']['closeMeals'] for r in wins])
        shortfalls = sum(r['spawned'] != r['configured'] for r in played)
        lines.append(f'| {name} | {width:g} | {delay:g} | {cap if cap is not None else "unlimited"} | {list(skipped) if skipped else "—"} | {len(wins)} / {len(played)} | {early} | {close:.1f} | {shortfalls} |')
    probes = [r for r in results if r['ecologyProbe']]
    if probes:
        lines += ['', '## Uncontested food-race probes', '',
                  'A ghost player leaves all food to the AI. This measures the first loss of an optimistic growth path; later hazard deaths may reopen it. It is not a survival probability.', '',
                  '| Candidate | Width | Seed | First blocked growth path (passes) | Reopened paths |', '|---|---:|---:|---:|---:|']
        for r in probes:
            deadline = r['stats'].get('firstStallLap')
            lines.append(f'| {r["candidate"]} | {r["width"]:g} | {r["seed"]} | {deadline:.2f} | {r["stats"].get("recoveredPaths", "unmeasured")} |' if deadline is not None else
                         f'| {r["candidate"]} | {r["width"]:g} | {r["seed"]} | none within {r["laps"]:.2f} | {r["stats"].get("recoveredPaths", "unmeasured")} |')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profiles', type=Path)
    parser.add_argument('--results', type=Path, help='Summarize an existing result file instead of preparing a study.')
    parser.add_argument('--seeds', default='0,7,13')
    parser.add_argument('--passes', default='0,1,2')
    parser.add_argument('--sizes', help='Comma-separated landscape sizes, e.g. 874x402,667x375.')
    parser.add_argument('--skip-fish', help='Semicolon-separated groups of IDs to skip on the first pass, e.g. 1;8;1,8.')
    parser.add_argument('--meal-limits', help='Comma-separated first-pass caps; -1 means unlimited.')
    parser.add_argument('--limit', type=float, default=75)
    parser.add_argument('--simulator', default='iPhone SE (3rd generation)')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--output', type=Path, default=STUDY / 'study')
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.results:
        args.output.with_suffix('.md').write_text(summarize(json.loads(args.results.read_text())))
        return
    if not args.profiles:
        parser.error('--profiles or --results is required')
    candidates = json.loads(args.profiles.read_text())
    if args.sizes:
        sizes = [tuple(float(n) for n in size.split('x')) for size in args.sizes.split(',')]
        candidates = [dict(candidate, width=width, height=height) for width, height in sizes for candidate in candidates]
    request = dict(candidates=candidates, seeds=[int(s) for s in args.seeds.split(',')],
                   policies=['collector', 'opportunist', 'cautious'], limit=args.limit,
                   delayedPasses=[float(s) for s in args.passes.split(',')], ecology=True)
    if args.meal_limits:
        request['firstPassMealLimits'] = [int(s) for s in args.meal_limits.split(',')]
    if args.skip_fish:
        request['skippedFirstPassFishIDs'] = [[]] + [[int(n) for n in group.split(',')] for group in args.skip_fish.split(';')]
    STUDY.mkdir(parents=True, exist_ok=True)
    marker = STUDY / 'simulation-study-request.json'
    marker.write_text(json.dumps(request, indent=2))
    args.output.with_suffix('.request.json').write_text(marker.read_text())
    if not args.run:
        print(f'Prepared {marker}. Run the ArcadeSimulationTests suite, then remove the marker.')
        return
    try:
        with args.output.with_suffix('.log').open('w') as log:
            subprocess.run(['xcodebuild', 'test', '-project', 'BiggerFish.xcodeproj', '-scheme', 'BiggerFish',
                            '-destination', f'platform=iOS Simulator,name={args.simulator}',
                            '-derivedDataPath', str(STUDY / 'DerivedData'),
                            '-only-testing:BiggerFishTests/ArcadeSimulationTests'], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        results = json.loads((STUDY / 'simulation-study-results.json').read_text())
        args.output.with_suffix('.json').write_text(json.dumps(results, indent=2))
        args.output.with_suffix('.md').write_text(summarize(results))
        print(f'{len(results)} rollouts: {args.output.with_suffix(".md")}')
    finally:
        marker.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
