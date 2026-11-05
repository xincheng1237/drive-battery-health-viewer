#import "CPowerUIBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <unistd.h>
#include <sys/sysctl.h>
#include <string.h>

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

static bool DBHVSystemDefersEighty(DBHVPowerUIStatus status) {
    return status.temporarily_disabled == 1 || DBHVReadGaugingLimitSuspension() == 1;
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
        output->engaged = output->enabled == 1 && output->current_state == 1;
    }
    return output->enabled >= 0 && output->current_state >= 0 && output->checkpoint >= 0;
}

static bool DBHVWaitFor(int32_t enabled, int32_t state, int32_t checkpoint, int32_t engaged,
                        int attempts, useconds_t delay) {
    for (int attempt = 0; attempt < attempts; attempt++) {
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
    @autoreleasepool {
        if (DBHVPowerUIClient) {
            DBHVPowerUIStatus snapshot;
            return DBHVReadStatus(&snapshot);
        }
        DBHVPowerUIHandle = dlopen(
            "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI",
            RTLD_NOW | RTLD_LOCAL
        );
        if (!DBHVPowerUIHandle) return false;
        Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
        if (!clientClass) return false;
        DBHVPowerUIClient = [[clientClass alloc] initWithClientName:@"DriveBatteryHealthViewer"];
        DBHVPowerUIStatus snapshot;
        return DBHVReadStatus(&snapshot);
    }
}

bool DBHVPowerUIReadStatus(DBHVPowerUIStatus *status) {
    @autoreleasepool {
        return DBHVPowerUIOpen() && DBHVReadStatus(status);
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

static bool DBHVWaitForEightyManaged(int attempts, useconds_t delay) {
    for (int attempt = 0; attempt < attempts; attempt++) {
        DBHVPowerUIStatus snapshot;
        if (DBHVReadStatus(&snapshot) && DBHVIsEightyManaged(snapshot)) {
            return true;
        }
        usleep(delay);
    }
    return false;
}

static bool DBHVScheduleEighty(int32_t batteryPercentage) {
    DBHVPowerUIStatus before;
    if (!DBHVReadStatus(&before) || DBHVSystemDefersEighty(before)) return false;
    int32_t level = MAX(0, MIN(100, batteryPercentage));
    NSDate *now = [NSDate date];
    NSDate *start = [now dateByAddingTimeInterval:-60.0];
    NSDate *deadline = [now dateByAddingTimeInterval:24.0 * 60.0 * 60.0];
    [DBHVPowerUIClient engageFrom:start
                            until:deadline
                      repeatUntil:deadline
               overrideAllSignals:YES];
    if (!DBHVWaitFor(1, 1, -1, -1, 30, 100000)) return false;
    DBHVPowerUIStatus after;
    if (!DBHVReadStatus(&after) || DBHVSystemDefersEighty(after)) return false;
    if (!DBHVPostCheckpoint((uint64_t)(100 + level))) return false;
    return DBHVWaitForEightyManaged(60, 100000);
}

bool DBHVPowerUIEngageEighty(int32_t batteryPercentage) {
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) return false;
        DBHVPowerUIStatus baseline;
        if (!DBHVReadStatus(&baseline)) return false;
        if (DBHVSystemDefersEighty(baseline)) return false;
        if (DBHVIsEightyManaged(baseline)) {
            return true;
        }

        bool cleanBaseline = baseline.enabled == 0 && baseline.current_state == 0 &&
            (baseline.checkpoint == 10 || baseline.checkpoint == 0);
        bool ownedTopOffTransition = baseline.enabled == 1 && baseline.current_state == 1 &&
            (baseline.checkpoint == 0 || baseline.checkpoint == 5);
        if (!cleanBaseline && !ownedTopOffTransition) {
            return false;
        }

        int32_t level = MAX(0, MIN(100, batteryPercentage));
        if (cleanBaseline && baseline.checkpoint == 10) {
            if (!DBHVPostCheckpoint((uint64_t)level) ||
                !DBHVWaitFor(0, 0, 0, -1, 30, 100000)) {
                return false;
            }
        }

        if (!DBHVScheduleEighty(level)) {
            // A system-menu override may have arrived during the request.
            // Never clear that user action as part of our failure cleanup.
            DBHVPowerUIStatus current;
            if (DBHVReadStatus(&current) && DBHVSystemDefersEighty(current)) return false;
            [DBHVPowerUIClient resetEngagementOverride];
            NSError *error = nil;
            [DBHVPowerUIClient disableSmartCharging:&error];
            return false;
        }
        return true;
    }
}

bool DBHVPowerUIRefreshEighty(int32_t batteryPercentage) {
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) return false;
        DBHVPowerUIStatus baseline;
        if (!DBHVReadStatus(&baseline) || !DBHVIsEightyManaged(baseline)) return false;
        return DBHVScheduleEighty(batteryPercentage);
    }
}

bool DBHVPowerUIDisable(void) {
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) return false;
        DBHVPowerUIStatus initial;
        if (DBHVReadStatus(&initial) && initial.enabled == 0 &&
            initial.current_state == 0 && initial.checkpoint == 10) {
            return true;
        }
        [DBHVPowerUIClient resetEngagementOverride];
        usleep(300000);
        NSError *error = nil;
        BOOL disabled = [DBHVPowerUIClient disableSmartCharging:&error];
        if (disabled && !error && DBHVWaitFor(0, 0, 10, 0, 40, 100000)) {
            return true;
        }

        // Checkpoint 5 is PowerUI's normal-charging top-off state. If the
        // private disable call is entitlement-gated on a beta build, a reset
        // override can still leave this safe state behind. It has no 80%
        // charge token and must be accepted as restored rather than reported
        // as a successful hold.
        DBHVPowerUIStatus final;
        return DBHVReadStatus(&final) && final.enabled == 1 &&
            final.current_state == 1 && final.checkpoint == 5 && final.engaged == 0;
    }
}
