@echo off
REM One command for everything:  .\run.bat            (asks which device)
REM                              .\run.bat -d chrome
REM                              .\run.bat -d windows
REM Starts the backend in its own window (if it is not already running), then runs the app.
curl -s -o nul http://localhost:8000/health
if errorlevel 1 (
  echo Starting backend in a new window...
  start "AI Healthcare Backend" cmd /c ""%~dp0..\scripts\run_backend.bat""
) else (
  echo Backend already running.
)
cd /d "%~dp0"
flutter run %*
