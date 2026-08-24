@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
echo ============================================================
echo DISK-CARE DISK SCAN - FULL READ-ONLY SCAN
echo ============================================================
echo Target: %DISKCARE_TARGET%
echo Deep traversal follows normal directories only.
echo Junctions, symlinks and other reparse points are inventoried and skipped.
echo No files will be deleted, moved, renamed or cleaned.
echo Reports are written only to: %DISKCARE_REPORT_DIR%
echo.
call "%~dp0SCAN_SAFETY_CHECK.cmd"
if errorlevel 1 (
  echo [ABORT] Safety audit did not pass.
  exit /b 1
)
call "%~dp0DISK_SUMMARY.cmd"
if errorlevel 1 echo [WARN] Disk summary returned an error.
call "%~dp0CACHE_CANDIDATES.cmd"
if errorlevel 1 echo [WARN] Cache scan returned an error.
set "DISKCARE_DIAG_LEVEL=FULL"
call "%~dp0SYSTEM_DIAGNOSTICS.cmd"
if errorlevel 1 echo [WARN] System diagnostics returned an error.
call "%~dp0DISK_SCAN_DEEP.cmd"
if errorlevel 1 (
  echo [ERROR] Deep inventory did not complete.
  exit /b 2
)
echo.
echo ============================================================
echo PHASE 2 v2 FULL SCAN FINISHED
echo Run 08_PHASE2_ACCEPTANCE.cmd next.
echo Reports: %DISKCARE_REPORT_DIR%
echo ============================================================
exit /b 0
