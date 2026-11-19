from datetime import UTC, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Path, Request
from pydantic import AwareDatetime, BaseModel, Field

from .model import HORIZON, PowerModel, Reading

router = APIRouter(prefix="/api/v1", tags=["power"])
LevelID = Annotated[int, Path(gt=0, le=2_147_483_647)]


class PowerReadingInput(BaseModel):
    observed_at: AwareDatetime
    load_kw: float = Field(ge=0, allow_inf_nan=False)
    capacity_kw: float = Field(gt=0, allow_inf_nan=False)

    def to_reading(self, level_id: int) -> Reading:
        return Reading(level_id, self.observed_at.astimezone(UTC), self.load_kw, self.capacity_kw)


class ForecastInput(BaseModel):
    previous: PowerReadingInput
    current: PowerReadingInput


class ModelInfo(BaseModel):
    version: str
    supported_levels: tuple[int, ...]
    training_start: datetime
    training_end: datetime
    trained_on: Literal["synthetic"] = "synthetic"


class Forecast(BaseModel):
    level_id: int
    probability: float = Field(ge=0, le=1)
    window_start: datetime
    window_end: datetime
    generated_at: datetime
    reading_source: Literal["synthetic_replay", "submitted_readings"]
    model: ModelInfo


class CalibrationBin(BaseModel):
    mean_probability: float
    observed_rate: float


class Evaluation(BaseModel):
    cutoff: datetime
    training_rows: int
    test_rows: int
    test_positive_rows: int
    baseline_probability: float
    baseline_brier: float
    brier: float
    precision_at_0_5: float
    recall_at_0_5: float
    calibration: list[CalibrationBin]


class ModelReport(BaseModel):
    model: ModelInfo
    evaluation: Evaluation


def power_model(request: Request) -> PowerModel:
    model = request.app.state.power_model
    if model is None:
        raise HTTPException(503, detail={
            "code": "model_unavailable", "message": "The power model has not been loaded.",
        })
    return model


LoadedModel = Annotated[PowerModel, Depends(power_model)]


def model_info(model: PowerModel) -> ModelInfo:
    return ModelInfo(
        version=model.version, supported_levels=model.supported_levels,
        training_start=model.training_start, training_end=model.training_end,
    )


def require_level(level_id: int, model: PowerModel) -> None:
    if level_id not in model.supported_levels:
        raise HTTPException(404, detail={
            "code": "insufficient_data", "message": "This level has insufficient training history.",
        })


def forecast(
    model: PowerModel, previous: Reading, current: Reading,
    source: Literal["synthetic_replay", "submitted_readings"],
) -> Forecast:
    now = datetime.now(UTC)
    try:
        if current.observed_at > now:
            raise ValueError("The current reading cannot be in the future.")
        probability = model.predict(previous, current)
    except ValueError as error:
        raise HTTPException(422, detail={"code": "invalid_readings", "message": str(error)}) from error
    return Forecast(
        level_id=current.level_id, probability=probability, window_start=current.observed_at,
        window_end=current.observed_at + HORIZON, generated_at=now,
        reading_source=source, model=model_info(model),
    )


@router.get("/levels/{level_id}/power/forecast")
def sample_forecast(level_id: LevelID, model: LoadedModel) -> Forecast:
    require_level(level_id, model)
    previous, current = model.latest[level_id]
    return forecast(model, previous, current, "synthetic_replay")


@router.post("/levels/{level_id}/power/forecast")
def forecast_from_readings(level_id: LevelID, payload: ForecastInput, model: LoadedModel) -> Forecast:
    require_level(level_id, model)
    return forecast(
        model, payload.previous.to_reading(level_id), payload.current.to_reading(level_id),
        "submitted_readings",
    )


@router.get("/power/model")
def power_model_report(model: LoadedModel) -> ModelReport:
    return ModelReport(model=model_info(model), evaluation=Evaluation(**model.evaluation))
