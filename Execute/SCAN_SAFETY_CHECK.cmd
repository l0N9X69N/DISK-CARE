@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
set "SCRIPT_DIR=%~dp0"
echo ============================================================
echo DISK-CARE DISK SCAN - STATIC SAFETY AUDIT
echo ============================================================
echo Checks CMD and internal PS1 source for destructive commands.
echo Also verifies explicit reparse-point protection in deep inventory.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$self='SCAN_SAFETY_CHECK.cmd'; $root=$env:SCRIPT_DIR;" ^
  "$regexes=@('(?im)^\s*(del|erase|rd|rmdir)\s+','(?i)Remove-Item','(?i)Clear-Content','(?i)Clear-RecycleBin','(?i)Move-Item','(?i)Rename-Item','(?i)Format-Volume','(?im)^\s*format(\.com)?\s+','(?im)^\s*diskpart(\.exe)?\s*$','(?i)cipher\s+/w','(?i)sdelete','(?i)docker\s+system\s+prune','(?i)wsl(\.exe)?\s+--unregister','(?i)git\s+clean\s+-','(?i)/StartComponentCleanup','(?i)/ResetBase','(?i)cleanmgr','(?i)defrag\s+','(?i)chkdsk\s+[^\r\n]*/f');" ^
  "$hits=New-Object Collections.Generic.List[object]; $files=@(Get-ChildItem -LiteralPath $root -Filter '*.cmd' -File; Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File); $files | Where-Object Name -ne $self | ForEach-Object { $text=Get-Content -LiteralPath $_.FullName -Raw; foreach($r in $regexes){ if($text -match $r){ $hits.Add([pscustomobject]@{File=$_.Name;Finding='DestructivePattern';Pattern=$r}) } } };" ^
  "$deep=Join-Path $root 'DISK_SCAN_DEEP_ENGINE.ps1'; if(-not (Test-Path -LiteralPath $deep)){ $hits.Add([pscustomobject]@{File='DISK_SCAN_DEEP_ENGINE.ps1';Finding='MissingDeepScanner';Pattern='file missing'}) }else{ $t=Get-Content -LiteralPath $deep -Raw; if($t -notmatch 'FileAttributes\]::ReparsePoint'){ $hits.Add([pscustomobject]@{File='DISK_SCAN_DEEP_ENGINE.ps1';Finding='MissingReparseGuard';Pattern='ReparsePoint guard not found'}) }; if($t -match '(?i)-FollowSymlink'){ $hits.Add([pscustomobject]@{File='DISK_SCAN_DEEP_ENGINE.ps1';Finding='UnsafeSymlinkFollow';Pattern='-FollowSymlink'}) }; if($t -notmatch 'SAFE_NO_REPARSE_FOLLOW'){ $hits.Add([pscustomobject]@{File='DISK_SCAN_DEEP_ENGINE.ps1';Finding='MissingTraversalManifest';Pattern='SAFE_NO_REPARSE_FOLLOW'}) } }; $cache=Join-Path $root 'CACHE_CANDIDATES.cmd'; if((Test-Path -LiteralPath $cache) -and ((Get-Content -LiteralPath $cache -Raw) -notmatch 'FileAttributes\]::ReparsePoint')){ $hits.Add([pscustomobject]@{File='CACHE_CANDIDATES.cmd';Finding='MissingReparseGuard';Pattern='ReparsePoint guard not found'}) };" ^
  "if($hits.Count -eq 0){ Write-Host 'PASS: No listed destructive commands found.'; Write-Host 'PASS: Explicit reparse guard present; -FollowSymlink absent.'; exit 0 }else{ Write-Host 'REVIEW REQUIRED:'; $hits | Format-Table -AutoSize; exit 2 }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
  echo.
  echo Safety audit: PASS
  exit /b 0
)
echo.
echo Safety audit: REVIEW REQUIRED
exit /b %RC%
