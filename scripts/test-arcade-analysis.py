"""Deterministic checks for the progression diagnostics, independent of Apple tooling."""
import importlib.util
from pathlib import Path
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


if __name__ == '__main__':
    unittest.main()
