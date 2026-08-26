#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cmath>
#include <limits>
#include <napi.h>

@class CGVirtualDisplayDescriptor;
@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)arg1
                       height:(NSUInteger)arg2
                  refreshRate:(CGFloat)arg3;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
- (instancetype)init;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)arg1;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)arg1;
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
- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)arg1;
@end

class VDisplay : public Napi::ObjectWrap<VDisplay> {
public:
  static Napi::Function GetClass(Napi::Env);
  VDisplay(const Napi::CallbackInfo &info);
  ~VDisplay();

private:
  Napi::Value CreateVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value CloneVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value DestroyVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value GetDisplayInfo(const Napi::CallbackInfo &info);

  CGVirtualDisplay *_display = nil;
  CGVirtualDisplayDescriptor *_descriptor = nil;
  CGVirtualDisplaySettings *_settings = nil;
  id _screenParamsObserver = nil;
  unsigned int _requestedWidth = 0;
  unsigned int _requestedHeight = 0;
  CGFloat _requestedRefreshRate = 0;

  void InitializeDescriptor(NSString *displayName, unsigned int width,
                            unsigned int height, int ppi, bool hiDPI,
                            std::string serial);
  void InitializeSettings(unsigned int width, unsigned int height,
                          CGFloat refreshRate, bool hiDPI);
  void ReleaseDisplayObjects();
  void PostProcessDisplay(CGDirectDisplayID mainDisplay, bool useMirror);
  void RegisterScreenParamsObserver();
  void RemoveScreenParamsObserver();
  void EnsurePhysicalDisplayStaysMain();
  NSArray<NSNumber *> *OnlinePhysicalDisplays();
  Napi::Object CreateDisplayObject(Napi::Env env, unsigned int width,
                                   unsigned int height,
                                   CGFloat requestedRefreshRate);
  Napi::Object BuildDisplayInfo(Napi::Env env, unsigned int width,
                                unsigned int height,
                                CGFloat requestedRefreshRate);
  bool ReadCurrentDisplayMode(CGDirectDisplayID displayID, NSUInteger *width,
                              NSUInteger *height, CGFloat *refreshRate);

  int Clamp(int value, int low, int high) {
    return (value < low) ? low : ((value > high) ? high : value);
  }

  double Clamp(double value, double low, double high) {
    return (value < low) ? low : ((value > high) ? high : value);
  }
};

VDisplay::VDisplay(const Napi::CallbackInfo &info) : ObjectWrap(info) {}

VDisplay::~VDisplay() { ReleaseDisplayObjects(); }

Napi::Function VDisplay::GetClass(Napi::Env env) {
  return DefineClass(
      env, "VDisplay",
      {
          InstanceMethod("createVirtualDisplay",
                         &VDisplay::CreateVirtualDisplay),
          InstanceMethod("cloneVirtualDisplay", &VDisplay::CloneVirtualDisplay),
          InstanceMethod("destroyVirtualDisplay",
                         &VDisplay::DestroyVirtualDisplay),
          InstanceMethod("getDisplayInfo", &VDisplay::GetDisplayInfo),
      });
}

void VDisplay::InitializeDescriptor(NSString *displayName, unsigned int width,
                                    unsigned int height, int ppi, bool hiDPI,
                                    std::string serialStr) {
  if (ppi <= 0) {
    ppi = 81;
  }

  // Physical pixels = 2x logical when HiDPI, 1x otherwise. The descriptor's
  // maxPixels* must describe the physical (backing) resolution so macOS
  // allocates enough framebuffer; the logical resolution is exposed through
  // the modes in InitializeSettings.
  const unsigned int physW = hiDPI ? width * 2 : width;
  const unsigned int physH = hiDPI ? height * 2 : height;

  _descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  _descriptor.name = displayName;
  _descriptor.maxPixelsWide = physW;
  _descriptor.maxPixelsHigh = physH;

  // HiDPI needs a high PPI so macOS recognises the display as Retina
  // (>=200 PPI threshold). Non-HiDPI stays at the caller's PPI.
  const int effectivePpi = hiDPI ? 220 : ppi;
  double ratio = 25.4 / effectivePpi;
  _descriptor.sizeInMillimeters = CGSizeMake(physW * ratio, physH * ratio);

  // DJB2 Hash Algorithm (Simple & Stable)
  unsigned long hash = 5381;
  for (char c : serialStr) {
    hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
  }

  unsigned int serialNum = (unsigned int)(hash & 0xFFFFFFFF);
  unsigned int productID = (unsigned int)((hash >> 16) & 0xFFFF);

  _descriptor.productID = productID;
  _descriptor.vendorID = 0xeeee;
  _descriptor.serialNum = serialNum;
}

void VDisplay::InitializeSettings(unsigned int width, unsigned int height,
                                  CGFloat refreshRate, bool hiDPI) {
  _settings = [[CGVirtualDisplaySettings alloc] init];
  _settings.hiDPI = hiDPI ? 1 : 0;

  // HiDPI: anchor mode (physical resolution) + logical mode. The anchor tells
  // macOS "this display is high-density", which unlocks HiDPI for the logical
  // mode. Non-HiDPI: a single mode at the requested resolution.
  const unsigned int physW = hiDPI ? width * 2 : width;
  const unsigned int physH = hiDPI ? height * 2 : height;

  NSMutableArray<CGVirtualDisplayMode *> *modes =
      [NSMutableArray arrayWithCapacity:hiDPI ? 2 : 1];

  if (hiDPI) {
    CGVirtualDisplayMode *anchorMode =
        [[CGVirtualDisplayMode alloc] initWithWidth:physW
                                             height:physH
                                        refreshRate:refreshRate];
    if (anchorMode) {
      [modes addObject:anchorMode];
      [anchorMode release];
    }
  }

  CGVirtualDisplayMode *logicalMode =
      [[CGVirtualDisplayMode alloc] initWithWidth:width
                                           height:height
                                      refreshRate:refreshRate];
  if (logicalMode) {
    [modes addObject:logicalMode];
    [logicalMode release];
  }

  if (modes.count > 0) {
    _settings.modes = modes;
  }
}

void VDisplay::ReleaseDisplayObjects() {
  // Keep the release order that has been used by this module: the descriptor
  // and settings are released before the display object itself.  Make the
  // cleanup idempotent so explicit destroy and ObjectWrap finalization share
  // the same safe path.
  RemoveScreenParamsObserver();
  if (_descriptor) {
    [_descriptor release];
    _descriptor = nil;
  }
  if (_settings) {
    [_settings release];
    _settings = nil;
  }
  if (_display) {
    [_display release];
    _display = nil;
  }
  _requestedWidth = 0;
  _requestedHeight = 0;
  _requestedRefreshRate = 0;
}

bool VDisplay::ReadCurrentDisplayMode(CGDirectDisplayID displayID,
                                      NSUInteger *width, NSUInteger *height,
                                      CGFloat *refreshRate) {
  if (!width || !height || !refreshRate) {
    return false;
  }

  *width = 0;
  *height = 0;
  *refreshRate = 0;

  CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
  if (!mode) {
    return false;
  }

  *width = CGDisplayModeGetPixelWidth(mode);
  *height = CGDisplayModeGetPixelHeight(mode);
  *refreshRate = CGDisplayModeGetRefreshRate(mode);
  CFRelease(mode);
  return *width > 0 && *height > 0;
}

Napi::Object VDisplay::BuildDisplayInfo(Napi::Env env, unsigned int width,
                                        unsigned int height,
                                        CGFloat requestedRefreshRate) {
  Napi::Object obj = Napi::Object::New(env);
  obj.Set(Napi::String::New(env, "id"),
          Napi::Number::New(env, _display.displayID));
  obj.Set(Napi::String::New(env, "width"), Napi::Number::New(env, width));
  obj.Set(Napi::String::New(env, "height"), Napi::Number::New(env, height));
  // Report integer rates to the caller (59.94 -> 60, 119.88 -> 120), matching
  // how displays are conventionally labelled. The exact fractional value is
  // still used internally to build the CGVirtualDisplayMode.
  obj.Set(Napi::String::New(env, "requestedRefreshRate"),
          Napi::Number::New(env, std::round(requestedRefreshRate)));

  NSUInteger actualWidth = 0;
  NSUInteger actualHeight = 0;
  CGFloat actualRefreshRate = 0;
  const bool hasCurrentMode = ReadCurrentDisplayMode(
      _display.displayID, &actualWidth, &actualHeight, &actualRefreshRate);

  // A freshly created virtual display may not have a settled CGDisplayMode
  // yet, so CGDisplayCopyDisplayMode can report 0x0. Fall back to the
  // descriptor's physical (backing) pixels — for HiDPI these are exactly 2x
  // the logical resolution, which is the physical size we asked for.
  if (!hasCurrentMode || actualWidth == 0 || actualHeight == 0) {
    if (_descriptor) {
      actualWidth = _descriptor.maxPixelsWide;
      actualHeight = _descriptor.maxPixelsHigh;
    }
    if (actualRefreshRate <= 0) {
      actualRefreshRate = requestedRefreshRate;
    }
  }

  obj.Set(Napi::String::New(env, "actualWidth"),
          Napi::Number::New(env, actualWidth));
  obj.Set(Napi::String::New(env, "actualHeight"),
          Napi::Number::New(env, actualHeight));
  obj.Set(Napi::String::New(env, "actualRefreshRate"),
          Napi::Number::New(env, std::round(actualRefreshRate)));
  obj.Set(Napi::String::New(env, "isOnline"),
          Napi::Boolean::New(env, CGDisplayIsOnline(_display.displayID)));
  obj.Set(Napi::String::New(env, "isActive"),
          Napi::Boolean::New(env, CGDisplayIsActive(_display.displayID)));
  return obj;
}

void VDisplay::PostProcessDisplay(CGDirectDisplayID mainDisplay,
                                  bool useMirror) {
  if (!_display) {
    return;
  }

  uint32_t newMainDisplayID = CGMainDisplayID();
  NSLog(@"Current Main Display after virtual display creation: %d",
        newMainDisplayID);

  CGDisplayConfigRef config = nullptr;
  CGError beginError = CGBeginDisplayConfiguration(&config);
  if (beginError == kCGErrorSuccess && config) {
    bool configurationValid = true;
    if (newMainDisplayID == _display.displayID &&
        newMainDisplayID != mainDisplay) {
      NSLog(@"Unintended case 1: Virtual display set as main display => "
            @"restore Primary Display as main display");
      CGError err = CGConfigureDisplayOrigin(config, mainDisplay, 0, 0);
      if (err != kCGErrorSuccess) {
        configurationValid = false;
        NSLog(@"Failed to restore primary display origin: %d", err);
      }
    }

    // If the primary display is mirroring the virtual display, disable it.
    uint32_t displayId = CGDisplayMirrorsDisplay(mainDisplay);
    NSLog(@"Mirror source of Primary Display is: %d", displayId);
    if (displayId == _display.displayID) {
      NSLog(@"Unintended case 2: Primary display is mirroring virtual display "
            @"=> disable mirror mode");
      CGError err = CGConfigureDisplayMirrorOfDisplay(config, displayId,
                                                      kCGNullDirectDisplay);
      if (err != kCGErrorSuccess) {
        configurationValid = false;
        NSLog(@"Failed to disable primary display mirror mode: %d", err);
      }
    }

    if (configurationValid) {
      CGError completeError =
          CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
      if (completeError != kCGErrorSuccess) {
        NSLog(@"[PostProcess] Failed to complete display configuration: %d",
              completeError);
      }
    } else {
      CGCancelDisplayConfiguration(config);
    }
  } else {
    NSLog(@"Failed to begin primary display configuration: %d", beginError);
  }

  boolean_t isMirror = CGDisplayIsInMirrorSet(_display.displayID);
  NSLog(@"Virtual Display is in mirror set: %d", isMirror);

  config = nullptr;
  beginError = CGBeginDisplayConfiguration(&config);
  if (beginError != kCGErrorSuccess || !config) {
    NSLog(@"Failed to begin virtual display mirror configuration: %d",
          beginError);
    return;
  }

  bool configurationValid = true;
  if (useMirror) {
    if (isMirror == 0) {
      NSLog(@"Enable Virtual Display mirror mode");
      CGError err = CGConfigureDisplayMirrorOfDisplay(
          config, _display.displayID, mainDisplay);
      if (err != kCGErrorSuccess) {
        configurationValid = false;
        NSLog(@"Failed to enable mirror mode: %d", err);
      }
    }
  } else if (isMirror == 1) {
    NSLog(@"Disable Virtual Display mirror mode");
    CGError err = CGConfigureDisplayMirrorOfDisplay(config, _display.displayID,
                                                    kCGNullDirectDisplay);
    if (err != kCGErrorSuccess) {
      configurationValid = false;
      NSLog(@"Failed to disable mirror mode: %d", err);
    }
  }

  if (configurationValid) {
    CGError completeError =
        CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    if (completeError != kCGErrorSuccess) {
      NSLog(@"[PostProcess] Failed to complete display configuration: %d",
            completeError);
    }
  } else {
    CGCancelDisplayConfiguration(config);
  }

  // Re-assert the physical-main invariant on every display-topology change:
  // WindowServer can re-adopt the virtual display as main from a remembered
  // arrangement at any point after creation, not only during this one-shot
  // restore — e.g. when a physical display is hot-plugged.
  RegisterScreenParamsObserver();
}

void VDisplay::RegisterScreenParamsObserver() {
  if (_screenParamsObserver) {
    return;
  }
  // The block captures `this` strongly, but the observer is removed in
  // RemoveScreenParamsObserver (called from ReleaseDisplayObjects), which
  // releases the block and breaks the cycle. Manual memory management: no ARC
  // __weak available here.
  _screenParamsObserver = [[NSNotificationCenter defaultCenter]
      addObserverForName:NSApplicationDidChangeScreenParametersNotification
                  object:nil
                   queue:[NSOperationQueue mainQueue]
              usingBlock:^(NSNotification *note) {
                EnsurePhysicalDisplayStaysMain();
              }];
}

void VDisplay::RemoveScreenParamsObserver() {
  if (_screenParamsObserver) {
    [[NSNotificationCenter defaultCenter] removeObserver:_screenParamsObserver];
    _screenParamsObserver = nil;
  }
}

NSArray<NSNumber *> *VDisplay::OnlinePhysicalDisplays() {
  NSMutableArray<NSNumber *> *physical = [NSMutableArray array];
  uint32_t online[16];
  uint32_t count = 0;
  if (CGGetOnlineDisplayList(16, online, &count) != kCGErrorSuccess) {
    return physical;
  }
  for (uint32_t i = 0; i < count; i++) {
    uint32_t id = online[i];
    // Filter out our own virtual display and any stale SideScreen-style
    // virtual display (vendor 0xEEEE) so they are not mistaken for physical
    // screens.
    if (id != _display.displayID && CGDisplayVendorNumber(id) != 0xEEEE) {
      [physical addObject:@(id)];
    }
  }
  return physical;
}

void VDisplay::EnsurePhysicalDisplayStaysMain() {
  if (!_display) {
    return;
  }
  uint32_t displayID = _display.displayID;
  if (CGMainDisplayID() != displayID) {
    return;
  }
  NSArray<NSNumber *> *physical = OnlinePhysicalDisplays();
  if (physical.count == 0) {
    // True headless operation: no physical display online, leave as-is.
    return;
  }
  uint32_t physicalMain = [physical[0] unsignedIntValue];

  CGDisplayConfigRef config = nullptr;
  if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess || !config) {
    return;
  }

  // Give the physical display the main slot and park the virtual display to
  // its right.
  int32_t physicalWidth = (int32_t)CGDisplayBounds(physicalMain).size.width;
  CGError result = CGConfigureDisplayOrigin(config, physicalMain, 0, 0);
  if (result == kCGErrorSuccess) {
    result = CGConfigureDisplayOrigin(config, displayID, physicalWidth, 0);
  }
  if (result != kCGErrorSuccess) {
    CGCancelDisplayConfiguration(config);
    NSLog(@"[MainGuard] Failed to rearrange displays: %d", result);
    return;
  }
  if (CGCompleteDisplayConfiguration(config, kCGConfigureForSession) ==
      kCGErrorSuccess) {
    NSLog(@"[MainGuard] Physical display restored as main — virtual display "
          @"parked beside it");
  }
}

Napi::Object VDisplay::CreateDisplayObject(Napi::Env env, unsigned int width,
                                           unsigned int height,
                                           CGFloat requestedRefreshRate) {
  return BuildDisplayInfo(env, width, height, requestedRefreshRate);
}

Napi::Value VDisplay::GetDisplayInfo(const Napi::CallbackInfo &info) {
  if (!_display) {
    return info.Env().Null();
  }
  return BuildDisplayInfo(info.Env(), _requestedWidth, _requestedHeight,
                          _requestedRefreshRate);
}

Napi::Value VDisplay::CreateVirtualDisplay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 8) {
    Napi::TypeError::New(env, "Wrong number of arguments")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Validate every value before tearing down an existing display. A malformed
  // replacement request must not destroy a healthy display that is already in
  // use by the caller.
  if (!info[0].IsNumber() || !info[1].IsNumber() || !info[2].IsNumber() ||
      !info[3].IsBoolean() || !info[4].IsString() || !info[5].IsNumber() ||
      !info[6].IsBoolean() || !info[7].IsString()) {
    Napi::TypeError::New(env, "Invalid virtual display argument types")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Params [width, height, refreshRate, hiDPI, displayName, ppi, useMirror,
  // serial]

  const double widthValue = info[0].As<Napi::Number>().DoubleValue();
  const double heightValue = info[1].As<Napi::Number>().DoubleValue();
  const double refreshRateValue = info[2].As<Napi::Number>().DoubleValue();
  const double ppiValue = info[5].As<Napi::Number>().DoubleValue();

  if (!std::isfinite(widthValue) || !std::isfinite(heightValue) ||
      !std::isfinite(refreshRateValue) || !std::isfinite(ppiValue) ||
      widthValue <= 0 || heightValue <= 0 || refreshRateValue <= 0 ||
      widthValue > std::numeric_limits<unsigned int>::max() ||
      heightValue > std::numeric_limits<unsigned int>::max() ||
      std::floor(widthValue) != widthValue ||
      std::floor(heightValue) != heightValue || ppiValue <= 0) {
    Napi::Error::New(env, "Invalid virtual display dimensions or refresh rate")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  const unsigned int width = static_cast<unsigned int>(widthValue);
  const unsigned int height = static_cast<unsigned int>(heightValue);
  // Keep the historical 30-120Hz contract, but preserve fractional values
  // such as 59.94 when a caller supplies them.
  const CGFloat refreshRate =
      static_cast<CGFloat>(Clamp(refreshRateValue, 30.0, 120.0));
  const bool hiDPI = info[3].As<Napi::Boolean>().Value();
  std::string displayNameStr = info[4].As<Napi::String>().Utf8Value();
  const int ppi = static_cast<int>(Clamp(ppiValue, 72.0, 300.0));
  const bool useMirror = info[6].As<Napi::Boolean>().Value();
  std::string serialStr = info[7].As<Napi::String>().Utf8Value();

  ReleaseDisplayObjects();

  NSString *displayName =
      [NSString stringWithUTF8String:displayNameStr.c_str()];
  if (!displayName || displayName.length == 0) {
    displayName = @"Virtual Display";
  }

  // store current main display id and bounds

  // store current main display id and bounds
  // CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
  uint32_t mainDisplay = CGMainDisplayID();
  NSLog(@"Previous Main display ID: %d", mainDisplay);

  InitializeDescriptor(displayName, width, height, ppi, hiDPI, serialStr);
  if (!_descriptor) {
    Napi::Error::New(env, "Failed to create display descriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  _display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
  if (!_display) {
    ReleaseDisplayObjects();
    Napi::Error::New(env, "Failed to create virtual display")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  InitializeSettings(width, height, refreshRate, hiDPI);
  if (!_settings || ![_display applySettings:_settings]) {
    ReleaseDisplayObjects();
    Napi::Error::New(env, "Failed to apply virtual display settings")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  _requestedWidth = width;
  _requestedHeight = height;
  _requestedRefreshRate = refreshRate;

  PostProcessDisplay(mainDisplay, useMirror);

  NSLog(@"Virtual display created with ID: %d", _display.displayID);
  return CreateDisplayObject(env, width, height, refreshRate);
}

Napi::Value VDisplay::CloneVirtualDisplay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  if (info.Length() < 2) {
    Napi::TypeError::New(env, "Wrong number of arguments")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  if (!info[0].IsString() || !info[1].IsBoolean()) {
    Napi::TypeError::New(env, "Invalid clone virtual display argument types")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Params [displayName, useMirror]
  std::string displayNameStr = info[0].As<Napi::String>().Utf8Value();
  NSString *displayName =
      [NSString stringWithUTF8String:displayNameStr.c_str()];
  if (!displayName || displayName.length == 0) {
    displayName = @"Virtual Display";
    displayNameStr = "Virtual Display";
  }

  const bool useMirror = info[1].As<Napi::Boolean>().Value();

  CGDirectDisplayID mainDisplay = CGMainDisplayID();
  CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(mainDisplay);
  if (!displayMode) {
    Napi::Error::New(env, "Failed to read the main display mode")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  NSScreen *mainScreen = [NSScreen mainScreen];
  CGFloat backingScaleFactor = mainScreen ? [mainScreen backingScaleFactor] : 1;
  if (!std::isfinite(backingScaleFactor) || backingScaleFactor <= 0) {
    backingScaleFactor = 1;
  }

  const double widthValue =
      static_cast<double>(CGDisplayModeGetPixelWidth(displayMode)) /
      backingScaleFactor;
  const double heightValue =
      static_cast<double>(CGDisplayModeGetPixelHeight(displayMode)) /
      backingScaleFactor;
  if (!std::isfinite(widthValue) || !std::isfinite(heightValue) ||
      widthValue <= 0 || heightValue <= 0 ||
      widthValue > std::numeric_limits<unsigned int>::max() ||
      heightValue > std::numeric_limits<unsigned int>::max()) {
    CFRelease(displayMode);
    Napi::Error::New(env, "Invalid main display dimensions")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  const unsigned int width = static_cast<unsigned int>(std::floor(widthValue));
  const unsigned int height =
      static_cast<unsigned int>(std::floor(heightValue));
  if (width == 0 || height == 0) {
    CFRelease(displayMode);
    Napi::Error::New(env, "Invalid main display dimensions")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  CGFloat refreshRate = CGDisplayModeGetRefreshRate(displayMode);
  if (!std::isfinite(refreshRate) || refreshRate <= 0) {
    refreshRate = 60;
  }
  refreshRate = static_cast<CGFloat>(Clamp(refreshRate, 30.0, 120.0));

  CGSize screenSize = CGDisplayScreenSize(mainDisplay);
  double dpi = 81;
  if (std::isfinite(screenSize.width) && screenSize.width > 0) {
    const double measuredDpi =
        CGDisplayPixelsWide(mainDisplay) / (screenSize.width / 25.4);
    if (std::isfinite(measuredDpi) && measuredDpi > 0) {
      dpi = measuredDpi;
    }
  }
  // increase DPI for retina display
  bool isHiDPI = (dpi > 200);

  const int ppi = static_cast<int>(Clamp(dpi, 72.0, 300.0));
  CFRelease(displayMode);

  ReleaseDisplayObjects();

  // Use displayName as serial seed to ensure consistent ID if same name is used
  InitializeDescriptor(displayName, width, height, ppi, isHiDPI,
                       displayNameStr);

  if (!_descriptor) {
    Napi::Error::New(env, "Failed to create display descriptor")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // NOTE: We rely on the hash from displayName.
  // If specific productID logic is needed for clones, it can be added here,
  // but user requested consistent name-based ID.
  // _descriptor.productID = CGDisplayModelNumber(mainDisplay) + 1; // Removed
  // to respect hash

  _descriptor.vendorID = CGDisplayVendorNumber(mainDisplay);

  _display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
  if (!_display) {
    ReleaseDisplayObjects();
    Napi::Error::New(env, "Failed to create virtual display")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  InitializeSettings(width, height, refreshRate, isHiDPI);
  if (!_settings || ![_display applySettings:_settings]) {
    ReleaseDisplayObjects();
    Napi::Error::New(env, "Failed to apply virtual display settings")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  _requestedWidth = width;
  _requestedHeight = height;
  _requestedRefreshRate = refreshRate;

  PostProcessDisplay(mainDisplay, useMirror);

  // Return the name-based object, consistent with standard Create
  return CreateDisplayObject(env, width, height, refreshRate);
}

Napi::Value VDisplay::DestroyVirtualDisplay(const Napi::CallbackInfo &info) {
  const bool hadDisplay = _display || _descriptor || _settings;
  ReleaseDisplayObjects();
  return Napi::Boolean::New(info.Env(), hadDisplay);
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  Napi::String name = Napi::String::New(env, "VDisplay");
  exports.Set(name, VDisplay::GetClass(env));
  return exports;
}

NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
