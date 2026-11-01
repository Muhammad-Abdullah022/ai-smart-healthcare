@echo off
title AI Smart Healthcare - APP
REM Double-click this AFTER START_BACKEND shows "Application startup complete".
cd /d "%~dp0..\frontend"

where flutter >nul 2>&1
if errorlevel 1 (
  echo Flutter was not found. Make sure Flutter is installed and added to PATH.
  pause
  exit /b 1
)

if not exist android (
  echo [setup] Adding Android / Web / Windows folders - first time only...
  call flutter create . --platforms=android,web,windows --org com.fyp.healthcare --project-name ai_smart_healthcare
  findstr /m "MyApp" test\widget_test.dart >nul 2>&1 && del test\widget_test.dart
)

echo Getting packages...
call flutter pub get

echo.
echo Building the app... it opens at http://localhost:5555 (refresh the page if it is blank at first)
start "" http://localhost:5555
call flutter run -d web-server --web-port 5555 --web-hostname localhost --release
echo.
echo App stopped.
pause
