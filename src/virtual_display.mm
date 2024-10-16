#include <napi.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

@class CGVirtualDisplayDescriptor;
@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)arg1 height:(NSUInteger)arg2 refreshRate:(CGFloat)arg3;
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
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay*);
- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)arg1;
@end

class VDisplay : public Napi::ObjectWrap<VDisplay> {
public:
    static Napi::Function GetClass(Napi::Env);
    VDisplay(const Napi::CallbackInfo &info);

private:
    Napi::Value CreateVirtualDisplay(const Napi::CallbackInfo &info);
    Napi::Value CloneVirtualDisplay(const Napi::CallbackInfo &info);
    Napi::Value DestroyVirtualDisplay(const Napi::CallbackInfo &info);
    
    CGVirtualDisplay *_display;
    CGVirtualDisplayDescriptor *_descriptor;
    CGVirtualDisplaySettings *_settings;

    void InitializeDescriptor(NSString *displayName, unsigned int width, unsigned int height, int ppi);
    void InitializeSettings(unsigned int width, unsigned int height, CGFloat refreshRate, bool hiDPI);
    Napi::Value CreateDisplayObject(Napi::Env env, unsigned int width, unsigned int height);
    
    int Clamp(int value, int low, int high) {
        return (value < low) ? low : ((value > high) ? high : value);
    }
};

VDisplay::VDisplay(const Napi::CallbackInfo &info) : ObjectWrap(info) {}

Napi::Function VDisplay::GetClass(Napi::Env env) {
    return DefineClass(env, "VDisplay", {
        InstanceMethod("createVirtualDisplay", &VDisplay::CreateVirtualDisplay),
        InstanceMethod("cloneVirtualDisplay", &VDisplay::CloneVirtualDisplay),
        InstanceMethod("destroyVirtualDisplay", &VDisplay::DestroyVirtualDisplay),
    });
}

void VDisplay::InitializeDescriptor(NSString *displayName, unsigned int width, unsigned int height, int ppi) {
    _descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    _descriptor.name = displayName;
    _descriptor.maxPixelsWide = width;
    _descriptor.maxPixelsHigh = height;
    
    double ratio = 25.4 / ppi;
    _descriptor.sizeInMillimeters = CGSizeMake(width * ratio, height * ratio);
    _descriptor.productID = 0xeeee + width + height + ppi;
    _descriptor.vendorID = 0xeeee;
    _descriptor.serialNum = 0x0001;
}

void VDisplay::InitializeSettings(unsigned int width, unsigned int height, CGFloat refreshRate, bool hiDPI) {
    _settings = [[CGVirtualDisplaySettings alloc] init];
    _settings.hiDPI = hiDPI ? 1 : 0;
    
    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:refreshRate];
    if (hiDPI) {
        CGVirtualDisplayMode *lowResMode = [[CGVirtualDisplayMode alloc] initWithWidth:width/2 height:height/2 refreshRate:refreshRate];
        _settings.modes = @[mode, lowResMode];
    } else {
        _settings.modes = @[mode];
    }
}

Napi::Value VDisplay::CreateDisplayObject(Napi::Env env, unsigned int width, unsigned int height) {
    Napi::Object obj = Napi::Object::New(env);
    obj.Set(Napi::String::New(env, "id"), Napi::Number::New(env, _display.displayID));
    obj.Set(Napi::String::New(env, "width"), Napi::Number::New(env, width));
    obj.Set(Napi::String::New(env, "height"), Napi::Number::New(env, height));
    return obj;
}

Napi::Value VDisplay::CreateVirtualDisplay(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 7) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }

    // Params [width, height, refreshRate, hiDPI, displayName, ppi, useMirror]

    unsigned int width = info[0].As<Napi::Number>().Uint32Value();
    unsigned int height = info[1].As<Napi::Number>().Uint32Value();
    CGFloat refreshRate = Clamp(info[2].As<Napi::Number>().Int32Value(), 30, 60);
    bool hiDPI = info[3].As<Napi::Boolean>().Value();
    std::string displayNameStr = info[4].As<Napi::String>().Utf8Value();
    int ppi = Clamp(info[5].As<Napi::Number>().Int32Value(), 72, 300);
    bool useMirror = info[6].As<Napi::Boolean>().Value();

    NSString *displayName = [NSString stringWithUTF8String:displayNameStr.c_str()];
    if (!displayName) {
        displayName = @"Virtual Display";
    }

    // store current main display id and bounds
    // CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
    uint32_t mainDisplay = CGMainDisplayID();
    NSLog(@"Previous Main display ID: %d", mainDisplay);

    InitializeDescriptor(displayName, width, height, ppi);
    if (!_descriptor) {
        Napi::Error::New(env, "Failed to create display descriptor").ThrowAsJavaScriptException();
        return env.Null();
    }

    _display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
    if (!_display) {
        Napi::Error::New(env, "Failed to create virtual display").ThrowAsJavaScriptException();
        return env.Null();
    }

    InitializeSettings(width, height, refreshRate, hiDPI);
    [_display applySettings:_settings];

    // postprocess start
    uint32_t newMainDisplayID = CGMainDisplayID();
    NSLog(@"Current Main Display after virtual display creation: %d", newMainDisplayID);
    
    CGDisplayConfigRef config;
    CGBeginDisplayConfiguration(&config);
    if (newMainDisplayID == _display.displayID && newMainDisplayID != mainDisplay) {
        NSLog(@"Unintended case 1: Virtual display set as main display => restore Primary Display as main display");
        CGConfigureDisplayOrigin(config, mainDisplay, 0, 0);
    }
   
    // if Primary Display is Mirroring Virtual Display, disable mirror mode
    uint32_t displayId = CGDisplayMirrorsDisplay(mainDisplay);
    NSLog(@"Mirror source of Primary Display is: %d", displayId);
    if (displayId == _display.displayID) {
        NSLog(@"Unintended case 2: Primary display is mirroring virtual display => disable mirror mode");
        CGConfigureDisplayMirrorOfDisplay(config, displayId, kCGNullDirectDisplay);
    }
    CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);

    boolean_t isMirror = CGDisplayIsInMirrorSet(_display.displayID);
    NSLog(@"Virtual Display is in mirror set: %d", isMirror);
    CGBeginDisplayConfiguration(&config);
    if (useMirror) {
        if (isMirror == 0) {
            NSLog(@"Enable Virtual Display mirror mode");
            // set mirror mode
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, _display.displayID, mainDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to enable mirror mode: %d", err);
            }
        }
    } else {
        if (isMirror == 0) {
            NSLog(@"Disable Virtual Display mirror mode");
            // if already in mirror mode, disable mirror mode
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, _display.displayID, kCGNullDirectDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to disable mirror mode: %d", err);
            }
        }
    }
    CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    // postprocess end

    NSLog(@"Virtual display created with ID: %d", _display.displayID);
    return CreateDisplayObject(env, width, height);
}

Napi::Value VDisplay::CloneVirtualDisplay(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();

    if (info.Length() < 2) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }

    // Params [displayName, useMirror]
    NSString *displayName = [NSString stringWithUTF8String:info[0].As<Napi::String>().Utf8Value().c_str()];
    if (!displayName || displayName.length == 0) {
        displayName = @"Virtual Display";
    }

    bool useMirror = info[1].As<Napi::Boolean>().Value();

    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(mainDisplay);
    
    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat backingScaleFactor = [mainScreen backingScaleFactor];
    
    unsigned int width = CGDisplayModeGetPixelWidth(displayMode) / backingScaleFactor;
    unsigned int height = CGDisplayModeGetPixelHeight(displayMode) / backingScaleFactor;
    CGFloat refreshRate = CGDisplayModeGetRefreshRate(displayMode);

    CGSize screenSize = CGDisplayScreenSize(mainDisplay);
    float dpi = CGDisplayPixelsWide(mainDisplay) / (screenSize.width / 25.4);
    // increase DPI for retina display
    bool isHiDPI = (dpi > 200);

    InitializeDescriptor(displayName, width, height, dpi);
    _descriptor.productID = CGDisplayModelNumber(mainDisplay) + 1;
    _descriptor.vendorID = CGDisplayVendorNumber(mainDisplay);

    _display = [[CGVirtualDisplay alloc] initWithDescriptor:_descriptor];
    InitializeSettings(width, height, refreshRate, isHiDPI);
    [_display applySettings:_settings];

    CFRelease(displayMode);

    // postprocess start
    uint32_t newMainDisplayID = CGMainDisplayID();
    NSLog(@"Current Main Display after virtual display creation: %d", newMainDisplayID);
    
    CGDisplayConfigRef config;
    CGBeginDisplayConfiguration(&config);
    if (newMainDisplayID == _display.displayID && newMainDisplayID != mainDisplay) {
        NSLog(@"Unintended case 1: Virtual display set as main display => restore Primary Display as main display");
        CGConfigureDisplayOrigin(config, mainDisplay, 0, 0);
    }
   
    // if Primary Display is Mirroring Virtual Display, disable mirror mode
    uint32_t displayId = CGDisplayMirrorsDisplay(mainDisplay);
    NSLog(@"Mirror source of Primary Display is: %d", displayId);
    if (displayId == _display.displayID) {
        NSLog(@"Unintended case 2: Primary display is mirroring virtual display => disable mirror mode");
        CGConfigureDisplayMirrorOfDisplay(config, displayId, kCGNullDirectDisplay);
    }
    CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);

    boolean_t isMirror = CGDisplayIsInMirrorSet(_display.displayID);
    NSLog(@"Virtual Display is in mirror set: %d", isMirror);
    CGBeginDisplayConfiguration(&config);
    if (useMirror) {
        if (isMirror == 0) {
            NSLog(@"Enable Virtual Display mirror mode");
            // set mirror mode
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, _display.displayID, mainDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to enable mirror mode: %d", err);
            }
        }
    } else {
        if (isMirror == 0) {
            NSLog(@"Disable Virtual Display mirror mode");
            // if already in mirror mode, disable mirror mode
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, _display.displayID, kCGNullDirectDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to disable mirror mode: %d", err);
            }
        }
    }
    CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    // postprocess end

    return CreateDisplayObject(env, width, height);
}

Napi::Value VDisplay::DestroyVirtualDisplay(const Napi::CallbackInfo &info) {
    if (_display) {
        [_descriptor release];
        _descriptor = nil;
        [_settings release];
        _settings = nil;
        [_display release];
        _display = nil;
        return Napi::Boolean::New(info.Env(), true);
    } else {
        return Napi::Boolean::New(info.Env(), false);
    }
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    Napi::String name = Napi::String::New(env, "VDisplay");
    exports.Set(name, VDisplay::GetClass(env));
    return exports;
}

NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)