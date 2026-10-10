// Diagnostic fixture using this repository's private CGVirtualDisplay
// declarations. Owns one 1280x720 display until EOF/stop; never configures
// another display. Build: clang++ -fobjc-arc -std=c++17 -framework Cocoa
// -framework CoreGraphics
//        native/diagnostic-display-modes.mm -o
//        /private/tmp/node-vdisplay-mode-fixture
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

@class CGVirtualDisplayDescriptor;
@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(CGFloat)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@end
@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end
@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

static void Emit(NSDictionary *value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value
                                                 options:NSJSONWritingSortedKeys
                                                   error:NULL];
  if (!data)
    return;
  NSMutableData *line = [data mutableCopy];
  [line appendBytes:"\n" length:1];
  const uint8_t *bytes = (const uint8_t *)line.bytes;
  size_t remaining = line.length;
  while (remaining > 0) {
    ssize_t amount = write(STDOUT_FILENO, bytes, remaining);
    if (amount > 0) {
      bytes += amount;
      remaining -= (size_t)amount;
    } else if (amount < 0 && errno == EINTR)
      continue;
    else
      return;
  }
}

static NSDictionary *ConnectionState(CGDirectDisplayID display) {
  // macOS 27 returns -1 from IsOnline/IsActive for removed and invalid IDs.
  // Treat list membership as authoritative, and expose raw results separately.
  CGDirectDisplayID onlineIDs[256], activeIDs[256];
  uint32_t onlineCount = 0, activeCount = 0;
  CGError onlineStatus = CGGetOnlineDisplayList(256, onlineIDs, &onlineCount);
  CGError activeStatus = CGGetActiveDisplayList(256, activeIDs, &activeCount);
  NSMutableArray *online = [NSMutableArray array],
                 *active = [NSMutableArray array];
  BOOL foundOnline = NO, foundActive = NO;
  for (uint32_t i = 0; onlineStatus == kCGErrorSuccess && i < onlineCount;
       i++) {
    [online addObject:@(onlineIDs[i])];
    if (onlineIDs[i] == display)
      foundOnline = YES;
  }
  for (uint32_t i = 0; activeStatus == kCGErrorSuccess && i < activeCount;
       i++) {
    [active addObject:@(activeIDs[i])];
    if (activeIDs[i] == display)
      foundActive = YES;
  }
  CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
  BOOL hasMode = mode != NULL;
  if (mode)
    CFRelease(mode);
  return @{
    @"online" : @(foundOnline),
    @"active" : @(foundActive),
    @"currentModePresent" : @(hasMode),
    @"onlineListStatus" : @(onlineStatus),
    @"activeListStatus" : @(activeStatus),
    @"onlineDisplayIds" : online,
    @"activeDisplayIds" : active,
    @"cgDisplayIsOnlineRaw" : @((int64_t)CGDisplayIsOnline(display)),
    @"cgDisplayIsActiveRaw" : @((int64_t)CGDisplayIsActive(display))
  };
}

@interface ModeFixture : NSObject
@property(nonatomic, strong) CGVirtualDisplayDescriptor *descriptor;
@property(nonatomic, strong) CGVirtualDisplaySettings *settings;
@property(nonatomic, strong) CGVirtualDisplay *display;
@property(nonatomic, strong) dispatch_source_t inputSource;
@property(nonatomic, strong) dispatch_source_t interruptSource;
@property(nonatomic, strong) dispatch_source_t terminateSource;
@property(nonatomic, strong) NSMutableData *input;
@property(nonatomic, strong) NSMutableArray<NSString *> *commands;
@property(nonatomic) CGDirectDisplayID ownDisplayID;
@property(nonatomic) CGDirectDisplayID originalMainDisplayID;
@property(nonatomic) NSUInteger sequence;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL stopping;
@property(nonatomic) BOOL failed;
- (void)start:(int)initialHz;
- (void)stop;
@end

@implementation ModeFixture
- (NSDictionary *)snapshot {
  CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.ownDisplayID);
  NSMutableDictionary *value = [@{
    @"displayId" : @(self.ownDisplayID),
    @"mainDisplayId" : @(CGMainDisplayID()),
    @"originalMainDisplayId" : @(self.originalMainDisplayID),
    @"online" : @(CGDisplayIsOnline(self.ownDisplayID) > 0),
    @"mirrorsDisplayId" : @(CGDisplayMirrorsDisplay(self.ownDisplayID)),
    @"inMirrorSet" : @(CGDisplayIsInMirrorSet(self.ownDisplayID)),
    @"actualRefreshRate" : mode ? @(CGDisplayModeGetRefreshRate(mode)) : @0,
    @"physicalWidth" : mode ? @(CGDisplayModeGetPixelWidth(mode)) : @0,
    @"physicalHeight" : mode ? @(CGDisplayModeGetPixelHeight(mode)) : @0,
    @"logicalWidth" : mode ? @(CGDisplayModeGetWidth(mode)) : @0,
    @"logicalHeight" : mode ? @(CGDisplayModeGetHeight(mode)) : @0
  } mutableCopy];
  if (mode)
    CFRelease(mode);
  CFArrayRef copied = CGDisplayCopyAllDisplayModes(self.ownDisplayID, NULL);
  NSMutableArray *rates = [NSMutableArray array];
  for (id object in (__bridge NSArray *)copied) {
    CGDisplayModeRef candidate = (__bridge CGDisplayModeRef)object;
    if (CGDisplayModeGetPixelWidth(candidate) != 1280 ||
        CGDisplayModeGetPixelHeight(candidate) != 720 ||
        CGDisplayModeGetWidth(candidate) != 1280 ||
        CGDisplayModeGetHeight(candidate) != 720)
      continue;
    NSNumber *rate = @(CGDisplayModeGetRefreshRate(candidate));
    if (![rates containsObject:rate])
      [rates addObject:rate];
  }
  if (copied)
    CFRelease(copied);
  value[@"availableModes"] =
      [rates sortedArrayUsingSelector:@selector(compare:)];
  return value;
}
- (void)fail:(NSString *)message {
  if (self.stopping)
    return;
  self.failed = YES;
  Emit(@{
    @"stage" : @"error",
    @"message" : message,
    @"displayId" : @(self.ownDisplayID)
  });
  [self stop];
}
- (void)start:(int)initialHz {
  self.originalMainDisplayID = CGMainDisplayID();
  self.input = [NSMutableData data];
  self.commands = [NSMutableArray array];
  _descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  _descriptor.name =
      [NSString stringWithFormat:@"Node Capture Mode Diagnostic %d", getpid()];
  _descriptor.maxPixelsWide = 1280;
  _descriptor.maxPixelsHigh = 720;
  _descriptor.sizeInMillimeters = CGSizeMake(1280 * 25.4 / 81, 720 * 25.4 / 81);
  _descriptor.vendorID = 0xeeee;
  _descriptor.productID = 0xd160;
  _descriptor.serialNum = arc4random_uniform(UINT32_MAX - 1) + 1;
  // Keep private display servicing independent of AppKit's main event loop.
  // The production addon leaves this at its default; explicitly choosing the
  // global queue here avoids starving private work on the fixture's main loop.
  [_descriptor setDispatchQueue:dispatch_get_global_queue(
                                    QOS_CLASS_USER_INTERACTIVE, 0)];
  _descriptor.terminationHandler = ^(id ignored, CGVirtualDisplay *display) {
  };
  Emit(@{@"stage" : @"startup", @"step" : @"create-display"});
  _display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
  if (!_display) {
    [self fail:@"Unable to create owned diagnostic virtual display"];
    return;
  }
  self.ownDisplayID = _display.displayID;
  if (self.ownDisplayID == 0 ||
      self.ownDisplayID == self.originalMainDisplayID) {
    [self fail:@"Owned display ID is invalid or aliases the original main "
               @"display"];
    return;
  }
  _settings = [[CGVirtualDisplaySettings alloc] init];
  _settings.hiDPI = 0;
  NSMutableArray *modes = [NSMutableArray array];
  for (NSNumber *rate in @[ @60, @90, @120 ]) {
    CGVirtualDisplayMode *mode =
        [[CGVirtualDisplayMode alloc] initWithWidth:1280
                                             height:720
                                        refreshRate:rate.doubleValue];
    if (!mode) {
      [self fail:@"Unable to allocate a required diagnostic mode"];
      return;
    }
    [modes addObject:mode];
  }
  _settings.modes = modes;
  Emit(@{
    @"stage" : @"startup",
    @"step" : @"apply-settings",
    @"displayId" : @(self.ownDisplayID)
  });
  if (![_display applySettings:_settings]) {
    [self fail:@"Virtual display rejected 60/90/120Hz settings"];
    return;
  }
  // Like the addon's PostProcessDisplay, commit a session configuration after
  // applySettings so WindowServer activates the display. Change only this
  // fixture's origin/mirror state; never rewrite physical/main display state.
  CGDisplayConfigRef configuration = NULL;
  CGError status = CGBeginDisplayConfiguration(&configuration);
  if (status != kCGErrorSuccess || !configuration) {
    [self fail:@"Unable to begin owned display activation"];
    return;
  }
  double right = CGRectGetMaxX(CGDisplayBounds(self.originalMainDisplayID));
  CGDirectDisplayID displays[64];
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(64, displays, &count) == kCGErrorSuccess) {
    for (uint32_t index = 0; index < count; index++) {
      if (displays[index] != self.ownDisplayID)
        right =
            std::max(right, CGRectGetMaxX(CGDisplayBounds(displays[index])));
    }
  }
  status = CGConfigureDisplayOrigin(configuration, self.ownDisplayID,
                                    (int32_t)std::ceil(right + 32), 0);
  if (status == kCGErrorSuccess)
    status = CGConfigureDisplayMirrorOfDisplay(configuration, self.ownDisplayID,
                                               kCGNullDirectDisplay);
  if (status != kCGErrorSuccess) {
    CGCancelDisplayConfiguration(configuration);
    [self fail:[NSString stringWithFormat:@"Owned activation setup failed: %d",
                                          status]];
    return;
  }
  status =
      CGCompleteDisplayConfiguration(configuration, kCGConfigureForSession);
  if (status != kCGErrorSuccess) {
    [self fail:[NSString stringWithFormat:@"Owned activation commit failed: %d",
                                          status]];
    return;
  }
  Emit(@{
    @"stage" : @"startup",
    @"step" : @"activation-committed",
    @"displayId" : @(self.ownDisplayID)
  });
  self.busy = YES;
  [self waitForModes:initialHz attempt:0];
  signal(SIGINT, SIG_IGN);
  signal(SIGTERM, SIG_IGN);
  __weak ModeFixture *weakSelf = self;
  self.interruptSource = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
  self.terminateSource = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(self.interruptSource, ^{
    [weakSelf stop];
  });
  dispatch_source_set_event_handler(self.terminateSource, ^{
    [weakSelf stop];
  });
  dispatch_resume(self.interruptSource);
  dispatch_resume(self.terminateSource);
  int flags = fcntl(STDIN_FILENO, F_GETFL);
  if (flags >= 0)
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
  self.inputSource = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(self.inputSource, ^{
    @autoreleasepool {
      [weakSelf readCommands];
    }
  });
  dispatch_resume(self.inputSource);
}
- (void)waitForModes:(int)initialHz attempt:(int)attempt {
  if (self.stopping)
    return;
  NSDictionary *state = [self snapshot];
  if ([state[@"mainDisplayId"] unsignedIntValue] !=
      self.originalMainDisplayID) {
    [self fail:@"Main display changed during fixture creation; removing only "
               @"the owned display"];
    return;
  }
  if ([state[@"mirrorsDisplayId"] unsignedIntValue] != 0 ||
      [state[@"inMirrorSet"] boolValue]) {
    [self
        fail:@"Owned diagnostic display unexpectedly mirrors another display"];
    return;
  }
  BOOL allModes = YES;
  for (NSNumber *wanted in @[ @60, @90, @120 ]) {
    BOOL found = NO;
    for (NSNumber *rate in state[@"availableModes"])
      if (std::abs(rate.doubleValue - wanted.doubleValue) <= 0.001)
        found = YES;
    allModes = allModes && found;
  }
  if ([state[@"online"] boolValue] && allModes) {
    [self switchTo:initialHz initial:YES];
    return;
  }
  if (attempt >= 60) {
    [self fail:[NSString stringWithFormat:
                             @"Required CG modes did not appear within 3s: %@",
                             state]];
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                 dispatch_get_main_queue(), ^{
                   @autoreleasepool {
                     [self waitForModes:initialHz attempt:attempt + 1];
                   }
                 });
}
- (void)switchTo:(int)hz initial:(BOOL)initial {
  if (self.stopping)
    return;
  self.busy = YES;
  CFArrayRef copied = CGDisplayCopyAllDisplayModes(self.ownDisplayID, NULL);
  CGDisplayModeRef selected = NULL;
  for (id object in (__bridge NSArray *)copied) {
    CGDisplayModeRef mode = (__bridge CGDisplayModeRef)object;
    if (CGDisplayModeGetPixelWidth(mode) == 1280 &&
        CGDisplayModeGetPixelHeight(mode) == 720 &&
        CGDisplayModeGetWidth(mode) == 1280 &&
        CGDisplayModeGetHeight(mode) == 720 &&
        std::abs(CGDisplayModeGetRefreshRate(mode) - hz) <= 0.001) {
      selected = CGDisplayModeRetain(mode);
      break;
    }
  }
  if (copied)
    CFRelease(copied);
  if (!selected) {
    [self fail:@"Requested mode is not advertised by the owned display"];
    return;
  }
  // The only mode mutation in this program is scoped to its own display ID.
  CGError status = CGDisplaySetDisplayMode(self.ownDisplayID, selected, NULL);
  CGDisplayModeRelease(selected);
  if (status != kCGErrorSuccess) {
    [self fail:[NSString
                   stringWithFormat:@"Owned CGDisplaySetDisplayMode failed: %d",
                                    status]];
    return;
  }
  if (!initial)
    self.sequence += 1;
  [self waitForRate:hz initial:initial attempt:0];
}
- (void)waitForRate:(int)hz initial:(BOOL)initial attempt:(int)attempt {
  if (self.stopping)
    return;
  NSMutableDictionary *state = [[self snapshot] mutableCopy];
  if ([state[@"mainDisplayId"] unsignedIntValue] !=
      self.originalMainDisplayID) {
    [self fail:@"Main display changed during fixture operation; removing only "
               @"the owned display"];
    return;
  }
  if ([state[@"mirrorsDisplayId"] unsignedIntValue] != 0 ||
      [state[@"inMirrorSet"] boolValue]) {
    [self fail:@"Owned diagnostic display unexpectedly entered a mirror set"];
    return;
  }
  if ([state[@"online"] boolValue] &&
      std::abs([state[@"actualRefreshRate"] doubleValue] - hz) <= 0.001 &&
      [state[@"physicalWidth"] intValue] == 1280 &&
      [state[@"physicalHeight"] intValue] == 720) {
    state[@"stage"] = initial ? @"ready" : @"mode";
    state[@"requestedHz"] = @(hz);
    state[@"sequence"] = @(self.sequence);
    state[@"processId"] = @(getpid());
    state[@"commands"] = @"mode 60|90|120, status, stop; EOF stops and "
                         @"destroys the owned display";
    Emit(state);
    self.ready = YES;
    self.busy = NO;
    [self pumpCommands];
    return;
  }
  if (attempt >= 40) {
    [self fail:[NSString
                   stringWithFormat:@"Owned mode did not settle within 2s: %@",
                                    state]];
    return;
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                 dispatch_get_main_queue(), ^{
                   @autoreleasepool {
                     [self waitForRate:hz initial:initial attempt:attempt + 1];
                   }
                 });
}
- (void)readCommands {
  if (self.stopping)
    return;
  uint8_t bytes[1024];
  while (YES) {
    ssize_t amount = read(STDIN_FILENO, bytes, sizeof(bytes));
    if (amount > 0)
      [self.input appendBytes:bytes length:(NSUInteger)amount];
    else if (amount == 0) {
      [self stop];
      return;
    } else if (errno == EINTR)
      continue;
    else if (errno == EAGAIN || errno == EWOULDBLOCK)
      break;
    else {
      [self fail:@"Unable to read fixture stdin"];
      return;
    }
    if (self.input.length > 4096) {
      [self fail:@"Fixture command input exceeded 4096 bytes"];
      return;
    }
  }
  while (YES) {
    const uint8_t *raw = (const uint8_t *)self.input.bytes;
    const uint8_t *newline =
        (const uint8_t *)memchr(raw, '\n', self.input.length);
    if (!newline)
      break;
    NSUInteger length = (NSUInteger)(newline - raw);
    NSString *line = [[NSString alloc] initWithBytes:raw
                                              length:length
                                            encoding:NSUTF8StringEncoding];
    [self.input replaceBytesInRange:NSMakeRange(0, length + 1)
                          withBytes:NULL
                             length:0];
    if (!line) {
      [self fail:@"Fixture command is not UTF-8"];
      return;
    }
    NSString *command = [line
        stringByTrimmingCharactersInSet:NSCharacterSet
                                            .whitespaceAndNewlineCharacterSet];
    if ([command isEqualToString:@"stop"]) {
      [self stop];
      return;
    }
    if (command.length > 0)
      [self.commands addObject:command];
    if (self.commands.count > 32) {
      [self fail:@"Fixture command queue exceeded 32 commands"];
      return;
    }
  }
  [self pumpCommands];
}
- (void)pumpCommands {
  if (!self.ready || self.busy || self.stopping || self.commands.count == 0)
    return;
  NSString *command = self.commands.firstObject;
  [self.commands removeObjectAtIndex:0];
  if ([command isEqualToString:@"status"]) {
    NSMutableDictionary *state = [[self snapshot] mutableCopy];
    state[@"stage"] = @"status";
    Emit(state);
    [self pumpCommands];
    return;
  }
  if ([command isEqualToString:@"mode 60"] ||
      [command isEqualToString:@"mode 90"] ||
      [command isEqualToString:@"mode 120"]) {
    [self switchTo:[[command substringFromIndex:5] intValue] initial:NO];
    return;
  }
  [self
      fail:[NSString stringWithFormat:@"Unknown fixture command: %@", command]];
}
- (void)stop {
  if (self.stopping)
    return;
  self.stopping = YES;
  if (self.inputSource)
    dispatch_source_cancel(self.inputSource);
  if (self.interruptSource)
    dispatch_source_cancel(self.interruptSource);
  if (self.terminateSource)
    dispatch_source_cancel(self.terminateSource);
  self.inputSource = nil;
  self.interruptSource = nil;
  self.terminateSource = nil;
  @autoreleasepool {
    _descriptor = nil;
    _settings = nil;
    _display = nil;
  }
  // Private objects may deallocate before WindowServer removes the process's
  // display connection. Report the pre-exit observation honestly; the runner
  // verifies removal in a separate --assert-offline invocation after close.
  BOOL online = self.ownDisplayID != 0 &&
                [ConnectionState(self.ownDisplayID)[@"online"] boolValue];
  Emit(@{
    @"stage" : @"stopped",
    @"displayId" : @(self.ownDisplayID),
    @"onlineBeforeProcessExit" : @(online),
    @"cgDisplayIsOnlineRawBeforeProcessExit" :
        @((int64_t)CGDisplayIsOnline(self.ownDisplayID)),
    @"mainDisplayId" : @(CGMainDisplayID()),
    @"originalMainDisplayId" : @(self.originalMainDisplayID)
  });
  exit(self.failed || CGMainDisplayID() != self.originalMainDisplayID ? 1 : 0);
}
@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc == 5 && strcmp(argv[1], "--assert-offline") == 0 &&
        strcmp(argv[3], "--assert-main") == 0) {
      char *endDisplay = NULL, *endMain = NULL;
      unsigned long display = strtoul(argv[2], &endDisplay, 10);
      unsigned long mainDisplay = strtoul(argv[4], &endMain, 10);
      if (display == 0 || display > UINT32_MAX || mainDisplay == 0 ||
          mainDisplay > UINT32_MAX || !endDisplay || *endDisplay != '\0' ||
          !endMain || *endMain != '\0' || display == mainDisplay) {
        Emit(@{
          @"stage" : @"error",
          @"message" : @"Invalid cleanup assertion display IDs"
        });
        return 1;
      }
      // Read-only path: does not initialize AppKit or create a display.
      double begun = NSProcessInfo.processInfo.systemUptime;
      NSDictionary *state = ConnectionState((CGDirectDisplayID)display);
      while ([state[@"online"] boolValue] &&
             NSProcessInfo.processInfo.systemUptime - begun < 3) {
        usleep(50000);
        state = ConnectionState((CGDirectDisplayID)display);
      }
      CGDirectDisplayID observedMain = CGMainDisplayID();
      BOOL passed = [state[@"onlineListStatus"] intValue] == kCGErrorSuccess &&
                    [state[@"activeListStatus"] intValue] == kCGErrorSuccess &&
                    ![state[@"online"] boolValue] &&
                    ![state[@"active"] boolValue] &&
                    ![state[@"currentModePresent"] boolValue] &&
                    observedMain == mainDisplay;
      NSMutableDictionary *result = [state mutableCopy];
      [result addEntriesFromDictionary:@{
        @"stage" : @"cleanup-verified",
        @"displayId" : @(display),
        @"mainDisplayId" : @(observedMain),
        @"expectedMainDisplayId" : @(mainDisplay),
        @"seconds" : @(NSProcessInfo.processInfo.systemUptime - begun),
        @"passed" : @(passed)
      }];
      Emit(result);
      return passed ? 0 : 1;
    }
    int initialHz = 60;
    if (argc == 3 && strcmp(argv[1], "--initial-hz") == 0 &&
        (strcmp(argv[2], "60") == 0 || strcmp(argv[2], "90") == 0 ||
         strcmp(argv[2], "120") == 0))
      initialHz = atoi(argv[2]);
    else if (argc != 1) {
      Emit(@{
        @"stage" : @"error",
        @"message" : @"Usage: fixture [--initial-hz 60|90|120] OR "
                     @"--assert-offline ID --assert-main MAIN_ID"
      });
      return 1;
    }
    signal(SIGPIPE, SIG_IGN);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    __attribute__((objc_precise_lifetime)) ModeFixture *fixture =
        [[ModeFixture alloc] init];
    dispatch_async(dispatch_get_main_queue(), ^{
      @autoreleasepool {
        [fixture start:initialHz];
      }
    });
    // Strong ownership until explicit process exit also protects queued work.
    [NSApp run];
    (void)fixture;
  }
  return 1;
}
