[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ExecuteRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExecuteRoot)) {
    $ExecuteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$ReleaseRoot = Split-Path -Parent $ExecuteRoot
$ManifestPath = Join-Path $ReleaseRoot 'release_manifest.csv'

Write-Host ('=' * 60)
Write-Host 'DISK-CARE - RELEASE INTEGRITY CHECK'
Write-Host ('=' * 60)

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host 'FAIL: release_manifest.csv is missing.'
    exit 1
}

$rows = @(Import-Csv -LiteralPath $ManifestPath)
if ($rows.Count -eq 0) {
    Write-Host 'FAIL: release_manifest.csv is empty.'
    exit 1
}

$failed = $false
$manifestPaths = @{}
foreach ($row in $rows) {
    $relative = [string]$row.RelativePath
    $manifestPaths[$relative.ToLowerInvariant()] = $true
    $path = Join-Path $ReleaseRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "FAIL: Missing: $relative"
        $failed = $true
        continue
    }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -ne [int64]$row.SizeBytes) {
        Write-Host "FAIL: Size mismatch: $relative"
        $failed = $true
        continue
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -ne ([string]$row.SHA256).ToUpperInvariant()) {
        Write-Host "FAIL: SHA256 mismatch: $relative"
        $failed = $true
    }
}

$actualFiles = @(Get-ChildItem -LiteralPath $ReleaseRoot -File -Recurse -ErrorAction Stop |
    Where-Object { $_.Name -notin @('release_manifest.csv','release_hashes.sha256') })
foreach ($file in $actualFiles) {
    $base = [System.IO.Path]::GetFullPath($ReleaseRoot).TrimEnd('\') + '\'
    $relative = [System.IO.Path]::GetFullPath($file.FullName).Substring($base.Length)
    if ($manifestPaths.ContainsKey($relative.ToLowerInvariant())) { continue }
    if ($relative.StartsWith('Output\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    Write-Host "FAIL: Unexpected unmanifested file: $relative"
    $failed = $true
}

if ($failed) {
    Write-Host 'Release integrity: FAIL'
    exit 1
}

Write-Host "PASS: $($rows.Count) manifest files match size and SHA256."
Write-Host 'PASS: Generated files are allowed only below Output.'
Write-Host 'Release integrity: PASS'
exit 0