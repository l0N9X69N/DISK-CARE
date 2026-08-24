@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"
set "OUT_TOP=%DISKCARE_REPORT_DIR%\top_folders_%TS%.csv"
set "OUT_LARGE=%DISKCARE_REPORT_DIR%\large_files_%TS%.csv"
set "OUT_OLD=%DISKCARE_REPORT_DIR%\old_large_files_%TS%.csv"
set "OUT_RECENT=%DISKCARE_REPORT_DIR%\recent_large_files_%TS%.csv"
set "OUT_ART=%DISKCARE_REPORT_DIR%\artifacts_%TS%.csv"
set "OUT_REPARSE=%DISKCARE_REPORT_DIR%\reparse_points_%TS%.csv"
set "OUT_ERR=%DISKCARE_REPORT_DIR%\deep_scan_errors_%TS%.csv"
set "OUT_MANIFEST=%DISKCARE_REPORT_DIR%\scan_manifest_%TS%.txt"
echo ============================================================
echo DISK-CARE DISK SCAN - DEEP INVENTORY
echo ============================================================
echo Target: %DISKCARE_TARGET%
echo Traversal policy: inventory reparse points, DO NOT FOLLOW them.
echo No delete, move, rename, cleanup or file-content modification.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DISK_SCAN_DEEP_ENGINE.ps1"
if errorlevel 1 (
  echo [ERROR] Deep inventory failed before completion.
  exit /b 1
)
echo.
echo Reports generated with one traversal:
echo   %OUT_TOP%
echo   %OUT_LARGE%
echo   %OUT_OLD%
echo   %OUT_RECENT%
echo   %OUT_ART%
echo   %OUT_REPARSE%
echo   %OUT_ERR%
echo   %OUT_MANIFEST%
exit /b 0
