# Hollow — Food and Power Backend

This prototype includes synthetic datasets, a fitted random forest predicting additional household ration demand, a deterministic proportional allocation optimizer, and FastAPI endpoints.

## Files
- `households.csv`: 3,000 synthetic household records with a generated demand label.
- `level_inventory.csv`: synthetic level population and **shared** distribution-center inventory.
- `food_submissions.csv`: example resident declarations with *placeholder* photo paths. No actual photos or image verification included.
- `ration_demand_model.pkl`: fitted scikit-learn random forest; load only from trusted sources.
- `metrics.json`: holdout evaluation on synthetic data.
- `build.py`: reproducibly regenerate data and retrain the model.
- `allocate.py`: proportional allocation via SciPy linear programming.
- `api.py`: example FastAPI endpoints.

## Start
```bash
python -m pip install -r requirements.txt
uvicorn api:app --reload
```
Visit `http://127.0.0.1:8000/docs` to test the API.

- `POST /food/predict-demand` supports synthetic levels 1–8. Invalid household counts and levels return HTTP 422.
- `POST /food/allocate` accepts nonnegative, finite demands and shared stock. It rounds each allocation down to the nearest 0.001 unit and reports unallocated stock, including any remainder from rounding.

Run regression tests with `python -m unittest discover -s tests`. Run `python build.py` to regenerate the synthetic datasets and model alongside the script. This replaces the bundled artifacts. The requirements pin scikit-learn to the version used to save the bundled model.

## Power outage forecasts

Run `python -m power.train` before starting the server. The trainer uses [power/sample.json](power/sample.json), containing synthetic six-hour load and capacity readings plus outage start times for levels 2–4. Run `python -m power.sample_data` to regenerate the deterministic sample. The trainer prints held-out metrics and writes the model to `power/outage_model.pkl`. Set `HOLLOW_POWER_MODEL_PATH` for a custom artifact location. Load only trusted artifacts and restart the server after retraining.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/v1/levels/{level_id}/power/forecast` | Forecast from the latest bundled readings, with the synthetic replay window in the response |
| POST | `/api/v1/levels/{level_id}/power/forecast` | Forecast from two submitted readings |
| GET | `/api/v1/power/model` | Model version, training range, supported levels, and held-out evaluation |

For POST, send `previous` and `current` objects, each with a timezone-aware `observed_at`, a nonnegative `load_kw`, and a positive `capacity_kw`. Readings must be ordered, at most 12 hours apart, and the current reading must follow the training label window. The forecast window starts at the current reading timestamp. Unsupported levels return HTTP 404 with `insufficient_data`. Power endpoints return HTTP 503 with `model_unavailable` if the server starts without the artifact.

Training removes examples whose 24-hour outcome windows would overlap the test period. The report compares Brier score against a constant training-prevalence baseline and includes precision, recall, and calibration bins. The evaluation measures performance on synthetic data only.

## Design cautions
- The label is computed from an invented formula; it is **not** a clinically or operationally validated estimate of food need.
- Private inventory is not shared inventory. Never allocate food from private supplies without consent.
- Water is recorded separately and not converted into food portions.
- Photo paths are placeholders. A photo cannot reliably establish ownership or quantities, and there is no vision model in this package.
- The optimizer distributes available **shared** food proportionally to predicted deficits. Real deployment requires nutritional rules, vulnerable-person safeguards, physical inventory verification, appeals, and human oversight.
- Predictions can change when you change the synthetic formula; replace with measured data and evaluate chronologically before real use.
