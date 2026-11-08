@echo off
title AI Smart Healthcare - BACKEND
REM Double-click this FIRST. Keep this window open while you use the app.
cd /d "%~dp0..\backend"

if not exist .venv (
  echo [1/3] Creating Python environment - first time only...
  python -m venv .venv
  if errorlevel 1 (
    echo.
    echo Python was not found. Install Python 3.11+ from https://www.python.org and tick "Add to PATH".
    pause
    exit /b 1
  )
)
call .venv\Scripts\activate

echo [2/3] Checking packages...
pip install -q -r requirements.txt
if errorlevel 1 (
  echo Package install failed. Check your internet connection and try again.
  pause
  exit /b 1
)

if not exist .env (
  echo backend\.env is missing. Copy .env.example to .env and fill it in.
  pause
  exit /b 1
)

REM Close any old backend still using port 8000 (otherwise the app may talk to old code).
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8000 " ^| findstr LISTENING') do (
  echo Closing old backend process %%p...
  taskkill /F /T /PID %%p >nul 2>&1
)

echo [3/3] Starting backend at http://localhost:8000  (API docs: http://localhost:8000/docs)
echo Wait for "Application startup complete", then start the app.
echo.
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
echo.
echo Backend stopped.
pause
