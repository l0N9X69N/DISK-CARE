@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
echo ============================================================
echo DISK-CARE DISK SCAN - QUICK READ-ONLY SCAN
echo ============================================================
echo Target: %DISKCARE_TARGET%
echo Quick scan does NOT traverse the full target tree.
echo.
call "%~dp0SCAN_SAFETY_CHECK.cmd"
if errorlevel 1 exit /b 1
call "%~dp0DISK_SUMMARY.cmd"
if errorlevel 1 echo [WARN] Disk summary returned an error.
call "%~dp0CACHE_CANDIDATES.cmd"
if errorlevel 1 echo [WARN] Cache scan returned an error.
set "DISKCARE_DIAG_LEVEL=QUICK"
call "%~dp0SYSTEM_DIAGNOSTICS.cmd"
if errorlevel 1 echo [WARN] Quick diagnostics returned an error.
echo.
echo QUICK SCAN FINISHED.
echo Reports: %DISKCARE_REPORT_DIR%
exit /b 0
