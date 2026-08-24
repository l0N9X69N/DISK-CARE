@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo DISK-CARE CLEANUP HARDENING - HARDENING ^& PORTABILITY
echo ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CLEANUP_HARDEN_ENGINE.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Phase 5 hardening run: PASS
) else (
    echo Phase 5 hardening run: FAIL ^(exit code %RC%^)
)

exit /b %RC%
