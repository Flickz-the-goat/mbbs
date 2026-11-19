# AGENTS.md — Hollow Coding Agent Instructions

This document governs automated coding work on **Hollow**, an iPhone-first hackathon prototype. Read `READ.md` before editing. Never represent planned features as implemented.

## Fixed stack

- **iOS:** Swift, SwiftUI, CoreBluetooth, URLSession, Codable; SwiftData or SQLite after a deliberate choice.
- **Backend:** Python 3.11+, FastAPI, Pydantic, SQLAlchemy, Alembic, PostgreSQL.
- **ML:** pandas, NumPy, scikit-learn for outage prediction.
- **Allocation:** SciPy and deterministic Python scheduling logic.
- **Photo review:** vision-capable model through backend, with manual-review state.
- **Do not add React Native, Expo, JavaScript, or a third-party Bluetooth service** unless the user explicitly changes the stack.

## Environment constraints
- CoreBluetooth has no usage subscription, but native iOS signing and distribution may have Apple account requirements.
- Do not assume more than one physical iPhone is available. Provide simulator/mock transport for routing tests; clearly distinguish simulation from real BLE testing.

## Implementation priorities

1. Make a runnable vertical slice before adding complexity.
2. Keep BLE messaging operational independently of the Python backend.
3. Make offline states explicit; queue local writes and sync only when a reachable server exists.
4. Use synthetic sample data for the demo; do not fabricate real forecast accuracy or verified inventory.
5. Preserve separation of concerns: views, transport, routing, persistence, API, prediction, allocation, and verification.

## Suggested layout

- `ios/HollowApp/Features/Messaging`: screens, `MeshRouter`, `BluetoothTransport`, mock transport, message queue.
- `ios/HollowApp/Features/Power`: forecast screens and view models.
- `ios/HollowApp/Features/Food`: submission, camera, review, pickup screens.
- `ios/HollowApp/Networking`: `URLSession` API client and error handling.
- `ios/HollowApp/Persistence`: local cache and offline outbox.
- `backend/app/api`: thin FastAPI routers.
- `backend/app/schemas`: Pydantic request/response contracts.
- `backend/app/models` and `backend/app/db`: SQLAlchemy models and database session.
- `backend/app/services`: business logic.
- `backend/ml`: data preparation, training, evaluation, inference.
- `backend/tests` and `ios/HollowAppTests`: automated tests.

## Swift and Bluetooth rules

- Use SwiftUI for views; do not put BLE state machines in view bodies.
- Isolate CoreBluetooth behind a protocol such as `PeerTransport` so it can be mocked.
- Implement both central and peripheral behavior as needed: discovery/connection and advertising/GATT service.
- Choose and document a stable custom BLE service UUID and characteristics; never rely on device names as authenticated identities.
- BLE messages need unique IDs, origin/destination, creation time, TTL, hop count, and payload.
- Implement deduplication, TTL decrement, store-and-forward, chunking/reassembly when necessary, and explicit end-to-end acknowledgments.
- A successful BLE write to an intermediate device is **not** proof of destination delivery.
- Test disconnects, duplicates, loops, expired messages, and app suspension.
- Do not promise reliable background mesh operation; iOS restricts advertising/scanning and background execution. Initial demo should keep apps foregrounded.
- Treat received BLE payloads as untrusted: validate size, schema, and version; do not execute received content.

## FastAPI rules

- Use typed Pydantic schemas and structured JSON errors.
- Keep routers thin and services testable without HTTP.
- Put settings, database URLs, model paths, and external API keys in environment variables. Never commit credentials.
- Validate level IDs, resident IDs, quantities, units, timestamps, and image sizes/types.
- Authenticate sensitive inventory, allocation, and pickup operations; distinguish resident and coordinator roles.
- Make write endpoints idempotent where retries can happen offline.
- Use Alembic migrations rather than modifying production tables ad hoc.
- Do not imply that BLE automatically connects an iPhone to FastAPI. HTTP needs a reachable network endpoint.

## Outage prediction rules

- Forecast **per level** using historical electrical readings and outage event times.
- Start with a time-window outage classifier (e.g. next 24 hours), not an unjustified exact outage timestamp.
- Create features using information available at prediction time only.
- Split training/evaluation chronologically; prevent leakage from future outages.
- Report sample size, baseline, precision/recall, and calibration where possible.
- Persist model version, training data range, and inference timestamp.
- Handle missing history and unseen levels explicitly; return unavailable/insufficient-data rather than invented probabilities.
- Estimate outage duration separately if supported by data.

## Food distribution rules

- Residents enter inventory with normalized food type, quantity, and unit, plus a newly captured photo.
- Photos are **supporting evidence**, not proof of ownership, weight, or unique inventory. Vision output must include uncertainty and manual-review handling.
- Separate private inventory from explicitly contributed or coordinator-controlled distributable stock.
- Allocate **only** distributable stock. Never infer consent from a submission.
- Preserve stock conservation, household needs, dietary restrictions, fairness, and shortage handling in the optimizer.
- If constraints cannot be met, report the shortage; do not fabricate inventory.
- Schedule pickup slots using station capacity and resident availability; avoid overlaps.
- Use unique single-use pickup tokens with transactional redemption and conflict handling for offline synchronization.
- Minimize collection and exposure of resident photos and sensitive data.

## Required tests

- **Routing:** duplicate suppression, TTL expiry, multi-hop simulation, disconnect/reconnect, destination acknowledgment, malformed packets.
- **ML:** chronological split, no leakage, valid level-specific outputs, insufficient-data behavior.
- **Food:** quantity/unit validation, private stock exclusion, no negative stock, shortage behavior, dietary constraints, scheduling capacity, duplicate token redemption.
- **API:** authorization, validation, idempotent retries, unavailable model/server, photo size limits.
- **iOS:** offline cached state and queue; use physical devices for actual BLE tests.

## Agent workflow

1. Inspect existing files and tests before changing code.
2. State the smallest implementation slice and its acceptance criteria.
3. Implement without unrelated refactors or new dependencies.
4. Add tests and run the available test suite; if Xcode is unavailable, state that native iOS compilation was **not verified**.
5. Update `READ.md` when architecture, setup, endpoints, or feature status changes.
6. Summarize changed files, tests run, limitations, and next unresolved blocker. Never claim a test passed unless it was executed.

## Hackathon definition of done

A working iPhone UI and FastAPI service; local message persistence; BLE direct messaging tested on real devices if available; multi-hop relay verified on three devices or clearly marked as simulated; level-specific outage predictions on held-out historical/synthetic data; food submission and photo review workflow; constrained allocation; non-overlapping pickup schedules; and single-use pickup redemption.
