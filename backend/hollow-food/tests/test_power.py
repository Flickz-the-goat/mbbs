import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from fastapi import HTTPException

from power.model import HORIZON, load_model
from power.routes import sample_forecast
from power.sample_data import SAMPLE_PATH
from power.train import prepare, split, train


class PowerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sample = SAMPLE_PATH.read_bytes()
        cls.model = train(cls.sample)

    def test_event_window_excludes_current_time_and_includes_24_hour_boundary(self):
        start = datetime(2025, 1, 1, tzinfo=UTC)
        current = start + timedelta(hours=6)
        end = current + HORIZON
        dataset = {
            "observed_through": end.isoformat(),
            "readings": [[2, time.isoformat(), 50, 100] for time in (start, current, end)],
            "outages": [[2, current.isoformat()]],
        }
        rows, _ = prepare(dataset)
        self.assertEqual([row.outage for row in rows], [False])
        dataset["outages"].append([2, end.isoformat()])
        rows, _ = prepare(dataset)
        self.assertEqual([row.outage for row in rows], [True])

    def test_split_purges_training_labels_that_overlap_test(self):
        import json

        rows, _ = prepare(json.loads(self.sample))
        training, testing, cutoff = split(rows)
        self.assertTrue(training and testing)
        self.assertTrue(all(row.current.observed_at + HORIZON < cutoff for row in training))
        self.assertTrue(all(row.current.observed_at >= cutoff for row in testing))
        self.assertTrue(all(row.previous.observed_at < row.current.observed_at for row in rows))

    def test_forecasts_use_level_specific_readings(self):
        estimates = []
        for level in (2, 3, 4):
            result = sample_forecast(level, self.model)
            self.assertEqual(result.level_id, level)
            self.assertEqual(result.window_end - result.window_start, HORIZON)
            self.assertEqual(result.reading_source, "synthetic_replay")
            self.assertTrue(0 <= result.probability <= 1)
            estimates.append(result.probability)
        self.assertGreater(len(set(estimates)), 1)

    def test_unseen_level_does_not_get_a_probability(self):
        with self.assertRaises(HTTPException) as error:
            sample_forecast(999, self.model)
        self.assertEqual(error.exception.status_code, 404)
        self.assertEqual(error.exception.detail["code"], "insufficient_data")

    def test_missing_artifact_loads_as_unavailable(self):
        with TemporaryDirectory() as directory:
            with patch.dict("os.environ", {"HOLLOW_POWER_MODEL_PATH": str(Path(directory) / "missing.pkl")}):
                self.assertIsNone(load_model())
