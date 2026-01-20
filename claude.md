# SahilStatsLite

A focused basketball game recording app with real-time scoreboard overlay.

## Design Principles

- **Keep it Lite** - Simpler than main app, faster to start recording
- **No duplicate code** - One component for each purpose (e.g., GameRow used everywhere)
- **Single entry points** - One place for settings, one place for game browsing
- **Resist scope creep** - If main app does it better, don't add it here

## Architecture

### Real-time Overlay System
The app uses a "what you see is what you get" approach where the scoreboard overlay is burned into the video in real-time during recording:

1. **RecordingManager** (`Services/RecordingManager.swift`)
   - Uses `AVCaptureVideoDataOutput` + `AVAssetWriter` for frame-by-frame processing
   - Captures video frames, applies overlay via `OverlayRenderer`, then writes to file
   - Handles video orientation based on device orientation when recording starts
   - Key properties marked `nonisolated(unsafe)` for background queue access
   - Recording starts automatically when entering landscape mode (pre-game footage)

2. **OverlayRenderer** (`Services/OverlayRenderer.swift`)
   - Draws NBA-style corner scorebug (bottom-right) directly onto CVPixelBuffer
   - Two-row layout: home team (top), away team (bottom) with color bars
   - Shows period (1st Half, 2nd Half, OT) and game clock
   - Clock color changes: white (running), orange (paused), red (last minute)
   - Uses Core Graphics with UIKit coordinate system (flipped at start)
   - Scales overlay based on video dimensions for consistent sizing

3. **UltraMinimalRecordingView** (`Views/UltraMinimalRecordingView.swift`)
   - Full-screen tap-to-score: left half = my team, right half = opponent
   - Multi-tap detection: 1 tap = +1, 2 taps = +2, 3 taps = +3
   - Visual feedback shows +1/+2/+3 that fades away
   - Bottom scoreboard is display-only (clock tap for pause/play)
   - Stats overlay accessible via person icon (top-right)
   - Requires landscape orientation for recording

4. **GamePersistenceManager** (`Services/GamePersistenceManager.swift`)
   - Saves/loads games as JSON to Documents/games.json
   - Tracks career stats (PPG, RPG, APG, shooting percentages)
   - Win/loss record tracking
   - Firebase sync: auto-syncs when signed in

5. **FirebaseService** (`Services/FirebaseService.swift`)
   - Real-time Firestore listener for games collection
   - CRUD operations with field mapping to main app schema
   - Uses `FirebaseGame` model for field name translation

6. **AuthService** (`Services/AuthService.swift`)
   - Firebase Authentication with Google Sign-In (matching main app)
   - Auth state listener for automatic sync setup

### Video Orientation
- Video rotation configured via `AVCaptureConnection.videoRotationAngle`
- Rotation configured BEFORE enabling frame capture (fixes pre-game footage orientation)
- landscapeLeft (volume down) → 0°, landscapeRight (volume up) → 180°

### Home Screen Layout
- **Settings gear** (top-left) - Opens SettingsView with account/sync status
- **New Game button** - Start recording a new game
- **Career Stats card** - Quick stats overview, tap for detailed career stats
- **Game Log card** - Opens AllGamesView with filters and pagination
- **Calendar month view** - Full month calendar with game days highlighted, tap day to see games

### Game Flow
1. **GameSetupView** - Enter team names, opponent, half length
2. **UltraMinimalRecordingView** - Record game with tap-to-score (recording starts on landscape)
3. **GameSummaryView** - Auto-saves video to Photos, shows player stats summary

### Player Stats Tracking
- Shooting: 2PT, 3PT, FT (made/attempted with percentages)
- Advanced: FG%, eFG%, TS%
- Other: assists, rebounds, steals, blocks, turnovers, fouls

## Key Files

| File | Purpose |
|------|---------|
| `Services/RecordingManager.swift` | Video capture, frame processing, AVAssetWriter |
| `Services/OverlayRenderer.swift` | NBA-style corner scorebug rendering |
| `Services/GamePersistenceManager.swift` | Game save/load, career stats, Firebase sync |
| `Services/FirebaseService.swift` | Firestore CRUD with real-time listener |
| `Services/AuthService.swift` | Firebase Auth with Google Sign-In |
| `Services/GameCalendarManager.swift` | iOS Calendar integration for upcoming games |
| `Models/FirebaseGame.swift` | Field mapping between Lite and main app |
| `Models/Game.swift` | Game data model with PlayerStats |
| `Models/AppState.swift` | App navigation and state management |

### Views (HomeView.swift contains most UI)

| Component | Purpose |
|-----------|---------|
| `HomeView` | Main screen with cards for stats, game log, calendar |
| `SettingsView` | Team name, calendar selection, account/sync status, sign in/out |
| `CareerStatsSheet` | Stats only: averages, trends, shooting charts |
| `AllGamesView` | Game browsing with filters, search, pagination |
| `GameDetailSheet` | Single game stats detail view |
| `GameRow` | Reusable game list row (used everywhere) |
| `CalendarMonthView` | iOS-native month calendar with game day indicators |
| `DayGamesSheet` | Sheet showing games on selected calendar day |
| `UltraMinimalRecordingView` | Recording UI with tap-to-score |
| `GameSummaryView` | Post-game summary with auto-save to Photos |

## Technical Notes

- **Player Birthday**: November 1, 2016 (used for age-based stat trending)
- **Swift Concurrency**: Uses `nonisolated(unsafe)` for properties accessed from video processing queue
- **Lazy Asset Writer Setup**: Writer configured on first frame to capture actual dimensions
- **Coordinate System**: OverlayRenderer flips CGContext to UIKit coords at start for simpler drawing
- **Half-based Timing**: Uses halves (not quarters) for AAU basketball games
- **Clock Speed**: Normal = 1 second intervals, last minute = 2x speed (decrements by 2)
- **Pre-game Footage**: Recording starts when entering landscape, overlay shows initial state (18:00 paused)

## Build Requirements
- iOS 17.0+
- Physical device required for camera recording (simulator shows placeholder)
- **GoogleService-Info.plist** - Download from Firebase Console (not in repo for security)
  - See `GoogleService-Info.plist.template` for required structure
  - Place in `SahilStatsLite/` directory
- **GoogleSignIn-iOS** package - Add via Xcode: File > Add Package Dependencies
  - URL: `https://github.com/google/GoogleSignIn-iOS`

## Firebase Integration

Syncs games with the main SahilStats app's Firebase database (`sahil-stats-tracker`).

### Authentication
- Google Sign-In (matches main SahilStats app)
- Settings gear (top-left) opens SettingsView with account management
- Gear icon badge shows sync status (green = synced, orange = syncing, red = error)

### Data Sync
- **Two-way sync**: Games created in Lite appear in main app and vice versa
- **Real-time listener**: Changes sync automatically when signed in
- **Offline support**: Local JSON storage works without sign-in
- **Field mapping**: `FirebaseGame` model translates between schemas

### Field Name Mapping (Lite ↔ Firebase/Main)
| Lite Field | Firebase Field |
|------------|----------------|
| `myScore` | `myTeamScore` |
| `opponentScore` | `opponentScore` |
| `fg2Made` | `fg2m` |
| `fg2Attempted` | `fg2a` |
| `fg3Made` | `fg3m` |
| `fg3Attempted` | `fg3a` |
| `ftMade` | `ftm` |
| `ftAttempted` | `fta` |
| `date` | `timestamp` |

## Gimbal Auto-Tracking (Optional)

DockKit framework (iOS 18+) support in `Services/GimbalTrackingManager.swift` for smart gimbals like Insta360 Flow 2 Pro. Auto-tracks subjects and adjusts zoom.

## Future Features (TODO)

### Integrations
- [x] **Calendar** - iOS Calendar integration with full month view
  - Parses "vs Team" or "@ Team" from event titles
  - Select which calendars to integrate (filter work calendars in Settings)
  - Days with games shown bold with orange dot
  - Tap day → shows list of games → tap game → pre-fills GameSetupView
- [x] **Firebase** - Cloud backup of games and stats (two-way sync with main app)

### Completed Features
- [x] Career Stats card with trend charts (age-based PPG, RPG, shooting, etc.)
- [x] Game Log with filtering (All/Wins/Losses), search, and pagination
- [x] Game detail view with full stats
- [x] Unified Settings (account + sync in one place)
- [x] Calendar integration with month view and selectable calendars
- [x] Team name setting (stored in UserDefaults, pre-fills GameSetupView)

### Future Enhancements (if needed)
- [ ] Season filtering for stats
- [ ] Team colors/logo customization
- [ ] Player profile settings (name, birthday)
