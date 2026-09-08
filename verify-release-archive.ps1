[CmdletBinding()]
param(
    [string]$ArchiveRoot = (Join-Path $PSScriptRoot 'release-archive'),
    [switch]$RequirePayloads
)

$ErrorActionPreference = 'Stop'
$archiveRootFullPath = [System.IO.Path]::GetFullPath($ArchiveRoot)
$catalogPath = Join-Path $archiveRootFullPath 'catalog.json'
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Archive catalog was not found: $catalogPath"
}

$catalog = (Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8) | ConvertFrom-Json
$checked = 0
$recordOnly = 0
$failures = New-Object System.Collections.Generic.List[string]

foreach ($entry in @($catalog.entries)) {
    if ($entry.archiveAvailable -ne $true) { continue }
    if ([String]::IsNullOrWhiteSpace([string]$entry.archivePath)) {
        [void]$failures.Add("$($entry.id): archiveAvailable is true but archivePath is empty")
        continue
    }

    $artifactPath = Join-Path $archiveRootFullPath ($entry.archivePath -replace '/', '\')
    $metadataPath = Join-Path (Split-Path -Parent $artifactPath) 'artifact.json'
    $sidecarPath = $artifactPath + '.sha256'
    $expectedHash = ([string]$entry.sha256).ToUpperInvariant()
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        if ($RequirePayloads) {
            [void]$failures.Add("$($entry.id): file is missing at $artifactPath")
            continue
        }

        # Binary payloads are intentionally excluded from Git.  A clean clone
        # can still validate the committed metadata and checksum sidecar.
        $recordOnly++
        if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
            [void]$failures.Add("$($entry.id): artifact.json is missing")
        }
        else {
            $metadata = (Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8) | ConvertFrom-Json
            if (([string]$metadata.sha256).ToUpperInvariant() -ne $expectedHash) {
                [void]$failures.Add("$($entry.id): artifact.json SHA-256 does not match catalog.json")
            }
            if ([string]$metadata.artifact -ne [string]$entry.artifact) {
                [void]$failures.Add("$($entry.id): artifact.json file name does not match catalog.json")
            }
        }
        if (-not (Test-Path -LiteralPath $sidecarPath -PathType Leaf)) {
            [void]$failures.Add("$($entry.id): SHA-256 sidecar is missing")
        }
        else {
            $sidecarText = (Get-Content -LiteralPath $sidecarPath -Raw -Encoding ASCII).Trim()
            if ($sidecarText -notmatch ('^' + [Regex]::Escape($expectedHash) + '\s+')) {
                [void]$failures.Add("$($entry.id): SHA-256 sidecar does not match catalog.json")
            }
        }
        continue
    }

    $checked++
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        [void]$failures.Add("$($entry.id): expected $($entry.sha256), found $actualHash")
    }

    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        [void]$failures.Add("$($entry.id): artifact.json is missing")
    }
    else {
        $metadata = (Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8) | ConvertFrom-Json
        if (([string]$metadata.sha256).ToUpperInvariant() -ne $actualHash) {
            [void]$failures.Add("$($entry.id): artifact.json SHA-256 does not match the file")
        }
        if ([string]$metadata.artifact -ne [string]$entry.artifact) {
            [void]$failures.Add("$($entry.id): artifact.json file name does not match catalog.json")
        }
    }

    if (-not (Test-Path -LiteralPath $sidecarPath -PathType Leaf)) {
        [void]$failures.Add("$($entry.id): SHA-256 sidecar is missing")
    }
    else {
        $sidecarText = (Get-Content -LiteralPath $sidecarPath -Raw -Encoding ASCII).Trim()
        if ($sidecarText -notmatch ('^' + [Regex]::Escape($actualHash) + '\s+')) {
            [void]$failures.Add("$($entry.id): SHA-256 sidecar does not match the file")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Release archive verification failed with $($failures.Count) issue(s)."
}

$catalogOnly = @($catalog.entries | Where-Object { $_.archiveAvailable -ne $true }).Count
Write-Output ("Archive verification passed: {0} payload file(s) checked, {1} committed metadata record(s) checked, {2} catalog-only record(s)." -f $checked, $recordOnly, $catalogOnly)
