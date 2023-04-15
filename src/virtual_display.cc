#include <Windows.h>
#include <napi.h>

class VirtualDisplay : public Napi::ObjectWrap<VirtualDisplay> {
public:
  static Napi::Object Init(Napi::Env env, Napi::Object exports);
  VirtualDisplay(const Napi::CallbackInfo &info);

  Napi::Value CreateVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value CloneVirtualDisplay(const Napi::CallbackInfo &info);
  Napi::Value DestroyVirtualDisplay(const Napi::CallbackInfo &info);

private:
  DEVMODE _devMode;
  DISPLAY_DEVICE _displayDevice;
  DWORD _displayId;
};

Napi::Object VirtualDisplay::Init(Napi::Env env, Napi::Object exports) {
  Napi::Function func =
      DefineClass(env, "VirtualDisplay",
                  {
                      InstanceMethod("createVirtualDisplay",
                                     &VirtualDisplay::CreateVirtualDisplay),
                      InstanceMethod("cloneVirtualDisplay",
                                     &VirtualDisplay::CloneVirtualDisplay),
                      InstanceMethod("destroyVirtualDisplay",
                                     &VirtualDisplay::DestroyVirtualDisplay),
                  });

  Napi::FunctionReference *constructor = new Napi::FunctionReference();
  *constructor = Napi::Persistent(func);
  exports.Set("VirtualDisplay", func);
  env.SetInstanceData(constructor);

  return exports;
}

VirtualDisplay::VirtualDisplay(const Napi::CallbackInfo &info)
    : Napi::ObjectWrap<VirtualDisplay>(info) {
  // Initialize display properties
  ZeroMemory(&_devMode, sizeof(_devMode));
  _devMode.dmSize = sizeof(_devMode);
  ZeroMemory(&_displayDevice, sizeof(_displayDevice));
  _displayDevice.cb = sizeof(_displayDevice);
  _displayId = 0;
}

Napi::Value
VirtualDisplay::CreateVirtualDisplay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  // Set DEVMODE properties for the virtual display
  _devMode.dmPelsWidth = 1280;
  _devMode.dmPelsHeight = 720;
  _devMode.dmBitsPerPel = 32;
  _devMode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL;

  // Create virtual display
  LONG result = ChangeDisplaySettingsEx(NULL, &_devMode, NULL,
                                        CDS_UPDATEREGISTRY | CDS_NORESET, NULL);

  if (result != DISP_CHANGE_SUCCESSFUL) {
    Napi::Error::New(env, "Failed to create virtual display")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Save display ID
  _displayId = 1;

  return Napi::Number::New(env, _displayId);
}

Napi::Value
VirtualDisplay::CloneVirtualDisplay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  // Find the primary display device
  for (int i = 0; EnumDisplayDevices(NULL, i, &_displayDevice, 0); i++) {
    if (_displayDevice.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) {
      break;
    }
  }

  // Get the primary display device settings
  EnumDisplaySettings(_displayDevice.DeviceName, ENUM_CURRENT_SETTINGS,
                      &_devMode);

  // Clone the virtual display
  LONG result = ChangeDisplaySettingsEx(NULL, &_devMode, NULL,
                                        CDS_UPDATEREGISTRY | CDS_NORESET, NULL);

  if (result != DISP_CHANGE_SUCCESSFUL) {
    Napi::Error::New(env, "Failed to clone virtual display")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Save display ID
  _displayId = 1;

  return Napi::Number::New(env, _displayId);
}

Napi::Value
VirtualDisplay::DestroyVirtualDisplay(const Napi::CallbackInfo &info) {
  Napi::Env env = info.Env();

  // Destroy the virtual display
  LONG result = ChangeDisplaySettingsEx(NULL, NULL, NULL, 0, NULL);

  if (result != DISP_CHANGE_SUCCESSFUL) {
    Napi::Error::New(env, "Failed to destroy virtual display")
        .ThrowAsJavaScriptException();
    return env.Null();
  }

  // Reset display ID
  _displayId = 0;

  return Napi::Number::New(env, _displayId);
}

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
  return VirtualDisplay::Init(env, exports);
}

NODE_API_MODULE(addon, InitAll)