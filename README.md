# Replay

Replay is an iOS camera app that buffers while you film, then lets you choose how much to keep when you stop.

## How it works

1. Open the app — live preview only.
2. Aim the phone, then tap the shutter to start.
3. While recording, tap **Clip** (scissors) to save the last 30 seconds without stopping.
4. Tap shutter again to stop — choose **Last 30 Seconds**, **Last 60 Seconds** (when long enough), **Full Recording**, or **Don't Save**. **Cancel** keeps a temporary Moment instead of deleting.
5. A frozen **Moment** stays available (Keep duration in the library) if you cancel or save — re-export anytime before it expires.
6. Open the in-app roll (left of the shutter when idle) for Moments + saved clips.

## Controls

- **HD · 30** (top) — tap to toggle HD/4K and cycle 24/30/60 fps
- Pinch to zoom; tap preview to focus
- Torch and mic mute in the top-right
- Leaving the app or taking a call ends the take and offers save

## Requirements

- iOS 17+
- Physical iPhone for camera / mic / Photos (Simulator compiles only)

## Build

```bash
xcodegen generate
open Replay.xcodeproj
```
