# Drive & Battery Health Viewer 1.0.6 for Windows

Version 1.0.6 is the first Windows release to use the macOS-aligned single-window
page hierarchy. It is available as a standard x64 installer and a portable
single executable; neither requires ZIP extraction or a separate tools folder.

## Highlights

- Overview, History, Settings, and About pages share one responsive Windows UI.
- History supports preview, full view, selection mode, Select All, batch export,
  batch deletion, and optional deletion of linked local exports.
- Read-only smartctl diagnostics add information for supported USB, SAT/SATA,
  NVMe, SCSI, and external storage devices.
- Serial-number masking applies consistently to the interface, clipboard,
  history, and exported reports.
- Hardware scans use cancellation, command and whole-scan time limits, stable
  drive identity checks, and stale-result rejection.

## Compatibility

The executable is built with Go 1.20.14 and supports Windows 7 SP1 or later.
Windows 10 version 1809 and later can use supported native storage protocol
queries. Earlier systems automatically continue through compatible WMI/WMIC and
smartctl readers. The page hierarchy, workflow, history, export, and privacy
features remain consistent across supported Windows versions.
