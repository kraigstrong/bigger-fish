#!/usr/bin/env python3
"""Local playtest diagnostics. Measures tension and progression, not a universal fun score, and lists slow frames."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import statistics

NEAR_EQUAL = 0.01
CLOSE_MEAL = 0.80


def edible(predator, prey, player_wins_ties=False):
    # Matches GameRules' symmetric near-equal bump interval.
    big = max(predator, prey)
    if big <= 0:
        return False
    if abs(predator - prey) / big < NEAR_EQUAL:
        return player_wins_ties
    return predator > prey


def growth_path(player_radius, others, efficiency, player_wins_ties=False):
    """Optimistic edible chain: ignores geometry, movement and future AI meals.

    If even this chain stalls, eating the current fish cannot complete the level.
    Hazards/other AI changes could still remove fish; this is not a proof of overall impossibility.
    Only call on snapshots without pending swallows.
    """
    radius = player_radius
    remaining = sorted(others)
    while remaining and edible(radius, remaining[0], player_wins_ties):
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
                [max(f['radius'], f['targetRadius']) for f in ai], config.get('absorptionEfficiency', 0.78), config.get('playerWinsTies', False))
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
                [f['radius'] for f in initial if not f.get('player')], config.get('absorptionEfficiency', 0.78), config.get('playerWinsTies', False))
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


# A hitch's "event just before" is the latest thing that happened up to this long before it.
EVENT_BEFORE_MS = 1000


def read_hitches(path, rows):
    """Slow frames (HitchLog, Debug builds): a run's own, or the hitch log's file for everywhere else."""
    hitches = []
    for row in rows:
        if row.get('type') == 'hitch':
            hitch = dict(row)
            hitch['file'] = path.name
            hitches.append(hitch)
    return hitches


def screen_and_phase(hitch):
    screen = hitch.get('screen', '?')
    return screen, hitch.get('phase') or '-'


def event_before(hitch):
    events = hitch.get('events') or []
    if events and events[0].get('agoMs', 0) <= EVENT_BEFORE_MS:
        return f"{events[0].get('event', '?')} {events[0].get('detail', '')}".strip()
    return '(nothing in the last second)'


def hitch_report(hitches):
    """The report's Hitches section: by screen and phase, then by the event just before, each worst first."""
    lines = ['## Hitches', '']
    if not hitches:
        return lines + ['No slow frames recorded.', '']

    def ms(hitch):
        return hitch.get('elapsedMs', 0)

    def grouped(key):
        groups = collections.defaultdict(list)
        for hitch in hitches:
            groups[key(hitch)].append(hitch)
        return sorted(groups.items(), key=lambda item: (-max(map(ms, item[1])), -len(item[1]), str(item[0])))

    capped = sum(h.get('suppressed', 0) for h in hitches)
    worst = max(hitches, key=ms)
    lines += [f"{len(hitches)} slow frames" + (f" (and {capped} more past the log's cap of 20 a second)" if capped else '')
              + f"; the worst took {ms(worst):.1f} ms.",
              '', 'A slow frame took at least 1.5 display intervals: it missed a refresh or more. Work is the main '
              "thread's longest stretch without a break in that frame; a long frame with little work came late rather "
              'than busy. Update is the scene\'s own update before it.', '',
              '### By screen and phase', '',
              '| Screen | Phase | Slow frames | Worst ms | Median ms | Worst work ms |', '|---|---|---:|---:|---:|---:|']
    for (screen, phase), group in grouped(screen_and_phase):
        lines.append(f"| {screen} | {phase} | {len(group)} | {max(map(ms, group)):.1f} | "
                     f"{statistics.median(map(ms, group)):.1f} | {max(h.get('workMs', 0) for h in group):.1f} |")
    lines += ['', '### By the event just before', '',
              '| Event just before | Slow frames | Worst ms | Median ms | Where |', '|---|---:|---:|---:|---|']
    for event, group in grouped(event_before):
        where = collections.Counter('/'.join(p for p in screen_and_phase(h) if p != '-') for h in group)
        lines.append(f"| {event} | {len(group)} | {max(map(ms, group)):.1f} | {statistics.median(map(ms, group)):.1f} | "
                     f"{', '.join(name for name, _ in where.most_common(3))} |")
    lines += ['', '### Worst slow frames', '']
    for hitch in sorted(hitches, key=ms, reverse=True)[:10]:
        place = '/'.join(p for p in (hitch.get('screen', '?'), hitch.get('detail'), hitch.get('phase')) if p)
        timing = f"work {hitch.get('workMs', 0):.1f} ms" + (
            f", update {hitch['updateMs']:.1f} ms" if 'updateMs' in hitch else '')
        before = '; '.join(f"{e.get('event', '?')} {e.get('detail', '')}".strip() + f" {e.get('agoMs', 0):.0f} ms before"
                           for e in (hitch.get('events') or [])[:4]) or 'nothing'
        lines.append(f"- {ms(hitch):.1f} ms ({timing}) on {place}, {hitch['file']} at {hitch.get('time', 0):.1f} s: {before}.")
    return lines + ['']


def write_reports(input_folder, output_folder):
    output_folder.mkdir(parents=True, exist_ok=True)
    results, hitches = [], []
    for path in sorted(input_folder.rglob('run-*.jsonl')):
        rows = read_records(path)
        if rows:
            result = analyze(rows)
            result['file'] = path.name
            results.append(result)
            hitches += read_hitches(path, rows)
    for path in sorted(input_folder.rglob('hitches-*.jsonl')):
        hitches += read_hitches(path, read_records(path))
    (output_folder / 'report.md').write_text(report(results) + '\n' + '\n'.join(hitch_report(hitches)))
    (output_folder / 'metrics.json').write_text(json.dumps(results, indent=2) + '\n')
    (output_folder / 'hitches.json').write_text(json.dumps(hitches, indent=2) + '\n')
    return results, hitches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=Path(__file__).resolve().parents[1] / 'build/arcade-runs')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'build/arcade-runs/analysis')
    args = parser.parse_args()
    results, hitches = write_reports(args.input, args.output)
    print(f"Analyzed {len(results)} runs and {len(hitches)} slow frames: {args.output / 'report.md'}")


if __name__ == '__main__':
    main()
