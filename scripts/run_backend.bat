@echo off
REM Starts the backend at http://localhost:8000  (API docs: http://localhost:8000/docs)
REM First run creates a Python virtual environment and installs packages (takes a few minutes).
cd /d "%~dp0..\backend"
if not exist .venv (
  echo Creating Python virtual environment...
  python -m venv .venv
  call .venv\Scripts\activate
  pip install -r requirements.txt
) else (
  call .venv\Scripts\activate
)
if not exist .env (
  echo backend\.env is missing. Copy .env.example to .env and fill it in.
  pause
  exit /b 1
)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
pause
