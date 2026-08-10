# smartmontools notice

This application includes the `smartctl` executable from smartmontools 7.5
(revision 5714) for read-only storage-device information queries.

- Upstream project: <https://www.smartmontools.org/>
- Official source mirror: <https://github.com/smartmontools/smartmontools>
- Release: `RELEASE_7_5`
- License: GNU General Public License, version 2 or (at your option) any later version
- Source archive MD5: `38c38b0b82db7fc4906cdd50d15a7931`

The complete corresponding upstream source archive is distributed alongside
this notice as `smartmontools-7.5.tar.gz`. The full license text is included as
`COPYING`. The executable is the official Universal macOS build containing
both `arm64` and `x86_64` slices. The repository copy is byte-identical to the
upstream release; packaging applies fresh ad-hoc signatures to the helper and
the enclosing app so macOS can validate the final bundle structure.

The stock Darwin backend does not provide generic USB/SCSI passthrough.
Accordingly, this application uses automatic read-only detection only. USB
S.M.A.R.T. data is available only when macOS or a separately installed,
compatible driver exposes the underlying device; unsupported values remain
blank and no driver is installed or requested by this application.
