#include <napi.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#include <map>

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

class VDisplayManager : public Napi::ObjectWrap<VDisplayManager> {
public:
    static Napi::Function GetClass(Napi::Env);
    VDisplayManager(const Napi::CallbackInfo &info);
    ~VDisplayManager();

private:
    struct DisplayInfo {
        CGVirtualDisplay *display;
        CGVirtualDisplayDescriptor *descriptor;
        CGVirtualDisplaySettings *settings;
        std::string name;
        unsigned int width;
        unsigned int height;
    };

    std::map<uint32_t, DisplayInfo> _displays;
    
    Napi::Value CreateVirtualDisplay(const Napi::CallbackInfo &info);
    Napi::Value CloneVirtualDisplay(const Napi::CallbackInfo &info);
    Napi::Value DestroyVirtualDisplay(const Napi::CallbackInfo &info);
    Napi::Value GetAllDisplays(const Napi::CallbackInfo &info);
    Napi::Value GetDisplayByID(const Napi::CallbackInfo &info);
    Napi::Value UpdateDisplaySettings(const Napi::CallbackInfo &info);
    
    void InitializeDescriptor(CGVirtualDisplayDescriptor *descriptor, NSString *displayName, 
                            unsigned int width, unsigned int height, int ppi);
    void InitializeSettings(CGVirtualDisplaySettings *settings, unsigned int width, 
                          unsigned int height, CGFloat refreshRate, bool hiDPI);
    Napi::Value CreateDisplayObject(Napi::Env env, const DisplayInfo& info);
    bool ConfigureDisplayMirrorMode(CGDirectDisplayID displayID, bool useMirror);
    CGDirectDisplayID FindExistingDisplayByName(const std::string& name);
    
    int Clamp(int value, int low, int high) {
        return (value < low) ? low : ((value > high) ? high : value);
    }
};

VDisplayManager::VDisplayManager(const Napi::CallbackInfo &info) : ObjectWrap(info) {}

VDisplayManager::~VDisplayManager() {
    for (auto& pair : _displays) {
        auto& info = pair.second;
        [info.descriptor release];
        [info.settings release];
        [info.display release];
    }
    _displays.clear();
}

Napi::Function VDisplayManager::GetClass(Napi::Env env) {
    return DefineClass(env, "VDisplayManager", {
        InstanceMethod("createVirtualDisplay", &VDisplayManager::CreateVirtualDisplay),
        InstanceMethod("cloneVirtualDisplay", &VDisplayManager::CloneVirtualDisplay),
        InstanceMethod("destroyVirtualDisplay", &VDisplayManager::DestroyVirtualDisplay),
        InstanceMethod("getAllDisplays", &VDisplayManager::GetAllDisplays),
        InstanceMethod("getDisplayByID", &VDisplayManager::GetDisplayByID),
        InstanceMethod("updateDisplaySettings", &VDisplayManager::UpdateDisplaySettings),
    });
}

CGDirectDisplayID VDisplayManager::FindExistingDisplayByName(const std::string& name) {
    for (const auto& pair : _displays) {
        if (pair.second.name == name) {
            return pair.first;
        }
    }
    return 0;
}

Napi::Value VDisplayManager::CreateVirtualDisplay(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 7) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }

    unsigned int width = info[0].As<Napi::Number>().Uint32Value();
    unsigned int height = info[1].As<Napi::Number>().Uint32Value();
    CGFloat refreshRate = Clamp(info[2].As<Napi::Number>().Int32Value(), 30, 60);
    bool hiDPI = info[3].As<Napi::Boolean>().Value();
    std::string displayNameStr = info[4].As<Napi::String>().Utf8Value();
    int ppi = Clamp(info[5].As<Napi::Number>().Int32Value(), 72, 300);
    bool useMirror = info[6].As<Napi::Boolean>().Value();

    // Check if display with this name already exists
    CGDirectDisplayID existingID = FindExistingDisplayByName(displayNameStr);
    if (existingID != 0) {
        // Return existing display if found
        return CreateDisplayObject(env, _displays[existingID]);
    }

    NSString *displayName = [NSString stringWithUTF8String:displayNameStr.c_str()];
    if (!displayName) {
        displayName = @"Virtual Display";
    }

    DisplayInfo newDisplay;
    newDisplay.name = displayNameStr;
    newDisplay.width = width;
    newDisplay.height = height;
    
    newDisplay.descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    InitializeDescriptor(newDisplay.descriptor, displayName, width, height, ppi);
    
    newDisplay.display = [[CGVirtualDisplay alloc] initWithDescriptor:newDisplay.descriptor];
    if (!newDisplay.display) {
        [newDisplay.descriptor release];
        Napi::Error::New(env, "Failed to create virtual display").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    newDisplay.settings = [[CGVirtualDisplaySettings alloc] init];
    InitializeSettings(newDisplay.settings, width, height, refreshRate, hiDPI);
    [newDisplay.display applySettings:newDisplay.settings];
    
    // Configure mirror mode
    ConfigureDisplayMirrorMode(newDisplay.display.displayID, useMirror);
    
    // Store the new display
    _displays[newDisplay.display.displayID] = newDisplay;
    
    return CreateDisplayObject(env, newDisplay);
}

Napi::Value VDisplayManager::GetAllDisplays(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    Napi::Array displays = Napi::Array::New(env);
    
    uint32_t index = 0;
    for (const auto& pair : _displays) {
        displays.Set(index++, CreateDisplayObject(env, pair.second));
    }
    
    return displays;
}

Napi::Value VDisplayManager::CloneVirtualDisplay(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();

    if (info.Length() < 2) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }

    NSString *displayName = [NSString stringWithUTF8String:info[0].As<Napi::String>().Utf8Value().c_str()];
    if (!displayName || displayName.length == 0) {
        displayName = @"Virtual Display";
    }

    bool useMirror = info[1].As<Napi::Boolean>().Value();

    // Check if display with this name already exists
    CGDirectDisplayID existingID = FindExistingDisplayByName(displayName.UTF8String);
    if (existingID != 0) {
        // Return existing display info
        auto it = _displays.find(existingID);
        if (it != _displays.end()) {
            return CreateDisplayObject(env, it->second);
        }
    }

    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    CGDisplayModeRef displayMode = CGDisplayCopyDisplayMode(mainDisplay);
    
    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat backingScaleFactor = [mainScreen backingScaleFactor];
    
    unsigned int width = CGDisplayModeGetPixelWidth(displayMode) / backingScaleFactor;
    unsigned int height = CGDisplayModeGetPixelHeight(displayMode) / backingScaleFactor;
    CGFloat refreshRate = CGDisplayModeGetRefreshRate(displayMode);

    CGSize screenSize = CGDisplayScreenSize(mainDisplay);
    float dpi = CGDisplayPixelsWide(mainDisplay) / (screenSize.width / 25.4);
    bool isHiDPI = (dpi > 200);

    DisplayInfo newDisplay;
    newDisplay.name = displayName.UTF8String;
    newDisplay.width = width;
    newDisplay.height = height;

    newDisplay.descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    InitializeDescriptor(newDisplay.descriptor, displayName, width, height, dpi);
    newDisplay.descriptor.productID = CGDisplayModelNumber(mainDisplay) + 1;
    newDisplay.descriptor.vendorID = CGDisplayVendorNumber(mainDisplay);

    newDisplay.display = [[CGVirtualDisplay alloc] initWithDescriptor:newDisplay.descriptor];
    if (!newDisplay.display) {
        [newDisplay.descriptor release];
        return env.Null();
    }

    newDisplay.settings = [[CGVirtualDisplaySettings alloc] init];
    InitializeSettings(newDisplay.settings, width, height, refreshRate, isHiDPI);
    [newDisplay.display applySettings:newDisplay.settings];

    CFRelease(displayMode);

    // Configure mirror mode
    ConfigureDisplayMirrorMode(newDisplay.display.displayID, useMirror);

    // Store the new display
    _displays[newDisplay.display.displayID] = newDisplay;

    return CreateDisplayObject(env, newDisplay);
}

Napi::Value VDisplayManager::GetDisplayByID(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    uint32_t displayID = info[0].As<Napi::Number>().Uint32Value();
    auto it = _displays.find(displayID);
    
    if (it != _displays.end()) {
        return CreateDisplayObject(env, it->second);
    }
    
    return env.Null();
}

Napi::Value VDisplayManager::UpdateDisplaySettings(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    
    // 인자 확인
    if (info.Length() < 4) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    // 디스플레이 ID
    uint32_t displayID = info[0].As<Napi::Number>().Uint32Value();
    
    // 디스플레이 찾기
    auto it = _displays.find(displayID);
    if (it == _displays.end()) {
        Napi::Error::New(env, "Display not found").ThrowAsJavaScriptException();
        return env.Null();
    }

    // 새로운 설정값
    unsigned int newWidth = info[1].As<Napi::Number>().Uint32Value();
    unsigned int newHeight = info[2].As<Napi::Number>().Uint32Value();
    CGFloat newRefreshRate = Clamp(info[3].As<Napi::Number>().Int32Value(), 30, 60);
    bool newHiDPI = info.Length() > 4 ? info[4].As<Napi::Boolean>().Value() : false;

    // 기존 디스플레이 정보 가져오기
    auto &displayInfo = it->second;
    CGVirtualDisplaySettings *settings = displayInfo.settings;
    
    // 설정 업데이트
    InitializeSettings(settings, newWidth, newHeight, newRefreshRate, newHiDPI);

    // 설정 적용
    if (![displayInfo.display applySettings:settings]) {
        Napi::Error::New(env, "Failed to apply display settings").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }

    // 디스플레이 정보 업데이트
    displayInfo.width = newWidth;
    displayInfo.height = newHeight;

    return Napi::Boolean::New(env, true);
}

Napi::Value VDisplayManager::DestroyVirtualDisplay(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    uint32_t displayID = info[0].As<Napi::Number>().Uint32Value();
    auto it = _displays.find(displayID);
    
    if (it != _displays.end()) {
        auto& displayInfo = it->second;
        [displayInfo.descriptor release];
        [displayInfo.settings release];
        [displayInfo.display release];
        _displays.erase(it);
        return Napi::Boolean::New(env, true);
    }
    
    return Napi::Boolean::New(env, false);
}

void VDisplayManager::InitializeDescriptor(CGVirtualDisplayDescriptor *descriptor, NSString *displayName, 
                                         unsigned int width, unsigned int height, int ppi) {
    descriptor.name = displayName;
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    
    double ratio = 25.4 / ppi;
    descriptor.sizeInMillimeters = CGSizeMake(width * ratio, height * ratio);
    descriptor.productID = 0xeeee + width + height + ppi;
    descriptor.vendorID = 0xeeee;
    descriptor.serialNum = 0x0001;
}

void VDisplayManager::InitializeSettings(CGVirtualDisplaySettings *settings, unsigned int width, 
                                       unsigned int height, CGFloat refreshRate, bool hiDPI) {
    settings.hiDPI = hiDPI ? 1 : 0;
    
    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] 
                                 initWithWidth:width height:height refreshRate:refreshRate];
    if (hiDPI) {
        CGVirtualDisplayMode *lowResMode = [[CGVirtualDisplayMode alloc] 
                                           initWithWidth:width/2 height:height/2 refreshRate:refreshRate];
        settings.modes = @[mode, lowResMode];
    } else {
        settings.modes = @[mode];
    }
}

bool VDisplayManager::ConfigureDisplayMirrorMode(CGDirectDisplayID displayID, bool useMirror) {
    CGDirectDisplayID mainDisplay = CGMainDisplayID();
    CGDisplayConfigRef config;
    CGBeginDisplayConfiguration(&config);
    
    if (useMirror) {
        if (!CGDisplayIsInMirrorSet(displayID)) {
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, displayID, mainDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to enable mirror mode: %d", err);
                return false;
            }
        }
    } else {
        if (CGDisplayIsInMirrorSet(displayID)) {
            CGError err = CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay);
            if (err != kCGErrorSuccess) {
                NSLog(@"Failed to disable mirror mode: %d", err);
                return false;
            }
        }
    }
    
    return CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly) == kCGErrorSuccess;
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    Napi::String name = Napi::String::New(env, "VDisplayManager");
    exports.Set(name, VDisplayManager::GetClass(env));
    return exports;
}

NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)