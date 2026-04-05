# SahilStatsLite — Handoff Notes (2026-04-05)

Full two-day session (2026-04-04 + 2026-04-05). Current build: **v186 Release**.

---

## Current State

All sync fixed, zero warnings, Release builds, fully wireless deploy, YouTube streaming framework in place.

---

## What Was Built (2026-04-05)

### Wireless Deploy Pipeline (fully working, no USB)
```
Work Mac → git push → SSH to personal Mac → bash ~/SahilStats/deploy.sh
    → xcodebuild Release, generic/platform=iOS
    → xcrun devicectl → Narayans-iPhone.coredevice.local
    → xcrun devicectl → Narayans-AppleWatch-8.coredevice.local (Series 8)
    → xcrun devicectl → Narayans-AppleWatch.coredevice.local (Ultra 2)
```
- Keychain unlocked via `~/.sahil_deploy_pass`
- Retry logic in `install_device()` — 3 attempts, 5s apart, never fatal
- Watch apps use embedded `iPhone.app/Watch/WatchApp.app` (same binary)
- Release builds: faster, smaller, no .debug.dylib signing issues
- Per-frame gimbal debugPrint guarded with `#if DEBUG`

### Build Number Verification
- iOS Settings → About: "1.0 (186)"
- Watch pre-game header: "build 186" (small text under SahilStats)

### Watch Sync (Fixed)
- `transferUserInfo` for all Watch→Phone scoring (guaranteed delivery)
- Wall clock timestamps — zero drift for full game
- `sendFullSnapshot()` — no merge, complete state snapshot

### Stats Improvements
- "Last 5" time period added to trend chart
- Recent form card: last 5 PPG vs season avg + best game callout
- Scrollable horizontal chart (no cramped x-axis labels)
- Team name shown in game log row (orange text)

### Watch Ultra 2 Text Sizing
- Score: 56pt, Clock: 28pt, Feedback: 26pt, TeamName: 13pt
- Series 8 also bumped: Score 40pt (was 38)

### YouTube Streaming Framework (HaishinKit v3)
**Status: Framework installed and compiling. Stream key pending (YouTube 24hr approval).**

Architecture:
```
OverlayRenderer composites frame once
    ↓ same CVPixelBuffer
AVAssetWriter (HEVC 15Mbps local)    StreamingService (H.264 6Mbps → YouTube)
```

Files:
- `StreamingService.swift` — RTMPConnection + RTMPStream (actor), setVideoSettings/setAudioSettings via await, frame injection via Task { await stream.append(sb) }
- `RecordingManager.swift` — `isStreamingActive` flag, forks composited frame after OverlayRenderer
- `UltraMinimalRecordingView.swift` — stream starts/stops with game clock, YT indicator in REC area
- `HomeView.swift` — Settings: "YouTube Live" section with SecureField for stream key

How it works:
- Set stream key once in Settings (YouTube Studio → Go Live → Stream → persistent key)
- Stream auto-starts when game clock starts, auto-stops at game end
- Same scoreboard overlay as local recording — parents see identical view
- Video auto-saves to YouTube when stream ends
- Rename video in YouTube Studio after each game

Stream key sharing: Share ONE YouTube watch link at season start. Parents bookmark it. Never changes.

---

## HONEST BLOAT AUDIT (do next session)

These files are compiled into the app but never used during games. Should be deleted.

| File | Lines | Reason |
|---|---|---|
| `AILabView.swift` | 262 | Stale — old pre-YOLO pipeline |
| `VideoAnalysisPipeline.swift` | 414 | Stale old pipeline |
| `TestVideoProcessor.swift` | 576 | Stale |
| `SkynetTestView.swift` | 520 | Stale |
| `CourtDetector.swift` | 448 | R&D, never worked well |
| `ActionProbabilityField.swift` | 369 | Unused |
| `GameStateDetector.swift` | 335 | Unused |
| **~3,174 lines total** | | **Delete these** |

Root dir scripts to delete: `dev_agent.py`, `gemini_agent.py`, `push_to_github.sh`
`SkynetTest/` folder: 3,300 lines of CLI R&D, never called by app — archive or delete.

`HomeView.swift` at 2,334 lines — watch it. Consider splitting stats sheet into its own file if it grows.

---

## TODO — Next Session

### Do Now (when stream key arrives)
1. **Test streaming end-to-end** — enter stream key in Settings, start a game, verify YouTube shows live feed with overlay
2. **Verify stream health reconnects** — test RTMP drop/reconnect behavior
3. **Battery test** — streaming + YOLO + gimbal = ~90 min. Get USB-C power bank.

### Still Pending
4. **Gimbal axis verify** — Y=yaw assumed. If gimbal tilts instead of pans: swap to X in GimbalTrackingManager.swift line ~242
5. **Kp tuning** — after first real game recording
6. **Watch end-game long press** — raise 0.5s→1.0s (one line WatchScoringView.swift)
7. **Ultra 2 deploy fix** — timed out intermittently, iOS auto-sync covers it

### YouTube Streaming Setup (user action needed)
- studio.youtube.com → Create → Go Live → Stream
- Set Latency: Low latency, Visibility: Unlisted, Stream type: Persistent
- Copy stream key → paste into app Settings

---

## Architecture Quick Reference

```
iPhone Camera (4K)
    ↓ 15fps AI frames (640x360)
SkynetProcessor (Swift actor)
    ├─ YOLOv8n CoreML (CONFIRMED LOADING)
    ├─ VNDetectHumanBodyPoseRequest
    ├─ BallDetector (fast-break early warning only)
    ├─ DeepTracker (Kalman + Hungarian)
    └─ PersonClassifier (player cluster = primary camera)
           ↓
    GimbalTrackingManager → PID setAngularVelocity (Y=yaw, Kp=1.6)
    RecordingManager → OverlayRenderer → CVPixelBuffer
           ↓                    ↓
    AVAssetWriter          StreamingService
    HEVC 15Mbps            H.264 6Mbps → YouTube RTMP
    local file             rtmps://a.rtmp.youtube.com/live2
```

## Devices
- iPhone: Narayans-iPhone.coredevice.local
- Watch Series 8 (scoring): Narayans-AppleWatch-8.coredevice.local
- Watch Ultra 2 (daily): Narayans-AppleWatch.coredevice.local
- Personal Mac SSH: narayan@Narayans-MacBook-Pro.local
- Deploy: `ssh narayan@Narayans-MacBook-Pro.local "bash ~/SahilStats/deploy.sh"`

## Key Constants to Tune
- Gimbal Kp: GimbalTrackingManager.swift (Kp = 1.6, maxPanVelocity = 0.8)
- Gimbal axis: Vector3D(x: 0, y: panVelocity, z: 0) — swap x/y if tilts instead of pans
- Stream bitrate: StreamingService.swift (6_000_000 = 6 Mbps)
- AI frame rate: SkynetProcessor.processInterval = 0.067 (15fps, raise to 0.1 if thermal issues)
