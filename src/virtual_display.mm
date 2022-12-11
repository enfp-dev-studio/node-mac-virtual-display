// #include "virtual_display.h"
#include <napi.h>

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

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
  static Napi::Object Init(Napi::Env env, Napi::Object exports);
  VDisplay(const Napi::CallbackInfo &info);

private:
  // double _value;
  CGVirtualDisplay *_display;
  CGVirtualDisplayDescriptor *_descriptor;
  CGVirtualDisplaySettings *_settings;
  // Napi::Value GetValue(const Napi::CallbackInfo &info);
  Napi::Value GetDisplayId(const Napi::CallbackInfo &info);

  void SetValue(const Napi::CallbackInfo &info, const Napi::Value &value);
};

Napi::Object VDisplay::Init(Napi::Env env, Napi::Object exports) {
  Napi::Function func = DefineClass(
      env, "VDisplay",
      {
          // Register a class instance accessor with getter and setter
          // functions.
          // InstanceAccessor<&VDisplay::GetValue,
          // &VDisplay::SetValue>("value"),
          // InstanceAccessor<&VDisplay::GetValue,
          // &VDisplay::SetValue>("value"),
          InstanceAccessor<&VDisplay::GetDisplayId>("displayId")

          // We can also register a readonly accessor by omitting the setter.
      });

  Napi::FunctionReference *constructor = new Napi::FunctionReference();
  *constructor = Napi::Persistent(func);
  env.SetInstanceData(constructor);
  exports.Set("VDisplay", func);

  return exports;
}

VDisplay::VDisplay(const Napi::CallbackInfo &info)
    : Napi::ObjectWrap<VDisplay>(info) {
  Napi::Env env = info.Env();
  // ...
  // Napi::Number value = info[0].As<Napi::Number>();
  // this->_value = value.DoubleValue();
  this->_descriptor = [[CGVirtualDisplayDescriptor alloc] init];
  this->_descriptor.name = @"Virtual Display";
  // this->_descriptor.name = "Test Display";
  this->_descriptor.maxPixelsWide = 1920;
  this->_descriptor.maxPixelsHigh = 1080;
  this->_descriptor.sizeInMillimeters = CGSizeMake(1800, 1012.5);
  this->_descriptor.productID = 0x1234;
  this->_descriptor.vendorID = 0x3456;
  this->_descriptor.serialNum = 0x0001;
  this->_display =
      [[CGVirtualDisplay alloc] initWithDescriptor:this->_descriptor];
  this->_settings = [[CGVirtualDisplaySettings alloc] init];
  this->_settings.hiDPI = 2;
  this->_settings.modes = @[
    [[CGVirtualDisplayMode alloc] initWithWidth:1920
                                         height:1080
                                    refreshRate:60],
    [[CGVirtualDisplayMode alloc] initWithWidth:1920
                                         height:1080
                                    refreshRate:30],
  ];
  [this->_display applySettings:this->_settings];
  // this->_display.terminationHandler = ^(id display, CGVirtualDisplay *error)
  // {
  //   NSLog(@"Termination handler called");
  // };
}

Napi::Value VDisplay::GetDisplayId(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();
  return Napi::Number::New(env, this->_display.displayID);
}

// Napi::Value VDisplay::GetValue(const Napi::CallbackInfo &info) {
//   Napi::Env env = info.Env();
//   return Napi::Number::New(env, this->_display.displayID);
// }

// void VDisplay::SetValue(const Napi::CallbackInfo &info,
//                         const Napi::Value &value) {
//   Napi::Env env = info.Env();
//   // ...
//   Napi::Number arg = value.As<Napi::Number>();
//   this->_value = arg.DoubleValue();
// }

// Initialize native add-on
Napi::Object Init(Napi::Env env, Napi::Object exports) {
  VDisplay::Init(env, exports);
  return exports;
}

NS_ASSUME_NONNULL_END

// Register and initialize native add-on
NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
// NODE_API_MODULE(virtual_display, Init)