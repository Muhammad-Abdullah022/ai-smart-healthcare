# Architecture (simple English)

```
Flutter app  ──HTTPS/JSON──▶  FastAPI backend  ──▶  MongoDB Atlas
                                    │
                                    └──▶  Gemini / Grok (AI keys live ONLY here)
```

The phone never talks to the database or the AI providers directly. That keeps secret keys off the phone
and lets the backend check that every user can only see their own data.

## Flutter (`frontend/lib/`)
| Folder | Holds | Example |
|---|---|---|
| `core/theme/` | Colors, fonts, spacing | `app_colors.dart` (#16324F navy, #14B8A6 teal…) |
| `core/router/` | Which screen opens for which URL, and login guards | `app_router.dart` |
| `core/config/` | App settings like the backend address | `app_config.dart` |
| `models/` | Plain data classes made from JSON | `user.dart`, `profile.dart`, `feature_catalog.dart` |
| `services/` | Talking to the outside world | `api_client.dart` (HTTP), `token_storage.dart`, `auth_repository.dart` |
| `providers/` | App-wide state the screens listen to | `auth_provider.dart` (who is logged in) |
| `widgets/` | Reusable building blocks | buttons, text fields, loading/empty/error views, disclaimer |
| `screens/` | One folder per area of the app | `auth/`, `home/`, `profile/`, `modules/`… |
| `utils/` | Small helpers | `validators.dart` |

**State management:** `provider` with one `AuthProvider` (a `ChangeNotifier`). It was chosen because it is the
simplest officially recommended approach and is easy for beginners to read. More providers are added per feature.

**Navigation:** `go_router`. The `authRedirect` function decides where a user may go
(splash → onboarding on first launch → login → home). It is unit tested.

**Tokens** are stored with `flutter_secure_storage` (Android Keystore), never in plain preferences.

## Backend (`backend/app/`)
| File/folder | Holds |
|---|---|
| `main.py` | Creates the app, connects MongoDB, registers routes |
| `core/config.py` | Reads settings from `.env` (fails clearly if a secret is missing) |
| `core/security.py` | Password hashing and tokens |
| `core/errors.py` | One error format: `{"error": {"code", "message"}}` |
| `db/mongo.py` | Connection + indexes |
| `models/` | Request/response shapes with validation (Pydantic) |
| `repositories/` | All database reads/writes |
| `routers/` | API endpoints, grouped by area |
| `deps.py` | Shared helpers such as "get the logged-in user" |

## Safety rules built into the design
* AI results always show `MedicalDisclaimer`; emergency numbers are shown without waiting for AI.
* Features without verified real data (labs, prices, pharmacy stock…) are labelled **Prototype** in the app.
* Every record route checks ownership on the backend.
