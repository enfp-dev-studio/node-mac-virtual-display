# SideScreen

The independent capture library at
https://github.com/enfp-dev-studio/node-mac-screen-capture adapts capture
configuration, quality presets, short-GOP encoding, and cached-frame replay
from SideScreen:
https://github.com/tranvuongquocdat/SideScreen

The root virtual-display npm package does not include this helper. A copy of
this notice ships with the separate capture package and must accompany its
distribution, including when the helper is bundled in an application.

Reference revision: `9b0ac6d671b67e6d36ccde48d41c84cf636b616d`.
See `MacHost/Sources/ScreenCapture.swift` and `MacHost/Sources/VideoEncoder.swift`.
The transport, Node process protocol, validation, and buffer ownership differ.

MIT License

Copyright (c) 2025 Side Screen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
