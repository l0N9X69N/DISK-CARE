@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"
set "OUT=%DISKCARE_REPORT_DIR%\cache_candidates_%TS%.csv"
set "ERR=%DISKCARE_REPORT_DIR%\cache_candidates_errors_%TS%.csv"
set "REP=%DISKCARE_REPORT_DIR%\cache_reparse_skipped_%TS%.csv"
echo [DISK-CARE v2] Measuring known cache/temp locations inside target scope.
echo Reparse points are skipped. No deletion will occur.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "function Export-Report { param($Data,[string]$Path,[string[]]$Columns); $arr=@($Data | Where-Object { $null -ne $_ }); if($arr.Count -gt 0){ $arr | Select-Object $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 } else { ($Columns -join ',') | Set-Content -LiteralPath $Path -Encoding UTF8 } };" ^
  "function In-Scope { param([string]$Path,[string]$Scope); $p=[IO.Path]::GetFullPath($Path).TrimEnd('\'); $s=[IO.Path]::GetFullPath($Scope).TrimEnd('\'); return ($p -ieq $s -or $p.StartsWith($s+'\',[StringComparison]::OrdinalIgnoreCase)) };" ^
  "function Measure-Safe { param([string]$Root,$ErrList,$RepList); [int64]$bytes=0; [int64]$files=0; $ri=Get-Item -LiteralPath $Root -Force -ErrorAction Stop; if(($ri.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ $RepList.Add([pscustomobject]@{Path=$ri.FullName;Action='ROOT_REPARSE_SKIPPED_NOT_FOLLOWED'}); return [pscustomobject]@{Bytes=$bytes;Files=$files} }; $stack=New-Object Collections.Generic.Stack[object]; $stack.Push($ri); while($stack.Count -gt 0){ $d=$stack.Pop(); $ev=@(); $children=@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable +ev); foreach($er in $ev){ $ep=if($er.TargetObject){[string]$er.TargetObject}else{$d.FullName}; $ErrList.Add([pscustomobject]@{Path=$ep;Message=$er.Exception.Message}) }; foreach($i in $children){ if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){ $RepList.Add([pscustomobject]@{Path=$i.FullName;Action='SKIPPED_NOT_FOLLOWED'}); continue }; if($i.PSIsContainer){$stack.Push($i)}else{$bytes += [int64]$i.Length; $files++} } }; return [pscustomobject]@{Bytes=$bytes;Files=$files} };" ^
  "$scope=(Get-Item -LiteralPath $env:DISKCARE_TARGET -Force).FullName;" ^
  "$candidates=@([pscustomobject]@{Category='User Temp';Safety='SAFE';Path=$env:TEMP},[pscustomobject]@{Category='Local Temp';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'Temp')},[pscustomobject]@{Category='Windows Temp';Safety='SAFE';Path=(Join-Path $env:WINDIR 'Temp')},[pscustomobject]@{Category='Chrome Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache')},[pscustomobject]@{Category='Chrome Code Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache')},[pscustomobject]@{Category='Edge Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache')},[pscustomobject]@{Category='Edge Code Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache')},[pscustomobject]@{Category='VS Code Cache';Safety='SAFE';Path=(Join-Path $env:APPDATA 'Code\Cache')},[pscustomobject]@{Category='VS Code CachedData';Safety='SAFE';Path=(Join-Path $env:APPDATA 'Code\CachedData')},[pscustomobject]@{Category='npm Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'npm-cache')},[pscustomobject]@{Category='Yarn Cache';Safety='REVIEW';Path=(Join-Path $env:LOCALAPPDATA 'Yarn\Cache')},[pscustomobject]@{Category='pip Cache';Safety='SAFE';Path=(Join-Path $env:LOCALAPPDATA 'pip\Cache')},[pscustomobject]@{Category='pnpm Store';Safety='REVIEW';Path=(Join-Path $env:LOCALAPPDATA 'pnpm\store')},[pscustomobject]@{Category='NuGet Packages';Safety='REVIEW';Path=(Join-Path $env:USERPROFILE '.nuget\packages')});" ^
  "$allErr=New-Object Collections.Generic.List[object]; $allRep=New-Object Collections.Generic.List[object]; $result=New-Object Collections.Generic.List[object];" ^
  "foreach($c in $candidates){ if($c.Path -and (Test-Path -LiteralPath $c.Path) -and (In-Scope $c.Path $scope)){ Write-Host ('Scanning cache candidate: '+$c.Path); $beforeE=$allErr.Count; $beforeR=$allRep.Count; $m=Measure-Safe $c.Path $allErr $allRep; $result.Add([pscustomobject]@{Category=$c.Category;Safety=$c.Safety;SizeGB=[math]::Round($m.Bytes/1GB,3);SizeMB=[math]::Round($m.Bytes/1MB,1);Files=$m.Files;Errors=($allErr.Count-$beforeE);ReparseSkipped=($allRep.Count-$beforeR);Path=[IO.Path]::GetFullPath($c.Path)}) } };" ^
  "$sorted=@($result | Sort-Object SizeMB -Descending); Export-Report $sorted $env:OUT @('Category','Safety','SizeGB','SizeMB','Files','Errors','ReparseSkipped','Path'); Export-Report $allErr $env:ERR @('Path','Message'); Export-Report $allRep $env:REP @('Path','Action');" ^
  "$total=($sorted | Measure-Object SizeMB -Sum).Sum; Write-Host ('Potential cache/temp observed: {0:N1} MB' -f $total); Write-Host ('Cache reparse points skipped: '+$allRep.Count)"
if errorlevel 1 (
  echo [ERROR] Cache scan failed.
  exit /b 1
)
echo.
echo Report: %OUT%
echo Errors: %ERR%
echo Reparse skipped: %REP%
exit /b 0
