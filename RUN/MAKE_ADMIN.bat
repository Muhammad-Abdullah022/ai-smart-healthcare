@echo off
title AI Smart Healthcare - MAKE ADMIN
REM Run once to create the administrator account (the admin creates doctor accounts in the app).
cd /d "%~dp0..\backend"
if not exist .venv (
  echo Run START_BACKEND.bat once first.
  pause
  exit /b 1
)
call .venv\Scripts\activate
python scripts\make_admin.py
pause
