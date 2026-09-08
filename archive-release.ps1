[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v?\d+\.\d+\.\d+$')]
    [string]$Version,

    [ValidateSet('user-satisfied', 'github-official', 'historical-test', 'current-working', 'missing-record')]
    [string]$Classification = 'current-working',

    [string]$ArchiveRoot = (Join-Path $PSScriptRoot 'release-archive'),

    [string]$Source = 'local-build',

    [string]$Description = '',

    [string]$DownloadUrl = ''
)

$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
    $targetUri = New-Object System.Uri($TargetPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
}

$artifactFullPath = Get-FullPath -Path $ArtifactPath
if (-not (Test-Path -LiteralPath $artifactFullPath -PathType Leaf)) {
    throw "Artifact was not found: $artifactFullPath"
}

$artifact = Get-Item -LiteralPath $artifactFullPath
$versionNormalized = $Version.Trim()
if (-not $versionNormalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
    $versionNormalized = 'v' + $versionNormalized
}

$archiveRootFullPath = Get-FullPath -Path $ArchiveRoot
$hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
$hashFolder = 'sha256-' + $hash.ToLowerInvariant()
$destinationDirectory = Join-Path (Join-Path (Join-Path $archiveRootFullPath 'artifacts') $Classification) (Join-Path $versionNormalized $hashFolder)
$destinationFile = Join-Path $destinationDirectory $artifact.Name

New-Item -ItemType Directory -Force -Path $archiveRootFullPath | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationDirectory) | Out-Null

$temporaryDirectory = Join-Path $archiveRootFullPath ('.tmp-' + [Guid]::NewGuid().ToString('N'))
$archiveTimestamp = [DateTime]::UtcNow.ToString('o')

try {
    New-Item -ItemType Directory -Force -Path $temporaryDirectory | Out-Null
    $temporaryArtifact = Join-Path $temporaryDirectory $artifact.Name
    Copy-Item -LiteralPath $artifact.FullName -Destination $temporaryArtifact -Force

    $sidecarName = $artifact.Name + '.sha256'
    $sidecarContent = $hash + '  ' + $artifact.Name + [Environment]::NewLine
    Write-Utf8NoBom -Path (Join-Path $temporaryDirectory $sidecarName) -Content $sidecarContent

    $metadata = [ordered]@{
        schemaVersion = 1
        version = $versionNormalized
        platform = 'windows-x64'
        artifact = $artifact.Name
        classification = $Classification
        status = 'archived'
        archiveAvailable = $true
        sha256 = $hash
        bytes = [int64]$artifact.Length
        archivedAtUtc = $archiveTimestamp
        source = $Source
        description = $Description
        downloadUrl = $DownloadUrl
    }
    $metadataJson = $metadata | ConvertTo-Json -Depth 8
    Write-Utf8NoBom -Path (Join-Path $temporaryDirectory 'artifact.json') -Content ($metadataJson + [Environment]::NewLine)

    if (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($existingHash -ne $hash) {
            throw "Archive collision detected at $destinationFile. Existing SHA-256 is $existingHash, incoming SHA-256 is $hash. No files were replaced."
        }
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
    elseif (Test-Path -LiteralPath $destinationDirectory) {
        throw "Archive directory already exists without the expected artifact: $destinationDirectory. No files were replaced."
    }
    else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationDirectory) | Out-Null
        Move-Item -LiteralPath $temporaryDirectory -Destination $destinationDirectory
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

$catalogPath = Join-Path $archiveRootFullPath 'catalog.json'
$entries = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
    $catalogText = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8
    if (-not [String]::IsNullOrWhiteSpace($catalogText)) {
        $catalog = $catalogText | ConvertFrom-Json
        if ($null -ne $catalog.entries) {
            foreach ($existingEntry in @($catalog.entries)) {
                [void]$entries.Add($existingEntry)
            }
        }
    }
}

$relativeArchivePath = Get-RelativePathCompat -BasePath $archiveRootFullPath -TargetPath $destinationFile
$newEntry = [ordered]@{
    id = ('artifact-' + $versionNormalized.TrimStart('v') + '-' + $hash.ToLowerInvariant())
    version = $versionNormalized
    platform = 'windows-x64'
    artifact = $artifact.Name
    classification = $Classification
    status = 'archived'
    archiveAvailable = $true
    sha256 = $hash
    bytes = [int64]$artifact.Length
    archivePath = ($relativeArchivePath -replace '\\', '/')
    archivedAtUtc = $archiveTimestamp
    source = $Source
    description = $Description
    downloadUrl = $DownloadUrl
}

$replacementIndex = -1
for ($index = 0; $index -lt $entries.Count; $index++) {
    $candidate = $entries[$index]
    if (($candidate.sha256 -eq $hash) -and
        ($candidate.artifact -eq $artifact.Name) -and
        ($candidate.classification -eq $Classification) -and
        ($candidate.version -eq $versionNormalized)) {
        $replacementIndex = $index
        break
    }
}
if ($replacementIndex -ge 0) {
    # An already archived entry is the source of truth.  Keeping its original
    # metadata makes repeated builds idempotent and preserves hand-written notes.
    $existing = $entries[$replacementIndex]
    if (($existing.status -ne 'archived') -or ($existing.archiveAvailable -ne $true)) {
        $entries[$replacementIndex] = [pscustomobject]$newEntry
    }
}
else {
    [void]$entries.Add([pscustomobject]$newEntry)
}

$catalogOutput = [ordered]@{
    schemaVersion = 1
    project = 'drive-battery-health-viewer'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    entries = [object[]]$entries.ToArray()
}

$catalogTemporaryPath = $catalogPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
try {
    $catalogJson = $catalogOutput | ConvertTo-Json -Depth 12
    Write-Utf8NoBom -Path $catalogTemporaryPath -Content ($catalogJson + [Environment]::NewLine)
    Move-Item -LiteralPath $catalogTemporaryPath -Destination $catalogPath -Force
}
finally {
    if (Test-Path -LiteralPath $catalogTemporaryPath) {
        Remove-Item -LiteralPath $catalogTemporaryPath -Force
    }
}

Write-Output ("Archived {0} ({1}) to {2}" -f $artifact.Name, $hash, $destinationFile)
