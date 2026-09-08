[CmdletBinding()]
param(
    [string]$ArchiveRoot = (Join-Path $PSScriptRoot 'release-archive')
)

$ErrorActionPreference = 'Stop'
$archiveRootFullPath = [System.IO.Path]::GetFullPath($ArchiveRoot)
$catalogPath = Join-Path $archiveRootFullPath 'catalog.json'
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Archive catalog was not found: $catalogPath"
}

$catalog = (Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8) | ConvertFrom-Json
$checked = 0
$failures = New-Object System.Collections.Generic.List[string]

foreach ($entry in @($catalog.entries)) {
    if ($entry.archiveAvailable -ne $true) { continue }
    if ([String]::IsNullOrWhiteSpace([string]$entry.archivePath)) {
        [void]$failures.Add("$($entry.id): archiveAvailable is true but archivePath is empty")
        continue
    }

    $artifactPath = Join-Path $archiveRootFullPath ($entry.archivePath -replace '/', '\')
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        [void]$failures.Add("$($entry.id): file is missing at $artifactPath")
        continue
    }

    $checked++
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne ([string]$entry.sha256).ToUpperInvariant()) {
        [void]$failures.Add("$($entry.id): expected $($entry.sha256), found $actualHash")
    }

    $metadataPath = Join-Path (Split-Path -Parent $artifactPath) 'artifact.json'
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

    $sidecarPath = $artifactPath + '.sha256'
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

$available = @($catalog.entries | Where-Object { $_.archiveAvailable -eq $true }).Count
$missing = @($catalog.entries | Where-Object { $_.archiveAvailable -ne $true }).Count
Write-Output ("Archive verification passed: {0} file(s) checked, {1} archived entr(y/ies), {2} record-only entr(y/ies)." -f $checked, $available, $missing)
