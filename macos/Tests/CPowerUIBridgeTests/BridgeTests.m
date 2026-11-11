#import <Foundation/Foundation.h>
#import <notify.h>
#include <unistd.h>
#include <assert.h>
#include <sys/sysctl.h>
#include <string.h>

// Isolate every notification and sleep used by the bridge. These tests never
// load a real PowerUI client and cannot write a system notification or charge.
static int notificationWrites;
static uint64_t lastCheckpointRequest;
static BOOL powerConnected = YES;
static bool FakeHasPower(void) { return powerConnected; }
static void (^onCheckpointPost)(void);
static uint64_t gaugingState;
static uint32_t registrationResult, readResult;
static const char *verifiedBuild = "24H212";
static int FakeSysctl(const char *name, void *value, size_t *size, void *newValue, size_t newSize) {
    size_t required = strlen(verifiedBuild) + 1;
    if (*size < required) return -1;
    memcpy(value, verifiedBuild, required); *size = required; return 0;
}
static uint32_t FakeGet(int token, uint64_t *state) { *state=gaugingState; return readResult; }
static uint32_t FakeRegister(const char *name, int *token) { *token=1; return registrationResult; }
static uint32_t FakeSet(int token, uint64_t state) { lastCheckpointRequest=state; notificationWrites++; return 0; }
static uint32_t FakePost(const char *name) { notificationWrites++; if (onCheckpointPost) onCheckpointPost(); return 0; }
static uint32_t FakeCancel(int token) { return 0; }
static int FakeSleep(useconds_t interval) { return 0; }
#define notify_register_check FakeRegister
#define notify_get_state FakeGet
#define sysctlbyname FakeSysctl
#define notify_set_state FakeSet
#define notify_post FakePost
#define notify_cancel FakeCancel
#define usleep FakeSleep
#import "../../Sources/CPowerUIBridge/CPowerUIBridge.m"

@interface FakeChargeClient : NSObject <DBHVSmartChargeClient>
@property(nonatomic,strong) NSDictionary *snapshot;
@property(nonatomic) int engagements;
@property(nonatomic) int resets;
@property(nonatomic) int disables;
@property(nonatomic) BOOL requestDuringEngagement;
@property(nonatomic) BOOL calibrationDuringEngagement;
@property(nonatomic) BOOL engaged;
@property(nonatomic) BOOL omitIsEngaged;
@property(nonatomic) BOOL unplugDuringEngagement;
@property(nonatomic,strong) NSDate *requestedDeadline;
@end
@implementation FakeChargeClient
- (instancetype)initWithClientName:(NSString *)name { return [self init]; }
- (NSDictionary *)status { return self.snapshot; }
- (NSDictionary *)powerLogStatus {
    if (self.omitIsEngaged) return @{};
    return @{@"isEngaged":@(self.engaged)};
}
- (void)engageFrom:(NSDate *)start until:(NSDate *)end repeatUntil:(NSDate *)repeat overrideAllSignals:(BOOL)override {
    self.engagements++;
    self.requestedDeadline=end;
    if (self.unplugDuringEngagement) powerConnected=NO;
    if (self.calibrationDuringEngagement) gaugingState=1;
    if (self.requestDuringEngagement) self.snapshot=@{@"Enabled":@YES,@"CurrentState":@3,@"Checkpoint":@0,@"TemporarilyDisabled":@YES};
}
- (void)resetEngagementOverride { self.resets++; }
- (BOOL)disableSmartCharging:(NSError **)error { self.disables++; return YES; }
@end

int main(void) { @autoreleasepool {
    FakeChargeClient *client=[FakeChargeClient new];
    DBHVPowerUIClient=client;
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@3,@"Checkpoint":@0,@"TemporarilyDisabled":@YES};
    DBHVPowerUIStatus state;
    assert(DBHVPowerUIReadStatus(&state) && state.temporarily_disabled==1);
    assert(!DBHVPowerUIEngageEighty(80, true, FakeHasPower));
    assert(!DBHVPowerUIRefreshEighty(80, FakeHasPower));
    assert(client.engagements==0 && client.resets==0 && client.disables==0 && notificationWrites==0);

    for (id value in @[@NO, @YES, @"1", @1.5, [NSNull null]]) {
        client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@2,@"TemporarilyDisabled":value};
        assert(DBHVPowerUIReadStatus(&state));
        int expected=[value isEqual:@YES]?1:([value isEqual:@NO]?0:-1);
        assert(state.temporarily_disabled==expected);
    }
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@2};
    assert(DBHVPowerUIReadStatus(&state) && state.temporarily_disabled==-1);

    // The request arrives during an in-flight engagement. Failure cleanup
    // must leave the new system choice alone, without reset or disable calls.
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@0,@"TemporarilyDisabled":@NO};
    client.requestDuringEngagement=YES;
    assert(!DBHVPowerUIEngageEighty(80, true, FakeHasPower));
    assert(client.engagements==1 && client.resets==0 && client.disables==0 && notificationWrites==0);
    client.engagements=0; client.requestDuringEngagement=NO;
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@2,@"TemporarilyDisabled":@NO};
    client.engaged=YES; gaugingState=1;
    assert(DBHVReadGaugingLimitSuspension()==1);
    assert(!DBHVPowerUIEngageEighty(80, true, FakeHasPower));
    assert(!DBHVPowerUIRefreshEighty(80, FakeHasPower));
    assert(client.engagements==0 && client.resets==0 && client.disables==0 && notificationWrites==0);

    verifiedBuild="unverified-build";
    assert(DBHVReadGaugingLimitSuspension()==-1);
    verifiedBuild="24H212"; gaugingState=2;
    assert(DBHVReadGaugingLimitSuspension()==-1);
    gaugingState=0; registrationResult=9;
    assert(DBHVReadGaugingLimitSuspension()==-1);
    registrationResult=0; readResult=9;
    assert(DBHVReadGaugingLimitSuspension()==-1);
    readResult=0;
    assert(DBHVReadGaugingLimitSuspension()==0);

    client.engaged=NO; client.calibrationDuringEngagement=YES;
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@0,@"TemporarilyDisabled":@NO};
    assert(!DBHVPowerUIEngageEighty(67, true, FakeHasPower));
    assert(client.engagements==1 && client.resets==0 && client.disables==0 && notificationWrites==0);

    // An expired or cleared owned request must be replaced, including above 80%.
    client.calibrationDuringEngagement=NO; gaugingState=0;
    client.engagements=0; notificationWrites=0;
    for (NSNumber *level in @[@70, @92, @99]) {
        client.engaged=NO;
        client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@NO};
        int previousRequests=client.engagements;
        NSDate *oldDeadline=[NSDate dateWithTimeIntervalSinceNow:-3600];
        client.requestedDeadline=oldDeadline;
        onCheckpointPost=^{
            client.engaged=level.intValue>=80;
            client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":client.engaged?@2:@1,@"TemporarilyDisabled":@NO};
        };
        assert(DBHVPowerUIEngageEighty(level.intValue, true, FakeHasPower));
        assert(client.engagements==previousRequests+1 && lastCheckpointRequest==100+level.intValue);
        assert([client.requestedDeadline timeIntervalSinceNow]>23*60*60);
        assert([client.requestedDeadline compare:oldDeadline]==NSOrderedDescending);
    }
    onCheckpointPost=nil;

    client.engaged=NO;
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@NO};
    int requests=client.engagements;
    int writes=notificationWrites;
    assert(!DBHVPowerUIEngageEighty(92, false, FakeHasPower));
    gaugingState=1;
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    gaugingState=0; readResult=9;
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    readResult=0;
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@YES};
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6};
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    assert(client.engagements==requests && notificationWrites==writes);
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@NO};
    client.requestDuringEngagement=YES;
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    client.requestDuringEngagement=NO;
    assert(client.engagements==requests+1 && notificationWrites==writes && client.resets==0 && client.disables==0);
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@NO};
    client.calibrationDuringEngagement=YES;
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    client.calibrationDuringEngagement=NO;
    assert(client.engagements==requests+2 && notificationWrites==writes && client.resets==0 && client.disables==0);
    gaugingState=0;
    assert(!DBHVPowerUIEngageEighty(92, true, FakeHasPower));
    assert(client.engagements==requests+3 && notificationWrites==writes+2 && client.resets==0 && client.disables==0);

    // The system decoded a full-battery payload as a 0% power event.
    // Never post 100 or 200 through the checkpoint transport.
    client.snapshot=@{@"Enabled":@NO,@"CurrentState":@0,@"Checkpoint":@10,@"TemporarilyDisabled":@NO};
    requests=client.engagements; writes=notificationWrites;
    assert(!DBHVPowerUIEngageEighty(100, false, FakeHasPower));
    assert(notificationWrites==writes && client.engagements==requests);
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@2,@"TemporarilyDisabled":@NO};
    client.engaged=YES;
    assert(!DBHVPowerUIRefreshEighty(100, FakeHasPower));
    assert(notificationWrites==writes && client.engagements==requests);
    assert(!DBHVPowerUIEngageEighty(-1, true, FakeHasPower));
    assert(!DBHVPowerUIEngageEighty(101, true, FakeHasPower));
    assert(notificationWrites==writes && client.engagements==requests);
    client.snapshot=@{@"Enabled":@YES,@"CurrentState":@1,@"Checkpoint":@6,@"TemporarilyDisabled":@NO};
    client.engaged=NO;
    powerConnected=NO;
    assert(!DBHVPowerUIEngageEighty(79, true, FakeHasPower));
    assert(notificationWrites==writes && client.engagements==requests);
    powerConnected=YES;
    client.unplugDuringEngagement=YES;
    assert(!DBHVPowerUIEngageEighty(79, true, FakeHasPower));
    assert(notificationWrites==writes && client.engagements==requests+1);
    assert(client.resets==0 && client.disables==0);
    client.unplugDuringEngagement=NO;
    powerConnected=YES;
    puts("PASS: disconnect during engagement suppresses checkpoint writes");

    puts("PASS: full and invalid battery readings cannot post ambiguous power events");

    puts("PASS: expired Checkpoint 6 re-engages below and above 80%, with a fresh deadline");
    puts("PASS: system full charge, calibration, unknown flags/builds, notification failures, and in-flight transitions never issue unintended control writes");

    // 1. Boundary 0 and 100 percent
    requests = client.engagements; writes = notificationWrites;
    assert(!DBHVPowerUIEngageEighty(0, true, FakeHasPower));
    assert(!DBHVPowerUIEngageEighty(0, false, FakeHasPower));
    assert(!DBHVPowerUIRefreshEighty(0, FakeHasPower));
    assert(client.engagements == requests && notificationWrites == writes);
    puts("PASS: 0% and 100% boundary cannot post checkpoints or engage XPC");

    // 2. Disengaged checkpoints 0, 1, 2, 5, 6 with ownsPolicy == true all recover to Checkpoint 2
    for (NSNumber *cp in @[@0, @1, @2, @5, @6]) {
        client.engaged = NO;
        client.snapshot = @{@"Enabled":@YES, @"CurrentState":@1, @"Checkpoint":cp, @"TemporarilyDisabled":@NO};
        gaugingState = 0; readResult = 0;
        requests = client.engagements; writes = notificationWrites;
        onCheckpointPost = ^{
            client.engaged = YES;
            client.snapshot = @{@"Enabled":@YES, @"CurrentState":@1, @"Checkpoint":@2, @"TemporarilyDisabled":@NO};
        };
        // Unowned must be rejected!
        assert(!DBHVPowerUIEngageEighty(80, false, FakeHasPower));
        assert(client.engagements == requests && notificationWrites == writes);
        // Owned must succeed and recover!
        assert(DBHVPowerUIEngageEighty(80, true, FakeHasPower));
        assert(client.engagements == requests + 1);
        onCheckpointPost = nil;
    }
    puts("PASS: owned disengaged checkpoints 0, 1, 2, 5, 6 all recover while unowned remain protected");

    // 3. Disable does not clobber system calibration (gauging=1) or system override (temporarily_disabled=1, checkpoint=10)
    int resets = client.resets; int disables = client.disables;
    gaugingState = 1;
    client.snapshot = @{@"Enabled":@YES, @"CurrentState":@1, @"Checkpoint":@2, @"TemporarilyDisabled":@NO};
    assert(DBHVPowerUIDisable());
    assert(client.resets == resets && client.disables == disables);
    gaugingState = 0;

    client.snapshot = @{@"Enabled":@YES, @"CurrentState":@3, @"Checkpoint":@10, @"TemporarilyDisabled":@YES};
    assert(DBHVPowerUIDisable());
    assert(client.resets == resets && client.disables == disables);

    client.snapshot = @{@"Enabled":@NO, @"CurrentState":@0, @"Checkpoint":@10, @"TemporarilyDisabled":@NO};
    assert(DBHVPowerUIDisable());
    assert(client.resets == resets && client.disables == disables);
    puts("PASS: DBHVPowerUIDisable never clobbers system calibration or system full charge");

    // 4. Missing isEngaged in powerLogStatus defaults to 0
    client.snapshot = @{@"Enabled":@YES, @"CurrentState":@1, @"Checkpoint":@2, @"TemporarilyDisabled":@NO};
    client.omitIsEngaged = YES;
    assert(DBHVPowerUIReadStatus(&state));
    assert(state.engaged == 0);
    client.omitIsEngaged = NO;
    puts("PASS: missing isEngaged in powerLogStatus defaults to 0");

    // 5. DBHVPowerUIRequestAbort interrupts in-flight wait loops immediately
    DBHVPowerUIClearAbortForTesting();
    DBHVPowerUIRequestAbort();
    client.snapshot = @{@"Enabled":@NO, @"CurrentState":@0, @"Checkpoint":@0, @"TemporarilyDisabled":@NO};
    assert(!DBHVPowerUIEngageEighty(80, false, FakeHasPower));
    DBHVPowerUIClearAbortForTesting();
    puts("PASS: DBHVPowerUIRequestAbort interrupts wait loops immediately");
} return 0; }
