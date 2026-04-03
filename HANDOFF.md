# SahilStatsLite — Handoff Notes (2026-04-03)

This document captures exact changes made in the latest session, reasoning behind each decision, and what to work on next.

---

## Session Summary

Major session. Fixed all critical tracking bugs, upgraded the detection pipeline from Apple Vision generic rectangles to YOLOv8n CoreML, and established a reliable push/pull workflow from PAN work Mac.

---

## Infrastructure Changes

**Git push now works directly from PAN work Mac.**
PAN's firewall does not block HTTPS to github.com. Direct `git push origin main` works. The SCP-to-personal-Mac workflow (`push_to_github.sh`, `dev_agent.py`) is no longer needed.

Full loop: edit on work Mac → commit → `git push` → `ssh narayan@Narayans-MacBook-Pro.local "cd /Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite && git pull origin main"`.

SSH hostname: `narayan@Narayans-MacBook-Pro.local` (`.local` resolves via mDNS; `.iyengarhome` does not resolve from PAN network).

---

## What Was Changed

### 1. Pan-only Gimbal (`GimbalTrackingManager.swift`)

**Problem:** The gimbal was fighting itself. `setRegionOfInterest` was sending a square ROI box, so DockKit tried to center both X and Y. On a basketball court, players stay at roughly the same height — the camera only needs to pan horizontally. Unnecessary tilt corrections were causing jitter.

**Fix:**
- ROI changed from a square box (`0.30 x 0.30`) to a tall narrow vertical strip (`0.25 wide x 0.90 tall`). DockKit sees the subject spanning full height, so it only pans.
- Deadband changed from 8% Euclidean (X+Y) to 2.5% X-only. Gimbal responds 3x sooner to horizontal action.

### 2. AI Frame Rate Fixed (`AutoZoomManager.swift`)

**Problem:** `processInterval = 0.25` meant Vision ran at 4fps despite RecordingManager delivering frames at 15fps. The 15fps change in RecordingManager from the previous session was having zero effect.

**Fix:** `processInterval` changed to `0.067` (15fps). If thermals are an issue during a full game, raise to `0.1` (10fps).

### 3. Vision Off Main Thread (`AutoZoomManager.swift`)

**Problem:** `processFrameWithSkynet` was dispatched via `Task { @MainActor }`. `VNDetectHumanRectanglesRequest` takes 30-100ms per frame. Running this on the main thread at 15fps was blocking the UI — score buttons, clock display, everything was freezing for ~50ms every 67ms.

**Fix:** Added `skynetQueue = DispatchQueue(label: "com.sahilstats.skynet", qos: .userInitiated)`. Vision detection and Kalman tracking now run entirely on `skynetQueue`. Results are returned as a `SkynetResult` struct and applied on `@MainActor` via `applySkynetResult()` — only `@Published` property writes and `GimbalTrackingManager` calls happen on the main thread.

Added `bgActionCenter: CGPoint` as a `nonisolated(unsafe)` shadow of `actionZoneCenter` — readable from `skynetQueue` without crossing the actor boundary.

### 4. CIContext Pooled (`PersonClassifier.swift`)

**Problem:** `classifyPeople(in: CVPixelBuffer)` was calling `CIContext()` inside the function body — creating a new GPU context 15 times per second. This was causing GPU resource churn and was a primary cause of thermal throttling.

**Fix:** `private let ciContext = CIContext(options: [.useSoftwareRenderer: false])` is now a stored property on `PersonClassifier`, created once.

### 5. Age Classifier Removed (`PersonClassifier.swift`)

**Problem:** The height-based kid/adult classifier was unreliable. A kid close to the camera looks the same height as an adult far away. The baseline (25th percentile of all detected heights) drifted toward adult height whenever parents walked through during warmup, causing real players to be misclassified.

**Fix:** Removed entirely. Classification is now: foreground filter (>50% frame height = ignore) + court bounds + ref stripe detection. Everyone inside court bounds who is standing = player. DeepTracker's appearance matching filters non-team members over time.

### 6. Body Pose Detection Added (`PersonClassifier.swift`)

**Problem:** Court contact was determined by `box.minY` (bounding box bottom). This is the lowest visible pixel, which could be a chair, a bag, or the bleacher row below — not the actual floor.

**Fix:** `VNDetectHumanBodyPoseRequest` now runs alongside the main detection in the same `VNImageRequestHandler` call (Vision batches them, near-zero extra cost). Each detection is matched to its nearest pose observation using torso joint positions (neck, shoulders, hips).

- **Ankle-based court contact:** Actual `leftAnkle`/`rightAnkle` joint positions used instead of `box.minY`.
- **Sitting detection:** Checks `(knee.y - ankle.y) > 0.04` in Vision space (y=0 = floor). A seated person's knee is at roughly hip height, not significantly above the ankle. Seated spectators in front-row bleachers are now filtered even if their bounding box falls within `courtBounds`.

### 7. Team Jersey Color Learning (`PersonClassifier.swift`)

**Problem:** No way to distinguish players from random people who briefly enter court bounds (parents walking across, coaches stepping on court).

**Fix:** During warmup, every on-court player detection's color histogram is accumulated (up to 600 samples). At game start (`resetTrackingState()` → `finalizeTeamColors()`), histograms are clustered into 2 team color profiles via dominant-hue bucketing. From that point, action center weighting multiplies each player's weight by 0.5x–1.5x based on jersey color match. Random passers-by without team jerseys get deprioritized automatically.

### 8. ObservationMomentum Dt Fixed (`DeepTracker.swift`)

**Problem:** `observationMomentum` used hardcoded `1/30` as the frame interval (assuming 30fps). After the AI frame rate fix, actual interval is `1/15`. Velocity was being computed as 2x too high, causing OC-SORT occlusion recovery to overshoot.

**Fix:** `update(detection:dt:)` now takes actual `dt` and uses it for momentum calculation. `observationCentricBox` uses `lastDt` (stored on `TrackedObject`) instead of hardcoded `1/30`.

### 9. YOLOv8n CoreML Detector (`YOLODetector.swift`, `PersonClassifier.swift`)

**Problem:** `VNDetectHumanRectanglesRequest` is Apple's generic person detector, not optimized for sports. Struggles with overlapping players, partial occlusion, and has poorly calibrated confidence scores.

**Fix:** New `YOLODetector.swift` — sports-optimized person detection via CoreML:
- Input: 640x360 CVPixelBuffer (our AI frame size)
- Letterboxes 640x360 → 640x640 with 140px gray pads top/bottom (YOLO standard: 114,114,114)
- Runs `MLModel.prediction()` directly (no VNCoreMLRequest overhead)
- Decodes `[1, 84, 8400]` output tensor (supports transposed `[1, 8400, 84]` too)
  - Features 0-3: cx, cy, w, h (normalized in 640x640 space, y=0 top)
  - Feature 4: person class score (COCO class 0 = person)
- Applies NMS (iouThreshold = 0.45, confidenceThreshold = 0.35)
- Reverses letterbox transform: `cy_orig = cy_640 * (640/360) - (140/360)`
- Flips Y for Vision coords: `visionCy = 1.0 - cy_top_orig`
- Reuses `CVPixelBufferPool` for letterbox buffers — no per-frame allocation

`PersonClassifier` uses YOLO when `yoloDetector.isAvailable` (model in bundle); falls back to `VNDetectHumanRectanglesRequest` otherwise. Body pose runs in both paths.

**Model file:** `yolov8n.mlpackage` (6.2MB) is in the Xcode project at `SahilStatsLite/SahilStatsLite/yolov8n.mlpackage`. Added to pbxproj as a file reference only — do NOT add to any explicit build phase. Xcode's implicit CoreML rule handles compilation and bundling. Output tensor name: `var_911`.

**To regenerate model on personal Mac:**
```bash
pip3 install ultralytics coremltools
python3 -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='coreml', imgsz=640, nms=False)"
```

---

## Current Architecture

```
iPhone Camera (4K)
    ↓ 15fps AI frames (640x360)
AutoZoomManager.processFrame() [nonisolated]
    ↓ skynetQueue (background)
        YOLOv8n CoreML → person bounding boxes
        + VNDetectHumanBodyPoseRequest → ankle positions, sitting check
        + BallDetector → orange ball position
        + DeepTracker (Kalman + Hungarian + OC-SORT) → tracks
        + Team color scoring → weight multiplier
        → SkynetResult { newActionCenter, newTargetZoom, ... }
    ↓ @MainActor applySkynetResult()
        → GimbalTrackingManager.updateTrackingROI() [pan-only strip]
        → DockKit physical pan
        → 60fps smooth zoom loop → RecordingManager.setZoom()
```

---

## Known Issues / What to Work on Next

### High Priority
1. **Watch sync still flaky** — Watch fails to receive calendar context or active game state. `updateApplicationContext` approach implemented but issue persists. Suspect WCSession daemon hang or OS version mismatch.
2. **Thermal budget** — Field test required. If phone gets hot during a full game, raise `processInterval` from `0.067` to `0.1` in `AutoZoomManager.swift`.

### Medium Priority
3. **PID gimbal control** — `setRegionOfInterest` is a hint, not a precise command. A PID controller computing angular error from `actionZoneCenter` deviation from (0.5, 0.5) would be more responsive. Check DockKit headers for angular velocity API.
4. **HEVC recording** — Currently H.264 at 10 Mbps for 4K. Should be HEVC at 15 Mbps: better quality, smaller files. Change `AVVideoCodecType.h264` → `.hevc` and `AVVideoAverageBitRateKey` → `15_000_000` in `RecordingManager.swift`.
5. **Tripod height** — Not a code issue. Camera should be 8-12 feet high for better detection angles.

---

## Repo

https://github.com/narayan-iyengar/SahilStatsLite

Work Mac clone: `~/personal/SahilStatsLite/`
Personal Mac Xcode project: `/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite/`
