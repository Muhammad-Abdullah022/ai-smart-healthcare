@echo off
title AI Smart Healthcare - FRONTEND
REM Start START_BACKEND.bat first. Then run this and choose a device by number (Chrome, Windows, phone, emulator).
cd /d "%~dp0..\frontend"

REM If a phone or emulator is connected by USB, link it to the backend on this PC (ignored otherwise).
set ADB=adb
where adb >nul 2>&1 || set ADB="%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
%ADB% reverse tcp:8000 tcp:8000 >nul 2>&1

call flutter pub get
echo.
echo Choose where to run the app (type the number and press Enter):
call flutter run
pause
