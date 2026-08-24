@echo off
setlocal EnableExtensions
call "%~dp0DISKCARE_RUNTIME_CONFIG.cmd"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%I"
set "OUT=%DISKCARE_REPORT_DIR%\system_diagnostics_%TS%.txt"
echo [DISK-CARE v2] Read-only system diagnostics for target scope.
echo Diagnostic level: %DISKCARE_DIAG_LEVEL%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Continue';" ^
  "function In-Scope { param([string]$Path,[string]$Scope); try{$p=[IO.Path]::GetFullPath($Path).TrimEnd('\');$s=[IO.Path]::GetFullPath($Scope).TrimEnd('\');return($p -ieq $s -or $p.StartsWith($s+'\',[StringComparison]::OrdinalIgnoreCase))}catch{return $false} };" ^
  "$target=(Get-Item -LiteralPath $env:DISKCARE_TARGET -Force).FullName; $item=Get-Item -LiteralPath $target -Force; $targetDrive=$item.PSDrive.Name+':'; $systemDrive=$env:SystemDrive; $systemRoot=$systemDrive+'\'; $lines=New-Object Collections.Generic.List[string];" ^
  "$lines.Add('DISK-CARE DISK SCAN - SYSTEM DIAGNOSTICS'); $lines.Add('Generated: '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')); $lines.Add('Target: '+$target); $lines.Add('DiagnosticLevel: '+$env:DISKCARE_DIAG_LEVEL); $lines.Add('ReadOnly: YES'); $lines.Add('');" ^
  "$lines.Add('[SYSTEM ROOT FILES]'); foreach($name in @('pagefile.sys','hiberfil.sys','swapfile.sys')){ $p=Join-Path $systemRoot $name; if((In-Scope $p $target) -and (Test-Path -LiteralPath $p)){ try{$f=Get-Item -LiteralPath $p -Force; $lines.Add(('{0}: {1:N2} GB | NEVER_DELETE | {2}' -f $name,($f.Length/1GB),$f.FullName))}catch{$lines.Add($name+': present but size unavailable | '+$_.Exception.Message)} } };" ^
  "$lines.Add(''); $lines.Add('[PAGEFILE USAGE]'); try{ $pf=@(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop); if($pf.Count){ foreach($p in $pf){$lines.Add(('Name={0} AllocatedMB={1} CurrentUsageMB={2} PeakUsageMB={3}' -f $p.Name,$p.AllocatedBaseSize,$p.CurrentUsage,$p.PeakUsage))} }else{$lines.Add('None reported.')} }catch{$lines.Add('Unavailable: '+$_.Exception.Message)};" ^
  "$lines.Add(''); $lines.Add('[SHADOW STORAGE]'); try{ $ss=@(Get-CimInstance Win32_ShadowStorage -ErrorAction Stop); if($ss.Count){ foreach($s in $ss){$lines.Add(('Used={0:N2} GB Allocated={1:N2} GB Max={2:N2} GB' -f ($s.UsedSpace/1GB),($s.AllocatedSpace/1GB),($s.MaxSpace/1GB)))} }else{$lines.Add('None reported.')} }catch{$lines.Add('Unavailable: '+$_.Exception.Message)};" ^
  "$lines.Add(''); $lines.Add('[WSL]'); if(Get-Command wsl.exe -ErrorAction SilentlyContinue){ try{ $wsl=& wsl.exe --list --verbose 2>&1; if($wsl){$wsl | ForEach-Object {$lines.Add([string]$_)}}else{$lines.Add('No WSL distributions reported.')} }catch{$lines.Add('Unavailable: '+$_.Exception.Message)} }else{$lines.Add('wsl.exe not found.')};" ^
  "$lines.Add(''); $lines.Add('[DOCKER / WSL VHD CANDIDATE PATHS]'); $dockerPaths=@((Join-Path $env:LOCALAPPDATA 'Docker\wsl'),(Join-Path $env:LOCALAPPDATA 'DockerDesktop'),(Join-Path $env:LOCALAPPDATA 'Packages')); foreach($p in $dockerPaths){ if($p -and (In-Scope $p $target)){ $lines.Add($p+' | Exists='+(Test-Path -LiteralPath $p)) } };" ^
  "$lines.Add(''); $lines.Add('[WINDOWS COMPONENT STORE ANALYSIS]'); if($targetDrive -ieq $systemDrive -and (In-Scope $env:WINDIR $target)){ if($env:DISKCARE_DIAG_LEVEL -ieq 'QUICK'){ $lines.Add('SKIPPED_QUICK_MODE') }elseif(Get-Command dism.exe -ErrorAction SilentlyContinue){ try{ $dism=& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English 2>&1; $lines.Add('Command: DISM /Online /Cleanup-Image /AnalyzeComponentStore /English'); $dism | ForEach-Object {$lines.Add([string]$_)} }catch{$lines.Add('Unavailable: '+$_.Exception.Message)} }else{$lines.Add('dism.exe not found.')} }else{$lines.Add('NOT_APPLICABLE_TARGET_SCOPE')};" ^
  "$lines.Add(''); $lines.Add('[SAFETY]'); $lines.Add('DeletionActions: 0'); $lines.Add('CleanupActions: 0'); $lines | Set-Content -LiteralPath $env:OUT -Encoding UTF8; $lines | ForEach-Object {Write-Host $_}"
if errorlevel 1 (
  echo [ERROR] System diagnostics failed.
  exit /b 1
)
echo.
echo Report: %OUT%
exit /b 0
