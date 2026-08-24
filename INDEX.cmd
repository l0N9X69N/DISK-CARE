@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "DISKCARE_RELEASE_ROOT=%~dp0"
set "DISKCARE_EXEC_ROOT=%~dp0Execute"
set "DISKCARE_OUTPUT_ROOT=%~dp0Output"
set "EXEC=%~dp0Execute"

:MENU
cls
echo ============================================================
echo                         DISK-CARE
echo ============================================================
echo Safety-first disk inventory, analysis, planning and hardening.
echo.
echo [1] Quick Scan
echo [2] Full Scan
echo [3] Deep Inventory
echo [4] Detailed Scan Tools
echo [5] Analyze Candidates
echo [6] Build Cleanup Plan
echo [7] Harden Approved Plan
echo [8] Open Results
echo [9] Verify Release Integrity
echo [0] Exit
echo.
set "CHOICE="
set /p "CHOICE=Choose: "

if "%CHOICE%"=="1" goto QUICK_SCAN
if "%CHOICE%"=="2" goto FULL_SCAN
if "%CHOICE%"=="3" goto DEEP_INVENTORY
if "%CHOICE%"=="4" goto SCAN_TOOLS
if "%CHOICE%"=="5" goto ANALYZE
if "%CHOICE%"=="6" goto PLAN
if "%CHOICE%"=="7" goto HARDEN
if "%CHOICE%"=="8" goto RESULTS
if "%CHOICE%"=="9" goto VERIFY
if "%CHOICE%"=="0" goto END

echo.
echo Invalid choice.
pause
goto MENU

:QUICK_SCAN
call "%EXEC%\DISK_SCAN_QUICK.cmd"
goto AFTER_RUN

:FULL_SCAN
call "%EXEC%\DISK_SCAN_FULL.cmd"
goto AFTER_RUN

:DEEP_INVENTORY
call "%EXEC%\DISK_SCAN_DEEP.cmd"
goto AFTER_RUN

:SCAN_TOOLS
cls
echo ============================================================
echo                    DISK-CARE - SCAN TOOLS
echo ============================================================
echo.
echo [1] Disk Summary
echo [2] Top Folders
echo [3] Large Files
echo [4] Cache Candidates
echo [5] Old Files
echo [6] Recent Large Files
echo [7] VHD Artifacts
echo [8] Reparse Points
echo [9] System Diagnostics
echo [0] Back
echo.
set "SCAN_CHOICE="
set /p "SCAN_CHOICE=Choose: "
if "%SCAN_CHOICE%"=="1" call "%EXEC%\DISK_SUMMARY.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="2" call "%EXEC%\DISK_TOP_FOLDERS.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="3" call "%EXEC%\DISK_LARGE_FILES.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="4" call "%EXEC%\CACHE_CANDIDATES.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="5" call "%EXEC%\DISK_OLD_FILES.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="6" call "%EXEC%\DISK_RECENT_LARGE_FILES.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="7" call "%EXEC%\VHD_ARTIFACTS.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="8" call "%EXEC%\REPARSE_POINTS.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="9" call "%EXEC%\SYSTEM_DIAGNOSTICS.cmd"& goto AFTER_SCAN_TOOL
if "%SCAN_CHOICE%"=="0" goto MENU
echo.
echo Invalid choice.
pause
goto SCAN_TOOLS

:AFTER_SCAN_TOOL
echo.
pause
goto SCAN_TOOLS

:ANALYZE
call "%EXEC%\DISK_ANALYZE.cmd"
goto AFTER_RUN

:PLAN
call "%EXEC%\CLEANUP_PLAN.cmd"
goto AFTER_RUN

:HARDEN
call "%EXEC%\CLEANUP_HARDEN.cmd"
goto AFTER_RUN

:RESULTS
if exist "%DISKCARE_OUTPUT_ROOT%" (
    start "" "%DISKCARE_OUTPUT_ROOT%"
) else (
    echo.
    echo No runtime output has been created yet.
    pause
)
goto MENU

:VERIFY
call "%EXEC%\RELEASE_VERIFY.cmd"
goto AFTER_RUN

:AFTER_RUN
echo.
pause
goto MENU

:END
endlocal
exit /b 0