"""Run: uvicorn api:app --reload (from this directory)."""
from contextlib import asynccontextmanager
from pathlib import Path
import pickle
from fractions import Fraction
from typing import Annotated

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, model_validator
from allocate import allocate
from power.model import load_model
from power.routes import router as power_router

MODEL_PATH=Path(__file__).with_name('ration_demand_model.pkl')
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load only this trusted, locally generated model file. Never unpickle user uploads.
    with MODEL_PATH.open('rb') as f:
        app.state.bundle=pickle.load(f)
    app.state.power_model = load_model()
    yield
app=FastAPI(title='Hollow Backend Prototype',lifespan=lifespan)
app.include_router(power_router)


@app.exception_handler(RequestValidationError)
async def invalid_request(_request: Request, exc: RequestValidationError) -> JSONResponse:
    # Raw input may contain NaN or Infinity, which JSON cannot represent.
    detail = [
        {key: error[key] for key in ('type', 'loc', 'msg')}
        for error in exc.errors()
    ]
    return JSONResponse(status_code=422, content={'detail': detail})


NonnegativeQuantity = Annotated[float, Field(ge=0, allow_inf_nan=False)]
class Household(BaseModel):
    level_id:int=Field(ge=1, le=8)
    household_size:int=Field(ge=1)
    children_count:int=Field(ge=0)
    senior_count:int=Field(ge=0)
    rice_kg:NonnegativeQuantity
    beans_kg:NonnegativeQuantity
    canned_food_count:int=Field(ge=0)
    water_liters:NonnegativeQuantity
    daily_portions_per_person:float=Field(gt=0, allow_inf_nan=False)
    planning_days:int=Field(ge=1,le=30)
    reserve_portions_per_person:NonnegativeQuantity

    @model_validator(mode='after')
    def validate_household_counts(self):
        if self.children_count + self.senior_count > self.household_size:
            raise ValueError('children_count + senior_count cannot exceed household_size')
        return self

class AllocationRequest(BaseModel):
    demands:list[NonnegativeQuantity]
    available_shared_units:NonnegativeQuantity
@app.post('/food/predict-demand')
def predict(household:Household):
    bundle=app.state.bundle
    data=household.model_dump()
    x=[[data[f] for f in bundle['features']]]
    prediction=max(0,float(bundle['model'].predict(x)[0]))
    return {'predicted_additional_ration_units':round(prediction,2),'unit':'synthetic portion equivalents','validated_for_real_distribution':False}
@app.post('/food/allocate')
def allocation(req:AllocationRequest):
    allocations=allocate(req.demands,req.available_shared_units)
    remaining = Fraction(str(req.available_shared_units)) - sum(
        Fraction(str(amount)) for amount in allocations
    )
    return {'allocated_units': allocations, 'remaining_units': float(remaining)}
