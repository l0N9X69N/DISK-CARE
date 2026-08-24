@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
echo [DISK-CARE v2] Reparse-point inventory is produced by the single-pass deep inventory.
echo Reparse points are recorded and never followed.
call "%~dp0DISK_SCAN_DEEP.cmd"
exit /b %ERRORLEVEL%
