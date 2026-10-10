# Replay

Replay is an iOS camera app that records on demand, then auto-saves the full take when you stop — with Undo if you didn’t mean it.

## How it works

1. Open the app — live preview only.
2. Aim the phone, then tap the shutter to start.
3. While recording, tap **Clip** (scissors) to save the last 30 seconds without stopping.
4. Tap shutter again to stop — the **full** recording saves to Photos and a temporary Moment. Tap **Undo** within a few seconds to discard.
5. Open a **Moment** later to re-export the last 30s, 60s, or full take before it expires (Keep duration in the library).
6. Open **Library** (left of the shutter when idle) for Moments + the Replay album.

## Controls

- **HD · 30** (top) — tap to toggle HD/4K and cycle 24/30/60 fps
- Pinch to zoom; tap preview to focus
- Torch and mic mute in the top-right
- Leaving the app or taking a call ends the take and auto-saves

## Requirements

- iOS 17+
- Physical iPhone for camera / mic / Photos (Simulator compiles only)

## Build

```bash
xcodegen generate
open Replay.xcodeproj
```

## Tests

```bash
xcodegen generate
xcodebuild test -scheme Replay -destination 'platform=iOS Simulator,name=iPhone 16'
```
