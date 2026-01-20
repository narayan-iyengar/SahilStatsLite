# SahilStatsLite

A basketball game recording app with real-time scoreboard overlay, similar to ScoreCam.

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
| `Models/FirebaseGame.swift` | Field mapping between Lite and main app |
| `Views/UltraMinimalRecordingView.swift` | Recording UI with tap-to-score |
| `Views/GameSummaryView.swift` | Post-game summary with auto-save to Photos |
| `Views/AuthView.swift` | Sign-in screen and profile management |
| `Models/Game.swift` | Game data model with PlayerStats |
| `Models/AppState.swift` | App navigation and state management |

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

## Firebase Integration

Syncs games with the main SahilStats app's Firebase database (`sahil-stats-tracker`).

### Authentication
- Google Sign-In (matches main SahilStats app)
- Profile button in HomeView header shows auth status
- Cloud sync icon shows sync status (green = synced, orange = syncing, red = error)

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

## Gimbal Auto-Tracking

Uses Apple's **DockKit** framework (iOS 18+) for smart gimbal integration:

- **What it tracks**: People/subjects detected by camera
- **Region of interest**: Court area (90% width, 75% height centered)
- **Auto-zoom**: Adjusts based on subject count (1-2 people = 2x, 3-4 = 1.5x, 5+ = 1x)
- **Compatible with**: Insta360 Flow 2 Pro and other DockKit gimbals
- **File**: `Services/GimbalTrackingManager.swift`

## Future Features (TODO)

### Settings Page (from Home Screen)
- [ ] Team name and abbreviation
- [ ] Team logo/image
- [ ] Team colors (for overlay color bars)
- [ ] Default half length
- [ ] Player name (currently hardcoded as "Sahil")
- [ ] Player birthday (currently hardcoded as Nov 1, 2016)

### Integrations
- [ ] **Calendar** - Sync games with calendar, schedule reminders
- [x] **Firebase** - Cloud backup of games and stats (two-way sync with main app)
- [ ] **YouTube** - Direct upload of game videos
- [ ] **Zoom** - Live streaming integration

### Home Screen Enhancements
- [x] Quick access to career stats from home (Career Stats card + sheet)
- [x] Stats dashboard / charts (age-based trend charts for PPG, RPG, Defense)
- [x] Clickable games with detail view (tap any game to see full stats)
- [x] View All Games with pagination and filtering (All/Wins/Losses + search)
- [ ] Season filtering for stats

### Gimbal / Recording
- [ ] Test with actual Insta360 Flow 2 Pro hardware
- [ ] Manual zoom controls
- [ ] Audio level monitoring
