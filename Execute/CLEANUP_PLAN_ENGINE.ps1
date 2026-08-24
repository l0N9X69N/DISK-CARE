[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Phase3Output,

    [Parameter(Position = 1)]
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-FirstPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Row.PSObject.Properties[$name]
        if ($null -ne $property) {
            $value = [string]$property.Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value.Trim()
            }
        }
    }
    return ''
}

function Get-LatestPhase3Output {
    $phase3Root = Resolve-FullPath (Join-Path $PSScriptRoot '..\Output\Analyze')
    if (-not (Test-Path -LiteralPath $phase3Root -PathType Container)) {
        throw "Phase 3 output root was not found: $phase3Root"
    }

    $latest = Get-ChildItem -LiteralPath $phase3Root -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like 'phase3_*' } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "No phase3_* output folder was found under: $phase3Root"
    }

    return $latest.FullName
}

function Get-CsvFirstRow {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return @(Import-Csv -LiteralPath $Path -ErrorAction Stop | Select-Object -First 1)
    }
    catch {
        return @()
    }
}

function Find-CandidateMatrix {
    param([Parameter(Mandatory = $true)][string]$Root)

    $csvFiles = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Filter '*.csv' -ErrorAction Stop)
    if ($csvFiles.Count -eq 0) {
        throw "No CSV report was found in Phase 3 output: $Root"
    }

    $preferred = @($csvFiles | Where-Object { $_.Name -match '(?i)candidate.*matrix|matrix.*candidate' } | Sort-Object LastWriteTimeUtc -Descending)
    if ($preferred.Count -gt 0) {
        return $preferred[0].FullName
    }

    $candidateNamed = @($csvFiles | Where-Object { $_.Name -match '(?i)candidate' } | Sort-Object LastWriteTimeUtc -Descending)
    if ($candidateNamed.Count -gt 0) {
        return $candidateNamed[0].FullName
    }

    foreach ($csv in ($csvFiles | Sort-Object LastWriteTimeUtc -Descending)) {
        $first = @(Get-CsvFirstRow -Path $csv.FullName)
        if ($first.Count -eq 0) {
            continue
        }
        if ($null -ne $first[0].PSObject.Properties['Path']) {
            return $csv.FullName
        }
    }

    throw 'No Phase 3 CSV with a recognizable candidate matrix could be identified.'
}

function Add-ProtectedPathsFromReport {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.HashSet[string]]$Set,
        [Parameter(Mandatory = $true)][string]$ReportPath
    )

    try {
        foreach ($row in @(Import-Csv -LiteralPath $ReportPath -ErrorAction Stop)) {
            $pathValue = Get-FirstPropertyValue -Row $row -Names @('Path', 'FullPath', 'TargetPath')
            if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
                [void]$Set.Add($pathValue)
            }
        }
    }
    catch {
        Write-Warning "Could not read protection evidence report: $ReportPath"
    }
}

if ([string]::IsNullOrWhiteSpace($Phase3Output)) {
    $Phase3Output = Get-LatestPhase3Output
}
else {
    $Phase3Output = Resolve-FullPath $Phase3Output
}

if (-not (Test-Path -LiteralPath $Phase3Output -PathType Container)) {
    throw "Phase 3 output folder does not exist: $Phase3Output"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot '..\Output\Plan'
}
$OutputRoot = Resolve-FullPath $OutputRoot

$phase3Normalized = $Phase3Output.TrimEnd([char[]]@('\', '/'))
$outputNormalized = $OutputRoot.TrimEnd([char[]]@('\', '/'))
$phase3Prefix = $phase3Normalized + [System.IO.Path]::DirectorySeparatorChar
if ($outputNormalized.Equals($phase3Normalized, [System.StringComparison]::OrdinalIgnoreCase) -or
    $outputNormalized.StartsWith($phase3Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputRoot must not be the Phase 3 output folder or a child of it.'
}

if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputFolder = Join-Path $OutputRoot ("phase4_{0}" -f $stamp)
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

$candidateMatrix = Find-CandidateMatrix -Root $Phase3Output
$candidateRows = @(Import-Csv -LiteralPath $candidateMatrix -ErrorAction Stop)

$protectedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$protectionEvidenceRows = New-Object System.Collections.Generic.List[object]
$evidenceReports = @(Get-ChildItem -LiteralPath $Phase3Output -File -Recurse -Filter '*.csv' -ErrorAction Stop |
    Where-Object { $_.Name -match '(?i)reparse|error' })
foreach ($report in $evidenceReports) {
    Add-ProtectedPathsFromReport -Set $protectedPaths -ReportPath $report.FullName
    try {
        foreach ($evidenceRow in @(Import-Csv -LiteralPath $report.FullName -ErrorAction Stop)) {
            $evidencePath = Get-FirstPropertyValue -Row $evidenceRow -Names @('Path', 'FullPath', 'TargetPath')
            if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
                $evidenceType = 'PROTECTED_EVIDENCE'
                if ($report.Name -match '(?i)reparse') { $evidenceType = 'REPARSE_EVIDENCE' }
                elseif ($report.Name -match '(?i)error') { $evidenceType = 'ERROR_EVIDENCE' }
                $protectionEvidenceRows.Add([pscustomobject][ordered]@{
                    Path = $evidencePath
                    EvidenceType = $evidenceType
                    EvidenceSource = $report.Name
                }) | Out-Null
            }
        }
    }
    catch {
        Write-Warning "Could not snapshot protection evidence report: $($report.FullName)"
    }
}

$planRows = New-Object System.Collections.Generic.List[object]
$seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$duplicateCount = 0

foreach ($row in $candidateRows) {
    $pathValue = Get-FirstPropertyValue -Row $row -Names @('Path', 'FullPath', 'TargetPath')
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
        continue
    }

    if (-not $seenPaths.Add($pathValue)) {
        $duplicateCount++
        continue
    }

    $sourceDecision = Get-FirstPropertyValue -Row $row -Names @('Decision', 'Recommendation', 'Classification', 'CandidateDecision', 'PlanDecision')
    $sourceReason = Get-FirstPropertyValue -Row $row -Names @('Reason', 'Evidence', 'Rationale', 'Notes', 'Explanation')
    $sizeBytes = Get-FirstPropertyValue -Row $row -Names @('SizeBytes', 'Bytes', 'Length', 'Size')
    $attributes = Get-FirstPropertyValue -Row $row -Names @('Attributes', 'FileAttributes', 'Flags')
    $reparseFlag = Get-FirstPropertyValue -Row $row -Names @('IsReparsePoint', 'ReparsePoint', 'IsReparse', 'Reparse')
    $sourceError = Get-FirstPropertyValue -Row $row -Names @('Error', 'ErrorMessage', 'Exception')

    $combined = "{0} {1} {2} {3}" -f $sourceDecision, $sourceReason, $attributes, $reparseFlag
    $isProtectedEvidence = $protectedPaths.Contains($pathValue)
    $isReparse = $isProtectedEvidence -or ($combined -match '(?i)reparse|do_not_touch|do not touch|symlink|junction')
    $isSourceProtected = $sourceDecision -match '(?i)do_not_touch|do not touch|keep|exclude|protected|blocked'
    $hasSourceError = (-not [string]::IsNullOrWhiteSpace($sourceError)) -or ($sourceDecision -match '(?i)error|failed')

    $planDecision = 'REVIEW_FOR_APPROVAL'
    $holdReason = 'Candidate is carried forward for human review only.'

    if ($isReparse) {
        $planDecision = 'EXCLUDE_DO_NOT_TOUCH'
        $holdReason = 'Reparse/symlink/junction evidence is protected and excluded.'
    }
    elseif ($isSourceProtected) {
        $planDecision = 'EXCLUDE_SOURCE_PROTECTED'
        $holdReason = 'Phase 3 source decision indicates the path is protected or excluded.'
    }
    elseif ($hasSourceError) {
        $planDecision = 'EXCLUDE_SOURCE_ERROR'
        $holdReason = 'Source diagnostics contain an error; no cleanup consideration is allowed.'
    }
    elseif ([string]::IsNullOrWhiteSpace($sourceDecision)) {
        $planDecision = 'HOLD_MISSING_DECISION'
        $holdReason = 'Phase 3 decision is missing; manual classification is required.'
    }

    $planRows.Add([pscustomobject][ordered]@{
        Path              = $pathValue
        SizeBytes         = $sizeBytes
        Phase3Decision    = $sourceDecision
        Phase3Reason      = $sourceReason
        PlanDecision      = $planDecision
        HoldReason        = $holdReason
        ApprovalState     = 'UNAPPROVED'
        ExecutionAllowed  = 'NO'
        ProposedAction    = 'NONE'
        Reviewer          = ''
        ReviewNote        = ''
        SourceMatrix      = [System.IO.Path]::GetFileName($candidateMatrix)
    }) | Out-Null
}

$planPath = Join-Path $outputFolder 'cleanup_plan.csv'
$approvalPath = Join-Path $outputFolder 'approval_template.csv'
$summaryPath = Join-Path $outputFolder 'phase4_summary.txt'
$manifestPath = Join-Path $outputFolder 'phase4_manifest.txt'
$snapshotPath = Join-Path $outputFolder 'phase3_candidate_source_snapshot.csv'
$protectionPath = Join-Path $outputFolder 'protection_evidence_paths.csv'

$planHeaders = 'Path,SizeBytes,Phase3Decision,Phase3Reason,PlanDecision,HoldReason,ApprovalState,ExecutionAllowed,ProposedAction,Reviewer,ReviewNote,SourceMatrix'
if ($planRows.Count -gt 0) {
    $planRows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
    $planRows | Export-Csv -LiteralPath $approvalPath -NoTypeInformation -Encoding UTF8
}
else {
    Set-Content -LiteralPath $planPath -Value $planHeaders -Encoding UTF8
    Set-Content -LiteralPath $approvalPath -Value $planHeaders -Encoding UTF8
}

Copy-Item -LiteralPath $candidateMatrix -Destination $snapshotPath -Force

$protectionHeaders = 'Path,EvidenceType,EvidenceSource'
$uniqueProtectionRows = @($protectionEvidenceRows | Sort-Object Path, EvidenceType, EvidenceSource -Unique)
if ($uniqueProtectionRows.Count -gt 0) {
    $uniqueProtectionRows | Export-Csv -LiteralPath $protectionPath -NoTypeInformation -Encoding UTF8
}
else {
    Set-Content -LiteralPath $protectionPath -Value $protectionHeaders -Encoding UTF8
}

$reviewCount = @($planRows | Where-Object { $_.PlanDecision -eq 'REVIEW_FOR_APPROVAL' }).Count
$excludedCount = @($planRows | Where-Object { $_.PlanDecision -like 'EXCLUDE_*' }).Count
$holdCount = @($planRows | Where-Object { $_.PlanDecision -like 'HOLD_*' }).Count

$summary = @(
    'DISK-CARE CLEANUP PLAN - CONTROLLED CLEANUP PLANNING',
    ('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
    ('Phase 3 input: {0}' -f $Phase3Output),
    ('Candidate source: {0}' -f $candidateMatrix),
    'Execution mode: PLAN_ONLY',
    'Deletion/Cleanup actions = 0',
    'Approval default: UNAPPROVED',
    'Execution allowed default: NO',
    ('Unique paths planned: {0}' -f $planRows.Count),
    ('Review for approval: {0}' -f $reviewCount),
    ('Excluded: {0}' -f $excludedCount),
    ('Held: {0}' -f $holdCount),
    ('Duplicate source paths ignored: {0}' -f $duplicateCount),
    ('Protection evidence reports read: {0}' -f $evidenceReports.Count),
    '',
    'Phase 4 never performs deletion. It only creates a review/approval plan.'
)
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8

$manifestLines = New-Object System.Collections.Generic.List[string]
$manifestLines.Add('DISK-CARE CLEANUP PLAN MANIFEST') | Out-Null
$manifestLines.Add(('Generated={0}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'))) | Out-Null
$manifestLines.Add(('Phase3Input={0}' -f $Phase3Output)) | Out-Null
$manifestLines.Add(('CandidateSource={0}' -f $candidateMatrix)) | Out-Null
$manifestLines.Add('ExecutionMode=PLAN_ONLY') | Out-Null
$manifestLines.Add('DeletionCleanupActions=0') | Out-Null
$manifestLines.Add('DefaultApprovalState=UNAPPROVED') | Out-Null
$manifestLines.Add('DefaultExecutionAllowed=NO') | Out-Null
$manifestLines.Add('') | Out-Null

foreach ($file in @($planPath, $approvalPath, $summaryPath, $snapshotPath, $protectionPath)) {
    $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
    $manifestLines.Add(('{0}  {1}' -f $hash.Hash, [System.IO.Path]::GetFileName($file))) | Out-Null
}
Set-Content -LiteralPath $manifestPath -Value $manifestLines -Encoding UTF8

Write-Host '============================================================'
Write-Host 'DISK-CARE CLEANUP PLAN - CONTROLLED CLEANUP PLANNING'
Write-Host '============================================================'
Write-Host ("Phase 3 input: {0}" -f $Phase3Output)
Write-Host ("Candidate source: {0}" -f $candidateMatrix)
Write-Host ("Phase 4 output: {0}" -f $outputFolder)
Write-Host ("Unique paths planned: {0}" -f $planRows.Count)
Write-Host ("Review for approval: {0}" -f $reviewCount)
Write-Host ("Excluded/Held: {0}" -f ($excludedCount + $holdCount))
Write-Host 'Execution mode: PLAN_ONLY'
Write-Host 'Deletion/Cleanup actions = 0'
Write-Host 'PASS: Phase 4 planning reports generated.'
