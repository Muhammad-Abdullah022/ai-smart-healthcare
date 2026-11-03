@echo off
REM Used by VS Code (Run / F5). Starts the backend if needed and links a USB phone or emulator.
set ADB=adb
where adb >nul 2>&1 || set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
%ADB% reverse tcp:8000 tcp:8000 >nul 2>&1

curl -s -o nul http://localhost:8000/health
if not errorlevel 1 (
  echo Application startup complete - backend already running
  exit /b 0
)

cd /d "%~dp0..\backend"
if not exist .venv python -m venv .venv
call .venv\Scripts\activate
pip install -q -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
