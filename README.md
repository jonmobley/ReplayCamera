# Replay

Replay is an iOS camera app that continuously buffers the last **30 seconds** of video and audio. Press **Save** when something worth keeping happens — no traditional record / stop.

## How it works

1. Open the app — the camera starts buffering immediately.
2. Hold until the moment you want.
3. Tap **Save** — Replay keeps your default length (30s by default) and writes it to a **Replay** album in Photos (syncs via iCloud Photos when enabled).
4. A frozen **Moment** stays available briefly so you can save another length from the same take.
5. Open the in-app roll (photo stack button) for Moments + saved clips.
6. Change the default save length in **Settings** (gear): 5 / 10 / 15 / 30 seconds.

## Requirements

- iOS 17+
- Physical iPhone for camera / mic / Photos (Simulator compiles only)

## Build

```bash
xcodegen generate
open Replay.xcodeproj
```
