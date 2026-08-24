@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"
set "OUT=%DISKCARE_REPORT_DIR%\disk_summary_%TS%.txt"
echo [DISK-CARE v2] Disk summary for: %DISKCARE_TARGET%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$item=Get-Item -LiteralPath $env:DISKCARE_TARGET -Force;" ^
  "$drive=$item.PSDrive.Name+':';" ^
  "$d=Get-CimInstance Win32_LogicalDisk | Where-Object DeviceID -eq $drive | Select-Object -First 1;" ^
  "if(-not $d){ throw 'Unable to resolve logical disk for target.' };" ^
  "$used=$d.Size-$d.FreeSpace;" ^
  "$lines=@();" ^
  "$lines+='DISK-CARE DISK SCAN - DISK SUMMARY';" ^
  "$lines+='Generated: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');" ^
  "$lines+='Target: '+$item.FullName;" ^
  "$lines+='Drive: '+$d.DeviceID;" ^
  "$lines+='FileSystem: '+$d.FileSystem;" ^
  "$lines+='Volume: '+$d.VolumeName;" ^
  "$lines+=('TotalGB: {0:N2}' -f ($d.Size/1GB));" ^
  "$lines+=('UsedGB: {0:N2}' -f ($used/1GB));" ^
  "$lines+=('FreeGB: {0:N2}' -f ($d.FreeSpace/1GB));" ^
  "$lines+=('UsedPercent: {0:N1}%%' -f (($used/$d.Size)*100));" ^
  "$lines | Set-Content -LiteralPath $env:OUT -Encoding UTF8;" ^
  "$lines | ForEach-Object { Write-Host $_ }"
if errorlevel 1 (
  echo [ERROR] Disk summary failed.
  exit /b 1
)
echo.
echo Report: %OUT%
exit /b 0
