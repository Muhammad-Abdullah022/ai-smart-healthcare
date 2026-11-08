# Changelog

## 0.2.0 — 2026-11-01
### Added
- AI service layer (Gemini + Groq, fallback, retries, schema validation) and medical safety rules.
- AI Symptom Checker with triage, follow-up questions, explanation and private history (features 1, 2, 4).
- In-memory DB dev mode, Chrome/Windows support, run scripts.

## 0.1.0 — 2026-11-01
### Added
- Excel task tracker (227 tasks, 8 sheets, live dashboard).
- FastAPI backend: config, bcrypt hashing, JWT access/refresh with rotation & revocation, register/login/logout/me,
  own-profile read/update, audit events, consistent errors, MongoDB indexes, 22 tests.
- Flutter app: healthcare theme (navy/teal, Inter), reusable widgets, go_router with auth guard, provider state,
  secure token storage, API client with auto refresh, splash, onboarding, login, register, forgot password (UI),
  home dashboard with 4 modules / 50 features, module & feature pages, profile view/edit, settings, search,
  records & notifications empty states, medical disclaimer, emergency numbers card. 4 test files.
- Docs: README, ARCHITECTURE, backend README with MongoDB Atlas steps.
- `scripts/flutter_checks.bat` to run Flutter checks on Windows.

## 2026-11-08 — AI Health Assistant chatbot
- New chat (features 13, 8, 9): asks the language first (English / اردو / Roman Urdu), reads replies aloud, voice messages, saved chat history.
- Upload a report (camera, photo, PDF) inside the chat or in "My reports"; Gemini reads values and flags them; no medicine advice.
- Old vs new report comparison.
- Backend: /assistant/chat, /assistant/chats, /reports (upload, list, compare, retry). New package python-multipart.
- Flutter packages: flutter_tts, speech_to_text, file_picker, image_picker, http_parser. Android: RECORD_AUDIO, CAMERA.
