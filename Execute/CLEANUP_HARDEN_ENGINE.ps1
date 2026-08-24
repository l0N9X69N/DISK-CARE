[CmdletBinding()]
param(
    [string]$Phase4OutputRoot,
    [string]$OutputRoot,
    [string]$ConfigPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Phase4OutputRoot)) {
    $Phase4OutputRoot = Join-Path $ScriptRoot '..\Output\Plan'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ScriptRoot '..\Output\Harden'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ScriptRoot '..\diskcare.config.json'
}

$ExecutionMode = 'HARDEN_ONLY'
$DeletionCleanupActions = 0
$AllowDestructiveActions = $false

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Name,
        [bool]$Passed,
        [string]$Message
    )

    $List.Add([pscustomobject]@{
        Check = $Name
        Result = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Message = $Message
    })
}

function Export-CsvSafe {
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]]$Rows,
        [Parameter(Mandatory = $true)] [string[]]$Headers,
        [Parameter(Mandatory = $true)] [string]$Path
    )

    if ($Rows.Count -gt 0) {
        $Rows | Select-Object -Property $Headers | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }

    $quoted = @()
    foreach ($header in $Headers) {
        $quoted += ('"' + ($header -replace '"', '""') + '"')
    }
    Set-Content -LiteralPath $Path -Value ($quoted -join ',') -Encoding UTF8
}

function Get-PropertyValue {
    param(
        [object]$Row,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Row.PSObject.Properties[$name]
        if ($null -ne $property) {
            return [string]$property.Value
        }
    }
    return $null
}

function Test-Truthy {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('1', 'TRUE', 'YES', 'Y') -contains $Value.Trim().ToUpperInvariant()
}

function Get-Phase4Directories {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }

    $self = Get-Item -LiteralPath $Root
    if ($self.Name -like 'phase4_*') {
        return @($self)
    }

    return @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like 'phase4_*' } |
        Sort-Object -Property LastWriteTime -Descending)
}

function Get-CsvRowCount {
    param([string]$Path)
    try {
        $rows = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
        return $rows.Count
    }
    catch {
        return -1
    }
}

function Get-ReportStats {
    param([System.IO.DirectoryInfo]$Directory)

    $files = @(Get-ChildItem -LiteralPath $Directory.FullName -File -Recurse -ErrorAction SilentlyContinue)
    $csvFiles = @($files | Where-Object { $_.Extension -ieq '.csv' })
    $csvRows = 0
    $invalidCsv = 0

    foreach ($csv in $csvFiles) {
        $count = Get-CsvRowCount -Path $csv.FullName
        if ($count -lt 0) {
            $invalidCsv++
        }
        else {
            $csvRows += $count
        }
    }

    $bytes = 0L
    foreach ($file in $files) {
        $bytes += [int64]$file.Length
    }

    return [pscustomobject]@{
        Folder = $Directory.FullName
        FileCount = $files.Count
        CsvFileCount = $csvFiles.Count
        CsvRowCount = $csvRows
        InvalidCsvCount = $invalidCsv
        TotalReportBytes = $bytes
    }
}

function Get-PathDisposition {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return [pscustomobject]@{ NormalizedPath = ''; PathClass = 'UNKNOWN'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Empty path' }
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($PathValue.Trim().Trim('"'))
    $normalized = $expanded
    try {
        if ($expanded -match '^[A-Za-z]:[\\/]') {
            $normalized = [System.IO.Path]::GetFullPath($expanded)
        }
    }
    catch {
        return [pscustomobject]@{ NormalizedPath = $expanded; PathClass = 'INVALID'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Path normalization failed' }
    }

    $trimmed = $normalized.TrimEnd('\')
    $protectedRoots = @(
        'C:',
        'C:\Windows',
        'C:\Users',
        'C:\Program Files',
        'C:\Program Files (x86)'
    )

    foreach ($root in $protectedRoots) {
        if ($trimmed -ieq $root) {
            return [pscustomobject]@{ NormalizedPath = $normalized; PathClass = 'PROTECTED'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Protected root' }
        }
    }

    $leaf = [System.IO.Path]::GetFileName($trimmed)
    if ($leaf -match '^(pagefile\.sys|hiberfil\.sys|swapfile\.sys)$') {
        return [pscustomobject]@{ NormalizedPath = $normalized; PathClass = 'PROTECTED'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Protected system-managed file' }
    }

    if ($trimmed -match '(?i)\.(vhd|vhdx)$') {
        return [pscustomobject]@{ NormalizedPath = $normalized; PathClass = 'EXTERNAL_PROTECTED'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'VHD/VHDX must not be directly modified' }
    }

    if ($trimmed -match '^[A-Za-z]:\\' -or $trimmed -match '^\\\\') {
        return [pscustomobject]@{ NormalizedPath = $normalized; PathClass = 'OBSERVED'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Phase 5 performs validation only; no path is executable' }
    }

    return [pscustomobject]@{ NormalizedPath = $normalized; PathClass = 'UNKNOWN'; Disposition = 'REJECT_NOT_EXECUTABLE'; Reason = 'Unrecognized path form' }
}

$checks = [System.Collections.Generic.List[object]]::new()
$phase4Dirs = @(Get-Phase4Directories -Root $Phase4OutputRoot)
if ($phase4Dirs.Count -eq 0) {
    Write-Host "FAIL: No Phase 4 output folder found under: $Phase4OutputRoot" -ForegroundColor Red
    exit 2
}

$latestPhase4 = $phase4Dirs[0]
$previousPhase4 = $null
if ($phase4Dirs.Count -gt 1) {
    $previousPhase4 = $phase4Dirs[1]
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$phase5Output = Join-Path $OutputRoot ("phase5_" + $stamp)
New-Item -ItemType Directory -Path $phase5Output -Force | Out-Null

Write-Host "Phase 4 input folder: $($latestPhase4.FullName)"
Write-Host "Phase 5 output folder: $phase5Output"

$config = $null
try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Config file not found: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Check -List $checks -Name 'ConfigParse' -Passed $true -Message '..\diskcare.config.json parsed successfully.'
}
catch {
    Add-Check -List $checks -Name 'ConfigParse' -Passed $false -Message $_.Exception.Message
}

if ($null -ne $config) {
    $configValid = $true
    $configMessages = [System.Collections.Generic.List[string]]::new()

    if ([int]$config.SchemaVersion -ne 1) { $configValid = $false; $configMessages.Add('SchemaVersion must be 1.') }
    if ([string]$config.ExecutionMode -ne 'HARDEN_ONLY') { $configValid = $false; $configMessages.Add('ExecutionMode must be HARDEN_ONLY.') }
    if ([bool]$config.AllowDestructiveActions -ne $false) { $configValid = $false; $configMessages.Add('AllowDestructiveActions must be false.') }
    if ([string]$config.RequiredPhase4ExecutionMode -ne 'PLAN_ONLY') { $configValid = $false; $configMessages.Add('RequiredPhase4ExecutionMode must be PLAN_ONLY.') }
    if ([string]$config.RequiredApproval -ne 'UNAPPROVED') { $configValid = $false; $configMessages.Add('RequiredApproval must be UNAPPROVED.') }
    if ([string]$config.RequiredExecutionAllowed -ne 'NO') { $configValid = $false; $configMessages.Add('RequiredExecutionAllowed must be NO.') }
    if ([string]$config.RequiredProposedAction -ne 'NONE') { $configValid = $false; $configMessages.Add('RequiredProposedAction must be NONE.') }

    $message = 'Configuration invariants are valid.'
    if ($configMessages.Count -gt 0) { $message = ($configMessages -join ' ') }
    Add-Check -List $checks -Name 'ConfigInvariants' -Passed $configValid -Message $message
}

$phase4Files = @(Get-ChildItem -LiteralPath $latestPhase4.FullName -File -Recurse -ErrorAction SilentlyContinue)
$phase4CsvFiles = @($phase4Files | Where-Object { $_.Extension -ieq '.csv' })
Add-Check -List $checks -Name 'Phase4ReportSet' -Passed ($phase4Files.Count -gt 0) -Message ("Files found: " + $phase4Files.Count)
Add-Check -List $checks -Name 'Phase4CsvSet' -Passed ($phase4CsvFiles.Count -gt 0) -Message ("CSV files found: " + $phase4CsvFiles.Count)

$allRows = [System.Collections.Generic.List[object]]::new()
$csvParseFailures = [System.Collections.Generic.List[string]]::new()
foreach ($csvFile in $phase4CsvFiles) {
    try {
        $header = Get-Content -LiteralPath $csvFile.FullName -TotalCount 1 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($header)) {
            throw 'CSV header is empty.'
        }
        $rows = @(Import-Csv -LiteralPath $csvFile.FullName -ErrorAction Stop)
        foreach ($row in $rows) {
            $row | Add-Member -NotePropertyName '__SourceCsv' -NotePropertyValue $csvFile.Name -Force
            $allRows.Add($row)
        }
    }
    catch {
        $csvParseFailures.Add("$($csvFile.Name): $($_.Exception.Message)")
    }
}
Add-Check -List $checks -Name 'CsvHeadersAndParsing' -Passed ($csvParseFailures.Count -eq 0) -Message $(if ($csvParseFailures.Count -eq 0) { 'All CSV files have readable headers.' } else { $csvParseFailures -join ' | ' })

$phase4ModeViolations = [System.Collections.Generic.List[string]]::new()
$approvalViolations = [System.Collections.Generic.List[string]]::new()
$executionViolations = [System.Collections.Generic.List[string]]::new()
$actionViolations = [System.Collections.Generic.List[string]]::new()
$reparseViolations = [System.Collections.Generic.List[string]]::new()
$pathRows = [System.Collections.Generic.List[object]]::new()

foreach ($row in $allRows) {
    $source = [string]$row.__SourceCsv

    $mode = Get-PropertyValue -Row $row -Names @('ExecutionMode')
    if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode.Trim().ToUpperInvariant() -ne 'PLAN_ONLY') {
        $phase4ModeViolations.Add("$source => ExecutionMode=$mode")
    }

    $approval = Get-PropertyValue -Row $row -Names @('Approval', 'ApprovalStatus')
    if (-not [string]::IsNullOrWhiteSpace($approval) -and $approval.Trim().ToUpperInvariant() -ne 'UNAPPROVED') {
        $approvalViolations.Add("$source => Approval=$approval")
    }

    $executionAllowed = Get-PropertyValue -Row $row -Names @('ExecutionAllowed', 'CanExecute')
    if (-not [string]::IsNullOrWhiteSpace($executionAllowed) -and $executionAllowed.Trim().ToUpperInvariant() -ne 'NO') {
        $executionViolations.Add("$source => ExecutionAllowed=$executionAllowed")
    }

    $proposedAction = Get-PropertyValue -Row $row -Names @('ProposedAction')
    if (-not [string]::IsNullOrWhiteSpace($proposedAction)) {
        $upperAction = $proposedAction.Trim().ToUpperInvariant()
        if ($upperAction -ne 'NONE') {
            $actionViolations.Add("$source => ProposedAction=$proposedAction")
        }
    }

    $genericAction = Get-PropertyValue -Row $row -Names @('Action')
    if (-not [string]::IsNullOrWhiteSpace($genericAction) -and $genericAction.Trim().ToUpperInvariant() -match 'DELETE|CLEANUP|REMOVE|PURGE|PRUNE') {
        $actionViolations.Add("$source => destructive Action=$genericAction")
    }

    $isReparse = Get-PropertyValue -Row $row -Names @('IsReparsePoint', 'ReparsePoint')
    $evidenceType = Get-PropertyValue -Row $row -Names @('EvidenceType', 'Type', 'Reason')
    $decision = Get-PropertyValue -Row $row -Names @('Decision', 'Disposition', 'Classification', 'Status', 'PlanDisposition', 'SafetyDisposition', 'SafetyDecision', 'Recommendation')
    $looksReparse = (Test-Truthy -Value $isReparse) -or ((-not [string]::IsNullOrWhiteSpace($evidenceType)) -and $evidenceType -match '(?i)reparse|junction|symlink')
    if ($looksReparse) {
        $explicitlyExcluded = (-not [string]::IsNullOrWhiteSpace($decision)) -and ($decision -match '(?i)EXCLUDE_DO_NOT_TOUCH|DO_NOT_TOUCH|EXCLUDE|REPARSE')
        $safelyNonExecutable = (-not [string]::IsNullOrWhiteSpace($executionAllowed)) -and ($executionAllowed.Trim().ToUpperInvariant() -eq 'NO') -and ([string]::IsNullOrWhiteSpace($proposedAction) -or $proposedAction.Trim().ToUpperInvariant() -eq 'NONE')
        if (-not $explicitlyExcluded -and -not $safelyNonExecutable) {
            $reparseViolations.Add("$source => reparse evidence is not explicitly excluded/non-executable")
        }
    }

    $pathValue = Get-PropertyValue -Row $row -Names @('ResolvedPath', 'TargetPath', 'Path', 'FullPath', 'Directory', 'FilePath')
    if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
        $disp = Get-PathDisposition -PathValue $pathValue
        $pathRows.Add([pscustomobject]@{
            SourceCsv = $source
            OriginalPath = $pathValue
            NormalizedPath = $disp.NormalizedPath
            PathClass = $disp.PathClass
            Phase5Disposition = $disp.Disposition
            ExecutionAllowed = 'NO'
            Reason = $disp.Reason
        })
    }
}

Add-Check -List $checks -Name 'Phase4ExecutionMode' -Passed ($phase4ModeViolations.Count -eq 0) -Message $(if ($phase4ModeViolations.Count -eq 0) { 'No non-PLAN_ONLY rows found.' } else { $phase4ModeViolations -join ' | ' })
Add-Check -List $checks -Name 'Phase4ApprovalDefault' -Passed ($approvalViolations.Count -eq 0) -Message $(if ($approvalViolations.Count -eq 0) { 'No approved rows found.' } else { $approvalViolations -join ' | ' })
Add-Check -List $checks -Name 'Phase4ExecutionAllowed' -Passed ($executionViolations.Count -eq 0) -Message $(if ($executionViolations.Count -eq 0) { 'No executable rows found.' } else { $executionViolations -join ' | ' })
Add-Check -List $checks -Name 'DeletionCleanupActions' -Passed ($actionViolations.Count -eq 0 -and $DeletionCleanupActions -eq 0) -Message $(if ($actionViolations.Count -eq 0) { 'Deletion/Cleanup actions = 0.' } else { $actionViolations -join ' | ' })
Add-Check -List $checks -Name 'ReparseExclusion' -Passed ($reparseViolations.Count -eq 0) -Message $(if ($reparseViolations.Count -eq 0) { 'Reparse evidence remains non-executable/excluded.' } else { $reparseViolations -join ' | ' })
Add-Check -List $checks -Name 'UnknownPathRejection' -Passed $true -Message 'Every observed path is emitted as REJECT_NOT_EXECUTABLE in Phase 5.'

$browserRows = [System.Collections.Generic.List[object]]::new()
$browserNames = @('chrome', 'msedge', 'firefox', 'brave')
if ($null -ne $config -and $null -ne $config.BrowserProcesses) {
    $browserNames = @($config.BrowserProcesses)
}
foreach ($browser in $browserNames) {
    $processes = @(Get-Process -Name $browser -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        $browserRows.Add([pscustomobject]@{
            ProcessName = $process.ProcessName
            PID = $process.Id
            Running = 'YES'
            Warning = 'Browser is running; cache files may be locked. Phase 5 does not close the process.'
        })
    }
}
Add-Check -List $checks -Name 'BrowserLockDetection' -Passed $true -Message $(if ($browserRows.Count -gt 0) { "Running browser processes detected: $($browserRows.Count). Warning report created." } else { 'No configured browser process is currently running.' })

$latestStats = Get-ReportStats -Directory $latestPhase4
$comparisonRows = [System.Collections.Generic.List[object]]::new()
if ($null -ne $previousPhase4) {
    $previousStats = Get-ReportStats -Directory $previousPhase4
    $comparisonRows.Add([pscustomobject]@{
        Metric = 'FileCount'
        Previous = $previousStats.FileCount
        Current = $latestStats.FileCount
        Delta = ($latestStats.FileCount - $previousStats.FileCount)
        PreviousFolder = $previousPhase4.FullName
        CurrentFolder = $latestPhase4.FullName
    })
    $comparisonRows.Add([pscustomobject]@{
        Metric = 'CsvRowCount'
        Previous = $previousStats.CsvRowCount
        Current = $latestStats.CsvRowCount
        Delta = ($latestStats.CsvRowCount - $previousStats.CsvRowCount)
        PreviousFolder = $previousPhase4.FullName
        CurrentFolder = $latestPhase4.FullName
    })
    $comparisonRows.Add([pscustomobject]@{
        Metric = 'TotalReportBytes'
        Previous = $previousStats.TotalReportBytes
        Current = $latestStats.TotalReportBytes
        Delta = ($latestStats.TotalReportBytes - $previousStats.TotalReportBytes)
        PreviousFolder = $previousPhase4.FullName
        CurrentFolder = $latestPhase4.FullName
    })
}
else {
    $comparisonRows.Add([pscustomobject]@{
        Metric = 'BaselineOnly'
        Previous = ''
        Current = $latestStats.FileCount
        Delta = ''
        PreviousFolder = ''
        CurrentFolder = $latestPhase4.FullName
    })
}
Add-Check -List $checks -Name 'ReportComparison' -Passed $true -Message $(if ($null -ne $previousPhase4) { 'Compared latest Phase 4 report set with previous report set.' } else { 'Only one Phase 4 report set exists; baseline comparison row created.' })

$failedChecks = @($checks.ToArray() | Where-Object { $_.Result -eq 'FAIL' })
$gateResult = $(if ($failedChecks.Count -eq 0) { 'PASS' } else { 'FAIL' })

$checksPath = Join-Path $phase5Output 'phase5_checks.csv'
$pathsPath = Join-Path $phase5Output 'path_validation.csv'
$browsersPath = Join-Path $phase5Output 'browser_lock_warnings.csv'
$comparisonPath = Join-Path $phase5Output 'report_comparison.csv'

Export-CsvSafe -Rows ($checks.ToArray()) -Headers @('Check', 'Result', 'Message') -Path $checksPath
Export-CsvSafe -Rows ($pathRows.ToArray()) -Headers @('SourceCsv', 'OriginalPath', 'NormalizedPath', 'PathClass', 'Phase5Disposition', 'ExecutionAllowed', 'Reason') -Path $pathsPath
Export-CsvSafe -Rows ($browserRows.ToArray()) -Headers @('ProcessName', 'PID', 'Running', 'Warning') -Path $browsersPath
Export-CsvSafe -Rows ($comparisonRows.ToArray()) -Headers @('Metric', 'Previous', 'Current', 'Delta', 'PreviousFolder', 'CurrentFolder') -Path $comparisonPath

$summaryObject = [ordered]@{
    Phase = 5
    Name = 'Hardening & Portability'
    GeneratedAt = (Get-Date).ToString('o')
    ExecutionMode = $ExecutionMode
    AllowDestructiveActions = $AllowDestructiveActions
    DeletionCleanupActions = $DeletionCleanupActions
    GateResult = $gateResult
    Phase4Input = $latestPhase4.FullName
    Phase4PreviousInput = $(if ($null -ne $previousPhase4) { $previousPhase4.FullName } else { $null })
    Phase4FileCount = $latestStats.FileCount
    Phase4CsvFileCount = $latestStats.CsvFileCount
    Phase4CsvRowCount = $latestStats.CsvRowCount
    Phase4InvalidCsvCount = $latestStats.InvalidCsvCount
    ObservedPathCount = $pathRows.Count
    BrowserWarnings = $browserRows.Count
    FailedCheckCount = $failedChecks.Count
    ReleaseEligible = $(if ($gateResult -eq 'PASS') { 'YES_FOR_RELEASE_CONSOLIDATION' } else { 'NO' })
    SafetyNote = 'Phase 5 is HARDEN_ONLY. Every observed path remains non-executable.'
}

$summaryJsonPath = Join-Path $phase5Output 'phase5_summary.json'
$summaryTxtPath = Join-Path $phase5Output 'phase5_summary.txt'
$summaryObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryJsonPath -Encoding UTF8

$summaryLines = @(
    'DISK-CARE CLEANUP HARDENING - HARDENING SUMMARY',
    ('Generated: ' + $summaryObject.GeneratedAt),
    ('Phase 4 input: ' + $summaryObject.Phase4Input),
    ('Execution mode: ' + $summaryObject.ExecutionMode),
    ('Allow destructive actions: ' + $summaryObject.AllowDestructiveActions),
    ('Deletion/Cleanup actions: ' + $summaryObject.DeletionCleanupActions),
    ('Gate result: ' + $summaryObject.GateResult),
    ('Phase 4 files: ' + $summaryObject.Phase4FileCount),
    ('Phase 4 CSV files: ' + $summaryObject.Phase4CsvFileCount),
    ('Phase 4 CSV rows: ' + $summaryObject.Phase4CsvRowCount),
    ('Observed paths: ' + $summaryObject.ObservedPathCount),
    ('Browser warnings: ' + $summaryObject.BrowserWarnings),
    ('Release eligible: ' + $summaryObject.ReleaseEligible),
    '',
    'Safety: every observed path is REJECT_NOT_EXECUTABLE in Phase 5.'
)
Set-Content -LiteralPath $summaryTxtPath -Value $summaryLines -Encoding UTF8

$packageRoot = Join-Path $phase5Output 'portable_package'
$packageFolder = Join-Path $packageRoot 'DiskCare-Phase5-Hardening'
New-Item -ItemType Directory -Path $packageFolder -Force | Out-Null

$sourceFiles = @(
    'CLEANUP_HARDEN.cmd',
    'CLEANUP_HARDEN_ENGINE.ps1',
    'HARDEN_SAFETY_CHECK.ps1',
    'PHASE5_ACCEPTANCE_CHECK.cmd',
    'PHASE5_ACCEPTANCE_CHECK.ps1',
    'PHASE5_REGRESSION_TESTS.ps1',
    '..\diskcare.config.json',
    'README_PHASE5.md'
)
foreach ($name in $sourceFiles) {
    $sourcePath = Join-Path $ScriptRoot $name
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $packageFolder $name) -Force
    }
}

# Portable packages must never embed the real machine's Phase 4/5 runtime paths.
# Create a small synthetic sample set instead of copying runtime reports.
$reportFolder = Join-Path $packageFolder 'sample_output_summary'
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
try {
    $sampleSummary = [ordered]@{
        Phase = 5
        Name = 'Hardening & Portability'
        GeneratedAt = '<SANITIZED_TIMESTAMP>'
        ExecutionMode = 'HARDEN_ONLY'
        AllowDestructiveActions = $false
        DeletionCleanupActions = 0
        GateResult = 'PASS'
        Phase4Input = '<SANITIZED_PHASE4_OUTPUT>'
        Phase4PreviousInput = $null
        Phase4FileCount = 0
        Phase4CsvFileCount = 0
        Phase4CsvRowCount = 0
        Phase4InvalidCsvCount = 0
        ObservedPathCount = 1
        BrowserWarnings = 0
        FailedCheckCount = 0
        ReleaseEligible = 'YES_FOR_RELEASE_CONSOLIDATION'
        SafetyNote = 'Synthetic sample only. No real-machine runtime paths are included.'
    }
    $sampleSummary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportFolder 'phase5_summary.json') -Encoding UTF8

    $sampleSummaryLines = @(
        'DISK-CARE CLEANUP HARDENING - SANITIZED SAMPLE SUMMARY',
        'Generated: <SANITIZED_TIMESTAMP>',
        'Phase 4 input: <SANITIZED_PHASE4_OUTPUT>',
        'Execution mode: HARDEN_ONLY',
        'Allow destructive actions: False',
        'Deletion/Cleanup actions: 0',
        'Gate result: PASS',
        'Observed paths: 1',
        'Release eligible: YES_FOR_RELEASE_CONSOLIDATION',
        '',
        'This is synthetic sample data. It does not contain runtime paths from the machine that built the package.'
    )
    Set-Content -LiteralPath (Join-Path $reportFolder 'phase5_summary.txt') -Value $sampleSummaryLines -Encoding UTF8

    $sampleChecks = @(
        [pscustomobject]@{ Check = 'ConfigInvariants'; Result = 'PASS'; Message = 'Synthetic sample: hardening invariants are valid.' },
        [pscustomobject]@{ Check = 'DeletionCleanupActions'; Result = 'PASS'; Message = 'Deletion/Cleanup actions = 0.' },
        [pscustomobject]@{ Check = 'PortableZip'; Result = 'PASS'; Message = 'Synthetic sample: portable ZIP creation passed.' }
    )
    Export-CsvSafe -Rows $sampleChecks -Headers @('Check', 'Result', 'Message') -Path (Join-Path $reportFolder 'phase5_checks.csv')

    $samplePaths = @(
        [pscustomobject]@{
            SourceCsv = 'sample_plan.csv'
            OriginalPath = 'C:\Users\Sample\AppData\Local\Temp\cache'
            NormalizedPath = 'C:\Users\Sample\AppData\Local\Temp\cache'
            PathClass = 'OBSERVED'
            Phase5Disposition = 'REJECT_NOT_EXECUTABLE'
            ExecutionAllowed = 'NO'
            Reason = 'Synthetic sample only; Phase 5 performs validation only.'
        }
    )
    Export-CsvSafe -Rows $samplePaths -Headers @('SourceCsv', 'OriginalPath', 'NormalizedPath', 'PathClass', 'Phase5Disposition', 'ExecutionAllowed', 'Reason') -Path (Join-Path $reportFolder 'path_validation.csv')
    Export-CsvSafe -Rows @() -Headers @('ProcessName', 'PID', 'Running', 'Warning') -Path (Join-Path $reportFolder 'browser_lock_warnings.csv')

    $sampleComparison = @(
        [pscustomobject]@{
            Metric = 'BaselineOnly'
            Previous = ''
            Current = '0'
            Delta = ''
            PreviousFolder = '<SANITIZED_PREVIOUS_PHASE4>'
            CurrentFolder = '<SANITIZED_PHASE4_OUTPUT>'
        }
    )
    Export-CsvSafe -Rows $sampleComparison -Headers @('Metric', 'Previous', 'Current', 'Delta', 'PreviousFolder', 'CurrentFolder') -Path (Join-Path $reportFolder 'report_comparison.csv')

    Set-Content -LiteralPath (Join-Path $reportFolder 'README_SAMPLE.txt') -Encoding UTF8 -Value @(
        'DISK-CARE CLEANUP HARDENING - SANITIZED SAMPLE OUTPUT',
        '',
        'All files in this folder are synthetic examples.',
        'No runtime Phase 4 paths, Phase 5 output paths, browser PIDs, or real-machine scan rows are copied into the portable package.',
        'The runtime phase5_manifest.txt is generated only in the real Phase 5 output folder.'
    )

    Add-Check -List $checks -Name 'PortableSampleSanitization' -Passed $true -Message 'Portable sample output is synthetic and does not copy runtime report rows.'
}
catch {
    Add-Check -List $checks -Name 'PortableSampleSanitization' -Passed $false -Message $_.Exception.Message
}

$zipPath = Join-Path $phase5Output ("DiskCare-Phase5-Hardening_" + $stamp + '.zip')
try {
    Compress-Archive -LiteralPath $packageFolder -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop
    Add-Check -List $checks -Name 'PortableZip' -Passed $true -Message ("Portable ZIP created: " + $zipPath)
}
catch {
    Add-Check -List $checks -Name 'PortableZip' -Passed $false -Message $_.Exception.Message
}

# Finalize checks and summary only after portable-package creation.
$failedChecks = @($checks.ToArray() | Where-Object { $_.Result -eq 'FAIL' })
$gateResult = $(if ($failedChecks.Count -eq 0) { 'PASS' } else { 'FAIL' })
Export-CsvSafe -Rows ($checks.ToArray()) -Headers @('Check', 'Result', 'Message') -Path $checksPath

$summaryObject.GateResult = $gateResult
$summaryObject.FailedCheckCount = $failedChecks.Count
$summaryObject.ReleaseEligible = $(if ($gateResult -eq 'PASS') { 'YES_FOR_RELEASE_CONSOLIDATION' } else { 'NO' })
$summaryObject | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryJsonPath -Encoding UTF8
$summaryLines[6] = ('Gate result: ' + $summaryObject.GateResult)
$summaryLines[12] = ('Release eligible: ' + $summaryObject.ReleaseEligible)
Set-Content -LiteralPath $summaryTxtPath -Value $summaryLines -Encoding UTF8

# Manifest is intentionally generated LAST. It covers every final top-level output
# artifact except itself, including the completed portable ZIP.
$manifestPath = Join-Path $phase5Output 'phase5_manifest.txt'
$manifestLines = [System.Collections.Generic.List[string]]::new()
$manifestLines.Add('DISK-CARE CLEANUP HARDENING - MANIFEST')
$manifestLines.Add(('Generated: ' + (Get-Date).ToString('o')))
$manifestLines.Add(('Phase4Input: ' + $latestPhase4.FullName))
$manifestLines.Add('IntegrityScope: all final top-level files except phase5_manifest.txt')
$manifestLines.Add('')
$manifestFiles = @(Get-ChildItem -LiteralPath $phase5Output -File -ErrorAction Stop |
    Where-Object { $_.Name -ne 'phase5_manifest.txt' } |
    Sort-Object Name)
foreach ($file in $manifestFiles) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $manifestLines.Add("$($file.Name)`t$($file.Length)`t$hash")
}
Set-Content -LiteralPath $manifestPath -Value $manifestLines -Encoding UTF8

Write-Host ''
foreach ($check in $checks) {
    if ($check.Result -eq 'PASS') {
        Write-Host ("PASS: " + $check.Check + ' - ' + $check.Message)
    }
    else {
        Write-Host ("FAIL: " + $check.Check + ' - ' + $check.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host ("Phase 5 gate: " + $gateResult) -ForegroundColor $(if ($gateResult -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host ("Portable ZIP: " + $zipPath)

if ($gateResult -ne 'PASS') {
    exit 3
}
exit 0
