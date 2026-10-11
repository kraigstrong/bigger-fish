"""Deterministic checks for the progression diagnostics, independent of Apple tooling."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('analysis', Path(__file__).with_name('analyze-arcade-runs.py'))
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class AnalysisTests(unittest.TestCase):
    def test_edible_chain_can_unlock_a_larger_meal(self):
        radius, remaining = analysis.growth_path(16, [12, 18, 24], 0.78)
        self.assertGreater(radius, 24)
        self.assertEqual(remaining, [])

    def test_two_remaining_giants_are_a_growth_dead_end(self):
        radius, remaining = analysis.growth_path(43.4, [47.7, 50], 0.78)
        self.assertEqual(radius, 43.4)
        self.assertEqual(remaining, [47.7, 50])

    def test_near_equal_fish_bump_instead_of_becoming_food(self):
        self.assertFalse(analysis.edible(16, 15.99))
        self.assertTrue(analysis.edible(16, 15.8))

    def test_player_ties_preserve_old_logs_and_unlock_new_growth_paths(self):
        self.assertFalse(analysis.edible(16, 16))
        self.assertTrue(analysis.edible(16, 16, player_wins_ties=True))
        self.assertTrue(analysis.edible(16, 16.1, player_wins_ties=True))
        self.assertFalse(analysis.edible(16, 16.3, player_wins_ties=True))
        self.assertEqual(analysis.growth_path(16, [16.1, 20], .82, True)[1], [])

    def test_incomplete_swallow_is_not_counted_as_a_meal(self):
        rows = [dict(type='start', world='jelly-bloom', level=2, configuration={}),
                dict(type='swallow_start', predatorID=0, preyID=2, predatorRadius=16, preyRadius=15),
                dict(type='end', outcome='lost', time=3, simTime=3)]
        result = analysis.analyze(rows)
        self.assertEqual(result['closeMeals'], 0)
        self.assertEqual(result['playerMeals'], 0)

    def test_growth_warning_and_cleanup_are_different(self):
        def fish(identifier, radius, player=False):
            return dict(id=identifier, radius=radius, targetRadius=radius, player=player, state='swimming', x=0, y=200)
        rows = [dict(type='start', world='jelly-bloom', level=2,
                     configuration=dict(absorptionEfficiency=.78, spawnGroups=[dict(count=2)]))]
        for tick in range(21):
            rows.append(dict(type='snapshot', phase='playing', simTime=tick*.2,
                             fish=[fish(0,43.4,True),fish(1,47.7),fish(2,50)], worldWidth=3496,screenWidth=874))
        rows.append(dict(type='end', outcome='lost', simTime=4, time=4))
        result = analysis.analyze(rows)
        self.assertEqual(result['deadlockSeconds'], 4)
        self.assertFalse(result['initialGrowthPath'])
        self.assertEqual(result['cleanupSeconds'], 0)
        self.assertEqual(result['aiMeals'], 0)
        self.assertTrue(any('no edible growth path' in s for s in result['alerts']))

    def test_hitches_from_runs_and_the_hitch_log_are_reported_worst_first(self):
        def hitch(screen, phase, elapsed, events, **extra):
            return dict(type='hitch', screen=screen, phase=phase, elapsedMs=elapsed, workMs=elapsed - 2, intervalMs=8.3,
                        events=[dict(event=e, detail=d, agoMs=ago) for e, d, ago in events], **extra)
        eaten = [('death', 'eaten', 3), ('haptic', 'eaten: heavy impact + error notification', 4)]
        run = [dict(type='start', world='shallow-reef', level=3, configuration={}),
               hitch('level', 'playing', 21.0, [('swallow', 'you eat', 40)], detail='shallow-reef.3', time=4.2),
               dict(type='end', outcome='lost', time=9, simTime=9)]
        log = [dict(type='hitch_session', time=0, screenMaximumFramesPerSecond=120),
               hitch('level', 'lost', 182.5, eaten, detail='shallow-reef.3', time=30.1, updateMs=1.2),
               hitch('level', 'lost', 60.0, eaten, detail='shallow-reef.3', time=52.0),
               hitch('credits', 'start_card', 16.7, [], time=70.0, suppressed=12),
               hitch('credits', 'start_card', 16.6, [('card', 'credits start card', 5000)], time=71.0),
               hitch('world_map', None, 95.0, [('screen', 'world_map', 120)], time=80.0)]
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            for name, rows in [('run-2026-a.jsonl', run), ('hitches-2026-b.jsonl', log)]:
                (folder / name).write_text(''.join(json.dumps(r) + '\n' for r in rows) + '{"partial')
            results, hitches = analysis.write_reports(folder, folder / 'analysis')
            text = (folder / 'analysis' / 'report.md').read_text()
            saved = json.loads((folder / 'analysis' / 'hitches.json').read_text())
        # The run is still analyzed as before; its slow frame joins the hitch log's.
        self.assertEqual([r['outcome'] for r in results], ['lost'])
        self.assertEqual(len(hitches), 6)
        self.assertEqual(len(saved), 6)
        self.assertEqual({h['file'] for h in hitches}, {'run-2026-a.jsonl', 'hitches-2026-b.jsonl'})
        section = text[text.index('## Hitches'):]
        self.assertIn('6 slow frames (and 12 more', section)
        self.assertIn('the worst took 182.5 ms', section)

        def rows(heading):
            table = section[section.index(heading):].split('\n\n')[1].splitlines()[2:]
            return [[cell.strip() for cell in line.strip('|').split('|')] for line in table]
        by_screen = rows('### By screen and phase')
        self.assertEqual([r[:3] for r in by_screen], [['level', 'lost', '2'], ['world_map', '-', '1'],
                                                      ['level', 'playing', '1'], ['credits', 'start_card', '2']])
        self.assertEqual(by_screen[0][3:], ['182.5', '121.2', '180.5'])
        by_event = rows('### By the event just before')
        self.assertEqual([r[:3] for r in by_event], [['death eaten', '2', '182.5'], ['screen world_map', '1', '95.0'],
                                                     ['swallow you eat', '1', '21.0'],
                                                     ['(nothing in the last second)', '2', '16.7']])
        self.assertEqual(by_event[0][4], 'level/lost')
        worst = section[section.index('### Worst slow frames'):].splitlines()[2]
        self.assertIn('182.5 ms (work 180.5 ms, update 1.2 ms) on level/shallow-reef.3/lost', worst)
        self.assertIn('death eaten 3 ms before; haptic eaten: heavy impact + error notification 4 ms before', worst)

    def test_no_hitches_says_so(self):
        self.assertEqual(analysis.hitch_report([])[:3], ['## Hitches', '', 'No slow frames recorded.'])


if __name__ == '__main__':
    unittest.main()
