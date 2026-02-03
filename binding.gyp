{
    "targets": [{
        "target_name": "virtual_display",
        "sources": [],
        "conditions": [
            ['OS=="mac"', {
                "sources": [
                    "src/virtual_display.mm"
                ],
            }, {
                "sources": [
                    "src/noop.cc"
                ]
            }]
        ],
        'include_dirs': [
            "<!@(node -p \"require('node-addon-api').include\")"
        ],
        'libraries': [],
        'dependencies': [
            "<!(node -p \"require('node-addon-api').gyp\")"
        ],
        'defines': ['NAPI_DISABLE_CPP_EXCEPTIONS'],
        "xcode_settings": {
            "MACOSX_DEPLOYMENT_TARGET": "10.14",
            "SYSTEM_VERSION_COMPAT": 1,
            "OTHER_CPLUSPLUSFLAGS": ["-std=c++17", "-stdlib=libc++"],
            "OTHER_LDFLAGS": [
                "-framework Cocoa",
                "-framework CoreGraphics",
                "-framework CoreVideo",
                "-framework IOKit"
            ]
        }
    }]
}
