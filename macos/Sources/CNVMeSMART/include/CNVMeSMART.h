#ifndef CNVMeSMART_h
#define CNVMeSMART_h

#include <stdint.h>

typedef struct DBHVNVMeSMARTData {
    uint8_t criticalWarning;
    uint8_t percentageUsed;
    uint16_t temperatureKelvin;
    uint64_t dataUnitsRead;
    uint64_t dataUnitsWritten;
    uint64_t powerCycles;
    uint64_t powerOnHours;
    uint64_t unsafeShutdowns;
    uint64_t mediaErrors;
} DBHVNVMeSMARTData;

/// Reads the public Apple NVMe SMART interface for the physical BSD disk name.
/// Returns 1 on success and 0 when the device or SMART interface is unavailable.
int32_t DBHVReadNVMeSMART(const char *bsdName, DBHVNVMeSMARTData *result);

/// Releases cached NVMe user clients before sleep or application shutdown.
/// The next read will create interfaces for the current controller lifecycle.
void DBHVResetNVMeSMARTInterfaces(void);

typedef struct DBHVBatteryLiveStatus {
    int32_t chargePercent;
    int32_t isCharging;
    int32_t externalConnected;
    int32_t temperatureCentiCelsius;
} DBHVBatteryLiveStatus;

/// Reads lightweight, current battery state and temperature without a full scan.
int32_t DBHVReadBatteryLiveStatus(DBHVBatteryLiveStatus *result);

#endif
