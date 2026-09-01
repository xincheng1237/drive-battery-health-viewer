#ifndef DBHV_C_POWER_UI_BRIDGE_H
#define DBHV_C_POWER_UI_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int32_t enabled;
    int32_t current_state;
    int32_t checkpoint;
    int32_t engaged;
} DBHVPowerUIStatus;

/// Opens the private framework dynamically and verifies that its smart-charge
/// client returns the state fields required by the reversible control path.
bool DBHVPowerUIOpen(void);

/// Reads a snapshot without changing charging state.
bool DBHVPowerUIReadStatus(DBHVPowerUIStatus *status);

/// Engages Apple's native optimized-battery-charging target (80%). The method
/// accepts only a clean baseline or the already-engaged native state.
bool DBHVPowerUIEngageEighty(int32_t battery_percentage);

/// Clears this process's engagement override and restores normal charging.
bool DBHVPowerUIDisable(void);

#endif
