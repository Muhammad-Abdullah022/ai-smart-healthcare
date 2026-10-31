@echo off
REM Runs all Flutter checks and saves the output to flutter_checks.log (same folder).
REM Double-click this file, or run it from a terminal.
set LOG=%~dp0flutter_checks.log
cd /d "%~dp0..\frontend"
echo ==== %DATE% %TIME% ==== > "%LOG%"
echo ---- flutter --version >> "%LOG%"
call flutter --version >> "%LOG%" 2>&1
if not exist android (
  echo ---- flutter create android platform >> "%LOG%"
  call flutter create . --platforms=android --org com.fyp.healthcare --project-name ai_smart_healthcare >> "%LOG%" 2>&1
  REM flutter create adds a sample test for its counter app; remove it.
  findstr /m "MyApp" test\widget_test.dart >nul 2>&1 && del test\widget_test.dart
)
echo ---- flutter pub get >> "%LOG%"
call flutter pub get >> "%LOG%" 2>&1
echo ---- flutter analyze >> "%LOG%"
call flutter analyze >> "%LOG%" 2>&1
echo ANALYZE_EXIT=%ERRORLEVEL% >> "%LOG%"
echo ---- flutter test >> "%LOG%"
call flutter test >> "%LOG%" 2>&1
echo TEST_EXIT=%ERRORLEVEL% >> "%LOG%"
echo ==== DONE ==== >> "%LOG%"
