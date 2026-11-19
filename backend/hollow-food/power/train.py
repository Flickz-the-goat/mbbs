"""Train and evaluate the outage classifier on the bundled synthetic dataset."""

import argparse
import hashlib
import json
import pickle
from bisect import bisect_right
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tempfile import NamedTemporaryFile

from sklearn import __version__ as sklearn_version
from sklearn.calibration import calibration_curve
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import brier_score_loss, precision_score, recall_score

from .model import HORIZON, MAX_READING_GAP, PowerModel, Reading, features, model_path
from .sample_data import SAMPLE_PATH

@dataclass(frozen=True)
class Example:
    previous: Reading
    current: Reading
    outage: bool


def prepare(dataset: dict) -> tuple[list[Example], dict[int, tuple[Reading, Reading]]]:
    through = datetime.fromisoformat(dataset["observed_through"])
    readings = defaultdict(list)
    events = defaultdict(list)
    for level, stamp, load, capacity in dataset["readings"]:
        observed = datetime.fromisoformat(stamp)
        if observed <= through:
            readings[level].append(Reading(level, observed, load, capacity))
    for level, stamp in dataset["outages"]:
        events[level].append(datetime.fromisoformat(stamp))

    examples, latest = [], {}
    for level, history in readings.items():
        history.sort(key=lambda reading: reading.observed_at)
        starts = sorted(events[level])
        for previous, current in zip(history, history[1:]):
            gap = current.observed_at - previous.observed_at
            if not 0 < gap.total_seconds() <= MAX_READING_GAP.total_seconds():
                continue
            latest[level] = (previous, current)
            label_end = current.observed_at + HORIZON
            if label_end <= through:
                next_event = bisect_right(starts, current.observed_at)
                outage = next_event < len(starts) and starts[next_event] <= label_end
                examples.append(Example(previous, current, outage))
    return sorted(examples, key=lambda item: item.current.observed_at), latest


def split(examples: list[Example]) -> tuple[list[Example], list[Example], datetime]:
    timestamps = sorted({row.current.observed_at for row in examples})
    if len(timestamps) < 2:
        raise ValueError("Insufficient history for a chronological split.")
    cutoff = timestamps[len(timestamps) * 4 // 5]
    training = [row for row in examples if row.current.observed_at + HORIZON < cutoff]
    testing = [row for row in examples if row.current.observed_at >= cutoff]
    return training, testing, cutoff


def train(dataset_bytes: bytes) -> PowerModel:
    dataset = json.loads(dataset_bytes)
    if dataset["source"] != "synthetic":
        raise ValueError("This training pipeline expects a synthetic dataset.")
    examples, latest = prepare(dataset)
    training, testing, cutoff = split(examples)
    level_targets = defaultdict(list)
    for row in training:
        level_targets[row.current.level_id].append(row.outage)
    levels = tuple(sorted(
        level for level, labels in level_targets.items()
        if len(labels) >= 12 and any(labels) and not all(labels)
    ))
    training = [row for row in training if row.current.level_id in levels]
    testing = [row for row in testing if row.current.level_id in levels]
    if not training or not testing:
        raise ValueError("Insufficient level history or held-out examples.")

    classifier = HistGradientBoostingClassifier(max_iter=80, random_state=42)
    labels = [row.outage for row in training]
    classifier.fit([features(row.previous, row.current) for row in training], labels)
    actual = [row.outage for row in testing]
    probabilities = classifier.predict_proba([features(row.previous, row.current) for row in testing])[:, 1]
    predicted = probabilities >= 0.5
    baseline = sum(labels) / len(labels)
    observed_rates, mean_probabilities = calibration_curve(actual, probabilities, n_bins=5)
    evaluation = {
        "cutoff": cutoff.isoformat(),
        "training_rows": len(training),
        "test_rows": len(testing),
        "test_positive_rows": sum(actual),
        "baseline_probability": baseline,
        "baseline_brier": brier_score_loss(actual, [baseline] * len(actual)),
        "brier": brier_score_loss(actual, probabilities),
        "precision_at_0_5": precision_score(actual, predicted, zero_division=0),
        "recall_at_0_5": recall_score(actual, predicted, zero_division=0),
        "calibration": [
            {"mean_probability": float(probability), "observed_rate": float(rate)}
            for probability, rate in zip(mean_probabilities, observed_rates)
        ],
    }
    digest = hashlib.sha256(dataset_bytes + sklearn_version.encode()).hexdigest()[:12]
    return PowerModel(
        classifier, f"outage-v1-{digest}", training[0].current.observed_at,
        training[-1].current.observed_at, evaluation, latest, levels,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=SAMPLE_PATH)
    parser.add_argument("--output", type=Path, default=model_path())
    args = parser.parse_args()
    model = train(args.data.read_bytes())
    with NamedTemporaryFile(dir=args.output.parent, delete=False) as output:
        temporary_path = Path(output.name)
        try:
            pickle.dump(model, output)
            output.close()
            temporary_path.replace(args.output)
        finally:
            temporary_path.unlink(missing_ok=True)
    print(json.dumps({"version": model.version, **model.evaluation}, indent=2))


if __name__ == "__main__":
    main()
