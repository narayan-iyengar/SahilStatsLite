# SahilStatsLite — Handoff Notes (2026-03-22)

This document captures the exact changes made in the latest session, the reasoning behind
each decision, and what to work on next. Written by Claude for continuity with Gemini or
any future AI session.

---

## What Was Changed Today

### 1. `SahilStatsLite/Services/RecordingManager.swift`

**One line change.** AI frame processing rate increased from 5fps to 15fps.

```swift
// BEFORE:
private let aiFrameInterval: CFAbsoluteTime = 0.2  // 5 FPS for AI processing

// AFTER:
private let aiFrameInterval: CFAbsoluteTime = 0.067  // 15 FPS for AI processing
```

**Why:** At 5fps, fast breaks look like teleportation to Skynet. Players move 10+ feet
between frames. 15fps gives Skynet enough temporal resolution to track motion smoothly.
The iPhone 16 Pro Max Neural Engine handles this easily. XBotGo/Falcon run at 30fps.
15fps is a safe intermediate step.

---

### 2. `SahilStatsLite/Services/GimbalTrackingManager.swift`

**Major architectural change.** Three AIs were fighting over gimbal motor control:
1. Insta360 Flow Pro 2's own internal tracking AI (hardware)
2. DockKit system tracking (`setSystemTrackingEnabled(true)`) — Apple's AI
3. Skynet (AutoZoomManager) — our AI

Result at games: gimbal jerks in multiple directions simultaneously.

**The fix:** Disable DockKit's system tracking AI entirely. Use the Insta360 as a pure
2-axis physical stabilizer. Skynet is the sole tracking brain. It steers the gimbal by
sending its computed `actionZoneCenter` to DockKit as a region of interest.

**Key behavior:**
- The moment the gimbal connects via DockKit, `setSystemTrackingEnabled(false)` is called
  immediately (not waiting for `startTracking()`). This eliminates the window where
  Insta360's own AI could kick in.
- `updateTrackingROI(center:)` is the new method. AutoZoomManager calls it after its
  deadband check. It sends a 30% ROI box centered on Skynet's action center to DockKit.
  DockKit physically pans/tilts the gimbal toward that region.
- Double deadband: Skynet's 5% deadband + Gimbal's 8% deadband. Gimbal only moves for
  meaningful shifts, not every micro-detection.
- `roiUpdateTask` cancels the previous async ROI call before sending a new one, preventing
  queued stale commands.

**Note on Insta360 app:** The user should set the Insta360 Flow app to **Lock mode** on
the gimbal (not Follow mode). DockKit overrides Insta360's tracking when connected, but
Lock mode in the Insta360 app ensures there's no conflict at the firmware level. Lock mode
= gyro stabilization only, no Insta360 tracking AI.

**Note on DockKit ROI + system tracking disabled:** When `setSystemTrackingEnabled(false)`,
`setRegionOfInterest` tells DockKit where to physically point the gimbal without running
Apple's subject-detection AI. The gimbal moves toward the ROI center mechanically.

Full diff of `GimbalTrackingManager.swift`:

```
REMOVED:
- courtRegion hardcoded CGRect
- setSystemTrackingEnabled(true) in startTracking()
- setRegionOfInterest(courtRegion) (static court region)
- trackingTask monitoring trackingStates (no longer needed)
- setSystemTrackingEnabled(false) in stopTracking() (now handled on connect)

ADDED:
- roiUpdateTask: Task<Void, Never>?
- roiDeadband: CGFloat = 0.08
- lastROICenter: CGPoint
- roiSize: CGFloat = 0.30
- setSystemTrackingEnabled(false) called immediately on gimbal connect
- updateTrackingROI(center: CGPoint) — public method for Skynet to call
  - Guards: gimbalMode == .track, isDockKitAvailable, isTrackingActive
  - Checks movement > roiDeadband before updating
  - Cancels previous roiUpdateTask before issuing new one
  - Builds 30% CGRect around center, calls accessory.setRegionOfInterest(roi)
```

---

### 3. `SahilStatsLite/Services/AutoZoomManager.swift`

**One line added.** After Skynet's deadband check passes and `actionZoneCenter` is updated,
steer the physical gimbal:

```swift
// ADDED inside processFrameWithSkynet(), after the deadband check:
if distance > centerDeadband {
    actionZoneCenter = rawActionCenter
    // Steer physical gimbal: Skynet tells DockKit where the action is.
    GimbalTrackingManager.shared.updateTrackingROI(center: actionZoneCenter)
}
```

---

### 4. `claude.md`

Synced to match `Gemini.md` (Feb 21 status). claude.md was 6 weeks behind. Now identical
in content, just with "Claude" as developer instead of "Gemini".

---

## Current Architecture (Tracking Stack)

```
iPhone Camera (4K)
       ↓
RecordingManager — 15fps AI frames → AutoZoomManager (Skynet)
                                            ↓
                              PersonClassifier (VNDetectHumanRectanglesRequest)
                              + BallDetector (color threshold)
                              + DeepTracker (SORT-style)
                                            ↓
                              actionZoneCenter computed
                                            ↓
                    ┌─────────────────────────────────────┐
                    ↓                                     ↓
           Digital zoom via                   GimbalTrackingManager
        RecordingManager.setZoom()         updateTrackingROI(center:)
                                                          ↓
                                          DockKit setRegionOfInterest()
                                                          ↓
                                          Insta360 Flow Pro 2 physical pan/tilt
```

Skynet is the only brain. Digital zoom + physical gimbal both follow the same
`actionZoneCenter`.

---

## Known Issues / What To Work On Next

### High Priority

**1. Tracking still runs on Vision's generic `VNDetectHumanRectanglesRequest`**
This is not sports-optimized. XBotGo/Falcon use YOLO or similar trained on sports footage.
The next meaningful tracking upgrade is replacing `VNDetectHumanRectanglesRequest` in
`PersonClassifier.swift` with a CoreML YOLO model (YOLOv8n works well, ~4MB, 30fps+ on
iPhone 16 Pro Max). Convert with `coremltools` from Python. This would dramatically improve
kid/adult separation accuracy over the current height-heuristic approach.

**2. PID gimbal control instead of ROI hints**
`setRegionOfInterest` tells DockKit "look in this area" but the response is not tight.
A proper PID controller computing angular error from `actionZoneCenter` deviation from
(0.5, 0.5) and sending angular velocity commands would be significantly more responsive.
This requires finding the correct DockKit API for angular velocity commands — check DockKit
framework headers in Xcode for `setAngularVelocity` or similar on `DockAccessory`.

**3. 15fps may need tuning**
Start with 15fps and test thermal performance. If the phone gets hot during a full game,
back off to 10fps (`aiFrameInterval: 0.1`). The sweet spot between responsiveness and
thermal budget needs field testing.

### Medium Priority

**4. Watch sync still debugging**
Per Gemini.md, Watch fails to receive calendar context or active game state despite
connectivity. Suspect WCSession daemon hang or OS version mismatch. The `updateApplicationContext`
approach was implemented but the issue persists.

**5. Tripod height**
Not a code issue. XBotGo/Soloshot are always mounted 8-12 feet high. From floor level,
players occlude each other constantly and Skynet gets confused bounding boxes. A taller
tripod dramatically improves detection quality before any code change.

---

## What Has NOT Changed (Still Working)

- 4K recording with real-time overlay (RecordingManager + OverlayRenderer)
- Skynet v5.0: Visual Re-ID, ball tracking fusion, foreground filter, court calibration
- Firebase sync, YouTube upload, Watch companion (scoring, clock, remote calibration)
- Edit game, ghost cleanup, discard workflow
- Court Priority Audio (back mic)
- Watch Always On (WKExtendedRuntimeSession)

---

## Repo

https://github.com/narayan-iyengar/SahilStatsLite

Local on work Mac: `~/personal/SahilStatsLite/`
Changes committed locally but NOT pushed (work laptop firewall blocks git push to GitHub).
To push: copy the 4 changed files to a personal device and push from there, or use
GitHub web editor to apply the diffs manually.
