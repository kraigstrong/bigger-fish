"""Regression checks for selecting a single validated campaign configuration."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'candidates', Path(__file__).with_name('validate-arcade-candidates.py'))
candidates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidates)


def winning_run(width, candidate='campaign', tuning=None):
    return dict(level=1, seed=4, candidate=candidate, width=width,
                tuning=tuning if tuning is not None else dict(difficulty=.5, speed=150),
                ecologyProbe=False, outcome='won', spawned=16, configured=16,
                initialGrowthPath=True, delayedPasses=0)


class CandidateTests(unittest.TestCase):
    def test_different_tunings_cannot_combine_winning_widths(self):
        rows = [winning_run(874), winning_run(852),
                winning_run(667, tuning=dict(difficulty=.8, speed=180))]
        self.assertEqual(candidates.select(rows, [874, 852, 667]), {})

    def test_different_candidates_cannot_combine_winning_widths(self):
        rows = [winning_run(874), winning_run(852), winning_run(667, candidate='other')]
        self.assertEqual(candidates.select(rows, [874, 852, 667]), {})

    def test_equivalent_tuning_key_order_is_accepted_and_reported(self):
        rows = [winning_run(874), winning_run(852),
                winning_run(667, tuning=dict(speed=150, difficulty=.5))]
        result = candidates.select(rows, [874, 852, 667])[1]
        self.assertEqual(result['candidate'], 'campaign')
        self.assertEqual(result['tuning'], dict(difficulty=.5, speed=150))
        self.assertEqual(result['wins'], {'874': 1, '852': 1, '667': 1})


if __name__ == '__main__':
    unittest.main()
