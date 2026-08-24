@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo DISK-CARE ANALYSIS - RUN
echo ============================================================
echo Analyze-only mode. This phase does not delete or clean files.
echo.

set "INPUT=%~1"
set "OUTPUT=%~2"

if not defined INPUT (
  set /p "INPUT=Phase 2 report folder: "
)

if defined OUTPUT (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DISK_ANALYZE_ENGINE.ps1" -InputDir "%INPUT%" -OutputDir "%OUTPUT%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DISK_ANALYZE_ENGINE.ps1" -InputDir "%INPUT%"
)

set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo Phase 3 run finished successfully.
) else (
  echo Phase 3 run failed with exit code %RC%.
)
exit /b %RC%
