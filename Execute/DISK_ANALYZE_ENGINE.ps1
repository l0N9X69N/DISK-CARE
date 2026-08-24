[CmdletBinding()]
param(
    [string]$InputDir,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$Phase3ExecutionMode = 'ANALYZE_ONLY'
$PhaseName = 'DISK-CARE ANALYSIS'

function Get-FirstMatchingColumn {
    param(
        [string[]]$Columns,
        [string[]]$Candidates
    )
    foreach ($candidate in $Candidates) {
        $match = $Columns | Where-Object { $_ -ieq $candidate } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $null
}

function Convert-SizeValueToBytes {
    param(
        [object]$Value,
        [string]$ColumnName
    )
    if ($null -eq $Value) { return 0L }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return 0L }

    $clean = $text -replace '[^0-9.,-]', ''
    $isUnitColumn = $ColumnName -match '(?i)(GiB|GB|MiB|MB|KiB|KB)$'
    if ($isUnitColumn -and $clean -match '^[-]?[0-9]+,[0-9]+$' -and $clean -notmatch '\.') {
        $clean = $clean -replace ',', '.'
    }

    $number = 0.0
    $parsed = [double]::TryParse(
        $clean,
        [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )
    if (-not $parsed) {
        $cleanDot = $clean -replace ',', '.'
        $parsed = [double]::TryParse(
            $cleanDot,
            [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$number
        )
    }
    if (-not $parsed -or $number -le 0) { return 0L }

    switch -Regex ($ColumnName) {
        '(?i)(SizeGiB|SizeGB|GiB|GB)$' { return [Int64][math]::Round($number * 1GB) }
        '(?i)(SizeMiB|SizeMB|MiB|MB)$' { return [Int64][math]::Round($number * 1MB) }
        '(?i)(SizeKiB|SizeKB|KiB|KB)$' { return [Int64][math]::Round($number * 1KB) }
        default { return [Int64][math]::Round($number) }
    }
}

function Normalize-DiskCarePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $p = $Path.Trim().Replace('/', '\')
    while ($p.Length -gt 3 -and $p.EndsWith('\')) {
        $p = $p.Substring(0, $p.Length - 1)
    }
    return $p.ToLowerInvariant()
}

function Test-SystemManagedPath {
    param([string]$NormalizedPath)

    if ([string]::IsNullOrWhiteSpace($NormalizedPath)) { return $false }

    if ($NormalizedPath -match '^[a-z]:\\windows(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\program files(?: \(x86\))?(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\programdata(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\boot(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\recovery(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\system volume information(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\\$recycle\.bin(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\documents and settings(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\(?:pagefile\.sys|hiberfil\.sys|swapfile\.sys|dumpstack\.log(?:\.tmp)?|bootmgr|bootnxt|ntldr|bootsect\.bak)$' -or
        $NormalizedPath -match '^[a-z]:\\(?:\$winreagent|config\.msi)(?:$|\\)') {
        return $true
    }

    if ($NormalizedPath -match '^[a-z]:\\users\\[^\\]+\\appdata\\local\\microsoft\\windowsapps(?:$|\\)' -or
        $NormalizedPath -match '^[a-z]:\\users\\[^\\]+\\appdata\\local\\programs(?:$|\\)') {
        return $true
    }

    return $false
}

function Test-ProtectedUserDataPath {
    param([string]$NormalizedPath)
    if ([string]::IsNullOrWhiteSpace($NormalizedPath)) { return $false }

    return ($NormalizedPath -match '^[a-z]:\\users\\[^\\]+\\(?:desktop|documents|pictures|videos|music|onedrive(?: - [^\\]+)?|dropbox)(?:$|\\)')
}

function Test-CacheLikePath {
    param([string]$NormalizedPath)
    if ([string]::IsNullOrWhiteSpace($NormalizedPath)) { return $false }

    $patterns = @(
        '\\appdata\\local\\temp(?:$|\\)',
        '\\inetcache(?:$|\\)',
        '\\cache(?:$|\\)',
        '\\code cache(?:$|\\)',
        '\\gpu cache(?:$|\\)',
        '\\localcache(?:$|\\)',
        '\\shadercache(?:$|\\)',
        '\\npm-cache(?:$|\\)',
        '\\pip\\cache(?:$|\\)',
        '\\.gradle\\caches(?:$|\\)',
        '\\nuget\\packages(?:$|\\)',
        '\\cacheddata(?:$|\\)',
        '\\cachedextensionvsixs(?:$|\\)',
        '\\.cache(?:$|\\)',
        '\\[^\\]+[_-]cache(?:$|\\)',
        '\\appdata\\local\\[^\\]+\\tmp(?:$|\\)'
    )

    foreach ($pattern in $patterns) {
        if ($NormalizedPath -match $pattern) { return $true }
    }
    return $false
}

function Get-Phase3Classification {
    param(
        [string]$Path,
        [Int64]$SizeBytes,
        [string[]]$SourceReports
    )

    $p = Normalize-DiskCarePath -Path $Path
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $sources = @($SourceReports | ForEach-Object { ([string]$_).ToLowerInvariant() })

    $hasReparseEvidence = $false
    $hasErrorEvidence = $false
    $hasCacheSourceEvidence = $false

    foreach ($source in $sources) {
        if ($source -match 'reparse') { $hasReparseEvidence = $true }
        if ($source -match 'error') { $hasErrorEvidence = $true }
        if ($source -match '^cache_candidates_' -and $source -notmatch 'error' -and $source -notmatch 'reparse') {
            $hasCacheSourceEvidence = $true
        }
    }

    # Evidence that a path is a reparse point is a hard stop. Never treat it as a cleanup candidate.
    if ($hasReparseEvidence) {
        return [pscustomobject]@{
            Category = 'REPARSE_POINT'
            Risk = 'CRITICAL'
            Decision = 'DO_NOT_TOUCH'
            Reason = 'Phase 2 identified this path as a reparse point. Phase 3 never follows or cleans reparse targets.'
        }
    }

    # Scan/access errors are diagnostic evidence, not cleanup candidates.
    if ($hasErrorEvidence) {
        return [pscustomobject]@{
            Category = 'SCAN_ERROR'
            Risk = 'HIGH'
            Decision = 'DO_NOT_TOUCH'
            Reason = 'Path came from an error report. Error rows are diagnostic only and are excluded from cleanup review.'
        }
    }

    if (Test-SystemManagedPath -NormalizedPath $p) {
        return [pscustomobject]@{
            Category = 'PROTECTED_SYSTEM'
            Risk = 'CRITICAL'
            Decision = 'DO_NOT_TOUCH'
            Reason = 'System or application-managed path.'
        }
    }

    if (Test-ProtectedUserDataPath -NormalizedPath $p) {
        return [pscustomobject]@{
            Category = 'PROTECTED_USER_DATA'
            Risk = 'HIGH'
            Decision = 'DO_NOT_TOUCH'
            Reason = 'Personal user-data location.'
        }
    }

    if ($ext -in @('.ost', '.pst')) {
        return [pscustomobject]@{
            Category = 'PROTECTED_USER_DATA'
            Risk = 'HIGH'
            Decision = 'DO_NOT_TOUCH'
            Reason = 'Mail data store. Raw deletion can cause data loss or forced resynchronization.'
        }
    }

    # A row explicitly emitted by Phase 2 cache_candidates is cache evidence even when the
    # path ends exactly at Cache/Temp and has no trailing slash.
    if ($hasCacheSourceEvidence -or (Test-CacheLikePath -NormalizedPath $p)) {
        return [pscustomobject]@{
            Category = 'CACHE_TEMP_CANDIDATE'
            Risk = 'MEDIUM'
            Decision = 'REVIEW_CANDIDATE'
            Reason = 'Phase 2 cache evidence or a recognized user/tool cache-temp path. Review only; no cleanup action is executed.'
        }
    }

    if ($ext -in @('.dmp', '.etl', '.log', '.tmp', '.old')) {
        return [pscustomobject]@{
            Category = 'LOG_DUMP_REVIEW'
            Risk = 'MEDIUM'
            Decision = 'MANUAL_REVIEW'
            Reason = 'Log/dump/temp-like extension outside a known cache location.'
        }
    }

    if ($ext -in @('.iso', '.zip', '.7z', '.rar', '.cab', '.msi', '.exe', '.nupkg')) {
        return [pscustomobject]@{
            Category = 'INSTALLER_ARCHIVE_REVIEW'
            Risk = 'MEDIUM'
            Decision = 'MANUAL_REVIEW'
            Reason = 'Installer/archive that may be reclaimable but requires owner review.'
        }
    }

    if ($SizeBytes -ge 1073741824L) {
        return [pscustomobject]@{
            Category = 'LARGE_FILE_REVIEW'
            Risk = 'MEDIUM'
            Decision = 'MANUAL_REVIEW'
            Reason = 'Item is at least 1 GiB and should be reviewed for value versus space.'
        }
    }

    return [pscustomobject]@{
        Category = 'GENERAL_REVIEW'
        Risk = 'LOW'
        Decision = 'MANUAL_REVIEW'
        Reason = 'No high-confidence cleanup rule matched.'
    }
}

Write-Host ('=' * 60)
Write-Host "$PhaseName - CANDIDATE ANALYSIS"
Write-Host ('=' * 60)
Write-Host 'Mode: ANALYZE ONLY. No deletion or cleanup command is executed.'

if ([string]::IsNullOrWhiteSpace($InputDir)) {
    $InputDir = Read-Host 'Phase 2 report folder'
}
if ([string]::IsNullOrWhiteSpace($InputDir)) {
    throw 'InputDir is required.'
}

$InputDir = [System.IO.Path]::GetFullPath($InputDir)
if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    throw "Input folder not found: $InputDir"
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot ("output\phase3_" + $stamp)
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$csvFiles = @(Get-ChildItem -LiteralPath $InputDir -File -Filter '*.csv' | Sort-Object Name)
if ($csvFiles.Count -eq 0) {
    throw "No CSV reports found in Phase 2 folder: $InputDir"
}

$sourceSummary = New-Object System.Collections.Generic.List[object]
$evidenceRows = New-Object System.Collections.Generic.List[object]

$pathCandidates = @('FullName', 'Path', 'FilePath', 'ItemPath', 'TargetPath', 'DirectoryPath', 'FolderPath')
$sizeCandidates = @('Length', 'LengthBytes', 'SizeBytes', 'TotalBytes', 'Bytes', 'FileSize', 'Size', 'SizeGiB', 'SizeGB', 'SizeMiB', 'SizeMB', 'SizeKiB', 'SizeKB')

foreach ($csv in $csvFiles) {
    $firstLine = Get-Content -LiteralPath $csv.FullName -TotalCount 1
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        $sourceSummary.Add([pscustomobject]@{
            SourceReport = $csv.Name
            RowCount = 0
            PathColumn = ''
            SizeColumn = ''
            Status = 'EMPTY_FILE_SKIPPED'
        })
        continue
    }

    $rows = @(Import-Csv -LiteralPath $csv.FullName)
    if ($rows.Count -gt 0) {
        $columns = @($rows[0].PSObject.Properties.Name)
    }
    else {
        $columns = @($firstLine -split ',' | ForEach-Object { $_.Trim().Trim('"') })
    }

    $pathColumn = Get-FirstMatchingColumn -Columns $columns -Candidates $pathCandidates
    $sizeColumn = Get-FirstMatchingColumn -Columns $columns -Candidates $sizeCandidates

    if (-not $pathColumn) {
        $sourceSummary.Add([pscustomobject]@{
            SourceReport = $csv.Name
            RowCount = $rows.Count
            PathColumn = ''
            SizeColumn = if ($sizeColumn) { $sizeColumn } else { '' }
            Status = 'NO_PATH_COLUMN_SKIPPED'
        })
        continue
    }

    $sourceSummary.Add([pscustomobject]@{
        SourceReport = $csv.Name
        RowCount = $rows.Count
        PathColumn = $pathColumn
        SizeColumn = if ($sizeColumn) { $sizeColumn } else { '' }
        Status = if ($rows.Count -eq 0) { 'VALID_HEADER_ZERO_ROWS' } else { 'PROCESSED' }
    })

    foreach ($row in $rows) {
        $itemPath = [string]$row.$pathColumn
        if ([string]::IsNullOrWhiteSpace($itemPath)) { continue }

        $sizeBytes = 0L
        if ($sizeColumn) {
            $sizeBytes = Convert-SizeValueToBytes -Value $row.$sizeColumn -ColumnName $sizeColumn
        }

        $evidenceRows.Add([pscustomobject]@{
            SourceReport = $csv.Name
            Path = $itemPath.Trim()
            NormalizedPath = Normalize-DiskCarePath -Path $itemPath
            SizeBytes = $sizeBytes
        })
    }
}

# Phase 3 v2 deduplicates by actual path, not by Path + SourceReport. Multiple Phase 2 reports
# become evidence for one classified path.
$matrix = New-Object System.Collections.Generic.List[object]
$groups = @($evidenceRows | Group-Object NormalizedPath | Sort-Object Name)
foreach ($group in $groups) {
    if ([string]::IsNullOrWhiteSpace($group.Name)) { continue }

    $items = @($group.Group)
    $path = [string]$items[0].Path
    $sources = @($items.SourceReport | Sort-Object -Unique)
    $maxSize = [Int64](($items | Measure-Object -Property SizeBytes -Maximum).Maximum)
    $class = Get-Phase3Classification -Path $path -SizeBytes $maxSize -SourceReports $sources

    $matrix.Add([pscustomobject]@{
        SourceReports = ($sources -join ';')
        EvidenceCount = $items.Count
        Path = $path
        SizeBytes = $maxSize
        SizeGiB = [math]::Round(($maxSize / 1GB), 3)
        Category = $class.Category
        Risk = $class.Risk
        Decision = $class.Decision
        Reason = $class.Reason
    })
}

$matrixUnique = @($matrix | Sort-Object Path)
$protected = @($matrixUnique | Where-Object { $_.Decision -eq 'DO_NOT_TOUCH' })
$review = @($matrixUnique | Where-Object { $_.Decision -ne 'DO_NOT_TOUCH' })
$reviewCandidates = @($matrixUnique | Where-Object { $_.Decision -eq 'REVIEW_CANDIDATE' })
$manualReview = @($matrixUnique | Where-Object { $_.Decision -eq 'MANUAL_REVIEW' })

$matrixPath = Join-Path $OutputDir ("phase3_candidate_matrix_" + $stamp + '.csv')
$protectedPath = Join-Path $OutputDir ("phase3_protected_items_" + $stamp + '.csv')
$reviewPath = Join-Path $OutputDir ("phase3_manual_review_" + $stamp + '.csv')
$sourcePath = Join-Path $OutputDir ("phase3_source_summary_" + $stamp + '.csv')
$summaryPath = Join-Path $OutputDir ("phase3_summary_" + $stamp + '.txt')
$manifestPath = Join-Path $OutputDir ("phase3_manifest_" + $stamp + '.txt')

$matrixHeader = 'SourceReports,EvidenceCount,Path,SizeBytes,SizeGiB,Category,Risk,Decision,Reason'
$sourceHeader = 'SourceReport,RowCount,PathColumn,SizeColumn,Status'

if ($matrixUnique.Count -gt 0) { $matrixUnique | Export-Csv -LiteralPath $matrixPath -NoTypeInformation -Encoding UTF8 }
else { Set-Content -LiteralPath $matrixPath -Value $matrixHeader -Encoding UTF8 }

if ($protected.Count -gt 0) { $protected | Export-Csv -LiteralPath $protectedPath -NoTypeInformation -Encoding UTF8 }
else { Set-Content -LiteralPath $protectedPath -Value $matrixHeader -Encoding UTF8 }

if ($review.Count -gt 0) { $review | Export-Csv -LiteralPath $reviewPath -NoTypeInformation -Encoding UTF8 }
else { Set-Content -LiteralPath $reviewPath -Value $matrixHeader -Encoding UTF8 }

if ($sourceSummary.Count -gt 0) { $sourceSummary | Export-Csv -LiteralPath $sourcePath -NoTypeInformation -Encoding UTF8 }
else { Set-Content -LiteralPath $sourcePath -Value $sourceHeader -Encoding UTF8 }

$categoryCounts = @($matrixUnique | Group-Object Category | Sort-Object Name)
$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add($PhaseName)
$summaryLines.Add("Run timestamp: $stamp")
$summaryLines.Add("Input: $InputDir")
$summaryLines.Add("Output: $OutputDir")
$summaryLines.Add("CSV reports inspected: $($csvFiles.Count)")
$summaryLines.Add("Evidence rows read: $($evidenceRows.Count)")
$summaryLines.Add("Unique paths classified: $($matrixUnique.Count)")
$summaryLines.Add("Protected rows: $($protected.Count)")
$summaryLines.Add("Review rows: $($review.Count)")
$summaryLines.Add("Review candidates: $($reviewCandidates.Count)")
$summaryLines.Add("Manual review rows: $($manualReview.Count)")
$summaryLines.Add('Deletion/Cleanup actions = 0')
$summaryLines.Add('Execution mode = ANALYZE_ONLY')
$summaryLines.Add('')
$summaryLines.Add('Category counts:')
foreach ($g in $categoryCounts) {
    $summaryLines.Add("- $($g.Name): $($g.Count)")
}
$summaryLines | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$manifestLines = @(
    $matrixPath,
    $protectedPath,
    $reviewPath,
    $sourcePath,
    $summaryPath
)
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host ''
Write-Host 'PASS: Phase 3 v2 analysis completed.'
Write-Host "Evidence rows read: $($evidenceRows.Count)"
Write-Host "Unique paths classified: $($matrixUnique.Count)"
Write-Host "Protected rows: $($protected.Count)"
Write-Host "Review candidates: $($reviewCandidates.Count)"
Write-Host "Manual review rows: $($manualReview.Count)"
Write-Host 'Deletion/Cleanup actions = 0'
Write-Host "Manifest: $([System.IO.Path]::GetFileName($manifestPath))"
Write-Host "Output: $OutputDir"
