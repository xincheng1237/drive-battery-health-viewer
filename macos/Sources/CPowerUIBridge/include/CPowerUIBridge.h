#ifndef DBHV_C_POWER_UI_BRIDGE_H
#define DBHV_C_POWER_UI_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t enabled;
    int32_t current_state;
    int32_t checkpoint;
    int32_t engaged;
    /// Explicit PowerUI TemporarilyDisabled flag: 0/1, or -1 if unavailable.
    /// This is independent of battery percentage and checkpoint numbers.
    int32_t temporarily_disabled;
} DBHVPowerUIStatus;

/// Opens the private framework dynamically and verifies that its smart-charge
/// client returns the state fields required by the reversible control path.
bool DBHVPowerUIOpen(void);

/// Reads a snapshot without changing charging state.
bool DBHVPowerUIReadStatus(DBHVPowerUIStatus *status);

/// Read-only, independently of PowerUI engagement. Returns 1 when powerd
/// reports SOC limiting suspended for gauging, 0 when not reported, or -1
/// for an unverified OS build, unavailable notification or unknown value.
/// Zero does not prove the entire calibration process has completed.
int32_t DBHVReadGaugingLimitSuspension(void);

/// Read-only check of the live adapter. The bridge calls this again before
/// a checkpoint notification, since the adapter can be removed during XPC.
typedef bool (*DBHVPowerUIExternalPowerCheck)(void);

/// Engages Apple's native optimized-battery-charging target (80%). The caller
/// must establish ownership before using this to recover an Apple top-off
/// transition; an unowned non-baseline state is never passed to this method.
bool DBHVPowerUIEngageEighty(int32_t battery_percentage, bool owns_policy, DBHVPowerUIExternalPowerCheck has_power);

/// Renews an already engaged 80% override before PowerUI reaches its full-
/// charge deadline. This keeps the adapter connected without allowing the
/// native 24-hour schedule to enter its automatic top-off window.
bool DBHVPowerUIRefreshEighty(int32_t battery_percentage, DBHVPowerUIExternalPowerCheck has_power);

/// Clears this process's engagement override and restores normal charging.
bool DBHVPowerUIDisable(void);

#endif
