@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RELEASE_VERIFY.ps1"
exit /b %ERRORLEVEL%