@echo off
title AI Smart Healthcare - DEMO DOCTOR LOGINS
REM Creates a login for every DEMO doctor profile (not the real government list).
cd /d "%~dp0..\backend"
if not exist .venv (
  echo Run START_BACKEND.bat once first.
  pause
  exit /b 1
)
call .venv\Scripts\activate
python scripts\make_demo_doctor_logins.py
pause
