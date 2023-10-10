// #include "virtual_display.h"
#include <napi.h>

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

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

@property(readonly, nonatomic) NSArray *modes;     // @synthesize modes=_modes;
@property(readonly, nonatomic) unsigned int hiDPI; // @synthesize hiDPI=_hiDPI;
@property(readonly, nonatomic)
    CGDirectDisplayID displayID; // @synthesize displayID=_displayID;
@property(readonly, nonatomic) id
    terminationHandler; // @synthesize terminationHandler=_terminationHandler;
@property(readonly, nonatomic)
    dispatch_queue_t queue; // @synthesize queue=_queue;
@property(readonly, nonatomic)
    unsigned int maxPixelsHigh; // @synthesize maxPixelsHigh=_maxPixelsHigh;
@property(readonly, nonatomic)
    unsigned int maxPixelsWide; // @synthesize maxPixelsWide=_maxPixelsWide;
@property(readonly, nonatomic) CGSize
    sizeInMillimeters; // @synthesize sizeInMillimeters=_sizeInMillimeters;
@property(readonly, nonatomic) NSString *name; // @synthesize name=_name;
@property(readonly, nonatomic)
    unsigned int serialNum; // @synthesize serialNum=_serialNum;
@property(readonly, nonatomic)
    unsigned int productID; // @synthesize productID=_productID;
@property(readonly, nonatomic)
    unsigned int vendorID; // @synthesize vendorID=_vendorID;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)arg1;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)arg1;

@end

@interface CGVirtualDisplayDescriptor : NSObject

@property(retain, nonatomic)
    dispatch_queue_t queue;                  // @synthesize queue=_queue;
@property(retain, nonatomic) NSString *name; // @synthesize name=_name;
@property(nonatomic)
    unsigned int maxPixelsHigh; // @synthesize maxPixelsHigh=_maxPixelsHigh;
@property(nonatomic)
    unsigned int maxPixelsWide; // @synthesize maxPixelsWide=_maxPixelsWide;
@property(nonatomic) CGSize
    sizeInMillimeters; // @synthesize sizeInMillimeters=_sizeInMillimeters;
@property(nonatomic)
    unsigned int serialNum; // @synthesize serialNum=_serialNum;
@property(nonatomic)
    unsigned int productID;                 // @synthesize productID=_productID;
@property(nonatomic) unsigned int vendorID; // @synthesize vendorID=_vendorID;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);

- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)arg1;

@end

class VDisplay : public Napi::ObjectWrap<VDisplay> {
public:
  //   static Napi::Object Init(Napi::Env env, Napi::Object exports);
  static Napi::Function GetClass(Napi::Env);
  VDisplay(const Napi::CallbackInfo &info);
  //   Napi::Value GetDisplayId(const Napi::CallbackInfo &info);
  Napi::Value CreateVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value CloneVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value DestroyVirtualDisplay(const Napi::CallbackInfo &info);

private:
  // double _value;
  CGVirtualDisplay *_display;
  CGVirtualDisplayDescriptor *_descriptor;
  CGVirtualDisplaySettings *_settings;
};

VDisplay::VDisplay(const Napi::CallbackInfo &info) : ObjectWrap(info) {
  //   Napi::Env env = info.Env();
}

Napi::Function VDisplay::GetClass(Napi::Env env) {
  return DefineClass(
      env, "VDisplay",
      {
          //   VDisplay::InstanceMethod("getDisplayId",
          //   &VDisplay::GetDisplayId),
          VDisplay::InstanceMethod("createVirtualDisplay",
                                   &VDisplay::CreateVirtualDisplay),
          VDisplay::InstanceMethod("cloneVirtualDisplay",
                                   &VDisplay::CloneVirtualDisplay),

          VDisplay::InstanceMethod("destroyVirtualDisplay",
                                   &VDisplay::DestroyVirtualDisplay),

      });
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  Napi::String name = Napi::String::New(env, "VDisplay");
  exports.Set(name, VDisplay::GetClass(env));
  return exports;
}

// https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/CoreGraphics/1251.8.4.2/CGVirtualDisplayDescriptor.h

Napi::Value VDisplay::CreateVirtualDisplay(const Napi::CallbackInfo &info) {
  if (this->_display) {
    return Napi::Number::New(info.Env(), this->_display.displayID);
  }
  Napi::Env env = info.Env();

  if (info.Length() < 5) {
    Napi::TypeError::New(env, "Wrong number of arguments")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  int width = info[0].As<Napi::Number>().Int32Value();
  int height = info[1].As<Napi::Number>().Int32Value();
  int frameRate = info[2].As<Napi::Number>().Int32Value();
  
  if (frameRate < 30) {
    frameRate = 30;
  } else if (frameRate > 60) {
    frameRate = 60;
  }
  unsigned int hiDPI = info[3].As<Napi::Boolean>().Value();

  NSString *displayName = [NSString stringWithUTF8String:info[4].As<Napi::String>().Utf8Value().c_str()];
  if (!displayName || displayName.length == 0) {
    displayName = @"Virtual Display";
  }

  this->_descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  this->_descriptor.name = displayName;
  this->_descriptor.maxPixelsWide = width;
  this->_descriptor.maxPixelsHigh = height;

  int ppi = info[5].As<Napi::Number>().Int32Value();

  if (ppi > 300) {
    ppi = 300;
  } else if (ppi < 72) {
    ppi = 72;
  }

  double ratio = 25.4 / ppi;

  this->_descriptor.sizeInMillimeters =
      CGSizeMake(width * ratio, height * ratio);
  this->_descriptor.productID = 0xeeee + width + height + ppi;
  this->_descriptor.vendorID = 0xeeee;
  this->_descriptor.serialNum = 0x0001;
  this->_display =
      [[CGVirtualDisplay alloc] initWithDescriptor:this->_descriptor];
  this->_settings = [[CGVirtualDisplaySettings alloc] init];
  this->_settings.hiDPI = hiDPI;

  if (hiDPI) {
    this->_settings.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:frameRate], 
    [[CGVirtualDisplayMode alloc] initWithWidth:width / 2 height:height / 2 refreshRate:frameRate]];
  } 
  else {
    this->_settings.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:frameRate]];
  }
  [this->_display applySettings:this->_settings];

  Napi::Object obj = Napi::Object::New(env);
  obj.Set(Napi::String::New(env, "id"),
          Napi::Number::New(env, this->_display.displayID));
  obj.Set(Napi::String::New(env, "width"), Napi::Number::New(env, width));
  obj.Set(Napi::String::New(env, "height"), Napi::Number::New(env, height));

  return obj;
}

Napi::Value VDisplay::CloneVirtualDisplay(const Napi::CallbackInfo &info) {
  if (this->_display) {
    return Napi::Number::New(info.Env(), this->_display.displayID);
  }
  Napi::Env env = info.Env();

  if (info.Length() < 1) {
    Napi::TypeError::New(env, "Wrong number of arguments")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  NSString *displayName = [NSString stringWithUTF8String:info[0].As<Napi::String>().Utf8Value().c_str()];
  if (!displayName || displayName.length == 0) {
    displayName = @"Virtual Display";
  }

  // Get the main display
  CGDirectDisplayID display = kCGDirectMainDisplay;

  // Get the current display mode
  CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(display);

  NSArray<NSScreen *> *screens = [NSScreen screens];
  CGFloat backingScaleFactor = [[screens objectAtIndex:0] backingScaleFactor];
  // Get the physical size of the display in millimeters
  unsigned int width = CGDisplayModeGetPixelWidth(displayMode) / backingScaleFactor; // required
  unsigned int height = CGDisplayModeGetPixelHeight(displayMode) / backingScaleFactor; // required
  double refreshRate = CGDisplayModeGetRefreshRate(displayMode);

  // Release resources
  CFRelease(displayMode);

  this->_descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  this->_descriptor.name = displayName;
  this->_descriptor.maxPixelsWide = width;
  this->_descriptor.maxPixelsHigh = height;
  this->_descriptor.sizeInMillimeters = CGDisplayScreenSize(display);
  unsigned int pixelWidth = CGDisplayPixelsWide(display);
  // unsigned int pixelHeight = CGDisplayPixelsHigh(display);
  CGSize screenSize = CGDisplayScreenSize(display);
  float dpi = pixelWidth / (screenSize.width / 25.4); // converting mm to inches

  // NSLog(@"CGDisplayScreenSize width: %f", screenSize.width);
  // NSLog(@"CGDisplayPixelsWide width: %d", pixelWidth);
  // NSLog(@"CGDisplayModeGetPixelWidth(displayMode): %d", width);
  // NSLog(@"DPI - pixelWidth / (CGDisplayModeGetPixelWidth / 25.4): %f", dpi);

  int hiDPI = 1;
  if (dpi > 150) {
    hiDPI = 2;
    NSLog(@"This is likely a HiDPI display. DPI: %f", dpi);
  } else {
    NSLog(@"This is likely not a HiDPI display. DPI: %f", dpi);
  }

  uint32_t vendorID = CGDisplayVendorNumber(display);
  uint32_t modelID = CGDisplayModelNumber(display);        
  NSLog(@"Vendor ID: %u", vendorID);
  NSLog(@"Model ID: %u", modelID);
  // this->_descriptor.sizeInMillimeters = CGSizeMake(1800, 1012.5);
  // this->_descriptor.maxPixelsWide = 1280;
  // this->_descriptor.maxPixelsHigh = 720;
  // this->_descriptor.sizeInMillimeters = CGSizeMake(1200, 675);
  this->_descriptor.productID = modelID + 1;
  this->_descriptor.vendorID = vendorID;
  this->_descriptor.serialNum = 0x0001;
  this->_display =
      [[CGVirtualDisplay alloc] initWithDescriptor:this->_descriptor];
  this->_settings = [[CGVirtualDisplaySettings alloc] init];
  this->_settings.hiDPI = hiDPI;
  this->_settings.modes = @[
    // [[CGVirtualDisplayMode alloc] initWithWidth:1280 height:720
    // refreshRate:60],
    // [[CGVirtualDisplayMode alloc] initWithWidth:1280 height:720
    // refreshRate:30],
    [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:refreshRate]
  ];
  [this->_display applySettings:this->_settings];

  Napi::Object obj = Napi::Object::New(env);
  obj.Set(Napi::String::New(env, "id"),
          Napi::Number::New(env, this->_display.displayID));
  obj.Set(Napi::String::New(env, "width"), Napi::Number::New(env, width));
  obj.Set(Napi::String::New(env, "height"), Napi::Number::New(env, height));
  return obj;
}

Napi::Value VDisplay::DestroyVirtualDisplay(const Napi::CallbackInfo &info) {
  if (this->_display) {
    [this->_descriptor release];
    this->_descriptor = nil;
    [this->_settings release];
    this->_settings = nil;
    [this->_display release];
    this->_display = nil;
    return Napi::Boolean::New(info.Env(), true);
  } else {
    return Napi::Boolean::New(info.Env(), false);
  }
}

// Napi::Value VDisplay::GetDisplayId(const Napi::CallbackInfo &info) {
//   Napi::Env env = info.Env();
//   return Napi::Number::New(env, this->_display.displayID);
// }

NS_ASSUME_NONNULL_END

// Register and initialize native add-on
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
// NODE_API_MODULE(virtual_display, Init)