# Sahil Stats - Project Context

> **UPDATED (2026-02-06):** "Earth Shattering" Tracking Update. Visual Re-ID (Color Histogram) now ignores distractions. Remote Court Calibration (Zone Mapping) via Watch D-Pad allows precise floor definition. Manual YouTube workflow (Background Session) replaces auto-upload anxiety.

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
- **Remote Calibration**: Use Watch D-Pad to adjust court corners on Phone AR view.

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

<h3>Four-Phase Workflow</h3>
1. **Setup**: Configure in Settings. Screen stays awake during warmup for tripod setup.
2. **Calibration**: Use "Scope" (AR) to mark court corners. Use Watch Remote if phone is high up.
3. **Game Recording**: Tap game clock to start. Video file recording begins. Skynet resets tracking momentum (keeps learned court bounds). Phone is a "dumb camera" from here.
4. **After game**: Review in Game Log. Tap "Upload to YouTube" manually when ready.

<h3>Settings vs Stats Separation</h3>
- **Settings screen**: Skynet AI toggle, Gimbal mode, Team names
- **Stats overlay**: Only shooting stats, other stats, and game controls (period, OT, end)
- **Camera Controls**: Tucked at bottom of Stats dashboard (Emergency Override).

<h3>Key Decisions</h3>
- **Skynet defaults to ON** - AI tracking is the main feature.
- **Manual Upload** - No anxiety about "is it uploading?". Capture first, share later.
- **Visual Re-ID** - Skynet learns jersey colors to ignore parents walking by.
- **Zone Mapping** - Manual calibration creates a "Force Field" around the court.

---

<h2>Current Status</h2>
- Old app: archived to `SahilStats-archive.zip` (100 files, 40k lines - too complex)
- New app: ~40 files, ~5,000 lines - git repo at `/SahilStats/SahilStatsLite/SahilStatsLite/`
- Phase 1: Recording + auto-tracking + score overlay (IN PROGRESS)
- Phase 2: Stats tagging
- Phase 3: Highlights and sharing

<h3>Phase 1 Progress (Updated 2026-02-06)</h3>
- [x] Basic project structure
- [x] Camera preview working
- [x] Floating Ubiquiti-style controls with score buttons (+1, +2, +3)
- [x] Running game clock with play/pause
- [x] Save to Photos functionality
- [x] ScoreTimelineTracker - records score snapshots with timestamps
- [x] OverlayCompositor - burns score overlay into video post-recording
- [x] Integration complete: RecordingView -> ScoreTimelineTracker -> OverlayCompositor -> GameSummaryView
- [x] **4K video recording support** (now default)
- [x] Broadcast-style overlay design (blue home, red/orange away, dark score boxes)
- [x] Landscape rotation handling for video composition
- [x] iOS 26 UIScreen.main deprecation fix
- [x] **Skynet v4.1**: Momentum Attention + Timeout Detection + Golden Smoothing.
- [x] **Skynet v5.0 (Earth Shattering)**: Visual Re-ID (Color Histogram) + AR Court Calibration (Zone Mapping).
- [x] **Watch Remote Calibration**: Adjust phone view from wrist.
- [x] **Manual YouTube Upload**: Background URLSession for reliable "put in pocket" uploads.
- [x] **Watch Sync Fix**: Handshake ensures Watch picks up active game instantly.

<h3>4K Record / SD AI Architecture</h3>

We use a "Smart Asymmetry" approach to balance quality and performance:
- **Recording**: 4K (3840x2160) for maximum memory quality.
- **AI Processing**: SD (640x360) for maximum intelligence.
- **Benefits**:
    - **Higher Detection Rates**: Vision API performs better on standardized lower resolutions.
    - **Thermal Efficiency**: Processing 90% fewer pixels in the AI path keeps the phone cooler.
    - **Real-time Performance**: Ensures 60fps recording isn't interrupted by heavy ML tasks.

---

<h2>Technical Details</h2>

<h3>Video Recording (RecordingManager.swift)</h3>
- Uses AVCaptureSession with AVCaptureVideoDataOutput + AVAssetWriter
- **New Default: 4K (3840x2160)** for maximum quality
- Real-time burned-in scoreboard overlay
- Async `stopRecordingAndWait()` ensures file is fully written before processing

<h3>Video Orientation Handling (ScoreCam Pattern)</h3>
**RecordingManager.swift** uses `UIWindowScene.interfaceOrientation` to set `videoRotationAngle` on the connection BEFORE recording.

<h3>Score Overlay Approach</h3>
**Real-time rendering**:
1. `OverlayRenderer.swift` uses Core Graphics to draw the scoreboard.
2. `RecordingManager` renders this overlay onto every pixel buffer before it reaches the `AVAssetWriter`.
3. Ensures what you see on screen is exactly what is saved to the file (WYSIWYG).

---

<h2>Project Structure (SahilStatsLite)</h2>

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
│   │   ├── SkynetTestView.swift             # Standalone Skynet test UI (pick video, run pipeline)
│   │   └── CourtCalibrationView.swift       # AR interface for manual court mapping
│   ├── Services/
│   │   ├── RecordingManager.swift           # AVFoundation 4K capture, frame callbacks for AI
│   │   ├── AutoZoomManager.swift            # Skynet orchestrator (zoom, pan, timeout detection)
│   │   ├── PersonClassifier.swift           # Classification + Re-ID + Court Geometry
│   │   ├── DeepTracker.swift                # SORT-style tracking with Visual Appearance Matching
│   │   ├── GimbalTrackingManager.swift      # DockKit gimbal pan/tilt/zoom integration
│   │   ├── GameCalendarManager.swift        # Calendar event parsing, team/opponent detection
│   │   ├── GamePersistenceManager.swift     # Local game storage (UserDefaults JSON)
│   │   ├── OverlayRenderer.swift            # Core Graphics scoreboard renderer (broadcast-style)
│   │   ├── WatchConnectivityService.swift   # iPhone-side WCSession (Watch ↔ Phone sync)
│   │   ├── YouTubeService.swift             # YouTube OAuth + Background Upload
│   │   ├── AuthService.swift                # Firebase/Google Sign-In auth wrapper
│   │   ├── FirebaseService.swift            # Firestore CRUD for games
│   │   ├── BallDetector.swift               # Orange basketball detection via color thresholding
│   │   ├── CourtDetector.swift              # Court line detection (R&D, limited success)
│   │   ├── ActionProbabilityField.swift     # Predictive action field for camera focus
│   │   ├── GameStateDetector.swift          # Play/dead-ball/timeout state detection
│   │   ├── ExperimentalFilters.swift        # R&D tracking filters (sandbox)
│   │   ├── TestVideoProcessor.swift         # Offline video processing for SkynetTestView
│   │   ├── VideoAnalysisPipeline.swift      # Full video analysis: detection → tracking → output
│   │   └── HomographyUtils.swift            # Math for court geometry mapping
│   └── Resources/
│       └── Info.plist                       # Privacy descriptions (camera, mic, photos, calendar)
├── SahilStatsLite.xcodeproj/                # Xcode project
├── SahilStatsLiteWatch Watch App/           ← Apple Watch companion
│   ├── SahilStatsLiteWatchApp.swift         # Watch app entry point
│   ├── WatchContentView.swift               # Root nav: waiting screen or scoring TabView
│   ├── WatchScoringView.swift               # Tap-to-score, clock, period, end game
│   ├── WatchShootingStatsView.swift         # Shooting stats (MAKE/MISS)
│   ├── WatchOtherStatsView.swift            # Detail stats (AST, REB, STL...)
│   ├── WatchGameConfirmationView.swift      # Pre-game confirmation from Watch
│   ├── WatchCalibrationView.swift           # Remote control for calibration
│   ├── WatchLayout.swift                    # Adaptive layout (compact/regular/ultra)
│   ├── WatchConnectivityClient.swift        # Watch-side WCSession handler
│   └── Assets.xcassets/                     # Watch app icons
└── SkynetTest/                              ← AI R&D tools (standalone)
    ├── SkynetVideoTest.swift                # CLI: broadcast-quality Skynet test on video files
    └── ailab.swift                           # CLI: person detection, heat map, zoom-in-post
```

---

<h2>Apple Watch App</h2>

<h3>Overview</h3>
The Watch app allows Narayan to control scoring remotely while the iPhone records on the gimbal.

<h3>Multi-Watch Setup</h3>
- Both watches paired to iPhone, **auto-switch OFF**.
- Before game: manually switch to scoring watch in Watch app on iPhone.
- Only one watch active at a time (Apple limitation).

<h3>Hardware</h3>
| Watch | Case | Role |
|-------|------|------|
| Ultra 2 (49mm) | PodX Adventure Classic | Primary — daily wear + games |
| Series 8 (45mm) | TinyPod Standard | Backup — dedicated remote |

<h3>Adaptive Layout (WatchLayout.swift)</h3>
The Watch UI auto-detects screen size via `WKInterfaceDevice.current().screenBounds`:
- **Ultra (49mm)**: Full layout - separate live/period lines, swipe hint.
- **Regular (45mm)**: Compact layout - combined live+period header.
- **Compact (40mm)**: Max score zones, smaller fonts.

<h3>Watch Scoring Interactions</h3>
- **Tap score** → Add +1 point.
- **Swipe DOWN on score** → Subtract -1 (fix mistake).
- **Tap period** → Advance (1st Half → 2nd Half → OT).
- **Tap clock** → Pause/Play.
- **Long press clock** → End Game (wait for spinner confirmation).
- **Digital Crown** → Scroll between Scoring / Shooting Stats / Detail Stats.

---

<h2>YouTube Upload (Lean Implementation)</h2>
- **Immediate Upload**: No WiFi queue needed (user has unlimited 5G).
- **Manual Trigger**: Upload button in Game Log. No auto-upload anxiety.
- **Background Session**: Upload continues if app is backgrounded/locked.
- **Keychain Auth**: Tokens stored locally on device.

---

<h2>AI Lab (R&D Complete)</h2>

**Skynet v5.0 (Earth Shattering)**:
- **Visual Re-ID**: `DeepTracker` extracts color histograms from player bounding boxes. If a track is lost (occlusion), it only re-matches if the visual appearance score is high (>0.85). This ignores parents/refs who don't match the team jersey color.
- **Zone Mapping (Calibration)**: `CourtCalibrationView` allows the user to drag 4 corners to define the court floor. `PersonClassifier` checks every detection against this geometry. Anything outside the green box is ignored.
- **Remote Calibration**: Use the Apple Watch to move the court corners on the iPhone screen (for tall tripods).

**Warmup → Game Transition:**
```
Landscape entry → Camera session + Skynet learning (hasCameraStarted = true)
  → Screen forced AWAKE (isIdleTimerDisabled = true)
  → PersonClassifier learns: court bounds, baseline kid height, ref stripe patterns
  → DeepTracker builds: initial track IDs, confidence baselines

Clock tap → Video recording starts (hasGameStarted = true)
  → AutoZoomManager.resetTrackingState() called
  → Resets: DeepTracker tracks, zoom, action center, momentum
  → KEEPS: court bounds (manual or learned), kid height baseline
```