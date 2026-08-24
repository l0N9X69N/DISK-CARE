@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
echo [DISK-CARE v2] Large-file report is produced by the single-pass deep inventory.
call "%~dp0DISK_SCAN_DEEP.cmd"
exit /b %ERRORLEVEL%
