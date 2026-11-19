"""Generate deterministic synthetic readings and outage start times."""

import json
import math
import random
from datetime import UTC, datetime, timedelta
from pathlib import Path

SAMPLE_PATH = Path(__file__).with_name("sample.json")
LEVELS = (2, 3, 4)
STEP = timedelta(hours=6)


def generate() -> dict:
    rng = random.Random(42)
    start = datetime(2025, 1, 1, tzinfo=UTC)
    readings, outages = [], []
    for level in LEVELS:
        stress = 0.0
        last_outage = start - timedelta(days=2)
        for index in range(240):
            stamp = start + index * STEP
            capacity = 220 + 30 * level
            stress = 0.82 * stress + rng.uniform(-0.12, 0.12)
            load = 0.73 + 0.08 * math.sin(index * math.pi / 2) + stress + 0.04 * (level - 3)
            readings.append([level, stamp.isoformat(), round(capacity * max(0.15, load), 2), capacity])
            hazard = 0.015 + 0.4 * max(0.0, min(1.0, (load - 0.67) / 0.4))
            if stamp - last_outage >= timedelta(hours=18) and rng.random() < hazard:
                outages.append([level, stamp.isoformat()])
                last_outage = stamp
    return {
        "source": "synthetic",
        "observed_through": stamp.isoformat(),
        "reading_columns": ["level_id", "observed_at", "load_kw", "capacity_kw"],
        "outage_columns": ["level_id", "started_at"],
        "readings": readings,
        "outages": outages,
    }


if __name__ == "__main__":
    SAMPLE_PATH.write_text(json.dumps(generate(), separators=(",", ":")) + "\n", encoding="utf-8")
