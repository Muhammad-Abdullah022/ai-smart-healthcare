# Project Status — 2026-11-01

Tracker: `E:\FYP SESMTER\task\Healthcare_AI_Task_Tracker.xlsx` (source of truth for task status).

## Done (verified)
| Task | What | Proof |
|---|---|---|
| A-04, C-01 | FastAPI backend skeleton, `/health` | pytest |
| C-02 | Settings from `.env`, refuses weak JWT secret | pytest |
| C-06 | bcrypt password hashing | pytest |
| C-07 | Access + refresh tokens, rotation, revocation | pytest |
| C-08 | Register / login / refresh / logout / me API | pytest (11 tests) |
| A-05 | Git, `.gitignore`, `.env.example` (no secrets) | git status checked |
| A-06, A-07 | Architecture + continuity docs | — |

| D-01, D-04–D-07, D-09 | AI layer: Gemini + Groq clients, fallback, retries, JSON validation, emergency rules | pytest (mocked AI) |

**Backend tests: 58 passed, 0 failed.**

## New: Symptom checker (features 1, 2, 4)
* `POST /assessments/symptoms` — emergency rules first (no AI, instant 1122 guidance), else AI → validated result.
* Doses removed from AI text; triage never lowered below rule result; history private per user.
* Flutter: symptom form, result screen (triage colour, causes, next steps, follow-up questions, "Why this result?"), history.
* Live AI not yet verified — needs one real run with your keys.

## Written, waiting for Flutter checks (status: Testing)
Theme, reusable widgets, router with login guard, API client (auto token refresh), secure token storage,
splash, 3 onboarding pages, login, register, home dashboard (4 modules / 50 features), module + feature screens,
profile view, settings with logout, search, records/notifications empty states, medical disclaimer, SOS numbers card.
Flutter tests written: validators, router redirects, API client (5), login screen (3).
`flutter analyze` / `flutter test` **have not run yet** → run `scripts\flutter_checks.bat`.

## In progress / blocked
* B-13 edit profile done, photo upload waits for C-12.
* B-08 forgot-password UI only — email sending needs C-09.
* C-03 **Blocked**: needs your MongoDB Atlas connection string in `backend/.env`.

## Known limitations
* Features 1, 2, 4 built (awaiting live test); the other 47 pages say "being built".
* Labs, prices, pharmacy stock, wearables, camera exercise are marked **Prototype** in the app.
* Emergency numbers (1122, 115, 15) must be verified against an official source before release.
