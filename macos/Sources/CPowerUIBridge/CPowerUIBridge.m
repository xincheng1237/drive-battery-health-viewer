#import "CPowerUIBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import <unistd.h>

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

bool DBHVPowerUIEngageEighty(int32_t batteryPercentage) {
    @autoreleasepool {
        if (!DBHVPowerUIOpen()) return false;
        DBHVPowerUIStatus baseline;
        if (!DBHVReadStatus(&baseline)) return false;
        if (baseline.enabled == 1 && baseline.current_state == 1 && baseline.engaged == 1) {
            return true;
        }
        if (baseline.enabled != 0 || baseline.current_state != 0 ||
            (baseline.checkpoint != 10 && baseline.checkpoint != 0)) {
            return false;
        }

        int32_t level = MAX(0, MIN(100, batteryPercentage));
        if (baseline.checkpoint == 10) {
            if (!DBHVPostCheckpoint((uint64_t)level) ||
                !DBHVWaitFor(0, 0, 0, -1, 30, 100000)) {
                return false;
            }
        }

        NSDate *now = [NSDate date];
        NSDate *start = [now dateByAddingTimeInterval:-60.0];
        NSDate *deadline = [now dateByAddingTimeInterval:24.0 * 60.0 * 60.0];
        [DBHVPowerUIClient engageFrom:start
                                until:deadline
                          repeatUntil:deadline
                   overrideAllSignals:YES];
        if (!DBHVWaitFor(1, 1, 0, -1, 30, 100000)) {
            [DBHVPowerUIClient resetEngagementOverride];
            return false;
        }
        if (!DBHVPostCheckpoint((uint64_t)(100 + level)) ||
            !DBHVWaitFor(1, 1, 2, 1, 60, 100000)) {
            [DBHVPowerUIClient resetEngagementOverride];
            NSError *error = nil;
            [DBHVPowerUIClient disableSmartCharging:&error];
            return false;
        }
        return true;
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
        if (!disabled || error) return false;
        return DBHVWaitFor(0, 0, 10, 0, 40, 100000);
    }
}
