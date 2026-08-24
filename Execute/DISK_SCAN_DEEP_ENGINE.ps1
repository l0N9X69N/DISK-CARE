$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
$now = Get-Date

function Export-Report {
    param(
        $Data,
        [string]$Path,
        [string[]]$Columns
    )

    $arr = @($Data | Where-Object { $null -ne $_ })
    if ($arr.Count -gt 0) {
        $arr | Select-Object $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
    else {
        ($Columns -join ',') | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Get-Safety {
    param([string]$Path)

    $p = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $protected = @(
        $env:WINDIR,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData
    ) | Where-Object { $_ }

    foreach ($x in $protected) {
        $q = [IO.Path]::GetFullPath($x).TrimEnd('\')
        if ($p -ieq $q -or $p.StartsWith($q + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return 'NEVER_DELETE'
        }
    }

    if ($p -match '(?i)\\System Volume Information(\\|$)' -or
        $p -match '(?i)\\\$Recycle\.Bin(\\|$)') {
        return 'NEVER_DELETE'
    }

    $leaf = [IO.Path]::GetFileName($p)
    if ($leaf -in @('pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'bootmgr', 'BOOTNXT')) {
        return 'NEVER_DELETE'
    }

    return 'REVIEW'
}

$root = Get-Item -LiteralPath $env:DISKCARE_TARGET -Force -ErrorAction Stop
if (-not $root.PSIsContainer) {
    throw 'Deep inventory target must be a directory or drive.'
}
if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Deep inventory target itself is a reparse point. Choose the physical directory or drive instead.'
}

$rootPath = [IO.Path]::GetFullPath($root.FullName)
if ($rootPath.EndsWith('\')) {
    $prefix = $rootPath
}
else {
    $prefix = $rootPath + '\'
}

$largeBytes = [double]$env:DISKCARE_LARGE_MB * 1MB
$oldMin = [double]$env:DISKCARE_OLD_MIN_MB * 1MB
$artifactMin = [double]$env:DISKCARE_ARTIFACT_MIN_MB * 1MB
$oldCut = $now.AddDays(-[int]$env:DISKCARE_OLD_DAYS)
$recentCut = $now.AddDays(-[int]$env:DISKCARE_RECENT_DAYS)

$large = New-Object 'System.Collections.Generic.List[object]'
$old = New-Object 'System.Collections.Generic.List[object]'
$recent = New-Object 'System.Collections.Generic.List[object]'
$art = New-Object 'System.Collections.Generic.List[object]'
$reparse = New-Object 'System.Collections.Generic.List[object]'
$errors = New-Object 'System.Collections.Generic.List[object]'
$top = @{}

$artifactTypes = @{
    '.vhd'  = 'VirtualDisk'
    '.vhdx' = 'VirtualDisk'
    '.iso'  = 'DiskImage'
    '.img'  = 'DiskImage'
    '.wim'  = 'WindowsImage'
    '.esd'  = 'WindowsImage'
    '.dmp'  = 'CrashDump'
    '.bak'  = 'Backup'
    '.zip'  = 'Archive'
    '.7z'   = 'Archive'
    '.rar'  = 'Archive'
    '.tar'  = 'Archive'
    '.gz'   = 'Archive'
    '.msi'  = 'Installer'
    '.exe'  = 'Installer'
}

$stack = New-Object 'System.Collections.Generic.Stack[object]'
$stack.Push($root)
[int64]$filesSeen = 0
[int64]$bytesSeen = 0
[int64]$dirsVisited = 0

while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    $dirsVisited++

    if (($dirsVisited % 250) -eq 0) {
        Write-Host ('Visited directories: {0} | Files: {1} | Reparse skipped: {2} | Errors: {3}' -f $dirsVisited, $filesSeen, $reparse.Count, $errors.Count)
    }

    $ev = @()
    $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable +ev)

    foreach ($er in $ev) {
        if ($er.TargetObject) {
            $ep = [string]$er.TargetObject
        }
        else {
            $ep = $dir.FullName
        }
        $errors.Add([pscustomobject]@{
            Path = $ep
            Message = $er.Exception.Message
        })
    }

    foreach ($i in $children) {
        # CRITICAL SAFETY RULE: inventory reparse points but never traverse them.
        if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            if ($i.PSObject.Properties['LinkType']) { $lt = [string]$i.LinkType } else { $lt = '' }
            if ($i.PSObject.Properties['Target']) { $tg = [string]($i.Target -join ';') } else { $tg = '' }
            if ($i.PSIsContainer) { $rt = 'DirectoryReparse' } else { $rt = 'FileReparse' }

            $reparse.Add([pscustomobject]@{
                Type = $rt
                Path = $i.FullName
                LinkType = $lt
                Target = $tg
                Action = 'SKIPPED_NOT_FOLLOWED'
            })
            continue
        }

        if ($i.PSIsContainer) {
            $stack.Push($i)
            continue
        }

        $filesSeen++
        $bytesSeen += [int64]$i.Length

        if ($i.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $i.FullName.Substring($prefix.Length)
        }
        else {
            $rel = $i.Name
        }

        $parts = $rel -split '\\', 2
        if ($parts.Count -gt 1) { $key = $parts[0] } else { $key = '[ROOT FILES]' }

        if (-not $top.ContainsKey($key)) {
            if ($key -eq '[ROOT FILES]') { $tp = $root.FullName } else { $tp = Join-Path $root.FullName $key }
            $top[$key] = @{
                Path = $tp
                Bytes = [int64]0
                Files = [int64]0
                Errors = [int64]0
                Reparse = [int64]0
            }
        }

        $top[$key].Bytes += [int64]$i.Length
        $top[$key].Files++

        $safety = Get-Safety $i.FullName
        $age = [math]::Floor(($now - $i.LastWriteTime).TotalDays)

        if ($i.Length -ge $largeBytes) {
            $row = [pscustomobject]@{
                Safety = $safety
                SizeMB = [math]::Round($i.Length / 1MB, 1)
                SizeGB = [math]::Round($i.Length / 1GB, 3)
                LastWriteTime = $i.LastWriteTime
                AgeDays = $age
                Extension = $i.Extension
                FullName = $i.FullName
            }
            $large.Add($row)

            if ($i.LastWriteTime -ge $recentCut) {
                $recent.Add($row)
            }
        }

        if ($i.Length -ge $oldMin -and $i.LastWriteTime -lt $oldCut) {
            $old.Add([pscustomobject]@{
                Safety = $safety
                SizeMB = [math]::Round($i.Length / 1MB, 1)
                SizeGB = [math]::Round($i.Length / 1GB, 3)
                LastWriteTime = $i.LastWriteTime
                AgeDays = $age
                Extension = $i.Extension
                FullName = $i.FullName
            })
        }

        $ext = if ($i.Extension) { $i.Extension.ToLowerInvariant() } else { '' }
        if ($artifactTypes.ContainsKey($ext) -and $i.Length -ge $artifactMin) {
            $art.Add([pscustomobject]@{
                Type = $artifactTypes[$ext]
                Safety = $safety
                SizeMB = [math]::Round($i.Length / 1MB, 1)
                SizeGB = [math]::Round($i.Length / 1GB, 3)
                LastWriteTime = $i.LastWriteTime
                Extension = $ext
                FullName = $i.FullName
            })
        }
    }
}

foreach ($r in $reparse) {
    if ($r.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $rr = $r.Path.Substring($prefix.Length)
        $pp = $rr -split '\\', 2
        if ($pp.Count -gt 1) { $k = $pp[0] } else { $k = '[ROOT FILES]' }
        if ($top.ContainsKey($k)) { $top[$k].Reparse++ }
    }
}

foreach ($e in $errors) {
    if ($e.Path -and $e.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $rr = $e.Path.Substring($prefix.Length)
        $pp = $rr -split '\\', 2
        if ($pp.Count -gt 1) { $k = $pp[0] } else { $k = '[ROOT FILES]' }
        if ($top.ContainsKey($k)) { $top[$k].Errors++ }
    }
}

$topResult = @(
    foreach ($k in $top.Keys) {
        $v = $top[$k]
        [pscustomobject]@{
            Safety = (Get-Safety $v.Path)
            Folder = $v.Path
            SizeGB = [math]::Round($v.Bytes / 1GB, 3)
            Files = $v.Files
            Errors = $v.Errors
            ReparseSkipped = $v.Reparse
        }
    }
) | Sort-Object SizeGB -Descending | Select-Object -First ([int]$env:DISKCARE_TOP_LIMIT)

$largeResult = @($large | Sort-Object SizeMB -Descending | Select-Object -First ([int]$env:DISKCARE_LARGE_LIMIT))
$oldResult = @($old | Sort-Object SizeMB -Descending | Select-Object -First ([int]$env:DISKCARE_OLD_LIMIT))
$recentResult = @($recent | Sort-Object SizeMB -Descending | Select-Object -First ([int]$env:DISKCARE_RECENT_LIMIT))
$artResult = @($art | Sort-Object SizeMB -Descending | Select-Object -First ([int]$env:DISKCARE_ARTIFACT_LIMIT))

Export-Report $topResult $env:OUT_TOP @('Safety','Folder','SizeGB','Files','Errors','ReparseSkipped')
Export-Report $largeResult $env:OUT_LARGE @('Safety','SizeMB','SizeGB','LastWriteTime','AgeDays','Extension','FullName')
Export-Report $oldResult $env:OUT_OLD @('Safety','SizeMB','SizeGB','LastWriteTime','AgeDays','Extension','FullName')
Export-Report $recentResult $env:OUT_RECENT @('Safety','SizeMB','SizeGB','LastWriteTime','AgeDays','Extension','FullName')
Export-Report $artResult $env:OUT_ART @('Type','Safety','SizeMB','SizeGB','LastWriteTime','Extension','FullName')
Export-Report $reparse $env:OUT_REPARSE @('Type','Path','LinkType','Target','Action')
Export-Report $errors $env:OUT_ERR @('Path','Message')

$sw.Stop()
$manifest = @(
    'DISK-CARE DISK SCAN - DEEP SCAN MANIFEST'
    'Status: COMPLETE'
    'Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    'Target: ' + $root.FullName
    'TraversalMode: SAFE_NO_REPARSE_FOLLOW'
    'SymlinkPolicy: INVENTORY_AND_SKIP'
    'DeletionActions: 0'
    'LargeThresholdMB: ' + $env:DISKCARE_LARGE_MB
    'OldDays: ' + $env:DISKCARE_OLD_DAYS
    'OldMinMB: ' + $env:DISKCARE_OLD_MIN_MB
    'RecentDays: ' + $env:DISKCARE_RECENT_DAYS
    'ArtifactMinMB: ' + $env:DISKCARE_ARTIFACT_MIN_MB
    'DirectoriesVisited: ' + $dirsVisited
    'FilesSeen: ' + $filesSeen
    'BytesSeen: ' + $bytesSeen
    ('DataSeenGB: {0:N3}' -f ($bytesSeen / 1GB))
    'ReparsePointsSkipped: ' + $reparse.Count
    'CoverageNote: DataSeen excludes skipped reparse targets and unreadable content.'
    'AccessOrReadErrors: ' + $errors.Count
    'LargeFilesReported: ' + $largeResult.Count
    'OldLargeFilesReported: ' + $oldResult.Count
    'RecentLargeFilesReported: ' + $recentResult.Count
    'ArtifactsReported: ' + $artResult.Count
    ('ElapsedSeconds: {0:N1}' -f $sw.Elapsed.TotalSeconds)
)

$manifest | Set-Content -LiteralPath $env:OUT_MANIFEST -Encoding UTF8
Write-Host ''
Write-Host 'DEEP INVENTORY COMPLETE'
$manifest | ForEach-Object { Write-Host $_ }
