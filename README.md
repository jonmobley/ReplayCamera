# Replay

Replay is an iOS camera app that continuously buffers the last **30 seconds** of video and audio. Press **Save** when something worth keeping happens — no traditional record / stop.

## How it works

1. Open the app — the camera starts buffering immediately.
2. Hold until the moment you want.
3. Tap **Save** — Replay instantly keeps your default length (30 seconds by default) and writes it to Photos in the background.
4. Change the default in **Settings** (gear) anytime: 5 / 10 / 15 / 30 seconds.

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
xcodebuild -scheme Replay -destination 'generic/platform=iOS Simulator' build
```
