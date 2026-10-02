#!/usr/bin/env python3
"""Local playtest diagnostics. Measures tension and progression, not a universal fun score."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path

NEAR_EQUAL = 0.01
CLOSE_MEAL = 0.80


def edible(predator, prey):
    # Matches GameRules' symmetric near-equal bump interval.
    return predator > prey and abs(predator - prey) / max(predator, prey) >= NEAR_EQUAL


def growth_path(player_radius, others, efficiency):
    """Optimistic edible chain: ignores geometry, movement and future AI meals.

    If even this chain stalls, eating the current fish cannot complete the level.
    Hazards/other AI changes could still remove fish; this is not a proof of overall impossibility.
    Only call on snapshots without pending swallows.
    """
    radius = player_radius
    remaining = sorted(others)
    while remaining and edible(radius, remaining[0]):
        radius = math.sqrt(radius * radius + efficiency * remaining.pop(0) ** 2)
    return radius, remaining


def read_records(path):
    records = []
    for line in path.read_text().splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def analyze(records):
    start = next((r for r in records if r.get('type') == 'start'), {})
    end = next((r for r in reversed(records) if r.get('type') == 'end'), {})
    config = start.get('configuration', {})
    duration = end.get('simTime', records[-1].get('simTime', 0) if records else 0)
    snapshots = [r for r in records if r.get('type') == 'snapshot' and r.get('phase') == 'playing']
    completed = {(r.get('predatorID'), r.get('preyID')) for r in records if r.get('type') == 'eat'}
    meals = [r for r in records if r.get('type') == 'swallow_start' and r.get('predatorID') == 0
             and (0, r.get('preyID')) in completed]
    ratios = [r['preyRadius'] / r['predatorRadius'] for r in meals]
    threat_time = nearby_time = measured_time = 0
    last_threat = None
    deadlock_start = None
    latest_deadlock = None
    for i, snapshot in enumerate(snapshots):
        player = next((f for f in snapshot.get('fish', []) if f.get('player')), None)
        if not player or player['state'] != 'swimming':
            continue
        ai = [f for f in snapshot['fish'] if not f.get('player') and f['state'] == 'swimming']
        threats = [f for f in ai if edible(f['radius'], player['radius'])]
        time = snapshot['simTime']
        dt = max(0, min(0.5, (snapshots[i + 1]['simTime'] if i + 1 < len(snapshots) else duration) - time))
        measured_time += dt
        if threats:
            threat_time += dt
            last_threat = time
            width = snapshot['worldWidth']
            def nearby(f):
                dx = abs(f['x'] - player['x']) % width
                dx = min(dx, width - dx)
                return math.hypot(dx, f['y'] - player['y']) - f['radius'] - player['radius'] <= snapshot['screenWidth'] * 0.15
            if any(nearby(f) for f in threats):
                nearby_time += dt
        # Growing target radii are more optimistic than partially animated radii.
        stable = all(f['state'] == 'swimming' for f in snapshot['fish'])
        if stable and ai:
            ceiling, remaining = growth_path(max(player['radius'], player['targetRadius']),
                [max(f['radius'], f['targetRadius']) for f in ai], config.get('absorptionEfficiency', 0.78))
            if remaining:
                if deadlock_start is None:
                    deadlock_start = time
                latest_deadlock = {'time': time, 'playerRadius': player['radius'],
                                   'optimisticRadius': ceiling, 'remainingRadii': remaining}
            else:
                deadlock_start = None
                latest_deadlock = None
    player_meals = [r for r in records if r.get('type') == 'eat' and r.get('predatorID') == 0]
    meal_times = [0] + [r['simTime'] for r in player_meals] + [duration]
    initial_ai = len(snapshots[0]['fish']) - 1 if snapshots else 0
    alerts = []
    initial_path = None
    if snapshots:
        initial = snapshots[0]['fish']
        initial_player = next((f for f in initial if f.get('player')), None)
        if initial_player and all(f['state'] == 'swimming' for f in initial):
            _, blocked = growth_path(initial_player['radius'],
                [f['radius'] for f in initial if not f.get('player')], config.get('absorptionEfficiency', 0.78))
            initial_path = not blocked
            if blocked:
                alerts.append('starting ecosystem has no edible growth path')
    if end.get('outcome') == 'lost' and duration < 5:
        alerts.append('early death (<5s)')
    deadlock_seconds = max(0, duration - deadlock_start) if deadlock_start is not None else 0
    if deadlock_seconds >= 2:
        alerts.append('no edible growth path at end; hazards/AI would need to change it')
    cleanup = max(0, duration - (last_threat or 0)) if snapshots else 0
    if cleanup >= 8 and cleanup > duration * 0.35:
        alerts.append('long tail without a larger fish')
    configured = config.get('configuredFishCount', sum(g['count'] for g in config.get('spawnGroups', [])))
    if snapshots and configured != initial_ai:
        alerts.append(f'spawn shortfall: {initial_ai}/{configured}')
    return dict(world=start.get('world'), level=start.get('level'), outcome=end.get('outcome', 'unfinished'),
        initialGrowthPath=initial_path,
        configurationID=hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()[:8],
        seconds=round(duration, 2), playerMeals=len(player_meals),
        aiMeals=sum(r.get('type') == 'eat' and r.get('predatorID') != 0 and r.get('preyID') != 0 for r in records),
        closeMeals=sum(r >= CLOSE_MEAL for r in ratios), veryCloseMeals=sum(r >= 0.90 for r in ratios),
        mealRatios=[round(r, 3) for r in ratios],
        threatShare=round(threat_time / measured_time, 3) if measured_time else None,
        nearbyThreatShare=round(nearby_time / measured_time, 3) if measured_time else None,
        cleanupSeconds=round(cleanup, 2), longestMealGap=round(max((b-a for a,b in zip(meal_times, meal_times[1:])), default=0), 2),
        deadlockSeconds=round(deadlock_seconds, 2), latestDeadlock=latest_deadlock,
        bounces=sum(r.get('type') == 'bounce' and r.get('fishID') == 0 for r in records),
        alerts=alerts, reason=end.get('reason'))


def report(results):
    lines = ['# Arcade playtest diagnostics', '',
        'These are balance diagnostics, not a fun score. Threats/cleanup refer to fish; tentacle danger remains.',
        'Growth paths optimistically ignore geometry and future AI eating. A stalled path needs another AI/hazard change to progress.', '',
        '| Recording | World / level | Result | Seconds | Close meals | Fish threat % | Cleanup seconds | Growth-stalled seconds |',
        '|---|---|---|---:|---:|---:|---:|---:|']
    for r in results:
        threat = f"{r['threatShare']*100:.0f}" if r['threatShare'] is not None else '?'
        lines.append(f"| {r['file']} | {r['world']} / {r['level']} | {r['outcome']} | {r['seconds']:.1f} | "
                     f"{r['closeMeals']}/{r['playerMeals']} | {threat} | {r['cleanupSeconds']:.1f} | {r['deadlockSeconds']:.1f} |")
    lines += ['', '## Batches with the same recorded settings', '']
    batches = collections.defaultdict(list)
    for r in results:
        batches[(r['world'], r['level'], r['configurationID'])].append(r)
    for (world, level, config), batch in batches.items():
        finished = [r for r in batch if r['outcome'] in ('won', 'lost')]
        wins = sum(r['outcome'] == 'won' for r in finished)
        early = sum(r['outcome'] == 'lost' and r['seconds'] < 5 for r in finished)
        stalled = sum(r['deadlockSeconds'] >= 2 for r in finished)
        lines.append(f'- {world} level {level}, settings {config}: {wins}/{len(finished)} wins; {early} early deaths; {stalled} endings with no edible growth path.')
        if len(finished) >= 5 and early >= len(finished) / 2:
            lines.append('  - At least half of attempts ended within five seconds; compare with player feedback about the opening risk.')
    lines += ['', '## Flags', '']
    for r in results:
        if r['alerts']:
            lines.append(f"- {r['file']}: {'; '.join(r['alerts'])}.")
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parents[1] / 'build/arcade-runs')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'build/arcade-runs/analysis')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for path in sorted(args.input.rglob('run-*.jsonl')):
        rows = read_records(path)
        if rows:
            result = analyze(rows)
            result['file'] = path.name
            results.append(result)
    (args.output / 'report.md').write_text(report(results))
    (args.output / 'metrics.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f"Analyzed {len(results)} runs: {args.output / 'report.md'}")


if __name__ == '__main__':
    main()
