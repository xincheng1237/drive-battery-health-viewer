# Windows dual-interface build

The Windows package has one public entry point and two user interfaces:

- `DriveBatteryHealthViewer.exe`: a Go 1.20.14 launcher that uses only Windows 7-era APIs;
- `DriveBatteryHealthViewer.Legacy.exe`: the existing Win32 interface and shared hardware/report/history engine;
- `modern\DriveBatteryHealthViewer.Modern.exe`: WinUI 3 for Windows 10 build 17763 (1809) or newer.

The release launcher starts the verified Win32 compatibility interface by default on every supported Windows version. This keeps the layout, typography, and DPI behavior stable across machines. The bundled WinUI 3 interface remains available for validation or opt-in evaluation with `DriveBatteryHealthViewer.exe --modern` (or `DBHV_USE_MODERN=1`) on Windows 10 build 17763 (1809) or newer; `--legacy` or `DBHV_FORCE_LEGACY=1` always selects the compatibility interface. Both interfaces use the same settings directory, history format, hardware scanner, health calculations, serial-number privacy rules, and report renderer.

## Reproducible release build

Run `build-windows.ps1` from PowerShell. The script refuses to build the Windows binaries with any Go version other than Go 1.20.14, runs all Go tests, produces both Go executables, publishes the framework-dependent WinUI application, enforces size limits, writes `dist\BUILD-MANIFEST.json`, and compiles the installer.

The modern UI is framework-dependent to avoid shipping a duplicate .NET and Windows App SDK runtime in every application update. On Windows 10 1809 or newer the installer may download missing Microsoft runtimes for the opt-in modern interface. If that cannot be completed, the default launcher still opens the full-function Win32 interface. Windows 7 and 8 never receive or load modern-runtime files.

## Immutable build archive

After the installer is compiled, `build-windows.ps1` calls `archive-release.ps1`
automatically. The installer is copied to
`release-archive/artifacts/<classification>/<version>/sha256-<hash>/`; an existing
hash directory is never overwritten. Rebuilding the same version therefore cannot
destroy an earlier package.

The default classification is `current-working`. A deliberate promotion can use
`-ArchiveClass user-satisfied` or `-ArchiveClass github-official`. The tracked
[`release-archive/catalog.json`](release-archive/catalog.json) contains the complete
history, including hash-only records for files that are no longer available. Run
`verify-release-archive.ps1` after copying or restoring archive files to check every
recorded SHA-256.

Current release size budgets:

- launcher: 5 MiB maximum;
- Win32 compatibility UI and shared core: 20 MiB maximum;
- framework-dependent modern UI: 65 MiB maximum.

Do not change these thresholds or switch to a self-contained WinUI publish without documenting and reviewing the installer-size impact.
