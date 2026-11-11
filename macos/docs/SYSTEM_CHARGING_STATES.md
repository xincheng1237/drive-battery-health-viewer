# System charging states

The Helper reports user-selected full charging and system gauging separately. The application's saved limit expresses intent; it is not proof that charging is currently limited. Actual holding, a system pause, unavailable telemetry, and a control failure remain distinct.

## User-selected full charge

PowerUI's explicit `TemporarilyDisabled` boolean identifies a system temporary override. The Helper preserves the saved limit and defers engagement/renewal until macOS explicitly clears it. Reconnecting power or reaching 100% does not independently cancel the user's system choice. If an observed override becomes unreadable, control remains deferred while the interface displays a confirmation message.

## System calibration

On the verified macOS 15.8.1 build `24H212`, powerd publishes `com.apple.system.powersources.gaugingmitigation`. Its state 1 reports SOC limiting suspended for battery gauging; 0 means no such suspension is reported. A zero value does **not** establish completion of the whole calibration process or successful restoration of protection.

The mapping was inspected in both slices of the local powerd binary:

- SHA-256: `067dbfb27c63093fdd6721f55cb1184037d8a40386ab5b135d73edeab55bff06`.
- arm64e: the mitigation-suspension branch at `0x1000483d8` leads to the state publication at `0x1000484fc`–`0x100048508`.
- x86_64: corresponding branch at `0x10004db1f`, state publication at `0x10004dc4f`–`0x10004dc5b`.

Registration success alone cannot verify that a private notification has a publisher. The reader therefore enables this mapping only for the verified build. Other builds, registration/read failures and values other than 0/1 yield unknown. Support for another build requires verification rather than extrapolation from battery percentage or checkpoint numbers.

When a positive calibration signal is observed, the Helper defers control, reports no holding, and provides a calibration reason to both interfaces. An unknown read after a positive signal retains the pause and displays “confirming calibration”. When the signal clears, normal policy verification resumes. Genuine subsequent failure remains an error; the code never labels a zero signal “calibration complete”.

The existing battery silhouette gains circular arrows for calibration. The NSStatusItem identity, saved position, visibility preference, and symmetric appearance/disappearance timing are retained. The glyph is static and uses the native template rendering path.

## Control boundaries

- No checkpoint manipulation or forced SMC fallback to block calibration.
- On native-80-only systems, failure to open PowerUI produces unavailable control instead of falling back to SMC limiting.
- Calibration or a user override arriving during engagement is checked before further checkpoint writes and before automatic failure cleanup.
- Explicit disable/uninstall retains the established restoration/ownership cleanup path.
- In-flight PowerUI waits abort immediately upon SIGTERM/SIGINT signal delivery via `DBHVPowerUIRequestAbort()`.
- Old status JSON lacking the optional new fields remains decodable.
- Status freshness and matching configuration are required for calibration/override presentation. Unknown states do not establish active protection.
- When the battery reaches 100%, no engage or renew requests are issued to PowerUI to prevent knocking active holds down to Checkpoint 0. The helper enters an Armed Waiting state until discharge below 100% occurs.
- When normal charging is restored and PowerUI enters Checkpoint 5, ownership marker is retained with `leaseState = .restoredTopOff` rather than unlinked, preventing future unowned deadlock.
- Native PowerUI control is restricted strictly to verified macOS builds (`24H212`). Unverified builds fail closed without mutating system policies.
- An overcharge monitor watches for >= 2% net charge increase or 45s/3-attempt failure past 80%, raising an explicit alert instead of misreporting an active hold.

## Validation

Swift Testing covers reason separation, percentages including 100%, reconnect observations, unknown/stale/mismatched data, old JSON, genuine faults, menu-bar state, glyph geometry, seven-language copy, and historical changelog preservation. Local previews render the actual notice in all seven languages and both color schemes.

`./scripts/test-powerui-bridge.sh` uses an isolated fake client, fake notifications and fake OS build query. It verifies that user overrides, calibration, unsupported builds, failed reads and in-flight pauses do not issue unintended control writes. It never sends actual system notifications or SMC writes.

A read-only probe on the release machine can verify the production reader's inactive/unknown values. The automated suite uses injected notifications and status records. Hardware observations are recorded separately from those tests.

## Overview charging explanation

`BatteryPowerNoticeReason` selects the explanation from live battery information and a current Helper status. Active-limit wording requires both readings at the limit, a successful hold, the same applied configuration, an available controller, and a status age below 20 seconds. Native PowerUI additionally requires explicit inactive calibration and temporary-full-charge observations. Other plugged-in, non-charging states retain the ordinary system-status wording.
