@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo DISK-CARE CLEANUP PLAN - CONTROLLED CLEANUP PLANNING
echo ============================================================
echo PLAN_ONLY. This phase does not delete or clean files.
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo ERROR: powershell.exe was not found.
  exit /b 1
)

if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLEANUP_PLAN_ENGINE.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLEANUP_PLAN_ENGINE.ps1" -Phase3Output "%~1"
)

if errorlevel 1 (
  echo.
  echo Phase 4 planning: FAIL
  exit /b 1
)

echo.
echo Phase 4 planning: PASS
exit /b 0
