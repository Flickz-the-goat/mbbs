import logging
import os
import pickle
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from math import cos, isfinite, pi, sin
from pathlib import Path

from sklearn.ensemble import HistGradientBoostingClassifier

HORIZON = timedelta(hours=24)
MAX_READING_GAP = timedelta(hours=12)
DEFAULT_MODEL_PATH = Path(__file__).with_name("outage_model.pkl")


def model_path() -> Path:
    return Path(os.environ.get("HOLLOW_POWER_MODEL_PATH") or DEFAULT_MODEL_PATH)


@dataclass(frozen=True)
class Reading:
    level_id: int
    observed_at: datetime
    load_kw: float
    capacity_kw: float


def features(previous: Reading, current: Reading) -> list[float]:
    gap = current.observed_at - previous.observed_at
    if previous.level_id != current.level_id or not timedelta(0) < gap <= MAX_READING_GAP:
        raise ValueError("Two readings for the same level, at most 12 hours apart, are required.")
    load_ratio = current.load_kw / current.capacity_kw
    trend = (load_ratio - previous.load_kw / previous.capacity_kw) / (gap / timedelta(hours=1))
    if not isfinite(load_ratio) or not isfinite(trend):
        raise ValueError("The readings produce a nonfinite load ratio or trend.")
    stamp = current.observed_at.astimezone(UTC)
    hour = stamp.hour + stamp.minute / 60
    phase = hour * pi / 12
    return [current.level_id, load_ratio, trend, sin(phase), cos(phase)]


@dataclass
class PowerModel:
    classifier: HistGradientBoostingClassifier
    version: str
    training_start: datetime
    training_end: datetime
    evaluation: dict
    latest: dict[int, tuple[Reading, Reading]]
    supported_levels: tuple[int, ...]

    def predict(self, previous: Reading, current: Reading) -> float:
        if current.level_id not in self.supported_levels:
            raise ValueError("This level has insufficient training history.")
        if current.observed_at < self.training_end + HORIZON:
            raise ValueError("Readings must follow the latest outage label used in training.")
        return float(self.classifier.predict_proba([features(previous, current)])[0, 1])


def load_model() -> PowerModel | None:
    try:
        # This path is set by the server operator and must point to a trusted artifact.
        with model_path().open("rb") as source:
            model = pickle.load(source)
        if not isinstance(model, PowerModel):
            raise TypeError("Unexpected power model type.")
        return model
    except FileNotFoundError:
        return None
    except (OSError, pickle.UnpicklingError, EOFError, ImportError, AttributeError, TypeError):
        logging.getLogger(__name__).exception("Could not load the power model.")
        return None
