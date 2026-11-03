@echo off
title AI Smart Healthcare - ANDROID PHONE
REM 1) Start START_BACKEND.bat first.  2) Connect your phone by USB with USB debugging ON.  3) Run this.
cd /d "%~dp0..\frontend"

set ADB=adb
where adb >nul 2>&1 || set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"

echo Connected devices:
%ADB% devices
echo.
echo Linking phone port 8000 to this PC's backend (over the USB cable)...
%ADB% reverse tcp:8000 tcp:8000
if errorlevel 1 (
  echo Could not link the phone. Check the USB cable, USB debugging, and accept the "Allow USB debugging" popup on the phone.
  pause
  exit /b 1
)

echo Installing and starting the app on your phone (first time takes a few minutes)...
call flutter run --dart-define=API_BASE_URL=http://localhost:8000
pause
