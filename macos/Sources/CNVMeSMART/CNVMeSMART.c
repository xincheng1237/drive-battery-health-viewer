#include "CNVMeSMART.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { kDBHVMaximumCachedNVMeDevices = 8 };

typedef struct DBHVNVMeInterfaceCache {
    char bsdName[64];
    uint64_t registryEntryID;
    IONVMeSMARTInterface **interface;
} DBHVNVMeInterfaceCache;

static DBHVNVMeInterfaceCache gInterfaceCache[kDBHVMaximumCachedNVMeDevices];
static size_t gInterfaceCacheCount = 0;
static pthread_mutex_t gInterfaceCacheLock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t DBHVLowUInt64(const uint64_t value[2]) {
    return value[1] == 0 ? value[0] : UINT64_MAX;
}

static bool DBHVServiceMatchesBSDName(io_service_t service, const char *bsdName) {
    CFTypeRef property = IORegistryEntrySearchCFProperty(
        service,
        kIOServicePlane,
        CFSTR("BSD Name"),
        kCFAllocatorDefault,
        kIORegistryIterateRecursively
    );
    if (property == NULL) { return false; }

    bool matches = false;
    if (CFGetTypeID(property) == CFStringGetTypeID()) {
        char value[64] = {0};
        if (CFStringGetCString((CFStringRef)property, value, sizeof(value), kCFStringEncodingUTF8)) {
            matches = strcmp(value, bsdName) == 0;
        }
    }
    CFRelease(property);
    return matches;
}

static uint64_t DBHVCurrentRegistryEntryID(const char *bsdName) {
    CFMutableDictionaryRef matching = IOServiceMatching("IONVMeBlockStorageDevice");
    if (matching == NULL) { return 0; }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (status != KERN_SUCCESS) { return 0; }

    uint64_t result = 0;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (DBHVServiceMatchesBSDName(service, bsdName)) {
            IORegistryEntryGetRegistryEntryID(service, &result);
            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return result;
}

static IONVMeSMARTInterface **DBHVCreateInterface(const char *bsdName, uint64_t *registryEntryID) {
    if (registryEntryID != NULL) { *registryEntryID = 0; }

    CFMutableDictionaryRef matching = IOServiceMatching("IONVMeBlockStorageDevice");
    if (matching == NULL) { return NULL; }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (status != KERN_SUCCESS) { return NULL; }

    IONVMeSMARTInterface **result = NULL;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (!DBHVServiceMatchesBSDName(service, bsdName)) {
            IOObjectRelease(service);
            continue;
        }

        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        uint64_t matchedEntryID = 0;
        IORegistryEntryGetRegistryEntryID(service, &matchedEntryID);
        status = IOCreatePlugInInterfaceForService(
            service,
            kIONVMeSMARTUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        );
        IOObjectRelease(service);
        if (status != KERN_SUCCESS || plugin == NULL) { continue; }

        IONVMeSMARTInterface **smart = NULL;
        HRESULT query = (*plugin)->QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
            (LPVOID *)&smart
        );
        (*plugin)->Release(plugin);
        if (query != S_OK || smart == NULL) { continue; }

        result = smart;
        if (registryEntryID != NULL) { *registryEntryID = matchedEntryID; }
        break;
    }

    IOObjectRelease(iterator);
    return result;
}

static void DBHVInvalidateCachedInterface(const char *bsdName);

static IONVMeSMARTInterface **DBHVCachedInterface(const char *bsdName) {
    for (size_t index = 0; index < gInterfaceCacheCount; index++) {
        if (strcmp(gInterfaceCache[index].bsdName, bsdName) == 0) {
            uint64_t currentEntryID = DBHVCurrentRegistryEntryID(bsdName);
            if (currentEntryID != 0 && currentEntryID == gInterfaceCache[index].registryEntryID) {
                return gInterfaceCache[index].interface;
            }
            DBHVInvalidateCachedInterface(bsdName);
            break;
        }
    }

    if (gInterfaceCacheCount >= kDBHVMaximumCachedNVMeDevices) { return NULL; }
    uint64_t registryEntryID = 0;
    IONVMeSMARTInterface **smart = DBHVCreateInterface(bsdName, &registryEntryID);
    if (smart == NULL) { return NULL; }

    DBHVNVMeInterfaceCache *slot = &gInterfaceCache[gInterfaceCacheCount++];
    strncpy(slot->bsdName, bsdName, sizeof(slot->bsdName) - 1);
    slot->bsdName[sizeof(slot->bsdName) - 1] = '\0';
    slot->registryEntryID = registryEntryID;
    slot->interface = smart;
    return smart;
}

static void DBHVInvalidateCachedInterface(const char *bsdName) {
    for (size_t index = 0; index < gInterfaceCacheCount; index++) {
        DBHVNVMeInterfaceCache *slot = &gInterfaceCache[index];
        if (strcmp(slot->bsdName, bsdName) != 0) { continue; }
        if (slot->interface != NULL) { (*slot->interface)->Release(slot->interface); }
        size_t last = gInterfaceCacheCount - 1;
        if (index != last) { gInterfaceCache[index] = gInterfaceCache[last]; }
        memset(&gInterfaceCache[last], 0, sizeof(gInterfaceCache[last]));
        gInterfaceCacheCount--;
        return;
    }
}

void DBHVResetNVMeSMARTInterfaces(void) {
    // Releasing Apple's NVMe user client while the process remains alive can
    // make the controller refuse an immediate replacement interface. Keep the
    // cached client across sleep and window lifecycle events instead. Every
    // read validates the registry-entry identity, and a failed SMART read
    // invalidates and recreates only the affected interface. The process owns
    // the cache, so macOS reclaims it normally at application termination.
}

int32_t DBHVReadNVMeSMART(const char *bsdName, DBHVNVMeSMARTData *result) {
    if (bsdName == NULL || result == NULL) { return 0; }
    memset(result, 0, sizeof(*result));

    NVMeSMARTData data;
    IOReturn status = kIOReturnError;
    pthread_mutex_lock(&gInterfaceCacheLock);
    for (int attempt = 0; attempt < 3; attempt++) {
        // Apple NVMe controllers expect the user client to be reused during
        // normal polling. If it stops responding after sleep/wake or a
        // controller reset, release that exact interface before recreating it.
        IONVMeSMARTInterface **smart = DBHVCachedInterface(bsdName);
        if (smart == NULL) { break; }
        memset(&data, 0, sizeof(data));
        status = (*smart)->SMARTReadData(smart, &data);
        if (status == kIOReturnSuccess) { break; }
        DBHVInvalidateCachedInterface(bsdName);
        usleep(20 * 1000);
    }
    pthread_mutex_unlock(&gInterfaceCacheLock);
    if (status != kIOReturnSuccess) { return 0; }

    result->criticalWarning = data.CRITICAL_WARNING;
    result->percentageUsed = data.PERCENTAGE_USED;
    result->temperatureKelvin = data.TEMPERATURE;
    result->dataUnitsRead = DBHVLowUInt64(data.DATA_UNITS_READ);
    result->dataUnitsWritten = DBHVLowUInt64(data.DATA_UNITS_WRITTEN);
    result->powerCycles = DBHVLowUInt64(data.POWER_CYCLES);
    result->powerOnHours = DBHVLowUInt64(data.POWER_ON_HOURS);
    result->unsafeShutdowns = DBHVLowUInt64(data.UNSAFE_SHUTDOWNS);
    result->mediaErrors = DBHVLowUInt64(data.MEDIA_ERRORS);
    return 1;
}

static int32_t DBHVIntegerValue(CFDictionaryRef dictionary, CFStringRef key, int32_t fallback) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) { return fallback; }
    int32_t number = fallback;
    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &number);
    return number;
}

static int32_t DBHVBatteryTemperatureCentiCelsius(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("AppleSmartBattery");
    if (matching == NULL) { return -1; }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching);
    if (service == IO_OBJECT_NULL) { return -1; }

    CFTypeRef property = IORegistryEntryCreateCFProperty(
        service,
        CFSTR("Temperature"),
        kCFAllocatorDefault,
        0
    );
    IOObjectRelease(service);
    if (property == NULL || CFGetTypeID(property) != CFNumberGetTypeID()) {
        if (property != NULL) { CFRelease(property); }
        return -1;
    }

    int32_t temperature = -1;
    CFNumberGetValue((CFNumberRef)property, kCFNumberSInt32Type, &temperature);
    CFRelease(property);
    return temperature > 0 && temperature <= 12000 ? temperature : -1;
}

int32_t DBHVReadBatteryLiveStatus(DBHVBatteryLiveStatus *result) {
    if (result == NULL) { return 0; }
    memset(result, 0, sizeof(*result));
    result->temperatureCentiCelsius = DBHVBatteryTemperatureCentiCelsius();

    CFTypeRef snapshot = IOPSCopyPowerSourcesInfo();
    if (snapshot == NULL) { return 0; }
    CFArrayRef sources = IOPSCopyPowerSourcesList(snapshot);
    if (sources == NULL) {
        CFRelease(snapshot);
        return 0;
    }

    int32_t success = 0;
    CFIndex count = CFArrayGetCount(sources);
    for (CFIndex index = 0; index < count; index++) {
        CFTypeRef source = CFArrayGetValueAtIndex(sources, index);
        CFDictionaryRef description = IOPSGetPowerSourceDescription(snapshot, source);
        if (description == NULL) { continue; }

        CFTypeRef type = CFDictionaryGetValue(description, CFSTR(kIOPSTypeKey));
        if (type == NULL
            || CFGetTypeID(type) != CFStringGetTypeID()
            || CFStringCompare((CFStringRef)type, CFSTR(kIOPSInternalBatteryType), 0) != kCFCompareEqualTo) {
            continue;
        }

        int32_t current = DBHVIntegerValue(description, CFSTR(kIOPSCurrentCapacityKey), -1);
        int32_t maximum = DBHVIntegerValue(description, CFSTR(kIOPSMaxCapacityKey), -1);
        if (current < 0 || maximum <= 0) { continue; }

        int32_t percent = (current * 100 + maximum / 2) / maximum;
        result->chargePercent = percent < 0 ? 0 : (percent > 100 ? 100 : percent);
        result->isCharging = CFDictionaryGetValue(description, CFSTR(kIOPSIsChargingKey)) == kCFBooleanTrue;

        CFTypeRef state = CFDictionaryGetValue(description, CFSTR(kIOPSPowerSourceStateKey));
        result->externalConnected = state != NULL
            && CFGetTypeID(state) == CFStringGetTypeID()
            && CFStringCompare((CFStringRef)state, CFSTR(kIOPSACPowerValue), 0) == kCFCompareEqualTo;
        success = 1;
        break;
    }

    CFRelease(sources);
    CFRelease(snapshot);
    return success;
}
