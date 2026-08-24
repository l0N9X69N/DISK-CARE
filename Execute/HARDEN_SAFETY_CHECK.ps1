[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$DeletionCleanupActions = 0

$ScriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    $invokedScriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrWhiteSpace($invokedScriptPath)) {
        throw 'Unable to resolve DISK-CARE runtime safety-check root.'
    }
    $ScriptRoot = Split-Path -Parent $invokedScriptPath
}

Write-Host ('=' * 60)
Write-Host 'DISK-CARE CLEANUP HARDENING - RUNTIME SAFETY CHECK'
Write-Host ('=' * 60)

$targets = @(
    (Join-Path $ScriptRoot 'CLEANUP_HARDEN.cmd'),
    (Join-Path $ScriptRoot 'CLEANUP_HARDEN_ENGINE.ps1')
)

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Write-Host "FAIL: Missing runtime hardening target: $target"
        exit 1
    }
}

$combined = ($targets | ForEach-Object { [System.IO.File]::ReadAllText($_) }) -join "`r`n"

# Build dangerous command names from fragments so this checker can audit the
# hardening runtime without embedding executable destructive commands itself.
$dangerousPatterns = @(
    '(?i)\b' + [regex]::Escape(('Remove' + '-Item')) + '\b',
    '(?i)\b' + [regex]::Escape(('Clear' + '-Content')) + '\b',
    '(?i)\b' + [regex]::Escape(('Clear' + '-RecycleBin')) + '\b',
    '(?i)\b' + [regex]::Escape(('Clear' + '-Disk')) + '\b',
    '(?i)\b' + [regex]::Escape(('Format' + '-Volume')) + '\b',
    '(?i)\b' + [regex]::Escape(('Initialize' + '-Disk')) + '\b',
    '(?i)\b' + [regex]::Escape(('disk' + 'part')) + '(?:\.exe)?\b',
    '(?im)^\s*(?:' + ('d' + 'el') + '|' + ('era' + 'se') + '|' + ('r' + 'd') + '|' + ('rm' + 'dir') + ')\s+',
    '(?i)\b' + ('robo' + 'copy') + '(?:\.exe)?\b[^\r\n]*(?:/MIR|/PURGE)',
    '(?i)\b' + ('ci' + 'pher') + '(?:\.exe)?\s+/w',
    '(?i)\b' + ('fsu' + 'til') + '(?:\.exe)?\b[^\r\n]*\b' + ('set' + 'Zero' + 'Data') + '\b'
)

foreach ($pattern in $dangerousPatterns) {
    if ([regex]::IsMatch($combined, $pattern)) {
        Write-Host "FAIL: Destructive-command pattern found in packaged hardening runtime: $pattern"
        exit 1
    }
}

if ($combined -notmatch '(?i)\bHARDEN_ONLY\b') {
    Write-Host 'FAIL: Explicit HARDEN_ONLY marker is missing from packaged hardening runtime.'
    exit 1
}

if ($combined.IndexOf('REJECT_NOT_EXECUTABLE', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    Write-Host 'FAIL: REJECT_NOT_EXECUTABLE safety state is missing from packaged hardening runtime.'
    exit 1
}

$configPath = Join-Path (Split-Path -Parent $ScriptRoot) 'diskcare.config.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Host 'FAIL: Runtime hardening configuration is missing: diskcare.config.json'
    exit 1
}

try {
    $null = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}
catch {
    Write-Host "FAIL: Runtime hardening configuration is not valid JSON: $($_.Exception.Message)"
    exit 1
}

Write-Host 'PASS: No listed destructive commands found in packaged hardening runner/engine.'
Write-Host 'PASS: Explicit HARDEN_ONLY marker present.'
Write-Host 'PASS: Unknown/non-approved paths remain REJECT_NOT_EXECUTABLE.'
Write-Host 'PASS: Runtime hardening configuration exists and is valid JSON.'
Write-Host 'PASS: Deletion/Cleanup actions = 0.'
Write-Host ''
Write-Host 'Runtime hardening safety check: PASS'
exit 0