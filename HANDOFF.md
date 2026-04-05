# SahilStatsLite — Handoff Notes (2026-04-04)

This document captures everything done across the two-day session (2026-04-03 and 2026-04-04), and the full TODO list for the next session.

---

## What Was Fixed (2026-04-03 — previous session)

See previous HANDOFF notes embedded in git history. Key wins:
- Pan-only gimbal, 15fps AI, Vision off main thread, CIContext pooling, age classifier removed
- Body pose detection, team color learning, YOLOv8n CoreML
- Player cluster as primary camera, ball as fast-break early warning only
- HEVC at 15 Mbps, PID gimbal velocity control
- SkynetProcessor Swift actor, zero concurrency warnings
- Build number auto-increments from git commit count

---

## What Was Fixed (2026-04-04 — this session)

### Watch Sync — Three Root Causes Fixed

**1. Score drops when phone backgrounded**
- Old: `sendMessage` requires phone foreground. During a game (phone recording, screen off), scores sent from Watch were silently dropped. Watch showed 23, phone showed 22, video overlay was wrong.
- Fix: `WatchConnectivityClient` now uses `transferUserInfo` for all scoring and stat sends. `transferUserInfo` queues messages and delivers them guaranteed even when phone is backgrounded. Added `didReceiveUserInfo` on phone side (`WatchConnectivityService`).

**2. Clock drift between phone and Watch**
- Old: Both phone and Watch ran independent `Timer.publish(every: 1.0)` countdown timers. These drift apart due to main thread load and BLE delivery delay. After 10 minutes, 3-5 second gap.
- Fix: Phone records `clockStartedAt = Date().timeIntervalSince1970` and `secondsAtClockStart = remainingSeconds` when clock starts/resumes. Watch computes `remaining = secondsAtClockStart - elapsed(since clockStartedAt)` using `Date()` directly. Both devices use the same wall clock — zero drift for a full game. Watch local timer now just refreshes the display, not counting down.

**3. Active game not showing on Watch**
- Old: `updateApplicationContext` was called with MERGED context. A game's worth of `scoreUpdate`, `clockUpdate`, `periodUpdate`, `gameState`, `endGame` flags all accumulated in the context simultaneously. Watch read conflicting flags and ended up in unpredictable state.
- Fix: `sendFullSnapshot()` replaces all individual send methods. Writes complete game state atomically, replacing entire context. Watch always reads a clean, consistent snapshot.

**Files changed:**
- `WatchConnectivityService.swift` — `sendFullSnapshot()`, removed merge, `didReceiveUserInfo`
- `WatchConnectivityClient.swift` — `transferUserInfo` for all sends, wall clock computation, `applyClockState()`
- `UltraMinimalRecordingView.swift` — `clockStartedAt` + `secondsAtClockStart` state vars, passed in all sync calls

### Build Number
- `CURRENT_PROJECT_VERSION` now passed as `$(git rev-list --count HEAD)` to xcodebuild
- Build 170+ as of this session, increments every commit
- Both iOS and Watch apps from same xcodebuild get same number → confirms sync

### Code Quality
- All Swift concurrency warnings eliminated (BallDetector, BallKalmanFilter, UltraSmoothZoomController stored vars marked `nonisolated(unsafe)`, private methods marked `nonisolated`)
- `SWIFT_STRICT_CONCURRENCY = minimal` in project build settings

### Infrastructure
- `bypassPermissions` in `.claude/settings.json` for project
- Broad wildcard rules in `~/.claude/settings.json`: `Bash(ssh:*)`, `Bash(git:*)`, `Bash(xcodebuild:*)`, `Bash(xcrun:*)`, `Bash(grep:*)`, `Bash(find:*)`, `Bash(brew:*)`
- `sahil_agent.py` v2 — zero-intervention agent with build-fix loop and Watch Series 8 deployment
- `deploy.sh` — pull+build+ios-deploy iPhone + xcrun devicectl Watch Series 8

---

## TODO — Next Session

### High Priority (confirmed broken at real games)

**1. Period clock reset verification**
When period advances (1st Half → 2nd Half → OT), the clock should reset to half length and `clockStartedAt` should be reset to 0 (paused). Verify this flows correctly through the new wall clock system. Check: does the Watch reflect period change + clock reset simultaneously?

**2. Gimbal PID axis verification (30-second test)**
`setAngularVelocity(Vector3D(x: 0, y: panVelocity, z: 0))` — Y axis assumed to be yaw (pan). Needs field test. If gimbal tilts instead of pans, change to `Vector3D(x: panVelocity, y: 0, z: 0)`. One line change in `GimbalTrackingManager.swift` line ~242.

**3. Kp tuning after first game**
Current `Kp = 1.6`, `maxPanVelocity = 0.8` rad/s. Both are theoretical. After recording a game, evaluate: was the gimbal sluggish (raise Kp) or did it overshoot/oscillate (lower Kp)?

### Medium Priority

**4. The "Matrix" offline experimentation framework**
Run last game's recorded video through the exact Skynet pipeline offline. Measure tracking quality (center stability, gimbal command frequency, false positive rate). Sweep parameters (Kp, confidence threshold, deadband) to find optimal config. Needs at least one real game recording first.

**5. Watch end-game long press threshold**
Current: 0.5s minimum. Risk: accidental game end mid-game. Raise to 1.0s.
File: `WatchScoringView.swift`, `onLongPressGesture(minimumDuration: 0.5)` → `1.0`.

**6. Period advancement protection**
Period chip (e.g. "1st Half") taps advances period. Small target, right above score zones — accidental trigger risk. Consider requiring confirmation or a longer press.

### Deferred / Won't Do

- AI Lab rewrite — not used during games, over-engineering
- Opponent jersey color persistence — warmup handles it
- Multi-point scoring on Watch — user prefers +1, muscle memory
- Watch Ultra 2 deployment — Series 8 is the scoring remote

---

## Architecture Quick Reference

```
iPhone Camera (4K)
    ↓ 15fps AI frames (640x360)
SkynetProcessor (Swift actor, background)
    ├─ YOLOv8n CoreML → person bounding boxes (fallback: VNDetectHumanRectanglesRequest)
    ├─ VNDetectHumanBodyPoseRequest → ankle positions, sitting filter
    ├─ BallDetector → fast-break early warning only (not primary tracking)
    ├─ DeepTracker (Kalman + Hungarian + OC-SORT) → track management
    └─ PersonClassifier → action center (player cluster PRIMARY)
           ↓
    SkynetResult → @MainActor applySkynetResult()
           ↓
    GimbalTrackingManager.updateTrackingROI()
           → setAngularVelocity PID (fallback: setRegionOfInterest pan-only strip)
           → DockKit → Insta360 Flow Pro 2 physical pan
```

**Watch sync (fixed):**
```
Phone → Watch: sendFullSnapshot() → updateApplicationContext (complete state, no merge)
Watch → Phone: transferUserInfo (guaranteed delivery, phone can be backgrounded)
Clock: wall clock timestamps (Date()), zero drift
```

**Devices:**
- iPhone: Narayan's iPhone 16 Pro Max — ios-deploy UDID `00008140-000078682693001C`
- Watch: Apple Watch Series 8 (TinyPod, remote scoring) — devicectl `1F6B54B5-D413-548A-A90C-351867F22E2C`
- Watch Ultra 2 — daily wear only, do NOT deploy to it

**Repos:**
- GitHub: https://github.com/narayan-iyengar/SahilStatsLite
- Work Mac clone: `~/personal/SahilStatsLite/`
- Personal Mac Xcode: `/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite/`
- SSH: `narayan@Narayans-MacBook-Pro.local` (`.local` resolves, `.iyengarhome` does not from PAN network)

**Key files:**
- `AutoZoomManager.swift` — SkynetProcessor actor, Kp/deadband tuning constants
- `GimbalTrackingManager.swift` — PID constants (Kp=1.6, maxPanVelocity=0.8, axis=Y)
- `WatchConnectivityService.swift` — phone-side sync, sendFullSnapshot
- `WatchConnectivityClient.swift` — Watch-side sync, transferUserInfo, wall clock
- `UltraMinimalRecordingView.swift` — clockStartedAt tracking, all sync call sites
- `deploy.sh` — `~/SahilStats/deploy.sh` on personal Mac
- `sahil_agent.py` — autonomous dev agent
