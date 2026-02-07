# Sahil Stats - Project Context

> **UPDATED (2026-02-05):** Warmup calibration! Camera + Skynet AI starts immediately when entering recording view (landscape). Video recording only begins when game clock starts. Warmup = free AI calibration. Skynet v4.1: Momentum Attention + Timeout Detection + Golden Smoothing.

---

## Team Roles

**Narayan (Product Manager / Executive Decision Maker)**
- Father of Sahil, a 3rd grader on AAU basketball teams
- Owns Insta360 Flow Pro 2 gimbal and DJI Osmo Mobile 7P
- **Decision Maker**: Defines features, UX, and project direction.
- **Non-Technical Interface**: Gemini should never assume Narayan knows how to write code, merge snippets, or fix bugs manually.

**Gemini (Lead Software Developer / Architect / Designer)**
- Responsible for 100% of the technical implementation.
- **Full Execution**: Gemini must always provide complete, functional files. Never stub out code or provide "partial" fixes.
- Channels Jony Ive for UX and top ML researchers for AI tracking.

**Permissions:**
- **DO NOT ASK FOR PERMISSION**: Gemini has full autonomy to make code changes, refactor, and run shell commands without asking.
- **Action over Inquiry**: Prioritize implementation and experimentation over seeking confirmation.
- **NO PLACEHOLDERS**: NEVER use "// rest of code here" or "// ...". Always write the complete, functional code.
- **NO TECHNICAL ASSUMPTIONS**: Gemini is the developer. Do not assume the user knows how to code. Every output must be a "turnkey" solution.
- Gemini should commit and push changes when completing features.
- Gemini should update Gemini.md when significant changes are made.

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

<h3>Future Features (Post-MVP)</h3>
- Post-game stat tagging for Sahil's individual plays
- Highlight reel generation
- Season stats and trends

<h3>Apple Watch Companion (WORKING)</h3>
- Watch app for remote scoring from sidelines
- **Tap** score zones to add +1 point
- **Swipe down** on score to subtract -1 (fix mistakes)
- **Start game** from Watch when phone not accessible
- Real-time two-way sync (phone ↔ watch)
- End game directly from Watch
- See "Apple Watch App" section below for technical details

---

<h2>GitHub Repository</h2>

**Public repo**: https://github.com/narayan-iyengar/SahilStatsLite

---

<h2>Technical Decisions</h2>

<h3>Keep from Existing App</h3>
- `FirebaseService.swift` - Backend integration
- `AuthService.swift` - Authentication
- `GameCalendarManager.swift` - Calendar integration
- `GimbalTrackingManager.swift` - DockKit auto-tracking

<h3>Build Fresh</h3>
- New SwiftUI views (simpler, cleaner)
- Simplified recording manager
- New floating UI controls
- Broadcast-style scoreboard overlay (ScoreCam-inspired)

<h3>Architecture</h3>
- Target: ~15 files, ~3,000 lines
- SwiftUI + SwiftData (or Firebase only)
- Single device focus (no multi-device sync)
- iOS 17+ minimum (for DockKit iOS 18+)

---

<h2>Hardware</h2>
- **Recording device**: iPhone (on gimbal)
- **Gimbal**: Insta360 Flow Pro 2 (DockKit compatible)
- **Backup gimbal**: DJI Osmo Mobile 7P (not DockKit, future consideration)

---

<h2>UX Design Philosophy (Jony Ive Style)</h2>

**Core Principle:** "You're a parent watching your kid's game, not babysitting an app."

<h3>Four-Phase Workflow</h3>
1. **Setup**: Configure in Settings (Skynet on/off, gimbal mode, team names)
2. **Warmup Calibration**: Enter recording view in landscape. Camera + Skynet start immediately — learns court bounds, player sizes, ref detection. No video file yet.
3. **Game Recording**: Tap game clock to start. Video file recording begins. Skynet resets tracking momentum (keeps learned court bounds). Phone is a "dumb camera" from here.
4. **After game**: Review, share, celebrate. Video contains only game footage.

<h3>Settings vs Stats Separation</h3>
- **Settings screen**: Skynet AI toggle, Gimbal mode, YouTube upload, Team names
- **Stats overlay**: Only shooting stats, other stats, and game controls (period, OT, end)
- No camera controls visible during recording - all pre-configured

<h3>Key Decisions</h3>
- **Skynet defaults to ON** - AI tracking is the main feature, shouldn't need to enable it
- **No zoom buttons during game** - Skynet handles zoom automatically
- **No gimbal mode switching during game** - set once before game
- **Stats overlay is for stats** - not a control panel for camera settings

<h3>Touch Philosophy</h3>
- Generous touch targets for sideline use (cold fingers, gloves, rushed taps)
- Tap to add points, long-press to subtract (fix mistakes)
- Swipe gestures for navigation, not precision actions

---

<h2>Current Status</h2>
- Old app: archived to `SahilStats-archive.zip` (100 files, 40k lines - too complex)
- New app: ~40 files, ~5,000 lines - git repo at `/SahilStats/SahilStatsLite/SahilStatsLite/`
- Phase 1: Recording + auto-tracking + score overlay (IN PROGRESS)
- Phase 2: Stats tagging
- Phase 3: Highlights and sharing

<h3>Phase 1 Progress (Updated 2026-02-05)</h3>
- [x] Basic project structure
- [x] Camera preview working
- [x] Floating Ubiquiti-style controls with score buttons (+1, +2, +3)
- [x] Running game clock with play/pause
- [x] Save to Photos functionality
- [x] ScoreTimelineTracker - records score snapshots with timestamps
- [x] OverlayCompositor - burns score overlay into video post-recording
- [x] Integration complete: RecordingView -> ScoreTimelineTracker -> OverlayCompositor -> GameSummaryView
- [x] Fixed timing issue: wait for video file to finish writing before processing
- [x] **4K video recording support** (now default)
- [x] Broadcast-style overlay design (blue home, red/orange away, dark score boxes)
- [x] Landscape rotation handling for video composition
- [x] iOS 26 UIScreen.main deprecation fix
- [x] **Skynet v4.1 Migration Complete**: Momentum Minds + Golden Smoothing integrated into Product.
- [ ] Physical device testing with gimbal

<h3>4K Record / SD AI Architecture</h3>

We use a "Smart Asymmetry" approach to balance quality and performance:
- **Recording**: 4K (3840x2160) for maximum memory quality.
- **AI Processing**: SD (640x360) for maximum intelligence.
- **Benefits**:
    - **Higher Detection Rates**: Vision API performs better on standardized lower resolutions (prevents kids looking "too small" or "too sharp").
    - **Thermal Efficiency**: Processing 90% fewer pixels in the AI path keeps the phone cooler and saves battery.
    - **Real-time Performance**: Ensures 60fps recording isn't interrupted by heavy ML tasks.

<h3>Experimental Filters (Phase 2 R&D - SANDBOX ONLY)</h3>

Researching advanced filters to further enhance "broadcast feel" beyond simple smoothing.

**1. Predictive Lead Tracker ("The Cameraman Algorithm")**
- **Concept**: Real cameramen "lead" the action rather than centering it. If a player drives right, the camera aims ahead of them.
- **Algorithm**: Linear regression on recent centroid positions to project target at `t + 0.4s`.
- **Status**: Implemented in `SkynetVideoTest.swift` (sandbox).

**2. Scene Activity Monitor (Context Awareness)**
- **Concept**: Detect "Game Energy" to differentiate Fast Breaks (high energy) from Timeouts (zero energy).
- **Algorithm**: Tracks magnitude of centroid velocity / optical flow over 1-second window.
- **Status**: Implemented in `SkynetVideoTest.swift` (sandbox).

---

<h2>Technical Details</h2>

<h3>Video Recording (RecordingManager.swift)</h3>
- Uses AVCaptureSession with AVCaptureVideoDataOutput + AVAssetWriter
- **New Default: 4K (3840x2160)** for maximum quality
- Real-time burned-in scoreboard overlay
- Async `stopRecordingAndWait()` ensures file is fully written before processing

<h3>Video Orientation Handling (ScoreCam Pattern)</h3>
**Key insight**: Record the video in the correct orientation from the start, then the compositor doesn't need to transform.

**RecordingManager.swift** uses `UIWindowScene.interfaceOrientation` to set `videoRotationAngle` on the connection BEFORE recording:
- Landscape Left (Home RIGHT): 180°
- Landscape Right (Home LEFT): 0°
- Portrait: 90°

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

<h3>Data Flow for AI Tracking</h3>
1. **RecordingManager** captures 4K frames.
2. **Downscaler** resizes AI-path frames to 640x360 (SD).
3. **AutoZoomManager** receives SD frames and runs Vision.
4. **PersonClassifier** identifies players using Momentum-Weighted Attention.
5. **AutoZoomManager** calculates crop/zoom and updates Camera zoom.

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
- **Long press clock** → End Game.
- **Swipe UP** → View Individual Stats.

---

<h2>YouTube Upload (Lean Implementation)</h2>
- **Immediate Upload**: No WiFi queue needed (user has unlimited 5G).
- **Keychain Auth**: Tokens stored locally on device.
- **Auto-Upload**: Game videos automatically upload to Sahil's YouTube channel upon completion.

---

<h2>AI Lab (R&D Complete)</h2>

**Skynet v4.1 (The Golden Hybrid)**:
- **Momentum Attention**: Weight players based on Kalman-filtered velocity (1x-3x, capped). Moving players matter more than stationary sideline noise.
- **Proximity Damping**: Slow down panning when subjects are close to lens.
- **Timeout Awareness**: When 60%+ of players have `boundingBox.midX < 0.15 || > 0.85`, zoom out to 1.0x automatically.
- **Standardized Vision**: AI receives 640x360 downscaled frames for consistent detection across 4K/1080p recording.
- **Warmup Calibration**: Camera + Skynet start during warmup (no video recording). Learns court bounds, player sizes, ref detection. When game clock starts, tracking momentum resets but learned calibration is preserved.

**Warmup → Game Transition:**
```
Landscape entry → Camera session + Skynet learning (hasCameraStarted = true)
  → PersonClassifier learns: court bounds, baseline kid height, ref stripe patterns
  → DeepTracker builds: initial track IDs, confidence baselines

Clock tap → Video recording starts (hasGameStarted = true)
  → AutoZoomManager.resetTrackingState() called
  → Resets: DeepTracker tracks, zoom, action center, momentum
  → KEEPS: court bounds, kid height baseline, height statistics
```

**Validated on physical footage**: `IMG_7205.mov` (stationary) and XBotGo moving footage.
- **Person detection rate**: ~90% on stationary, ~50% on moving SD.
- **Ball detection rate**: ~10-40% (floor reflections remain a challenge).
