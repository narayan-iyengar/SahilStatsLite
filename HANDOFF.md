# Rebound — Handoff Notes (2026-04-25)

Current build: **v297 Release**. App rebranded from SahilStatsLite to **Rebound**.

---

## Current State

Feature-complete. All core systems working: recording, tracking, streaming, Watch scoring, auto-upload.
HaishinKit removed from SPM. UX polished (Tier 1+2 complete).

---

## Architecture

```
Watch (Source of Truth when connected)
    → scores, clock, period, stats
    → sends to Phone via transferUserInfo
    → runs independently when Phone unavailable

iPhone (Camera + Recording + Streaming)
    ← follows Watch state when connected
    → becomes source of truth if Watch disconnected
    → 4K recording with burned-in score overlay
    → 1080p YouTube live stream (custom RTMP)
    → YOLOv8n auto-tracking via DockKit gimbal
```

### Streaming Pipeline (Custom RTMP, no HaishinKit)
```
Camera 4K → CIContext scale 1080p → VTCompressionSession H.264 → FLV → NWConnection TCP:1935
                                                                  + Silent AAC loop (A/V sync)
                                                                  → YouTube (a.rtmp.youtube.com)
```

### Tracking Pipeline (Skynet v5.1)
```
Camera → Downscale 640x360 → YOLOv8n (0.15 conf) → PersonClassifier → DeepTracker
                                                         ↓
                                               GimbalTrackingManager
                                               ├─ Pan PID (Kp=0.8, negated)
                                               ├─ Tilt PID (Kp=0.4)
                                               └─ Gravity drift (-0.05 rad/s after 5s no detect)
```

## Key Files

| File | Purpose |
|------|---------|
| `SahilRTMPStreamer.swift` | Custom RTMP (~350 lines, zero dependencies) |
| `StreamingService.swift` | Streaming lifecycle, YouTube broadcast API |
| `YouTubeService.swift` | OAuth, upload, broadcast management → Sahil Hoops channel |
| `AutoZoomManager.swift` | Skynet orchestrator |
| `YOLODetector.swift` | YOLOv8n CoreML, letterbox, NMS |
| `GimbalTrackingManager.swift` | DockKit PID (pan + tilt + gravity) |
| `WatchConnectivityClient.swift` | Watch-side: standalone clock, period, stats |
| `WatchConnectivityService.swift` | Phone-side: receives Watch state |
| `RecordingManager.swift` | 4K capture, overlay, frame fork to streaming |
| `OverlayRenderer.swift` | Score overlay — 4 styles built (classic active, others ready) |

## Recent Changes

### Apr 25 — UX Polish (Tier 1+2)
- HaishinKit removed from SPM (was unused, slowed builds)
- Game log film icon for games with local video
- Haptic feedback on phone score taps
- Stat tiles capsule-shaped with white-on-color (AST, REB, STL, BLK, TO, PF)
- Tracking indicator visible during recording (player count + gimbal status)
- Smart clock +1:00 undo via long-press (warning haptic)
- 4 scoreboard overlay styles built in OverlayRenderer (Classic, Full Bar, Broadcast, Pill)
  - Picker removed (style switching had a binding bug, classic works, not worth debugging)
  - Code preserved for future use

### Apr 25 — Watch Standalone Mode
- Watch clock counts down independently (was frozen without phone)
- Watch advances periods locally with clock reset
- Personal fouls wired (was placeholder)
- New game fully resets all stats

### Apr 18-19 — Tracking + Rebrand
- YOLO coordinates fixed (pixel→normalized, was causing 0 detections)
- Gimbal pan direction negated (was opposite)
- Tilt PID added (Kp=0.4) + gravity drift
- App rebranded to "Rebound"
- Repo renamed to github.com/narayan-iyengar/rebound

### Apr 7-8 — Streaming
- Custom RTMP implementation (replaced HaishinKit entirely)
- Silent AAC for A/V sync
- Auto-broadcast via YouTube API (unlisted, Sports, ultra-low latency)
- Per-game streaming toggle in GameSetupView

## YouTube
- Channel: Sahil Hoops (@RealDeadlSahil, UCUMg4lDQC7cxgpHc5xrOH4w)
- All uploads + broadcasts target this channel
- Titles: "Team vs Opponent", descriptions: "Recorded with Rebound"

## Known Issues
- Free dev cert expires unpredictably (considering $99/yr Apple Developer Program)
- Ultra 2 often times out on wireless deploy
- YOLO foreground filter blocks home testing (works at game distance 10+ feet)
- Tilt direction confirmed at home, untested at game (may need sign flip)
- Scoreboard style picker binding broken (styles render correctly, switching doesn't work — low priority)

## Optimization Plan (Tier 3+4 — not yet implemented)

### Tier 3 — Medium Risk (touches existing logic)
- CVPixelBuffer pool reuse for streaming (performance — replaces per-frame allocation)
- RTMP auto-reconnect on WiFi drop (streaming resilience)
- Silent audio fallback when AVAudioConverter fails explicitly
- YouTube broadcast API retry on network blip

### Tier 4 — Higher Risk (architecture changes)
- `nonisolated(unsafe)` audit and reduction (~49 across codebase, potential data races)
- Game persistence conflict resolution hardening (Firebase merge edge cases)
- Explicit AI frame pipeline replacing fragile callback pattern

## Deploy
```bash
ssh narayan@Narayans-MacBook-Pro.local "bash ~/SahilStats/deploy.sh"
```
