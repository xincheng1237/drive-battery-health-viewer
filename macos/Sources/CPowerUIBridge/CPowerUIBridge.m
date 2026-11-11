#import "CPowerUIBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <unistd.h>
#include <sys/sysctl.h>
#include <string.h>
#include <pthread.h>
#include <stdatomic.h>

@protocol DBHVSmartChargeClient
- (instancetype)initWithClientName:(NSString *)name;
- (NSDictionary *)status;
- (NSDictionary *)powerLogStatus;
- (void)engageFrom:(NSDate *)start
             until:(NSDate *)deadline
       repeatUntil:(NSDate *)repeatUntil
overrideAllSignals:(BOOL)overrideAllSignals;
- (void)resetEngagementOverride;
- (BOOL)disableSmartCharging:(NSError **)error;
@end

static void *DBHVPowerUIHandle;
static id<DBHVSmartChargeClient> DBHVPowerUIClient;

static atomic_bool gDBHVPowerUIAbortRequested = false;
static pthread_mutex_t gDBHVPowerUIMutex;

void DBHVPowerUIRequestAbort(void) {
    atomic_store(&gDBHVPowerUIAbortRequested, true);
}

void DBHVPowerUIClearAbortForTesting(void) {
    atomic_store(&gDBHVPowerUIAbortRequested, false);
}

static void DBHVInitMutex(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&gDBHVPowerUIMutex, &attr);
        pthread_mutexattr_destroy(&attr);
    });
}

#define DBHV_LOCK() do { DBHVInitMutex(); pthread_mutex_lock(&gDBHVPowerUIMutex); } while (0)
#define DBHV_UNLOCK() do { pthread_mutex_unlock(&gDBHVPowerUIMutex); } while (0)

int32_t DBHVReadGaugingLimitSuspension(void) {
    // Verified against both powerd slices in macOS 15.8.1 / 24H212.
    // Private notification names can register successfully even on builds
    // without a publisher, so registration success alone is not support.
    char build[128] = {0};
    size_t length = sizeof(build);
    if (sysctlbyname("kern.osversion", build, &length, NULL, 0) != 0 ||
        strcmp(build, "24H212") != 0) return -1;
    int token = NOTIFY_TOKEN_INVALID;
    uint64_t state = 0;
    if (notify_register_check("com.apple.system.powersources.gaugingmitigation", &token) != NOTIFY_STATUS_OK) return -1;
    uint32_t result = notify_get_state(token, &state);
    notify_cancel(token);
    if (result != NOTIFY_STATUS_OK || state > 1) return -1;
    return (int32_t)state;
}

bool DBHVSystemDefersEighty(DBHVPowerUIStatus status) {
    return status.temporarily_disabled == 1 || DBHVReadGaugingLimitSuspension() == 1 ||
           status.current_state == 3 || status.checkpoint == 10;
}

static bool DBHVMayScheduleEighty(DBHVPowerUIStatus status, bool requireKnownInactive) {
    if (DBHVSystemDefersEighty(status)) return false;
    if (requireKnownInactive) {
        return status.temporarily_disabled == 0 && DBHVReadGaugingLimitSuspension() == 0;
    }
    return status.temporarily_disabled != 1 && DBHVReadGaugingLimitSuspension() != 1;
}

static int32_t DBHVInteger(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    return [value respondsToSelector:@selector(intValue)] ? [value intValue] : -1;
}

static bool DBHVReadStatus(DBHVPowerUIStatus *output) {
    if (!DBHVPowerUIClient || !output) return false;
    NSDictionary *status = [DBHVPowerUIClient status];
    NSDictionary *powerLog = [DBHVPowerUIClient powerLogStatus];
    if (![status isKindOfClass:[NSDictionary class]] || status.count == 0) return false;

    output->enabled = DBHVInteger(status, @"Enabled");
    output->current_state = DBHVInteger(status, @"CurrentState");
    output->checkpoint = DBHVInteger(status, @"Checkpoint");
    id temporary = status[@"TemporarilyDisabled"];
    output->temporarily_disabled = -1;
    if ([temporary isKindOfClass:[NSNumber class]] &&
        ([temporary isEqualToNumber:@0] || [temporary isEqualToNumber:@1])) {
        output->temporarily_disabled = [temporary intValue];
    }
    output->engaged = DBHVInteger(powerLog, @"isEngaged");
    if (output->engaged < 0) {
        output->engaged = 0;
    }
    return output->enabled >= 0 && output->current_state >= 0 && output->checkpoint >= 0;
}

static bool DBHVWaitFor(int32_t enabled, int32_t state, int32_t checkpoint, int32_t engaged,
                        int attempts, useconds_t delay) {
    for (int attempt = 0; attempt < attempts; attempt++) {
        if (atomic_load(&gDBHVPowerUIAbortRequested)) return false;
        DBHVPowerUIStatus snapshot;
        if (DBHVReadStatus(&snapshot) &&
            (enabled < 0 || snapshot.enabled == enabled) &&
            (state < 0 || snapshot.current_state == state) &&
            (checkpoint < 0 || snapshot.checkpoint == checkpoint) &&
            (engaged < 0 || snapshot.engaged == engaged)) {
            return true;
        }
        usleep(delay);
    }
    return false;
}

static bool DBHVPostCheckpoint(uint64_t state) {
    static const char *name = "com.apple.powerui.checkpoint";
    int token = NOTIFY_TOKEN_INVALID;
    uint32_t result = notify_register_check(name, &token);
    if (result == NOTIFY_STATUS_OK) result = notify_set_state(token, state);
    if (result == NOTIFY_STATUS_OK) result = notify_post(name);
    if (token != NOTIFY_TOKEN_INVALID) notify_cancel(token);
    return result == NOTIFY_STATUS_OK;
}

bool DBHVPowerUIOpen(void) {
    DBHV_LOCK();
    @autoreleasepool {
        if (DBHVPowerUIClient) {
            DBHVPowerUIStatus snapshot;
            bool ok = DBHVReadStatus(&snapshot);
            DBHV_UNLOCK();
            return ok;
        }
        DBHVPowerUIHandle = dlopen(
            "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI",
            RTLD_NOW | RTLD_LOCAL
        );
        if (!DBHVPowerUIHandle) {
            DBHV_UNLOCK();
            return false;
        }
        Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
        if (!clientClass) {
            DBHV_UNLOCK();
            return false;
        }
        DBHVPowerUIClient = [[clientClass alloc] initWithClientName:@"DriveBatteryHealthViewer"];
        DBHVPowerUIStatus snapshot;
        bool ok = DBHVReadStatus(&snapshot);
        DBHV_UNLOCK();
        return ok;
    }
}

bool DBHVPowerUIReadStatus(DBHVPowerUIStatus *status) {
    DBHV_LOCK();
    @autoreleasepool {
        bool ok = DBHVPowerUIOpen() && DBHVReadStatus(status);
        DBHV_UNLOCK();
        return ok;
    }
}

static bool DBHVIsEightyEngaged(DBHVPowerUIStatus status) {
    return !DBHVSystemDefersEighty(status) && status.enabled == 1 && status.current_state == 1 &&
        status.checkpoint == 2 && status.engaged == 1;
}

// Checkpoint 1 means PowerUI has accepted the 80% policy and is charging
// toward the limit. Checkpoint 2 means the battery has reached the limit and
// PowerUI is actively holding it there. Both are successful managed states;
// only checkpoint 2 should be presented to the user as "holding".
static bool DBHVIsEightyManaged(DBHVPowerUIStatus status) {
    return !DBHVSystemDefersEighty(status) && status.enabled == 1 && status.current_state == 1 &&
        (status.checkpoint == 1 || DBHVIsEightyEngaged(status));
}

static bool DBHVWaitForEightyManaged(int attempts, useconds_t delay, bool requireKnownInactive) {
    for (int attempt = 0; attempt < attempts; attempt++) {
        if (atomic_load(&gDBHVPowerUIAbortRequested)) return false;
        DBHVPowerUIStatus snapshot;
        if (DBHVReadStatus(&snapshot)) {
            if (!DBHVMayScheduleEighty(snapshot, requireKnownInactive)) return false;
            if (DBHVIsEightyManaged(snapshot)) return true;
        }
        usleep(delay);
    }
    return false;
}

static bool DBHVWaitForEightyEngaged(int attempts, useconds_t delay) {
    for (int attempt = 0; attempt < attempts; attempt++) {
        if (atomic_load(&gDBHVPowerUIAbortRequested)) return false;
        DBHVPowerUIStatus snapshot;
        if (DBHVReadStatus(&snapshot)) {
            if (DBHVSystemDefersEighty(snapshot)) return false;
            if (DBHVIsEightyEngaged(snapshot)) return true;
        }
        usleep(delay);
    }
    return false;
}

// The checkpoint payload uses two decimal digits for the battery level (1..99).
// Level 0 and 100 cannot be safely encoded without collision or ambiguous adapter events.
static bool DBHVCanEncodeCheckpointLevel(int32_t level) {
    return level >= 1 && level < 100;
}

static bool DBHVScheduleEighty(int32_t batteryPercentage, bool requireKnownInactive,
                              DBHVPowerUIExternalPowerCheck hasPower) {
    if (!DBHVCanEncodeCheckpointLevel(batteryPercentage)) return false;
    DBHVPowerUIStatus before;
    if (!DBHVReadStatus(&before) || !DBHVMayScheduleEighty(before, requireKnownInactive) || !hasPower()) return false;
    NSDate *now = [NSDate date];
    NSDate *start = [now dateByAddingTimeInterval:-60.0];
    NSDate *deadline = [now dateByAddingTimeInterval:24.0 * 60.0 * 60.0];
    [DBHVPowerUIClient engageFrom:start
                            until:deadline
                      repeatUntil:deadline
               overrideAllSignals:YES];
    if (!DBHVWaitFor(1, 1, -1, -1, 30, 100000)) return false;
    DBHVPowerUIStatus after;
    if (!DBHVReadStatus(&after) || !DBHVMayScheduleEighty(after, requireKnownInactive) || !hasPower()) return false;
    if (!DBHVPostCheckpoint((uint64_t)(100 + batteryPercentage))) return false;

    if (batteryPercentage >= 80) {
        // Prioritize waiting for Checkpoint 2 (engaged = 1)
        if (DBHVWaitForEightyEngaged(20, 150000) && hasPower()) {
            return true;
        }
        // If not engaged but in Checkpoint 1, reassert checkpoint once more
        DBHVPowerUIStatus mid;
        if (DBHVReadStatus(&mid) && mid.enabled == 1 && mid.current_state == 1 &&
            mid.checkpoint == 1 && hasPower()) {
            DBHVPostCheckpoint((uint64_t)(100 + batteryPercentage));
            if (DBHVWaitForEightyEngaged(10, 150000) && hasPower()) {
                return true;
            }
        }
        // If accepted by PowerUI (Checkpoint 1 or 2), return true so upper-layer
        // PowerUIOverchargeMonitor can govern re-assertion and overcharge detection.
        DBHVPowerUIStatus finalStatus;
        return DBHVReadStatus(&finalStatus) && DBHVIsEightyManaged(finalStatus) && hasPower();
    }

    return DBHVWaitForEightyManaged(60, 100000, requireKnownInactive) && hasPower();
}

bool DBHVPowerUIEngageEighty(int32_t batteryPercentage, bool ownsPolicy, DBHVPowerUIExternalPowerCheck hasPower) {
    if (!hasPower || !hasPower()) return false;
    DBHV_LOCK();
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) {
            DBHV_UNLOCK();
            return false;
        }
        DBHVPowerUIStatus baseline;
        if (!DBHVReadStatus(&baseline)) {
            DBHV_UNLOCK();
            return false;
        }
        if (DBHVSystemDefersEighty(baseline)) {
            DBHV_UNLOCK();
            return false;
        }

        // Boundary check: level must be in 1..99.
        if (!DBHVCanEncodeCheckpointLevel(batteryPercentage)) {
            DBHV_UNLOCK();
            return false;
        }

        // If battery < 80% and already managed, or battery >= 80% and already engaged:
        if (batteryPercentage < 80 ? DBHVIsEightyManaged(baseline) : DBHVIsEightyEngaged(baseline)) {
            DBHV_UNLOCK();
            return ownsPolicy;
        }

        bool cleanBaseline = baseline.enabled == 0 && baseline.current_state == 0 &&
            (baseline.checkpoint == 10 || baseline.checkpoint == 0);
        bool ownedEnabled = ownsPolicy && baseline.enabled == 1 && baseline.current_state == 1;
        // Expand owned recovery check to include checkpoints 0, 1, 2, 5, 6 with engaged == 0
        bool recoverableOwnedPolicy = ownedEnabled && baseline.engaged == 0 &&
            (baseline.checkpoint == 0 || baseline.checkpoint == 1 || baseline.checkpoint == 2 ||
             baseline.checkpoint == 5 || baseline.checkpoint == 6) &&
            DBHVMayScheduleEighty(baseline, true);

        if (!cleanBaseline && !recoverableOwnedPolicy) {
            DBHV_UNLOCK();
            return false;
        }

        if (cleanBaseline && baseline.checkpoint == 10) {
            if (!hasPower() || !DBHVPostCheckpoint((uint64_t)batteryPercentage) ||
                !DBHVWaitFor(0, 0, 0, -1, 30, 100000)) {
                DBHV_UNLOCK();
                return false;
            }
        }

        if (!DBHVScheduleEighty(batteryPercentage, recoverableOwnedPolicy, hasPower)) {
            // Leave owned schedules in place for the next verification.
            // Only roll back a failed first request with readable pause state.
            DBHVPowerUIStatus current;
            if (ownsPolicy || !DBHVReadStatus(&current) || current.temporarily_disabled != 0 ||
                DBHVReadGaugingLimitSuspension() == 1) {
                DBHV_UNLOCK();
                return false;
            }
            usleep(300000);
            [DBHVPowerUIClient resetEngagementOverride];
            NSError *error = nil;
            [DBHVPowerUIClient disableSmartCharging:&error];
            DBHV_UNLOCK();
            return false;
        }
        DBHV_UNLOCK();
        return true;
    }
}

bool DBHVPowerUIRefreshEighty(int32_t batteryPercentage, DBHVPowerUIExternalPowerCheck hasPower) {
    if (!DBHVCanEncodeCheckpointLevel(batteryPercentage) || !hasPower || !hasPower()) return false;
    DBHV_LOCK();
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) {
            DBHV_UNLOCK();
            return false;
        }
        DBHVPowerUIStatus baseline;
        if (!DBHVReadStatus(&baseline) || !DBHVIsEightyManaged(baseline)) {
            DBHV_UNLOCK();
            return false;
        }
        bool result = DBHVScheduleEighty(batteryPercentage, false, hasPower);
        DBHV_UNLOCK();
        return result;
    }
}

bool DBHVPowerUIDisable(void) {
    DBHV_LOCK();
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) {
            DBHV_UNLOCK();
            return false;
        }
        DBHVPowerUIStatus initial;
        if (DBHVReadStatus(&initial)) {
            if (initial.enabled == 0 && initial.current_state == 0 && initial.checkpoint == 10) {
                DBHV_UNLOCK();
                return true;
            }
            if (DBHVSystemDefersEighty(initial)) {
                // Never clobber active system calibration or system full charge!
                DBHV_UNLOCK();
                return true;
            }
        }
        [DBHVPowerUIClient resetEngagementOverride];
        usleep(300000);
        NSError *error = nil;
        BOOL disabled = [DBHVPowerUIClient disableSmartCharging:&error];
        if (disabled && !error && DBHVWaitFor(0, 0, 10, 0, 40, 100000)) {
            DBHV_UNLOCK();
            return true;
        }

        DBHVPowerUIStatus final;
        bool result = DBHVReadStatus(&final) && final.enabled == 1 &&
            final.current_state == 1 && final.checkpoint == 5 && final.engaged == 0;
        DBHV_UNLOCK();
        return result;
    }
}
