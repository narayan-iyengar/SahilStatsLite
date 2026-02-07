# Sahil Stats - Project Context

> **UPDATED (2026-02-05):** Warmup calibration! Camera + Skynet AI starts immediately when you enter recording view (landscape). Video file recording only begins when you tap the game clock. Warmup = free AI calibration for court bounds and player sizes. Skynet v4.1: Momentum Attention + Timeout Detection + Golden Smoothing.

---

## Team Roles

**Narayan (Product Manager / End User)**
- Father of Sahil, a 3rd grader on AAU basketball teams
- Owns Insta360 Flow Pro 2 gimbal and DJI Osmo Mobile 7P
- Wants to record games and track stats for Sahil
- Decision maker on features and UX

**Claude (Software Developer / Architect / Designer / ML Researcher)**
- Kick-butt iOS app developer with deep knowledge of Swift and iOS frameworks
- Works for Apple (in spirit) - knows AVFoundation, DockKit, Vision, Core ML, Camera Control like the back of hand
- World-class developer, UX designer, user researcher, and all-around genius
- Channels Jony Ive for interface design: simplicity, clarity, generous touch targets
- **Channels top ML/Vision researchers**: Fei-Fei Li (ImageNet, human-centric vision), Kaiming He (ResNet, Mask R-CNN), Ross Girshick (R-CNN family, object detection), Yann LeCun (ConvNets), Andrej Karpathy (Tesla Autopilot, practical CV)
- Deep knowledge of: object detection (YOLO, SSD, Faster R-CNN), pose estimation (OpenPose, MediaPipe), tracking (SORT, DeepSORT, ByteTrack), action recognition, attention mechanisms
- Understands tradeoffs: accuracy vs latency, on-device vs cloud, real-time vs batch
- Responsible for technical implementation
- Makes architectural decisions
- Writes clean, maintainable code
- Proposes solutions, Narayan approves

**Permissions:**
- Claude has permission to make code changes without asking
- Claude has permission to run shell commands (git, build, etc.) without asking
- Claude should commit and push changes when completing features
- Claude should update CLAUDE.md when significant changes are made

---

## Project Vision

A hybrid of **XBotGO** (auto-tracking) + **ScoreCam** (video with score overlay) for personal use.

### Core Features (MVP)
1. **Auto-tracking** via DockKit (Insta360 Flow Pro 2)
2. **Live score overlay** burned into video
3. **Running game clock** with quarter support
4. **Floating Ubiquiti-style controls** for score input
5. **Calendar integration** for game scheduling
6. **Firebase backend** for data persistence

### Future Features (Post-MVP)
- Post-game stat tagging for Sahil's individual plays
- Highlight reel generation
- Season stats and trends

### Apple Watch Companion (WORKING)
- Watch app for remote scoring from sidelines
- **Tap** score zones to add +1 point
- **Swipe down** on score to subtract -1 (fix mistakes)
- **Start game** from Watch when phone not accessible
- Real-time two-way sync (phone ↔ watch)
- End game directly from Watch
- See "Apple Watch App" section below for technical details

---

## GitHub Repository

**Public repo**: https://github.com/narayan-iyengar/SahilStatsLite

---

## Technical Decisions

### Keep from Existing App
- `FirebaseService.swift` - Backend integration
- `AuthService.swift` - Authentication
- `GameCalendarManager.swift` - Calendar integration
- `GimbalTrackingManager.swift` - DockKit auto-tracking

### Build Fresh
- New SwiftUI views (simpler, cleaner)
- Simplified recording manager
- New floating UI controls
- Broadcast-style scoreboard overlay (ScoreCam-inspired)

### Architecture
- Target: ~15 files, ~3,000 lines
- SwiftUI + SwiftData (or Firebase only)
- Single device focus (no multi-device sync)
- iOS 17+ minimum (for DockKit iOS 18+)

---

## Hardware
- **Phone**: iPhone 16 Pro Max (A18 Pro, 48MP main camera, 5x telephoto, 0.5x ultra-wide, Camera Control button, USB-C)
- **Gimbal**: Insta360 Flow Pro 2 (DockKit compatible)
- **Backup gimbal**: DJI Osmo Mobile 7P (not DockKit, future consideration)
- **Watch (primary)**: Apple Watch Ultra 2 (49mm) in PodX Adventure Classic case
- **Watch (backup)**: Apple Watch Series 8 (45mm) in TinyPod Standard case

---

## UX Design Philosophy (Jony Ive Style)

**Core Principle:** "You're a parent watching your kid's game, not babysitting an app."

### Four-Phase Workflow
1. **Setup**: Configure in Settings (Skynet on/off, gimbal mode, team names)
2. **Warmup Calibration**: Enter recording view in landscape. Camera preview + Skynet AI start learning immediately (court bounds, player sizes, ref detection). No video file created yet. This is free calibration time.
3. **Game Recording**: Tap game clock to start. Video file recording begins. Skynet resets tracking momentum (keeps learned court bounds from warmup). Phone is a "dumb camera" from here.
4. **After game**: Review, share, celebrate. Video contains only game footage, no warmup.

### Settings vs Stats Separation
- **Settings screen**: Skynet AI toggle, Gimbal mode, YouTube upload, Team names
- **Stats overlay**: Only shooting stats, other stats, and game controls (period, OT, end)
- No camera controls visible during recording - all pre-configured

### Key Decisions
- **Skynet defaults to ON** - AI tracking is the main feature, shouldn't need to enable it
- **No zoom buttons during game** - Skynet handles zoom automatically
- **No gimbal mode switching during game** - set once before game
- **Stats overlay is for stats** - not a control panel for camera settings

### Touch Philosophy
- Generous touch targets for sideline use (cold fingers, gloves, rushed taps)
- Tap to add points, long-press to subtract (fix mistakes)
- Swipe gestures for navigation, not precision actions

---

## Current Status
- Old app: archived to `SahilStats-archive.zip` (100 files, 40k lines - too complex)
- New app: ~40 files, ~5,000 lines - in `/SahilStats/SahilStatsLite/SahilStatsLite/` (git repo root)
- Phase 1: Recording + auto-tracking + score overlay (IN PROGRESS)
- Phase 2: Stats tagging
- Phase 3: Highlights and sharing

### Phase 1 Progress (Updated 2026-02-05)
- [x] Basic project structure
- [x] Camera preview working
- [x] Floating Ubiquiti-style controls with score buttons (+1, +2, +3)
- [x] Running game clock with play/pause
- [x] Save to Photos functionality
- [x] ScoreTimelineTracker - records score snapshots with timestamps
- [x] OverlayCompositor - burns score overlay into video post-recording
- [x] Integration complete: RecordingView -> ScoreTimelineTracker -> OverlayCompositor -> GameSummaryView
- [x] Fixed timing issue: wait for video file to finish writing before processing
- [x] **4K video recording support** (now default, `.hd4K3840x2160`)
- [x] Broadcast-style overlay design (blue home, red/orange away, dark score boxes)
- [x] Landscape rotation handling for video composition
- [x] iOS 26 UIScreen.main deprecation fix
- [x] **Skynet v4.1**: Momentum Attention (velocity-weighted tracking), Timeout Detection (bench rush → zoom out), Golden Smoothing (broadcast-quality motion)
- [x] **Warmup Calibration**: Camera + Skynet start on landscape entry, video recording starts on first clock tap. Warmup = free AI learning period.
- [ ] Physical device testing with gimbal

### Bug Fixes (Comprehensive List)

**Video Recording Issues:**
- **Video file not ready error**: Added `stopRecordingAndWait()` async method that waits for AVCaptureFileOutputRecordingDelegate callback before navigating to summary. Shows "Finishing recording..." UI while waiting.
- **Recording never started**: Fixed race condition where `requestPermissionsAndSetup()` returned before session was ready. Now uses `withCheckedContinuation` to properly wait for `session.startRunning()` to complete before returning.
- **Double recording start**: Added guards to prevent `startRecording()` from being called twice, which caused "Cannot Record" AVFoundation error.
- **"Cannot Record" error (AVFoundationErrorDomain -11805)**: Added safeguards in `startRecording()`:
  - Check if session is running, start it if not
  - Verify video connection is active before recording
  - Wait up to 0.5s for connection to become active
  - Return meaningful error message if connection fails
  - Reset `isRecording = false` on error so user can retry

**Permission Issues:**
- **Missing permissions**: Created Info.plist with required privacy descriptions (Camera, Microphone, Photo Library, Calendar). Without these, iOS won't show permission dialogs.
- **Simulator detection**: Added `#if targetEnvironment(simulator)` checks to show helpful "Simulator Mode" message instead of black screen.

**Video Orientation Issues (FINAL FIX - ScoreCam Pattern):**
- **Problem**: Video was being recorded in device native orientation, then compositor tried to apply transforms to correct it - this was overly complex and error-prone.
- **Solution**: Follow ScoreCam pattern - set `videoRotationAngle` on the recording connection BEFORE calling `startRecording()`. This records the video in the correct display orientation from the start.
- **RecordingManager.swift**: Now sets rotation angle based on device orientation before recording:
  - Portrait: 90°
  - Portrait upside down: 270°
  - Landscape left (home button on left): 0°
  - Landscape right (home button on right): 180°
- **OverlayCompositor.swift**: Now uses identity transform and natural size directly - no rotation needed since video is already correct.

**Video Overlay Issues:**
- **Overlay colors missing**: Redesigned to broadcast-style with colored team boxes (blue home, red/orange away) and dark score/clock boxes.
- **Team names truncated**: Added proper width constraints and truncation mode for team name labels.
- **Initial state not showing (0-0, Q1, clock)**: CATextLayers in AVVideoComposition need explicit animation timing. Added `addStaticAnimation()` helper that sets `beginTime = AVCoreAnimationBeginTimeAtZero` and `fillMode = .both` to ensure ALL layers (backgrounds, labels, scores) render from frame 0.
- **UIScreen.main deprecation (iOS 26)**: Replaced all `UIScreen.main.scale` references with fixed `3.0` value for Retina 3x displays.

### Important: Physical Device Required
Camera recording requires a **physical iPhone**. The iOS Simulator doesn't have camera access:
- On simulator: Shows "Simulator Mode" message with instructions
- On device: Shows camera preview and records video

To test properly:
1. Connect iPhone to Mac
2. Select your iPhone as the run destination in Xcode
3. Build and run (Cmd+R)

### Required Info.plist Keys
- `NSCameraUsageDescription` - Camera access for recording
- `NSMicrophoneUsageDescription` - Microphone for game audio
- `NSPhotoLibraryAddUsageDescription` - Save videos to Photos
- `NSCalendarsUsageDescription` - Read calendar for game schedule

---

## Technical Details

### Video Recording (RecordingManager.swift)
- Uses AVCaptureSession with AVCaptureMovieFileOutput
- Supports 4K (3840x2160), 1080p, 720p presets (auto-selects best available)
- Video stabilization enabled when supported
- Async `stopRecordingAndWait()` ensures file is fully written before processing

### Video Orientation Handling (ScoreCam Pattern)
**Key insight**: Record the video in the correct orientation from the start, then the compositor doesn't need to transform.

**RecordingManager.swift** sets `videoRotationAngle` on the recording connection BEFORE calling `startRecording()`:
```swift
let deviceOrientation = UIDevice.current.orientation
let rotationAngle: CGFloat
switch deviceOrientation {
case .portrait: rotationAngle = 90
case .portraitUpsideDown: rotationAngle = 270
case .landscapeLeft: rotationAngle = 0    // Home button on left
case .landscapeRight: rotationAngle = 180  // Home button on right
default: rotationAngle = 90  // Default to portrait
}
if connection.isVideoRotationAngleSupported(rotationAngle) {
    connection.videoRotationAngle = rotationAngle
}
```

**OverlayCompositor.swift** uses identity transform and natural size directly:
- `calculateRenderSize()` returns natural size without transformation
- `createVideoComposition()` uses `.identity` transform on the layer instruction
- No need for rotation math - video is already oriented correctly

**CALayer Animation Timing for AVFoundation:**
Static CATextLayers need explicit animation timing to render from frame 0:
```swift
func addStaticAnimation(to layer: CALayer, duration: TimeInterval) {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 1.0
    animation.toValue = 1.0
    animation.duration = duration
    animation.beginTime = AVCoreAnimationBeginTimeAtZero  // Critical!
    animation.fillMode = .both
    layer.add(animation, forKey: "staticOpacity")
}
```
Without this, static layers may not appear until partway through the video.

### Score Overlay Approach
**Post-processing** (like ScoreCam):
1. Record raw video + track score/clock in `ScoreTimelineTracker`
2. When game ends, run `OverlayCompositor` to burn overlay into video
3. Uses `AVVideoComposition` with `CALayer` for overlay
4. Animated score transitions using `CAKeyframeAnimation`
5. More reliable than real-time overlay burning

### Overlay Design (Broadcast-style)
```
┌─────────┬────┬─────┬────┬─────────┐
│  HOME   │ 0  │ Q1  │ 0  │  AWAY   │
│  (blue) │    │6:00 │    │ (orange)│
└─────────┴────┴─────┴────┴─────────┘
```
- Home team: Blue background (#007AFF)
- Away team: Orange/red background (#FF6B35)
- Score boxes: Dark background (#1C1C1E)
- Center: Quarter + countdown clock

---

## Project Structure (SahilStatsLite)

**Git repo root**: `/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite/`

All files have documentation headers (PURPOSE, KEY TYPES, DEPENDS ON) for quick context.

```
SahilStatsLite/SahilStatsLite/              ← Git repo root
├── claude.md                                # Project context for Claude
├── Gemini.md                                # Project context for Gemini
├── SahilStatsLite/                          ← iOS app source
│   ├── SahilStatsLiteApp.swift              # App entry point, AppState, AppDelegate, screen routing
│   ├── Components/
│   │   └── MissingComponents.swift          # Stub components for compilation
│   ├── Models/
│   │   ├── Game.swift                       # Game, PlayerStats, ScoreEvent, GameResult models
│   │   └── FirebaseGame.swift               # Codable Firebase data model for cloud sync
│   ├── Views/
│   │   ├── HomeView.swift                   # Home screen: hero card, game log, career stats, settings
│   │   ├── GameSetupView.swift              # Pre-game setup: opponent, team, half length, video toggle
│   │   ├── UltraMinimalRecordingView.swift  # Main recording UI: full-screen tap zones, scoreboard, warmup
│   │   ├── GameSummaryView.swift            # Post-game summary: scores, shooting %, video save
│   │   ├── ManualGameEntryView.swift        # Manual stats-only entry (no video)
│   │   ├── AuthView.swift                   # Firebase sign-in + sync controls
│   │   ├── AILabView.swift                  # AI lab: test Skynet pipeline on recorded videos
│   │   └── SkynetTestView.swift             # Standalone Skynet test UI (pick video, run pipeline)
│   ├── Services/
│   │   ├── RecordingManager.swift           # AVFoundation 4K capture, frame callbacks for AI
│   │   ├── AutoZoomManager.swift            # Skynet v4.1 orchestrator (zoom, pan, timeout detection)
│   │   ├── PersonClassifier.swift           # Player/ref/adult classification, court bounds, heat map
│   │   ├── DeepTracker.swift                # SORT-style tracking, KalmanFilter2D, TrackedObject
│   │   ├── GimbalTrackingManager.swift      # DockKit gimbal pan/tilt/zoom integration
│   │   ├── GameCalendarManager.swift        # Calendar event parsing, team/opponent detection
│   │   ├── GamePersistenceManager.swift     # Local game storage (UserDefaults JSON)
│   │   ├── OverlayRenderer.swift            # Core Graphics scoreboard renderer (broadcast-style)
│   │   ├── WatchConnectivityService.swift   # iPhone-side WCSession (Watch ↔ Phone sync)
│   │   ├── YouTubeService.swift             # YouTube OAuth + resumable upload (~200 lines)
│   │   ├── AuthService.swift                # Firebase/Google Sign-In auth wrapper
│   │   ├── FirebaseService.swift            # Firestore CRUD for games
│   │   ├── BallDetector.swift               # Orange basketball detection via color thresholding
│   │   ├── CourtDetector.swift              # Court line detection (R&D, limited success)
│   │   ├── ActionProbabilityField.swift     # Predictive action field for camera focus
│   │   ├── GameStateDetector.swift          # Play/dead-ball/timeout state detection
│   │   ├── ExperimentalFilters.swift        # R&D tracking filters (sandbox)
│   │   ├── TestVideoProcessor.swift         # Offline video processing for SkynetTestView
│   │   └── VideoAnalysisPipeline.swift      # Full video analysis: detection → tracking → output
│   └── Resources/
│       └── Info.plist                       # Privacy descriptions (camera, mic, photos, calendar)
├── SahilStatsLite.xcodeproj/                # Xcode project
├── SahilStatsLiteWatch Watch App/           ← Apple Watch companion
│   ├── SahilStatsLiteWatchApp.swift         # Watch app entry point
│   ├── WatchContentView.swift               # Root nav: waiting screen or scoring TabView
│   ├── WatchScoringView.swift               # Tap-to-score, clock, period, end game
│   ├── WatchStatsView.swift                 # Shooting stats (MAKE/MISS) + other stats
│   ├── WatchGameConfirmationView.swift      # Pre-game confirmation from Watch
│   ├── WatchLayout.swift                    # Adaptive layout (compact/regular/ultra)
│   ├── WatchConnectivityClient.swift        # Watch-side WCSession handler
│   └── Assets.xcassets/                     # Watch app icons
└── SkynetTest/                              ← AI R&D tools (standalone)
    ├── SkynetVideoTest.swift                # CLI: broadcast-quality Skynet test on video files
    └── ailab.swift                           # CLI: person detection, heat map, zoom-in-post
```

### Data Flow for Score Overlay
1. **RecordingView** starts `ScoreTimelineTracker` when recording begins
2. Initial snapshot captured at timestamp 0 (score 0-0, Q1, full clock)
3. Score/clock changes update the tracker in real-time
4. When game ends, timeline snapshots are stored in `RecordingManager`
5. **GameSummaryView** runs `OverlayCompositor` to burn overlay into video
6. User can save/share the processed video with embedded scoreboard

---

## Dependencies Required
- Firebase (FirebaseCore, FirebaseAuth, FirebaseFirestore)
- DockKit (iOS 18+ for gimbal tracking)
- GoogleSignIn (for YouTube OAuth)

---

## Career Stats Feature

The Career Stats sheet (accessible from HomeView) tracks Sahil's progress over time.

**Stats tracked:**
- Points (PPG), Rebounds (RPG), Assists (APG)
- Defense (STL+BLK), Shooting (FG%), Win Rate

**Time period options:**
- **By Age** - Long-term yearly view (original)
- **By Month** - Monthly averages for seasonal trends
- **By Week** - Last 12 weeks for granular progress (default)

The weekly view is recommended since youth player progress over a year appears flat, but week-to-week shows meaningful variation.

---

## Known Issues / TODO
1. ~~**App icon**~~ - DONE (copied from SahilStats)
2. **Physical device testing** - Test full recording flow on iPhone with gimbal
3. **Gimbal tracking** - DockKit has limitations (see below)
4. **YouTube upload testing** - Test OAuth flow and actual upload to YouTube
5. ~~**Watch app requires paid account**~~ - RESOLVED
6. ~~**Auto expand/collapse floating bar**~~ - Not needed with Watch as primary input

### Gimbal Tracking Issues (2026-01-31)

**User Feedback:** Gimbal was tracking random things at game, not focused on action.

**Root Cause:** DockKit uses Apple's built-in person tracking which is general-purpose, not optimized for basketball. It may:
- Follow sideline movement (parents, other players)
- Lose track during fast action
- Not understand court boundaries

**Limitations:**
- Gimbal can only **physically pan/tilt** the phone
- Gimbal **cannot control digital zoom** - that's software-only
- DockKit's tracking algorithm is a black box

**Current Approach:**
- Added `setZoom()` for manual zoom control (pinch-to-zoom + buttons)
- Region of interest set to court area (0.05-0.95 horizontal, 0.15-0.90 vertical)
- Post-processing zoom (AI Lab) can salvage footage

**Future Options:**
1. **Disable DockKit tracking** - Just use gimbal for stabilization, not auto-pan
2. **Manual pan mode** - User controls pan, AI controls zoom
3. **Wait for better DockKit** - Apple may improve for sports use cases

**For now:** Use manual zoom controls on phone + Watch for score. Gimbal provides stabilization. AI post-processing handles zoom-in-post.

### Insta360 Deep Track & AI Tracker Research (2026-02-01)

**Insta360 Deep Track 4.0 (from their PDF):**
- Multi-scale correlation filter + Kalman filtering for tracking
- Person re-identification for occlusion recovery
- 0.3s re-acquisition time after losing subject
- PDF explicitly states "DockKit struggles with fast motion"
- Deep Track locked to Insta360 app ecosystem - no SDK/API access

**AI Tracker Accessory ($46):**
- Has its **own tiny camera** for independent tracking
- Connects via **USB-C** to gimbal mount (not Bluetooth)
- Physical **button** to activate tracking (press = "track largest subject")
- Also supports **gesture mode** (raise hand to activate)
- No SDK or API - pure hardware solution
- Does NOT provide zoom control (tracking only)

**AI Tracker Workflow:**
1. Set up phone on gimbal before game
2. Press AI Tracker button to lock onto Sahil
3. Walk to sidelines
4. Control recording from Watch
5. AI Tracker follows Sahil, gimbal pans to keep him centered

**Concerns:**
- Gesture mode unreliable (refs raise hands, parents wave, etc.)
- Button must be pressed physically - no remote activation
- No DockKit integration - can't control from our app

**Decision: Test DockKit First**
Before buying AI Tracker, test current DockKit + our app at a real game. If tracking quality is acceptable, no need for additional hardware. If DockKit fails, AI Tracker is the fallback ($46 one-time cost).

### Recent Changes (2025-01-17)

**AAU Halves Support:**
- Changed from quarters to halves for AAU basketball games
- GameSetupView: Select 18 or 20 minute halves
- RecordingView: Shows "H1", "H2" instead of "Q1"-"Q4"
- OverlayCompositor: Video overlay shows "H1", "H2"
- Game model: `halfLength` replaces `quarterLength`, `currentHalf` replaces `currentQuarter`

**Orientation Fix (WORKING):**
- RecordingManager: Sets recording rotation once at start using `UIDevice.current.orientation`, defaults to landscape (180°)
- CameraPreviewView: Updates preview rotation dynamically in `layoutSubviews()` and `updateUIView()`
- Preview uses device orientation, falls back to interface orientation when device is flat
- Preview rotates correctly when device rotates; recording stays locked to initial orientation

### Preview vs Recording Orientation - FIXED (2025-01-15)

**Symptom**: Live preview shows one orientation, final video shows different orientation.

**Root Cause**:
1. Preview layer (`AVCaptureVideoPreviewLayer`) auto-rotates based on interface orientation
2. Recording was using `UIDevice.current.orientation` which is unreliable (returns `.faceUp`, `.unknown` when device is flat)
3. **Critical bug**: `UIDeviceOrientation.landscapeLeft` (home LEFT) vs `UIInterfaceOrientation.landscapeLeft` (home RIGHT) are OPPOSITE!

**Fix Applied**: RecordingManager.swift now uses `UIWindowScene.interfaceOrientation`:
```swift
if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
    switch windowScene.interfaceOrientation {
    case .portrait: rotationAngle = 90
    case .portraitUpsideDown: rotationAngle = 270
    case .landscapeLeft: rotationAngle = 180  // home button on RIGHT
    case .landscapeRight: rotationAngle = 0   // home button on LEFT
    default: rotationAngle = 90
    }
}
```

Falls back to `UIDevice.current.orientation` if window scene unavailable. This should match the preview layer's auto-rotation.

---

## Apple Watch App

### Overview
The Watch app allows Narayan to control scoring remotely while the iPhone records on the gimbal. Two devices:
- **Ultra 2 (49mm) in PodX Adventure Classic**: Daily watch + game day scorer
- **Series 8 (45mm) in TinyPod Standard**: Dedicated scoring remote, backup

### Multi-Watch Setup
- Both watches paired to iPhone, **auto-switch OFF**
- Before game: manually switch to scoring watch in Watch app on iPhone
- After game: switch back to daily watch (or put Ultra 2 on wrist with auto-switch)
- Only one watch active at a time (Apple limitation)

### Hardware
| Watch | Case | Role |
|-------|------|------|
| Ultra 2 (49mm) | PodX Adventure Classic ($60) | Primary — daily wear + games |
| Series 8 (45mm) | TinyPod Standard ($80) | Backup — dedicated remote |

**Connectivity**: Bluetooth to iPhone (~30-100ft, covers a basketball court)

### Adaptive Layout (WatchLayout.swift)
The Watch UI auto-detects screen size via `WKInterfaceDevice.current().screenBounds`:
- **Ultra (49mm, 205x251pt)**: Full layout - separate live/period lines, swipe hint, clock helper text
- **Regular (45mm, 198x242pt)**: Compact layout - combined live+period header, larger score zones, no hints
- **Compact (40-41mm)**: Even tighter - smaller fonts, maximum score zone area

Key dimensions by size:
| Element | Compact (41mm) | Regular (45mm) | Ultra (49mm) |
|---------|---------------|----------------|--------------|
| Score font | 34pt | 38pt | 42pt |
| Clock font | 15pt | 17pt | 20pt |
| Header | Combined | Combined | Separate lines |
| Swipe hint | Hidden | Hidden | Shown |
| Clock helper | Hidden | Hidden | "running"/"hold to end" |

### Watch App Structure
```
SahilStatsLite/SahilStatsLite/SahilStatsLiteWatch Watch App/
├── SahilStatsLiteWatchApp.swift       # Watch app entry point
├── WatchContentView.swift             # Main navigation view
├── WatchScoringView.swift             # Adaptive scoring (tap +1, swipe -1)
├── WatchStatsView.swift               # Individual player stats
├── WatchGameConfirmationView.swift    # Pre-game confirmation screen
├── WatchLayout.swift                  # Auto-detect watch size, adaptive dimensions
├── WatchConnectivityClient.swift      # Watch-side WCSession handling
└── Assets.xcassets/                   # Watch app icons
```

### iOS App Watch Support
```
SahilStatsLite/SahilStatsLite/SahilStatsLite/Services/
└── WatchConnectivityService.swift  # iPhone-side WCSession handling
```

### Bundle Identifiers
- iOS app: `com.narayan.SahilStats`
- Watch app: `com.narayan.SahilStats.watchkitapp`
- Development Team: `TTV9QQRD5H`

### WatchConnectivity Architecture

**Data Flow:**
```
Watch (WatchConnectivityClient) <--WCSession--> iPhone (WatchConnectivityService)
         |                                              |
   User taps +2                                  Updates game score
         |                                              |
   sendMessage()  ─────────────────────────>   onScoreUpdate callback
                                                        |
                                               RecordingView updates UI
                                               ScoreTimelineTracker records
```

**Message Types (WatchMessage struct):**
- `scoreUpdate` - Score changed (team, points)
- `clockUpdate` - Clock state (remainingSeconds, isRunning)
- `periodUpdate` - Period changed (period, periodIndex)
- `statUpdate` - Individual stat (statType, value)
- `gameState` - Full game sync (all fields)
- `endGame` - Game ended

**Initialization (IMPORTANT):**
WatchConnectivityService must be initialized at app launch. Added to AppDelegate:
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
    FirebaseApp.configure()

    // Start WatchConnectivity session - MUST happen at launch
    _ = WatchConnectivityService.shared
    debugPrint("[AppDelegate] WatchConnectivity service initialized")

    return true
}
```

Without this, the WCSession never activates and Watch communication fails silently.

### Developer Account Notes

Watch app installation was successfully completed on 2026-01-21. Key steps that worked:
1. Clear Xcode device caches: `rm -rf ~/Library/Developer/Xcode/DerivedData`
2. Let Xcode download Watch debug symbols (can take 5-15 min on beta watchOS)
3. Keep Watch on charger and awake during symbol download
4. Build and run Watch app scheme to "Apple Watch via [iPhone name]"

### Watch Installation Methods

**Method 1: Via Xcode (requires Watch-Mac connection)**
1. Select "SahilStatsLiteWatch Watch App" scheme
2. Select "Apple Watch via [iPhone name]" as destination
3. Build and run (Cmd+R)

**Method 2: Via iPhone Watch app (recommended)**
1. Build iOS app to iPhone (embeds Watch app automatically)
2. On iPhone: Watch app → My Watch → scroll to "Available Apps"
3. Find "SahilStatsLiteWatch" → tap Install

### Watch-Mac Connection Issues (2025-01-20)

**Error:** "A networking error occurred. Device rejected connection request."
```
Domain: com.apple.dt.CoreDeviceError
Code: 4
Recovery Suggestion: Ensure the device is paired with this machine.
```

**Requirements for Watch debugging:**
1. iPhone must be connected to Mac (USB or trusted wirelessly)
2. Watch must be paired with iPhone
3. Developer Mode ON on Watch: Settings → Privacy & Security → Developer Mode
4. Watch must be unlocked and awake during install
5. All three devices on same network

**Connection path:** Watch → iPhone → Mac (Watch never connects directly to Mac)

**Troubleshooting:**
1. Xcode: Window → Devices and Simulators (Cmd+Shift+2)
2. Click iPhone → look for "Paired Watches" section
3. Watch should appear - if warning shown, try re-pairing
4. Keep Watch screen awake (tap it) during connection attempts

**Beta software note (iOS 26 / watchOS 26):**
- Beta versions may have connectivity bugs
- Method 2 (via iPhone Watch app) often more reliable than Xcode direct install

### Console.app Filtering for Watch Debugging

**Filter by process:**
```
process:SahilStatsLiteWatch
```

**Filter by subsystem (if using os_log):**
```
subsystem:com.narayan.SahilStats.watchkitapp
```

**To see Watch logs:**
1. Open Console.app
2. Select your Apple Watch in left sidebar (under Devices)
3. Enter filter in search bar
4. Enable: Action → Include Info Messages / Include Debug Messages

**Note:** Current code uses `debugPrint()` which may not show reliably in Console.app. For better filtering, switch to `os_log` / `Logger`:
```swift
import os
private let logger = Logger(subsystem: "com.narayan.SahilStats.watchkitapp", category: "connectivity")
logger.info("Message here")
```

### Current Watch App Status (2026-01-21) - WORKING

- [x] Watch app UI implemented (WatchScoringView, WatchContentView, WatchStatsView)
- [x] WatchConnectivity communication layer complete
- [x] iOS app WatchConnectivityService initialized at launch
- [x] Watch app installed on physical Apple Watch
- [x] Real-time clock sync (every 1 second)
- [x] End game from Watch saves directly (no phone confirmation needed)
- [x] Auto-save video to Photos when game ends
- [x] Return to home screen after game ends
- [ ] os_log logging not yet added (using debugPrint)

### Recent Fixes (2026-01-21)

1. **Clock sync improved**: Changed from every 5 seconds to every 1 second for real-time display
2. **End game from Watch**: Now calls `endGame()` directly instead of showing confirmation on phone
3. **End game notification**: iPhone sends `endGame` message back to Watch so it returns to waiting screen
4. **Auto-save to Photos**: Video automatically saved to Photos library when game ends
5. **Go to home screen**: After game ends, app returns directly to home screen (skips summary screen)
6. **Watch Stats redesign (Jony Ive-inspired)**: Complete UX overhaul with generous touch targets, swipe navigation, haptic feedback
7. **Career Stats time period selector**: Progress chart now supports By Age, By Month, or By Week views for more granular progress tracking
8. **YouTube upload (lean)**: ~200 lines, Keychain-based auth, immediate upload (no WiFi queue needed with 5G)
9. **OT functionality fixed**: Period tap cycles 1st Half → 2nd Half → OT, tapping in OT adds +1 min, only long-press clock ends game
10. **WYSIWYG overlays**: SwiftUI overlay redesigned to match NBA corner-style video overlay (bottom-right position)
11. **4-char team names**: Changed from 3 to 4 characters for better readability (e.g., "LAVA" vs "LAV")
12. **Blinking colon**: Clock colon blinks when RUNNING (both iOS and Watch) - indicates active clock
13. **Subtle tap zones**: Very faint orange/blue tints with center divider to indicate tap areas
14. **Removed WatchAppMockup.swift**: -622 lines of dead code (real Watch app is working)
15. **Watch period sync fix**: `sendPeriodUpdate` now includes `isRunning` so Watch shows correct clock state (orange/solid) in 2nd Half and OT
16. **iOS blinking colon fix**: Created dedicated `BlinkingColon` view struct with its own timer - fixes issue where colon wasn't blinking on iOS
17. **App icons**: Copied 1024.png from SahilStats to both iOS and Watch app
18. **Smart calendar filtering**: Only shows calendar events containing Sahil's team names (Uneqld, Lava, Elements). No complex calendar grid - just "Upcoming Games" list.
19. **Swipe to ignore**: Practices and non-game events can be swiped away (ignored). They won't reappear.
20. **Auto opponent detection**: "Uneqld vs Hawks" → Opponent detected as "Hawks" automatically.
21. **Hero Card calendar UI**: Next game shown prominently with large time, opponent name, location, and "Record Game" button. Tournament days show "LATER TODAY" section for multiple games.
22. **Smart team detection from calendar**: "Royal Kings - Bay Area Lava" → Detects "Lava" as your team, "Royal Kings" as opponent. Auto-selects team in GameSetupView.
23. **Normalized team names**: Removed case duplicates (e.g., "Lava" and "LAVA" merged to just "Lava"). Settings now shows clean list.
24. **Upcoming Games sheet**: "More games this month" link shows full list grouped by date (Today, Tomorrow, Friday Jan 24, etc.) instead of going to Settings.
25. **Jony Ive header cleanup**: Removed settings icon from header. Settings now a subtle text link at bottom of scroll content. Header is clean and centered.
26. **Hidden scroll indicators**: Removed scroll bar for cleaner look.
27. **Direct hide button**: Replaced ellipsis menu with subtle `eye.slash` icon - one tap to hide a game, no menu.
28. **Undo toast for hide**: Shows "Game hidden" toast with Undo button for 3 seconds. Capsule design with blur background. Tap Undo to restore.

### Jony Ive UI Refinements (2026-02-01)

**Scoring UI (UltraMinimalRecordingView.swift):**

Tested interactive scoreboard controls vs full-screen tap zones. Jony Ive philosophy: "Simplicity is the ultimate sophistication." Large tap zones are more forgiving during fast games.

**Final Design - Full-Screen Tap Zones:**
```
┌──────────────────┬──────────────────┐
│                  │                  │
│   LEFT HALF      │   RIGHT HALF     │
│   (Your Team)    │   (Opponent)     │
│                  │                  │
│   TAP = +1       │   TAP = +1       │
│   SWIPE ← = -1   │   SWIPE ← = -1   │
│   PINCH = ZOOM   │   PINCH = ZOOM   │
│                  │                  │
├──────────────────┴──────────────────┤
│     [Scoreboard - Display Only]      │
│     (clock still tappable)           │
└──────────────────────────────────────┘
```

**Gestures:**
- **Tap** → Add +1 point (multi-tap accumulator: 1/2/3)
- **Swipe LEFT** → Subtract -1 point (fix mistakes) - horizontal swipe doesn't conflict with pinch
- **Pinch** → Zoom camera 0.5x-3.0x (uses `.simultaneousGesture()`)
- **Tap clock** → Pause/play

**Swipe directions (symmetric):**
- Left half: swipe **LEFT** (away from center) to subtract
- Right half: swipe **RIGHT** (away from center) to subtract
- Both directions are "push away" gestures - intuitive for removing points

**Camera Control button (iPhone 16+) - REMOVED:**
We explored adding Camera Control support but removed it because:
- Camera Control button is ON THE PHONE
- User's workflow: set up gimbal → walk to sidelines → use Watch to score
- You're not near the phone during the game, so the button is useless
- Required 3 extension targets (Capture Extension, Widget Extension, CameraCaptureIntent) = bloat

**Decision:** Keep it simple. Watch + pinch zoom before walking away + overlay buttons are sufficient. Jony would approve.

**Feedback Animations:**
- **+1 animation**: Green/orange pill with "+1" fades after 0.6s
- **-1 animation**: Same style, shows when swiping down to subtract

**Zoom Range:**
- Changed from 1.0-3.0x to 0.5-3.0x
- 0.5x uses ultra-wide camera on compatible iPhones
- Zoom controls also available in stats overlay (±0.5x buttons)

**Gesture Conflict Resolution:**
- Pinch gesture on same layer as tap zones using `.simultaneousGesture()`
- Swipe down for subtract (avoids long-press vs tap conflicts)
- Scoreboard is display-only except clock (simplifies touch handling)

---

## Watch App UI Details

### WatchContentView (Main Entry)
The root view that shows either:
- **Waiting screen** - When no game is active (shows basketball icon, "Waiting for game...")
- **TabView** - When game is active (swipe vertically between Scoring and Stats)

Shows connection status: "Phone not connected" warning if `isPhoneReachable = false`

### WatchScoringView (Primary Screen)
The main scoring interface during games.

**Layout (top to bottom):**
```
┌─────────────────────────────┐
│         ● LIVE              │  <- Green dot when clock running, orange when paused
├─────────────────────────────┤
│           H1                │  <- Period indicator (tap to advance)
├──────────────┬──────────────┤
│              │              │
│     42       │     38       │  <- Score zones (tap to add +1)
│    SAHI      │     OPP      │  <- Team names (truncated to 4 chars)
│              │              │
├──────────────┴──────────────┤
│          12:34              │  <- Clock (tap to pause/play)
│         running             │  <- Shows "hold to end" when paused
├─────────────────────────────┤
│          ═══ Stats          │  <- Swipe hint
└─────────────────────────────┘
```

**Interactions:**
- **Tap score** → Add +1 point (shows "+1" feedback animation)
- **Tap period** → Advance to next period (H1 → H2)
- **Tap clock** → Toggle pause/play
- **Long press clock (0.5s)** → Show "End Game?" confirmation
- **Swipe up** → Go to Stats view

**End Game Overlay:**
- Shows final score with color (green if winning, red if losing)
- Cancel or End buttons

### WatchStatsView (Secondary Screen) - Jony Ive Redesign
Individual player stats tracking for Sahil. Redesigned with generous touch targets and swipe navigation.

**Design Principles:**
- Simplicity: Focus on one task at a time
- Generous touch targets: Large 80pt MAKE/MISS buttons
- Intuitive navigation: Horizontal swipe between shooting and other stats
- Clear visual hierarchy: Points prominent, then shot type, then actions
- Haptic feedback on every action

**Shooting Stats Layout (Primary):**
```
┌─────────────────────────────┐
│  28 PTS            3/5      │  <- Points + current shot stats
├─────────────────────────────┤
│  ┌─────┬─────┬─────┐       │
│  │ 2PT │ 3PT │ FT  │       │  <- Pill selector (tap to switch)
│  └─────┴─────┴─────┘       │
│                             │
│  ┌───────────┬───────────┐ │
│  │     ✓     │     ✗     │ │
│  │   MAKE    │   MISS    │ │  <- BIG 80pt buttons
│  │  (green)  │   (red)   │ │
│  └───────────┴───────────┘ │
│       More stats →          │  <- Swipe hint
└─────────────────────────────┘
```

**Other Stats Layout (Swipe Left):**
```
┌─────────────────────────────┐
│  ← Shooting                 │
├─────────────────────────────┤
│  ┌─────┬─────┬─────┐       │
│  │  2  │  4  │  1  │       │
│  │ AST │ REB │ STL │       │  <- Tap to increment
│  └─────┴─────┴─────┘       │
│  ┌─────┬─────┬─────┐       │
│  │  0  │  2  │  0  │       │
│  │ BLK │ TO  │ PF  │       │
│  └─────┴─────┴─────┘       │
└─────────────────────────────┘
```

**Navigation:**
- Vertical swipe: Score ↔ Stats (main TabView)
- Horizontal swipe: Shooting ↔ Other stats (within Stats)

**Points Calculation:**
```swift
points = (fg2Made * 2) + (fg3Made * 3) + ftMade
```

### WatchConnectivityClient (Watch-side)

**Published State:**
```swift
// Connection
@Published var isPhoneReachable: Bool = false
@Published var hasActiveGame: Bool = false

// Game state (synced from iPhone)
@Published var teamName: String = "MY TEAM"
@Published var opponent: String = "OPP"
@Published var myScore: Int = 0
@Published var oppScore: Int = 0
@Published var remainingSeconds: Int = 18 * 60  // 18 min default
@Published var isClockRunning: Bool = false
@Published var period: String = "1st Half"
@Published var periodIndex: Int = 0

// Player stats
@Published var fg2Made/fg2Att, fg3Made/fg3Att, ftMade/ftAtt
@Published var assists, rebounds, steals, blocks, turnovers
```

**Outgoing Messages (Watch → iPhone):**
- `addScore(team: "my"/"opp", points: 1/2/3)` - Score update
- `toggleClock()` - Pause/resume clock
- `advancePeriod()` - Move to next period
- `updateStat(statType, value)` - Individual stat change
- `endGame()` - End the game

**Incoming Messages (iPhone → Watch):**
- `gameState` - Full sync when game starts
- `scoreUpdate` - Score changed on iPhone
- `clockUpdate` - Clock state changed
- `periodUpdate` - Period advanced
- `endGame` - Game ended on iPhone

**Optimistic Updates:**
Watch updates local state immediately when user taps (for responsiveness), then sends message to iPhone. If iPhone is unreachable, local state still updates but won't sync.

### Design Decisions

**Why +1 only on Watch (not +2, +3)?**
- Watch screen too small for multiple buttons
- Most youth basketball scores are layups (+2) anyway
- User can tap twice quickly for +2
- Stats view handles shooting detail (2PT make = +2 points)

**Why vertical TabView?**
- Matches watchOS conventions (swipe up/down)
- Scoring is primary (first tab)
- Stats is secondary (swipe up to access)

**Why truncate team names to 4 chars?**
- Watch screen is tiny (~40mm)
- "SAHI" fits better than "SAHIL'S TEAM"
- Full name shown on Stats view header

**Colors:**
- Orange = Sahil's team / accent color
- Green = clock running / made shots
- Red = missed shots
- White with opacity = secondary text

---

## YouTube Upload (Lean Implementation)

### Overview
Auto-uploads game videos to YouTube (public) for building a portfolio and sharing Sahil's highlights.

### Design Philosophy (Steve Jobs / Jony Ive)
- **No WiFi monitoring** - User has unlimited 5G, no need for queue
- **No upload queue** - Upload immediately when game ends
- **No Firebase for tokens** - Use Keychain (simpler, local)
- **~200 lines total** - Minimal code, maximum functionality

### Files
```
SahilStatsLite/Services/
└── YouTubeService.swift    # Auth + upload (~200 lines)
```

### YouTubeService.swift
Single class handling both authentication and upload:

**State:**
```swift
@Published var isAuthorized: Bool      // Connected to YouTube
@Published var isUploading: Bool       // Currently uploading
@Published var uploadProgress: Double  // 0.0 - 1.0
@Published var lastError: String?      // Error message if failed
@Published var isEnabled: Bool         // User preference toggle
```

**Auth Flow:**
1. User taps "Connect YouTube" in Settings
2. `authorize()` triggers Google Sign-In with YouTube upload scope
3. Tokens stored in Keychain (not Firebase)
4. Token refresh happens automatically if >45 minutes old

**Upload Flow:**
1. Game ends → video saved to Photos
2. If `isEnabled && isAuthorized` → upload begins (non-blocking)
3. Uses YouTube resumable upload API for large files
4. Retries up to 3 times on failure
5. Videos uploaded as **public**

### Settings UI
YouTube section in SettingsView:
- Toggle: "Auto-upload to YouTube"
- Status: Connected/Not connected
- Button: "Connect YouTube" or "Disconnect"

### Video Title/Description Format
```
Title: "Wildcats vs Thunder - Jan 21, 2026"
Description:
  Wildcats 42 - 38 Thunder
  Sahil: 15 pts

  Recorded with Sahil Stats
```

### Keychain Storage
- Service: `com.narayan.SahilStats.youtube`
- Keys: `accessToken`, `refreshToken`, `tokenTimestamp`

### Why Not WiFi Monitoring?
Original SahilStats had WiFi-only uploads with a queue system. This was removed because:
- User has unlimited 5G data plan
- Simpler code without queue management
- Immediate upload is better UX
- No need for persistence/retry infrastructure

### Why Keychain Instead of Firebase?
- YouTube tokens are device-local (no cross-device sync needed)
- Keychain is built-in, secure, no network required
- Reduces Firebase dependencies
- Simpler code (~50 lines vs ~100 lines for Firebase)

---

## AI Lab (R&D Complete - 2026-01-24)

> **STATUS**: R&D phase complete. Stripe detection + heat map + zoom-in-post all working. Ready for Skynet mode (real-time learning).

### Overview
Advanced AI features to crush XBotGo and enhance game videos. Two-layer tracking system: gimbal constraints + post-processing zoom.

### The XBotGo Problem
XBotGo's auto-tracking has a critical flaw: during timeouts or dead balls, the gimbal follows sideline movement (parents, other teams walking by) instead of holding position on the court. Users are forced to manually calibrate court bounds, which is tedious and error-prone.

**Our solution**: AI that learns court bounds automatically from player activity (heat map) and ignores sideline activity.

### R&D Results (2026-01-24)

| Approach | Result | Notes |
|----------|--------|-------|
| **VNDetectRectanglesRequest** | ❌ Garbage | Detects windows, ceiling trusses, signs - NOT court lines |
| **VNDetectHumanBodyPoseRequest** | ⚠️ Flaky | Works sometimes, weird diagonal lines, partial skeletons |
| **VNDetectHumanRectanglesRequest** | ✅ Works | Reliable human bounding boxes |
| **Heat Map (player positions)** | ✅ Primary | Learn court bounds from where players cluster |
| **Hoop Detection (orange rim scan)** | ❌ Unreliable | Too many false positives, lines drawn in wrong places |
| **Stripe Detection (ref jerseys)** | ✅ Works | Black/white alternating pattern in torso = REF |
| **Kid/Adult Classification** | ✅ Works | Size-based: adults are 25%+ taller than median |
| **Zoom-in-Post** | ✅ Works | Crop video to follow action center with smooth easing |

### Stripe Detection (Ref Jerseys)

Refs wear black/white striped jerseys. We detect this by sampling the torso region:

```swift
// Sample vertical line through torso
// Look for light/dark transitions (brightness > 140 vs < 140)
// Must be low saturation (grayscale, not colored stripes)
// 3+ transitions = striped jersey = REF

// Color coding:
// Yellow = REF (striped jersey detected)
// Cyan   = PLAYER (kid on court, no stripes)
// Magenta = ADULT? (adult on court, no stripes - rare)
// Orange = BENCH (kid off court)
// Red    = COACH (adult off court, no stripes)
```

### Kid vs Adult Classification

Since players are kids and coaches/parents are adults, we classify by bounding box size:

```swift
// Calculate median height of all detected people
// Adults are typically 25%+ taller than median (kids)
let adultThreshold = medianHeight * 1.25
```

### Heat Map Approach (Fallback)

Instead of trying to detect court lines visually, we track where players cluster over time:

```
First 60 seconds of game:
┌─────────────────────────────────┐
│ 0  0  0  0  0  0  0  0  0  0  │  ← Ceiling (ignore)
│ 0  2  5  8 12 14  9  6  3  1  │  ← Players cluster here
│ 1  4  9 15 18 20 16 11  5  2  │  ← HIGH ACTIVITY = COURT
│ 0  3  7 13 17 19 14  8  4  1  │
│ 2  1  0  0  0  0  0  0  1  3  │  ← Sidelines (low activity)
└─────────────────────────────────┘
```

**Key insight**: We don't need to detect court lines. We just need to know where players ARE vs where they AREN'T.

### Tools Created

**1. Playground (for quick experiments):**
```
SkynetTest/AILabPlayground.playground
```
- Visual frame analysis
- Heat map generation
- Skeleton/pose visualization
- Note: Unstable with heavy video processing

**2. Command-line tool (stable):**
```
SkynetTest/ailab.swift

Usage:
swift SkynetTest/ailab.swift <video_path> [start_seconds] [duration_seconds] [--zoom]

Examples:
swift SkynetTest/ailab.swift "~/game.mp4" 0 60           # Tracking overlay mode
swift SkynetTest/ailab.swift "~/game.mp4" 0 60 --zoom    # Zoom-in-post mode
```

**Two modes:**

| Mode | Flag | Output | Purpose |
|------|------|--------|---------|
| Tracking | (default) | `AILab_Tracked.mp4` | Debug/tune - shows classifications |
| Zoom | `--zoom` | `AILab_Zoomed.mp4` | Final output - cropped following action |

**Features:**
- **Heat map** - learns court bounds from player positions
- **Stripe detection** - identifies refs by black/white jersey pattern
- **Kid/adult classification** - filters coaches/parents by size
- **Action center** - weighted average of player positions (bigger = closer = more weight)
- **Smooth easing** - camera doesn't jump, eases toward action (20% per frame)
- **2x zoom** - 4K→1080p or 1080p→540p crop headroom

**Tracking mode output:**
- Green rectangle = tracking region (heat map based)
- Red shaded = ignore zones
- Cyan = PLAYER, Yellow = REF, Orange = BENCH, Red = COACH

**Zoom mode output:**
- Cropped video following action center
- Smooth pan as action moves across court
- Progress shows: `Center:(0.35,0.52) Players:3 Refs:1`

### Tracking Region Calculation

```swift
// From heat map, find cells above 40% of max activity
// Skip top 30% (ceiling) and bottom 5% (camera operator)
// Add padding for player feet
let region = TrackingRegion(
    minX: 0.03,   // Left bound
    maxX: 0.97,   // Right bound
    minY: 0.05,   // Bottom (with padding)
    maxY: 0.70    // Top (exclude ceiling)
)
```

### Two-Layer Tracking Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     DURING GAME (Real-time)                      │
├─────────────────────────────────────────────────────────────────┤
│  iPhone on Gimbal                                                │
│  └─→ DockKit auto-tracks people (physical pan)                   │
│      └─→ Our AI constrains tracking region                       │
│          └─→ Ignores sideline movement during timeouts           │
│                                                                  │
│  Records 4K wide-angle footage                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     POST-GAME (Polish)                           │
├─────────────────────────────────────────────────────────────────┤
│  Run ailab.swift --zoom on recorded video                        │
│  └─→ Virtual zoom following action center                        │
│      └─→ Smoother than mechanical gimbal                         │
│          └─→ Catches moments gimbal missed                       │
│                                                                  │
│  Output: Cropped, professional-looking game video                │
└─────────────────────────────────────────────────────────────────┘
```

### Warmup Calibration Architecture (2026-02-05)

**The Problem:** User sets up camera on gimbal 2-5 minutes before tip-off during warmups. Old flow started recording AND Skynet simultaneously, wasting storage on warmup footage AND cold-starting tracking.

**The Solution:** Decouple camera/Skynet from video file recording.

```
View appears (landscape) → Camera session starts + Skynet starts learning
  → Court bounds learned from player positions during warmup
  → Player height baseline calibrated (kids vs adults)
  → Ref stripe detection calibrated
  → NO video file created yet

User taps game clock → Video file recording begins
  → AutoZoomManager.resetTrackingState() called
  → Resets: tracking momentum, zoom, DeepTracker tracks, action center
  → KEEPS: court bounds, baseline kid height, height statistics from warmup
```

**Key Architectural Insight:** `captureOutput` delegate in RecordingManager already has two independent paths:
1. **AI path** — runs when `onFrameForAI` callback is set (works as long as camera session runs)
2. **Recording path** — runs when `assetWriter` exists (only after `startRecording()`)

So Skynet gets frames during warmup with zero changes to RecordingManager.

**State Variables (UltraMinimalRecordingView):**
- `hasCameraStarted` — Camera session + Skynet active (set on landscape entry)
- `hasGameStarted` — Video file recording active (set on first clock tap)

**resetTrackingState() Methods:**
- `AutoZoomManager.resetTrackingState()` — Resets DeepTracker, zoom, action center. Keeps PersonClassifier court bounds.
- `PersonClassifier.resetTrackingState()` — Resets centroid history. Keeps courtBounds, baselineKidHeight, recentHeights.

### Skynet Mode (Real-time Learning) - IMPLEMENTED

> **STATUS**: Skynet v4.1 — Momentum Attention + Timeout Detection + Golden Smoothing. Skynet is ON by default (only "Off" or "Auto" modes). Warmup calibration provides free learning period before game starts.

**Deep Track 4.0 Research Summary (Insta360 Patents US11509824B2, JP2021527865A):**
- **Multi-scale correlation filter (MSCF)** - Appearance models from adjacent regions
- **Kalman filtering** - Motion prediction, trajectory smoothing, 15% jitter reduction
- **Occlusion detection** - Reliability score + occlusion score with threshold-based strategy switching
- **Person re-identification (ReID)** - Appearance embeddings for re-locking after occlusion
- **Recovery sequence** - Zoom out → pan toward last direction → use ReID to re-lock
- **0.3 second re-acquisition** - Measured in independent testing

**What Skynet Implements:**

| Deep Track 4.0 Feature | Skynet Implementation |
|------------------------|----------------------|
| Multi-scale correlation filter | ✅ PersonClassifier with Vision framework |
| Kalman filtering | ✅ KalmanFilter2D class (position + velocity) |
| Reliability scoring | ✅ TrackedObject.reliabilityScore (0-1) |
| Occlusion scoring | ✅ TrackedObject.occlusionScore with thresholds |
| SORT-style tracking | ✅ DeepTracker with ID persistence |
| Recovery mode | ✅ Zoom out when primary track lost |
| Person classification | ✅ Kid/adult/ref filtering (unique advantage) |

**How It Works:**
- Uses `PersonClassifier.swift` for smart classification:
  - **Players (kids)**: Multiple heuristics - height ratio, absolute size, aspect ratio
  - **Refs**: Multi-sample stripe detection (5 vertical + horizontal)
  - **Adults/Coaches**: Filtered out, not tracked
- Uses `DeepTracker.swift` for SORT-style tracking:
  - **Kalman filter** per tracked object for smooth motion prediction
  - **Track ID persistence** across frames (not just per-frame detection)
  - **Reliability/occlusion scores** trigger recovery strategies
  - **Group bounding box** for dynamic framing
- Rolling heat map learns court bounds over time
- Action center calculated from Kalman-filtered positions (much smoother)
- Zoom based on player spread with recovery awareness (zoom out if tracking lost)

**Core Principles:**
1. **No hardcoded assumptions** - works from center court, corner, bleachers, any angle
2. **Learn from observation** - players cluster = court, adults on edges = sideline
3. **Continuous adaptation** - keep learning throughout game, adjust to halftime, timeouts

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│                    SKYNET MODE                           │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  CONTINUOUS LEARNING (entire game):                      │
│  ├─ Sample frames every 0.5-1 sec                       │
│  ├─ Detect people, classify (kid/adult)                 │
│  ├─ Update rolling heat map (recent weighted higher)    │
│  ├─ Recalculate court bounds from heat map              │
│  └─ No "hold still" phase - learn while tracking        │
│                                                          │
│  REAL-TIME TRACKING:                                     │
│  ├─ Filter: within court bounds + kid-sized             │
│  ├─ Calculate action center (weighted by size)          │
│  ├─ Pan gimbal → action center                          │
│  ├─ Zoom based on player spread (max 1.5x)              │
│  └─ Smooth easing (no jumpy movement)                   │
│                                                          │
│  SMART BEHAVIORS:                                        │
│  ├─ Timeout: players cluster at edges → hold position   │
│  ├─ Fast break: action moves quickly → smooth follow    │
│  ├─ Under basket: cluster → subtle zoom in              │
│  └─ Spread offense: wide → zoom out                     │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Implementation Files:**

1. **PersonClassifier.swift** - Smart person classification
```swift
class PersonClassifier {
    func classifyPeople(in pixelBuffer: CVPixelBuffer) -> [ClassifiedPerson]
    func calculateActionCenter(from people: [ClassifiedPerson]) -> CGPoint
    func calculateZoomFactor(from people: [ClassifiedPerson], ...) -> CGFloat
    func updateCourtBounds(from heatMap: [[Int]], threshold: Double)
}
```

2. **DeepTracker.swift** - SORT-style tracking with Kalman filtering (NEW)
```swift
class KalmanFilter2D {
    // State: [x, y, vx, vy] - position and velocity
    func predict(dt: Double) -> CGPoint   // Motion prediction
    func update(measurement: CGPoint)      // Correct with detection
    var positionUncertainty: Double        // For reliability scoring
}

class TrackedObject {
    let kalman: KalmanFilter2D
    var reliabilityScore: Float           // 0-1, drops when missed
    var occlusionScore: Float             // Increases when occluded
    var state: State                      // .tentative, .confirmed, .lost, .deleted

    static let confirmHits = 3            // Frames to confirm track
    static let maxMisses = 15             // ~0.5 sec before deletion
}

class DeepTracker {
    func update(detections: [ClassifiedPerson], dt: Double) -> [TrackedObject]
    func getActionCenter(filterPlayers: Bool) -> CGPoint  // Kalman-smoothed
    func getGroupBoundingBox() -> CGRect                  // Deep Track 4.0 envelope
    func calculateZoom(minZoom: CGFloat, maxZoom: CGFloat) -> CGFloat

    var isInRecoveryMode: Bool            // True when primary track lost
    var averageReliability: Float         // Track confidence
}
```

3. **AutoZoomManager.swift** - Integrates everything
```swift
enum AutoZoomMode {
    case off, smooth, responsive, skynet  // Skynet uses DeepTracker
}

// In Skynet mode:
let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)
let activeTracks = deepTracker.update(detections: classifiedPeople, dt: dt)
let actionCenter = deepTracker.getActionCenter(filterPlayers: true)  // Kalman-smoothed!
let zoom = deepTracker.calculateZoom(...)  // Recovery-aware
```

**Classification types (PersonClassifier):**
```swift
enum PersonType {
    case player      // Kid on court → TRACK
    case referee     // Striped jersey → Track but lower weight
    case coach       // Adult on sideline → IGNORE
    case benchPlayer // Kid on bench → IGNORE
    case spectator   // Unknown → IGNORE
}
```

2. **AutoZoomManager.swift** - Skynet v4.1 integration
```swift
enum AutoZoomMode: String, CaseIterable {
    case off = "Off"    // Manual zoom only
    case auto = "Auto"  // AI tracks players, ignores refs/adults
}

// v4.1 processing pipeline:
func processFrameWithSkynet(_ pixelBuffer: CVPixelBuffer) {
    let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)
    let activeTracks = deepTracker.update(detections: classifiedPeople, dt: dt)
    let actionCenter = personClassifier.calculateActionCenter(from: activeTracks) // Momentum-weighted
    let zoom = deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 2.0)

    // Timeout detection: 60%+ players at edges → zoom out to 1.0x
    let isTimeout = players.count >= 3 && edgePlayers/players > 0.6
    smoothZoomController.isTimeoutMode = isTimeout
}
```

3. **RecordingManager.swift** - Frame callback for AI
```swift
// Callback for AI processing (5 FPS)
var onFrameForAI: ((CVPixelBuffer) -> Void)?

// Called in sample buffer delegate:
if let callback = onFrameForAI, now - lastAIFrameTime >= 0.2 {
    callback(pixelBuffer)
}
```

**Why This Crushes XBotGo:**

| XBotGo | Skynet |
|--------|--------|
| Manual calibration | Self-learning |
| Fixed court bounds | Continuous adaptation |
| Follows any human | Filters by size + position |
| No zoom intelligence | Smart zoom on clusters |
| Gets lost on timeouts | Holds position (learned sideline) |
| One angle only | Works from any angle |

### Self-Learning / Self-Correcting Mode

**The Key Insight:** Gimbal can only pan/tilt (physical movement). Zoom is software-only. So Skynet controls BOTH:
- **DockKit** → Physical pan/tilt to keep action in frame
- **AVCaptureDevice.videoZoomFactor** → Software zoom based on player spread

**Self-Correcting Feedback Loop:**
```
┌─────────────────────────────────────────────────────────────┐
│                 SKYNET SELF-CORRECTION                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. OBSERVE: Sample frame every 0.5 sec                     │
│     └─→ Detect all humans (VNDetectHumanRectanglesRequest)  │
│                                                              │
│  2. CLASSIFY: Who's who?                                    │
│     ├─→ Size filter: Kids (players) vs Adults (coaches)     │
│     ├─→ Position filter: On-court vs sideline               │
│     └─→ Stripe filter: Refs (black/white jersey)            │
│                                                              │
│  3. LEARN: Update rolling heat map                          │
│     ├─→ Where players cluster = COURT (track here)          │
│     ├─→ Where adults stand = SIDELINE (ignore)              │
│     └─→ Decay old data (0.95x) so it adapts to game flow    │
│                                                              │
│  4. CORRECT: Adjust tracking                                │
│     ├─→ IF tracking outside heat map → snap back to court   │
│     ├─→ IF players spread wide → zoom OUT (1.0x)            │
│     ├─→ IF players cluster → zoom IN (up to 1.5x)           │
│     └─→ IF timeout (all players at edges) → HOLD position   │
│                                                              │
│  5. SMOOTH: No jumpy movements                              │
│     └─→ Ease toward target (20% per frame)                  │
│                                                              │
│  REPEAT every 0.5 sec throughout entire game                │
└─────────────────────────────────────────────────────────────┘
```

**Self-Correcting Behaviors:**

| Situation | Detection | Correction |
|-----------|-----------|------------|
| Gimbal tracking parent on sideline | Adult outside heat map | Snap back to court center |
| Fast break across court | Action center moved >30% | Smooth pan to follow |
| Under-basket play | Players clustered tight | Zoom in to 1.3-1.5x |
| Full-court press | Players spread wide | Zoom out to 1.0x |
| Timeout | All players at edges | Hold position, no panic |
| Halftime | Court empty | Hold last position |
| Ref running through | Striped jersey detected | Filter out, don't follow |

**Why No Manual Calibration:**
- Heat map LEARNS court bounds from where players actually play
- First 30-60 seconds: rapid learning as players run around
- After that: continuous refinement throughout game
- Works from ANY camera angle (center court, corner, bleachers)

### Ultra-Smooth Tracking v3/v4.1 (2026-02-05)

> **LATEST**: Broadcast-quality tracking migrated to product as Skynet v4.1. Added Momentum Attention (velocity-weighted via Kalman filter), Timeout Detection (bench rush awareness), warmup calibration workflow. Tested on real game footage (IMG_7205.mov). Person detection 89.5% — players drive 100% of focus.

**The Problem (v1-v2):**
Initial Skynet had good detection but jittery output — camera jumped between detected positions. v2 added person detection but centroid still jittered when 10+ players were on court (Vision detects different subsets each frame).

**v3 Key Insight:** With 10+ fast-moving players, the center of mass jumps around every detection cycle. Fix: proximity-weighted centroid (near players matter more) + rolling average over 8 cycles (~0.8s).

**Research Applied:**
| Algorithm | Implementation | Purpose |
|-----------|---------------|---------|
| Extended Kalman Filter | 6-state [x, y, vx, vy, ax, ay] | Smooth motion prediction |
| SORT-style tracking | Hungarian algorithm assignment | Track ID persistence |
| OC-SORT | Observation-centric recovery | Handle occlusions |
| VNDetectHumanRectanglesRequest | Every 6 frames (~10fps) | Person detection (89.5% rate) |
| Proximity-weighted centroid | `weight = max(0.1, 1.0 - distance * 2.0)` | Near-focus players matter more |
| Rolling centroid average | 8-sample window (~0.8s) | Eliminate detection flickering |
| Kid/adult classification | Median height * 1.25 threshold | Filter coaches/parents |

**v3 Parameters (validated on real game footage):**
```swift
// Focus movement (UltraSmoothFocusTracker) - VideoAnalysisPipeline.swift
positionSmoothing = 0.008   // 0.8% per frame (was 2%) - broadcast-slow pan
velocityDamping = 0.75      // Stronger decay (was 0.85) - less momentum carry
deadZone = 0.06             // 6% dead zone (was 2%) - ignore centroid jitter
maxSpeed = 0.006            // 0.6% per frame (was 1.5%) - very slow max pan
minStreakForUpdate = 8      // 8 frames ~0.13s (was 2) - require agreement

// Zoom control (UltraSmoothZoomController) - AutoZoomManager.swift
zoomSmoothing = 0.005       // 0.5% per frame (was 1%) - ultra slow zoom
deadZone = 0.04             // 4% dead zone (was 3%)
maxZoomSpeed = 0.004        // Half of previous (was 0.008)
minStreakForUpdate = 6      // 6 frames (was 3)
minZoom = 1.0, maxZoom = 1.5  // Tighter range (was 1.6)

// Centroid smoothing (PersonClassifier.swift)
centroidHistorySize = 8     // Rolling average over ~0.8s of detections
proximityWeight = max(0.1, 1.0 - distance * 2.0)  // Near-focus bias

// Focus weights (ball vs players)
// Players detected: 70% player, 30% ball (players are far more reliable)
// No ball detected: 100% player (ball only 10% detection rate on wood courts)
```

**Hoop False Positive Fix (BallDetector.swift):**
The orange basketball hoop rim was being detected as the ball. Fixed by:
```swift
// Position filter - upper 25% of frame is hoop zone
if centerY < 0.25 { continue }  // Skip detections in upper portion

// Edge filter - extreme horizontal edges
if centerX < 0.05 || centerX > 0.95 { continue }

// Tighter aspect ratio (0.5 to 2.0)
guard aspectRatio > 0.5 && aspectRatio < 2.0 else { continue }

// Size penalty - large clusters are more likely hoop
let sizePenalty = clusterCells.count > 15 ? Float(clusterCells.count - 15) * 0.02 : 0
```

**Files Updated (v3):**
1. `VideoAnalysisPipeline.swift` - UltraSmoothFocusTracker v3 params (slower, bigger dead zone)
2. `AutoZoomManager.swift` - UltraSmoothZoomController v3 params + focus hint feedback
3. `PersonClassifier.swift` - Proximity-weighted centroid + rolling average
4. `SkynetTest/SkynetVideoTest.swift` - Standalone test tool with person detection + pool fix

**Test Tool (SkynetTest/):**
```bash
cd ~/SahilStats/SahilStatsLite/SahilStatsLite/
swift SkynetTest/SkynetVideoTest.swift ~/path/to/video.mp4          # First 2 min (default)
swift SkynetTest/SkynetVideoTest.swift ~/path/to/video.mp4 60       # First 60 seconds
swift SkynetTest/SkynetVideoTest.swift ~/path/to/video.mp4 --full   # Entire video
swift SkynetTest/SkynetVideoTest.swift ~/path/to/video.mp4 --no-debug  # No overlay
```
Outputs `*_ultrasmooth.mp4` with debug overlay showing:
- Person boxes (green = player/kid, red = adult/coach)
- Magenta diamond = player center of mass
- Ball detection (orange circle)
- Focus crosshair (cyan, always at crop center)
- Status panel with player count dots, spread/zoom bars

**Results (IMG_7205.mov, 1280x720 @ 60fps):**
| Metric | v1 | v2 | v3 |
|--------|-----|-----|-----|
| Person detection | N/A | 89.5% | 89.5% |
| Ball detection | 71% | 10.1% | 10.1% |
| Video jitter | High | Moderate (shaky with many players) | Eliminated |
| Hoop false positives | Yes | No | No |
| Zoom oscillation | Frequent | Occasional | Rare |
| Processing speed | 157 fps | 149 fps | 148 fps |

**Why ball detection dropped from 71% to 10%:**
The original test was on a video with good contrast. Real gym footage (wood court + overhead lighting) creates orange-ish floor reflections that confuse the ball detector. v3 compensates by leaning heavily on player detection instead.

### Future Refinements

1. ~~**Ref detection**~~ → DONE (stripe pattern detection in PersonClassifier)
2. ~~**Dynamic filtering**~~ → DONE (per-frame classification via PersonClassifier)
3. ~~**Zoom-in-post**~~ → DONE (action center + smooth easing)
4. ~~**Real-time learning**~~ → DONE (Skynet mode in AutoZoomManager)
5. ~~**Ultra-smooth tracking**~~ → DONE (broadcast-quality motion smoothing)
6. **Ball tracking** - Follow the orange basketball for action focus
7. **Highlight detection** - Cluster under basket = scoring play

### What We CAN'T Test From a Desk

- Does DockKit actually respond to our filtering?
- Does it feel smoother than XBotGo?
- Real-world timeout/substitution handling

**These require real-world testing with gimbal at a game.**

### Files

All AI R&D tools are now in the `SkynetTest/` directory within the git repo:
```
SkynetTest/
├── AILabPlayground.playground  # Visual experiments (unstable)
├── ailab.swift                  # Command-line tool (stable)
└── SkynetVideoTest.swift        # Broadcast-quality Skynet test tool
```

---

## Pending Tasks

### Saturday Game Day Test (Priority 1)
- [ ] Full recording flow on physical iPhone + gimbal
- [ ] Watch scoring works from sideline
- [ ] Video saves with overlay correctly
- [ ] YouTube upload works (OAuth + actual upload)

### Post-Saturday (Priority 2)
- [ ] Game editing in Game Log (edit scores/stats after game)
- [ ] Integrate heat map into GimbalTrackingManager
- [ ] Test AI tracking at real game with gimbal
- [ ] Compare tracking quality vs XBotGo

### AI Lab - Completed R&D (2026-01-24)
- [x] Playground created for Vision experiments
- [x] Tested VNDetectRectanglesRequest (doesn't work for courts)
- [x] Tested VNDetectHumanBodyPoseRequest (flaky)
- [x] Validated heat map approach (primary method)
- [x] Created command-line tool (ailab.swift)
- [x] Tested on real game footage (XBotGo and corner camera)
- [x] ~~Hoop detection~~ - tried, too unreliable (false positives)
- [x] **Stripe detection** - black/white pattern = REF jersey
- [x] **Kid/adult classification** - size-based filtering (25%+ taller = adult)
- [x] **Per-frame classification** - dynamic PLAYER/REF/BENCH/COACH labels
- [x] **Action center calculation** - weighted avg (bigger box = closer = more weight)
- [x] **Smooth easing** - 20% per frame movement toward target
- [x] **Zoom-in-post** - `--zoom` flag outputs cropped video following action
- [x] **Skynet mode** - real-time learning during game (integrated into AutoZoomManager)
