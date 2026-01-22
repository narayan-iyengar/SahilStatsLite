# Sahil Stats - Project Context

> **UPDATED (2026-01-21):** Watch app working, YouTube upload added (lean ~200 lines), WYSIWYG overlays (SwiftUI matches video), blinking colon when paused, 4-char team names, OT fixed.

---

## Team Roles

**Narayan (Product Manager / End User)**
- Father of Sahil, a 3rd grader on AAU basketball teams
- Owns Insta360 Flow Pro 2 gimbal and DJI Osmo Mobile 7P
- Wants to record games and track stats for Sahil
- Decision maker on features and UX

**Claude (Software Developer / Architect / Designer)**
- World-class developer, UX designer, user researcher, and all-around genius
- Channels Jony Ive for interface design: simplicity, clarity, generous touch targets
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
- Tap score zones to add +1 point per tap
- Real-time clock sync (every 1 second)
- End game directly from Watch (saves without phone confirmation)
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
- **Recording device**: iPhone (on gimbal)
- **Gimbal**: Insta360 Flow Pro 2 (DockKit compatible)
- **Backup gimbal**: DJI Osmo Mobile 7P (not DockKit, future consideration)

---

## Current Status
- Existing app: 100 files, 40k lines (too complex) - in `/SahilStats/SahilStats/`
- New app: ~20 files, ~3,700 lines - in `/SahilStats/SahilStatsLite/`
- Phase 1: Recording + auto-tracking + score overlay (IN PROGRESS)
- Phase 2: Stats tagging
- Phase 3: Highlights and sharing

### Phase 1 Progress (Updated 2025-01-15)
- [x] Basic project structure
- [x] Camera preview working
- [x] Floating Ubiquiti-style controls with score buttons (+1, +2, +3)
- [x] Running game clock with play/pause
- [x] Save to Photos functionality
- [x] ScoreTimelineTracker - records score snapshots with timestamps
- [x] OverlayCompositor - burns score overlay into video post-recording
- [x] Integration complete: RecordingView -> ScoreTimelineTracker -> OverlayCompositor -> GameSummaryView
- [x] Fixed timing issue: wait for video file to finish writing before processing
- [x] 4K video recording support (falls back to 1080p/720p if unavailable)
- [x] Broadcast-style overlay design (blue home, red/orange away, dark score boxes)
- [x] Landscape rotation handling for video composition
- [x] iOS 26 UIScreen.main deprecation fix
- [ ] Auto expand/collapse floating control bar
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

```
SahilStatsLite/
├── SahilStatsLiteApp.swift           # App entry point + AppState
├── Models/
│   └── Game.swift                    # Game, ScoreEvent models
├── Views/
│   ├── HomeView.swift                # Home screen with game list + Career Stats
│   ├── GameSetupView.swift           # Quick opponent entry
│   ├── RecordingView.swift           # Full-screen recording with floating controls
│   ├── UltraMinimalRecordingView.swift # Simplified recording UI
│   └── GameSummaryView.swift         # Post-game summary + video processing
├── Services/
│   ├── RecordingManager.swift        # AVFoundation video capture (4K support)
│   ├── GimbalTrackingManager.swift   # DockKit integration
│   ├── GameCalendarManager.swift     # Calendar integration
│   ├── ScoreTimelineTracker.swift    # Tracks score/clock during recording
│   ├── OverlayCompositor.swift       # Burns overlay into video post-recording
│   ├── WatchConnectivityService.swift # iPhone-side Watch communication
│   └── YouTubeService.swift          # YouTube auth + upload (~200 lines)
├── Resources/
│   └── Info.plist                    # Privacy descriptions
└── SahilStatsLiteWatch Watch App/    # Apple Watch companion
    ├── SahilStatsLiteWatchApp.swift  # Watch app entry point
    ├── WatchContentView.swift        # Main navigation
    ├── WatchScoringView.swift        # Remote score controls
    ├── WatchStatsView.swift          # Stats display
    └── WatchConnectivityClient.swift # Watch-side communication
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
3. **Gimbal tracking** - DockKit integration needs real-world testing
4. **YouTube upload testing** - Test OAuth flow and actual upload to YouTube
5. ~~**Watch app requires paid account**~~ - RESOLVED
6. ~~**Auto expand/collapse floating bar**~~ - Not needed with Watch as primary input

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
The Watch app allows Narayan to control scoring from his wrist while the iPhone records on the gimbal. This is the key UX improvement - hands-free recording with remote score control.

### Watch App Structure
```
SahilStatsLite/SahilStatsLite/SahilStatsLiteWatch Watch App/
├── SahilStatsLiteWatchApp.swift    # Watch app entry point
├── WatchContentView.swift          # Main navigation view
├── WatchScoringView.swift          # Score buttons (+1, +2, +3)
├── WatchStatsView.swift            # Stats display
├── WatchConnectivityClient.swift   # Watch-side WCSession handling
└── Assets.xcassets/                # Watch app icons
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
18. **Smart opponent detection**: Calendar events now auto-detect opponent by recognizing Sahil's team names (Uneqld, Lava, Elements). No need for "vs" prefix.
19. **iOS Calendar-style day view**: Tapping a date now navigates (push transition) to a day detail view instead of showing a popup sheet. Large date number header like Apple Calendar.

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
Auto-uploads game videos to YouTube (unlisted) for building a portfolio and easy sharing with coaches.

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
5. Videos uploaded as **unlisted** (not public)

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
