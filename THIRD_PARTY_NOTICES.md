# Third-party notices

## smartmontools 7.5

The Windows executable embeds `smartctl.exe`, `drivedb.h`, and the complete
license text from the official smartmontools 7.5 Windows release (revision
5714). They are extracted automatically to the current user's cache on first
use; users do not need to manage a separate tools directory.

- Project: https://www.smartmontools.org/
- Source release: https://sourceforge.net/projects/smartmontools/files/smartmontools/7.5/
- Purpose in this application: read-only drive identity and S.M.A.R.T. queries
- License: GNU General Public License, version 2 or later

The complete upstream `COPYING.txt` is embedded in the application and is
extracted beside `smartctl.exe`. The application does not invoke smartmontools
self-tests, writes, repair operations, erase operations, or firmware-update
operations.
