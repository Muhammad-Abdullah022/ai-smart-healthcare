@echo off
title AI Smart Healthcare - APP
REM Double-click this SECOND (after the backend says "Application startup complete").
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
echo Starting the app in Chrome at http://localhost:5555 ...
call flutter run -d chrome --web-port 5555
echo.
echo App stopped.
pause
