@echo off
title AI Smart Healthcare - EXPORT DOCTOR ACCOUNTS
REM Saves all doctor accounts (name, specialty, city, login email, status) to Doctor_Accounts.xlsx
cd /d "%~dp0..\backend"
if not exist .venv (
  echo Run START_BACKEND.bat once first.
  pause
  exit /b 1
)
call .venv\Scripts\activate
pip install -q openpyxl
python scripts\export_doctor_accounts.py
if exist "..\Doctor_Accounts.xlsx" start "" "..\Doctor_Accounts.xlsx"
pause
