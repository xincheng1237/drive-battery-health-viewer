[CmdletBinding()]
param(
    [string]$GoExe = "C:\Users\PCbeta\Documents\Codex\2026-08-10\github-plugin-github-openai-curated-remote-2\work\go120\go\bin\go.exe",
    [string]$DotNetExe = "C:\Users\PCbeta\Documents\Codex\dbhv-dotnet8\dotnet.exe",
    [string]$NuGetPackages = "C:\Users\PCbeta\Documents\Codex\dbhv-nuget",
    [string]$InnoCompiler = "C:\Users\PCbeta\Documents\Codex\2026-08-10\github-plugin-github-openai-curated-remote-2\work\tools\inno7\ISCC.exe",
    [ValidateSet('user-satisfied', 'github-official', 'historical-test', 'current-working', 'missing-record')]
    [string]$ArchiveClass = "current-working",
    [string]$ArchiveRoot = (Join-Path $PSScriptRoot "release-archive"),
    [switch]$SkipArchive,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$distRoot = Join-Path $projectRoot "dist"
$modernOut = Join-Path $distRoot "modern"
$goCache = Join-Path $projectRoot ".gocache120"

function Invoke-Checked([string]$File, [string[]]$Arguments, [string]$WorkingDirectory) {
    Push-Location $WorkingDirectory
    try {
        & $File @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE`: $File $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Remove-DirectoryLink([string]$Path) {
    # PowerShell 5 can throw a NullReferenceException when Remove-Item is
    # used on a directory junction.  Directory.Delete removes the link
    # itself (without traversing its target), with rmdir as a compatibility
    # fallback for older Windows/PowerShell combinations.
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        [System.IO.Directory]::Delete($Path, $false)
    }
    catch {
        & $env:ComSpec /d /c "rmdir `"$Path`"" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to remove temporary directory link: $Path"
        }
    }
    if (Test-Path -LiteralPath $Path) {
        throw "Temporary directory link still exists: $Path"
    }
}

if (-not (Test-Path -LiteralPath $GoExe)) { throw "Go 1.20.14 not found: $GoExe" }
if (-not (Test-Path -LiteralPath $DotNetExe)) { throw ".NET 8 SDK not found: $DotNetExe" }

$goVersion = (& $GoExe version) -join "`n"
if ($goVersion -notmatch 'go1\.20\.14\s+windows/amd64') {
    throw "Windows binaries must be built with Go 1.20.14 windows/amd64. Found: $goVersion"
}

New-Item -ItemType Directory -Force -Path $distRoot, $goCache, $NuGetPackages | Out-Null
$env:GOCACHE = $goCache
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CGO_ENABLED = "0"
$env:NUGET_PACKAGES = $NuGetPackages

Invoke-Checked $GoExe @("test", "./...") $projectRoot
Invoke-Checked $GoExe @("build", "-trimpath", "-ldflags", "-s -w -H=windowsgui", "-o", (Join-Path $distRoot "DriveBatteryHealthViewer.Legacy.exe"), ".") $projectRoot
Invoke-Checked $GoExe @("build", "-trimpath", "-ldflags", "-s -w -H=windowsgui", "-o", (Join-Path $distRoot "DriveBatteryHealthViewer.exe"), ".\cmd\launcher") $projectRoot

if (Test-Path -LiteralPath $modernOut) {
    $resolvedModern = (Resolve-Path -LiteralPath $modernOut).Path
    if (-not $resolvedModern.StartsWith($distRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean unexpected modern output path: $resolvedModern"
    }
    Remove-Item -LiteralPath $resolvedModern -Recurse -Force
}

# The WinUI XAML compiler still creates paths long enough to exceed legacy
# Windows limits when this repository is deeply nested. A temporary junction
# keeps only the build path short; all output remains under dist\modern.
$shortRoot = Join-Path $env:TEMP ("dbhv-modern-src-" + $PID)
Remove-DirectoryLink $shortRoot
New-Item -ItemType Junction -Path $shortRoot -Target $projectRoot | Out-Null
try {
    $modernProject = Join-Path $shortRoot "modern\DriveBatteryHealthViewer.Modern.csproj"
    Invoke-Checked $DotNetExe @(
        "publish", $modernProject,
        "-c", "Release", "-r", "win-x64", "--self-contained", "false",
        "-p:WindowsAppSDKSelfContained=false", "-p:PublishReadyToRun=false",
        "-o", (Join-Path $shortRoot "dist\modern")
    ) $shortRoot
}
finally {
    Remove-DirectoryLink $shortRoot
}

# Debug symbols are not required at runtime and are deliberately excluded from
# the public installer to keep the package lean.
$modernPdb = Join-Path $modernOut "DriveBatteryHealthViewer.Modern.pdb"
if (Test-Path -LiteralPath $modernPdb) {
    Remove-Item -LiteralPath $modernPdb -Force
}

$launcher = Get-Item -LiteralPath (Join-Path $distRoot "DriveBatteryHealthViewer.exe")
$legacy = Get-Item -LiteralPath (Join-Path $distRoot "DriveBatteryHealthViewer.Legacy.exe")
$modernFiles = @(Get-ChildItem -LiteralPath $modernOut -File -Recurse)
$modernBytes = ($modernFiles | Measure-Object -Property Length -Sum).Sum

if ($launcher.Length -gt 5MB) { throw "Launcher exceeds 5 MiB: $($launcher.Length) bytes" }
if ($legacy.Length -gt 20MB) { throw "Compatibility UI exceeds 20 MiB: $($legacy.Length) bytes" }
if ($modernBytes -gt 65MB) { throw "Modern UI exceeds 65 MiB: $modernBytes bytes" }

$manifest = [ordered]@{
    version = "1.0.6"
    architecture = "x64"
    builtAtUtc = [DateTime]::UtcNow.ToString("o")
    go = "go1.20.14"
    modernFramework = ".NET 8 + Windows App SDK 1.8.11"
    selection = [ordered]@{
        default = "Compatibility UI with the verified 1.0.6 layout on every supported Windows version"
        modern = "Optional modern UI on Windows 10 build 17763 (1809) or newer via --modern or DBHV_USE_MODERN=1"
        fallback = "Compatibility UI remains the release fallback when the modern UI or its runtime cannot start"
    }
    files = @(
        [ordered]@{ path = $launcher.Name; bytes = $launcher.Length; sha256 = (Get-FileHash -LiteralPath $launcher.FullName -Algorithm SHA256).Hash.ToLowerInvariant() },
        [ordered]@{ path = $legacy.Name; bytes = $legacy.Length; sha256 = (Get-FileHash -LiteralPath $legacy.FullName -Algorithm SHA256).Hash.ToLowerInvariant() },
        [ordered]@{ path = "modern"; bytes = $modernBytes; count = $modernFiles.Count }
    )
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $distRoot "BUILD-MANIFEST.json") -Encoding UTF8

$launcherHash = (Get-FileHash -LiteralPath $launcher.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $distRoot "$($launcher.Name).sha256") `
    -Value "$launcherHash  $($launcher.Name)" -Encoding ASCII

if (-not $SkipInstaller) {
    if (-not (Test-Path -LiteralPath $InnoCompiler)) { throw "Inno Setup compiler not found: $InnoCompiler" }
    Invoke-Checked $InnoCompiler @((Join-Path $projectRoot "installer.iss")) $projectRoot
}

Write-Host "Built launcher: $([Math]::Round($launcher.Length / 1MB, 2)) MiB"
Write-Host "Built compatibility UI/core: $([Math]::Round($legacy.Length / 1MB, 2)) MiB"
Write-Host "Built modern UI: $([Math]::Round($modernBytes / 1MB, 2)) MiB in $($modernFiles.Count) files"
if (-not $SkipInstaller) {
    $setup = Get-Item -LiteralPath (Join-Path $distRoot "DriveBatteryHealthViewer_v1.0.6_Windows_x64_Setup.exe")
    $setupHash = (Get-FileHash -LiteralPath $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $distRoot "$($setup.Name).sha256") `
        -Value "$setupHash  $($setup.Name)" -Encoding ASCII
    Write-Host "Built installer: $($setup.FullName) ($([Math]::Round($setup.Length / 1MB, 2)) MiB)"

    if (-not $SkipArchive) {
        $archiveScript = Join-Path $projectRoot "archive-release.ps1"
        if (-not (Test-Path -LiteralPath $archiveScript -PathType Leaf)) {
            throw "Archive script not found: $archiveScript"
        }
        try {
            & $archiveScript `
                -ArtifactPath $setup.FullName `
                -Version "1.0.6" `
                -Classification $ArchiveClass `
                -ArchiveRoot $ArchiveRoot `
                -Source "build-windows.ps1"
        }
        catch {
            throw "Archive step failed: $($_.Exception.Message)"
        }
    }
}
