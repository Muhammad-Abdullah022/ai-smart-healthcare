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
REM Build this PC's Wi-Fi address into the phone app, so it also works without the USB cable.
set LANIP=
for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lan_ip.ps1"`) do set LANIP=%%i
if defined LANIP (
  echo Phone app will use the backend at http://%LANIP%:8000 ^(and localhost over USB^)
  call flutter run --dart-define=LAN_SERVER=http://%LANIP%:8000
) else (
  call flutter run
)
pause
