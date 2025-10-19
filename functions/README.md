# Somewhere Engage Functions

This folder contains a Cloud Functions (TypeScript) skeleton for the "Engage" orchestrator.

## How it works
- POST /engage/event is implemented by the `postEvent` function.
- It records events, loads user context from Firestore, applies policy, calls a Goose agent (optional), persists decisions, and routes actions (messages/tasks).
- Rate limiting uses a Firestore-backed token bucket per-user in the `rate_limits/{uid}` collection.

## Environment variables
- GOOSE_AGENT_URL (optional): URL to call the Goose agent runtime (POST input JSON). If not set, a local heuristic is used.
- GOOSE_API_KEY (optional): Bearer token for the Goose agent call.
- DEFAULT_TZ (optional): fallback timezone, default `UTC`.
- DEFAULT_QUIET_START / DEFAULT_QUIET_END: default quiet hours (numbers, default 22 and 8).
- TOKEN_CAPACITY: token bucket capacity (default 5).
- TOKEN_REFILL_INTERVAL_MS: refill interval in milliseconds (default 30min).
- TOKEN_REFILL_TOKENS: tokens added per interval (default 1).

## Running tests locally
Prereqs:
- Node 18+
- npm
- firebase-tools (to run Firestore emulator)

Steps:
1. Install deps:
   cd functions && npm ci
2. Start Firestore emulator:
   firebase emulators:start --only firestore
3. Run tests:
   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test


## Deploy
We use Firebase Cloud Functions (v2) — add a deploy workflow in .github/workflows/deploy.yml that uses a FIREBASE_SERVICE_ACCOUNT secret to authenticate and deploy.

## Notes
- Tests use the Firestore emulator for integration tests.
- CI workflow config already included to start emulator and run tests on push/PR.
