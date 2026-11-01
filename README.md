# AI Smart Healthcare — Disease Assessment and Patient Support System

Final Year Project. A Flutter mobile app backed by a Python FastAPI server and MongoDB Atlas,
using Google Gemini and xAI Grok (through the backend only) for AI features.

> ⚠️ This app provides health information only. It is **not** a medical diagnosis tool, is **not**
> clinically validated, and has **no** regulatory approval.

| Folder | What it is |
|---|---|
| `frontend/` | Flutter app (Android first) |
| `backend/` | FastAPI server (auth, profiles, later AI and records) |
| `ARCHITECTURE.md` | How the code is organised, in simple English |
| `PROJECT_STATUS.md` | What is done, what is in progress |
| `NEXT_SESSION.md` | Exactly where to continue next time |
| `CHANGELOG.md` | History of changes |

The task tracker lives separately at `E:\FYP SESMTER\task\Healthcare_AI_Task_Tracker.xlsx`.

## Run everything with one command
From VS Code's terminal:
```powershell
cd "E:\FYP SESMTER\app\frontend"
.\run.bat -d chrome      # or: -d windows, or no -d to pick the emulator
```
`run.bat` starts the backend in its own window (if it is not already running), then runs `flutter run`.
Or press **F5** in VS Code with the "App + Backend" configuration.

## Quick start (manual)

### 1. Backend
```powershell
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env      # then open .env and fill in your values
python -m pytest            # run the tests
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Open http://localhost:8000/docs to try the API. See `backend/README.md` for MongoDB Atlas setup.

### 2. Flutter app
```powershell
cd frontend
flutter create . --platforms=android --org com.fyp.healthcare   # first time only: adds android/ folder
flutter pub get
flutter analyze
flutter test
flutter run
```
The Android emulator reaches your PC's backend at `http://10.0.2.2:8000` (the default).
For a real phone on the same Wi-Fi, use your PC's IP:
`flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000`
