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

2. **OverlayRenderer** (`Services/OverlayRenderer.swift`)
   - Draws ScoreCam-style bottom bar directly onto CVPixelBuffer
   - Uses Core Graphics with UIKit coordinate system (flipped at start)
   - Scales overlay based on video dimensions for consistent sizing

3. **RecordingView** (`Views/RecordingView.swift`)
   - Shows camera preview with SwiftUI scoreboard overlay (mirrors burned-in version)
   - Floating control bar for scoring (+1, +2, +3), clock, and game end
   - Requires landscape orientation for recording

### Video Orientation
- Video rotation configured via `AVCaptureConnection.videoRotationAngle`
- Orientation captured when recording starts based on device orientation
- landscapeLeft (volume down) → 0°, landscapeRight (volume up) → 180°

### Game Flow
1. **GameSetupView** - Enter team names, opponent, half length
2. **RecordingView** - Record game with live scoring controls
3. **GameSummaryView** - View final score, share/save video (already has overlay burned in)

## Key Files

| File | Purpose |
|------|---------|
| `Services/RecordingManager.swift` | Video capture, frame processing, AVAssetWriter |
| `Services/OverlayRenderer.swift` | Real-time scoreboard drawing on frames |
| `Views/RecordingView.swift` | Recording UI with preview + controls |
| `Views/GameSummaryView.swift` | Post-game summary (simplified, no post-processing) |
| `Models/Game.swift` | Game data model with scores, events |
| `Models/AppState.swift` | App navigation and state management |

## Technical Notes

- **Swift Concurrency**: Uses `nonisolated(unsafe)` for properties accessed from video processing queue
- **Lazy Asset Writer Setup**: Writer configured on first frame to capture actual dimensions
- **Coordinate System**: OverlayRenderer flips CGContext to UIKit coords at start for simpler drawing
- **Half-based Timing**: Uses halves (not quarters) for AAU basketball games

## Build Requirements
- iOS 17.0+
- Physical device required for camera recording (simulator shows placeholder)
