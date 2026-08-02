# Replay

Replay is an iOS camera app that continuously buffers the last **15 seconds** of video and audio. Press **Save** when something worth keeping happens — no traditional record / stop, no piles of unused footage.

## How it works

1. Open the app — the camera starts buffering immediately.
2. Pick a buffer length (5 / 10 / 15 / 30 seconds) if you want.
3. Hold until the moment you want.
4. Tap **Save** to write the trailing window to Photos.

## Requirements

- iOS 17+
- Physical iPhone for camera / mic / Photos (Simulator compiles only)

## Build

```bash
xcodegen generate
open Replay.xcodeproj
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -scheme Replay -destination 'platform=iOS Simulator,name=iPhone 16' build
```
