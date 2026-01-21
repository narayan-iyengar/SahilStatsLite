//
//  UltraMinimalRecordingView.swift
//  SahilStatsLite
//
//  Ultra-minimal recording view with real camera integration
//  Single scoreboard, tap-to-score, stats overlay, game persistence
//

import SwiftUI
import AVFoundation
import Combine
import Photos

struct UltraMinimalRecordingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var gimbalManager = GimbalTrackingManager.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @ObservedObject private var watchService = WatchConnectivityService.shared

    // Game state
    @State private var myScore: Int = 0
    @State private var opponentScore: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var period: String = "1st Half"
    @State private var isClockRunning: Bool = false

    // Player stats (Sahil)
    @State private var playerStats = PlayerStats()

    // Shooting stats for UI (mirrors playerStats)
    @State private var fg2Made: Int = 0
    @State private var fg2Att: Int = 0
    @State private var fg3Made: Int = 0
    @State private var fg3Att: Int = 0
    @State private var ftMade: Int = 0
    @State private var ftAtt: Int = 0

    // Timer
    @State private var timer: AnyCancellable?

    // Tap-to-score
    @State private var myTapCount: Int = 0
    @State private var oppTapCount: Int = 0
    @State private var myTapTimer: AnyCancellable?
    @State private var oppTapTimer: AnyCancellable?

    // UI state
    @State private var showSahilStats: Bool = false
    @State private var showEndConfirmation: Bool = false
    @State private var isFinishingRecording: Bool = false
    @State private var isPortrait: Bool = true
    @State private var hasStartedRecording: Bool = false
    @State private var isPulsing: Bool = false

    // Computed
    private var halfLength: Int {
        appState.currentGame?.halfLength ?? 18
    }

    private var clockTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var sahilPoints: Int {
        (fg2Made * 2) + (fg3Made * 3) + ftMade
    }

    private var isCrunchTime: Bool {
        remainingSeconds < 60 && remainingSeconds > 0
    }

    private var timerInterval: TimeInterval {
        1.0  // Always 1-second updates for smooth video overlay
    }

    // Shooting percentages
    private var fgPct: Double {
        let att = fg2Att + fg3Att
        let made = fg2Made + fg3Made
        return att > 0 ? Double(made) / Double(att) * 100 : 0
    }

    private var fg3Pct: Double {
        fg3Att > 0 ? Double(fg3Made) / Double(fg3Att) * 100 : 0
    }

    private var ftPct: Double {
        ftAtt > 0 ? Double(ftMade) / Double(ftAtt) * 100 : 0
    }

    private var efgPct: Double {
        let att = fg2Att + fg3Att
        let made = fg2Made + fg3Made
        return att > 0 ? (Double(made) + 0.5 * Double(fg3Made)) / Double(att) * 100 : 0
    }

    private var tsPct: Double {
        let fga = fg2Att + fg3Att
        let denominator = 2 * (Double(fga) + 0.44 * Double(ftAtt))
        return denominator > 0 ? Double(sahilPoints) / denominator * 100 : 0
    }

    var body: some View {
        ZStack {
            // Full screen camera
            cameraPreview

            // Top bar: REC dot (left) + Menu icon (right)
            VStack {
                HStack {
                    recIndicator
                        .padding(.leading, 20)

                    Spacer()

                    // Stats button - frosted glass style for visibility against any background
                    Button(action: { showSahilStats = true }) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            )
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 12)
                Spacer()
            }

            // Smart Scoreboard at bottom (only in landscape, or always in stats-only/simulator)
            if !isPortrait || recordingManager.isSimulator || appState.isStatsOnly {
                VStack {
                    Spacer()
                    smartScoreboard
                        .padding(.horizontal, 50)
                        .padding(.bottom, 20)
                }
            }

            // Full-screen tap areas for scoring (left = my team, right = opponent)
            if !isPortrait || recordingManager.isSimulator || appState.isStatsOnly {
                HStack(spacing: 0) {
                    // Left half - My team tap area
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { handleMyTeamTap() }

                    // Right half - Opponent tap area
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { handleOpponentTap() }
                }
                .padding(.top, 60)     // Leave room for top bar (REC + menu)
                .padding(.bottom, 100) // Leave room for scoreboard
            }

            // Tap feedback overlays (centered in each half)
            HStack {
                if myTapCount > 0 {
                    tapFeedback(count: myTapCount, color: .orange)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if oppTapCount > 0 {
                    tapFeedback(count: oppTapCount, color: .blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 60)
            .animation(.spring(response: 0.2), value: myTapCount)
            .animation(.spring(response: 0.2), value: oppTapCount)

            // Stats overlay
            if showSahilStats {
                sahilStatsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // End game confirmation
            if showEndConfirmation {
                endGameConfirmation
            }

            // Rotate to landscape prompt (not needed for stats-only mode)
            if isPortrait && !recordingManager.isSimulator && !appState.isStatsOnly {
                rotatePromptOverlay
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientationState()
        }
        .task {
            initializeGameState()
            updateOrientationState()

            // Only setup camera if recording video
            if !appState.isStatsOnly {
                recordingManager.reset()
                updateOverlayState()
                await recordingManager.requestPermissionsAndSetup()

                // If already in landscape when camera is ready, start recording
                if !isPortrait && !hasStartedRecording && recordingManager.isSessionReady && !recordingManager.isSimulator {
                    debugPrint("📹 Starting recording (already in landscape)")
                    hasStartedRecording = true
                    updateOverlayState()
                    recordingManager.startRecording()
                    gimbalManager.startTracking()
                }
            }
        }
        .onDisappear {
            if !appState.isStatsOnly {
                stopRecording()
                recordingManager.stopSession()
            }
        }
        .animation(.spring(response: 0.3), value: showSahilStats)
    }

    // MARK: - Initialize Game State

    private func initializeGameState() {
        remainingSeconds = halfLength * 60
        setupWatchCallbacks()
        sendGameStateToWatch()
    }

    // MARK: - Watch Connectivity

    private func setupWatchCallbacks() {
        // Handle score updates from watch
        watchService.onScoreUpdate = { [self] team, points in
            if team == "my" {
                myScore += points
            } else {
                opponentScore += points
            }
            updateOverlayState()
            sendScoreToWatch()
        }

        // Handle clock toggle from watch
        watchService.onClockToggle = { [self] in
            toggleClock()
        }

        // Handle period advance from watch
        watchService.onPeriodAdvance = { [self] in
            advancePeriod()
        }

        // Handle stat updates from watch
        watchService.onStatUpdate = { [self] statType, value in
            switch statType {
            case "fg2Made":
                fg2Made += value
                myScore += 2
            case "fg2Att": fg2Att += value
            case "fg3Made":
                fg3Made += value
                myScore += 3
            case "fg3Att": fg3Att += value
            case "ftMade":
                ftMade += value
                myScore += 1
            case "ftAtt": ftAtt += value
            case "assists": playerStats.assists += value
            case "rebounds": playerStats.rebounds += value
            case "steals": playerStats.steals += value
            case "blocks": playerStats.blocks += value
            case "turnovers": playerStats.turnovers += value
            default: break
            }
            updateOverlayState()
            sendScoreToWatch()
        }

        // Handle end game from watch - end and save directly
        watchService.onEndGame = { [self] in
            endGame()
        }
    }

    private func sendGameStateToWatch() {
        let periodNames = ["1st Half", "2nd Half", "OT", "OT2", "OT3"]
        let periodIdx = periodNames.firstIndex(of: period) ?? 0

        watchService.sendGameState(
            teamName: appState.currentGame?.teamName ?? "Home",
            opponent: appState.currentGame?.opponent ?? "Away",
            myScore: myScore,
            oppScore: opponentScore,
            remainingSeconds: remainingSeconds,
            isClockRunning: isClockRunning,
            period: period,
            periodIndex: periodIdx
        )
    }

    private func sendScoreToWatch() {
        watchService.sendScoreUpdate(myScore: myScore, oppScore: opponentScore)
    }

    private func sendClockToWatch() {
        watchService.sendClockUpdate(remainingSeconds: remainingSeconds, isRunning: isClockRunning)
    }

    private func sendPeriodToWatch() {
        let periodNames = ["1st Half", "2nd Half", "OT", "OT2", "OT3"]
        let periodIdx = periodNames.firstIndex(of: period) ?? 0
        watchService.sendPeriodUpdate(period: period, periodIndex: periodIdx, remainingSeconds: remainingSeconds)
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreview: some View {
        if appState.isStatsOnly {
            // Stats-only mode - no camera, just a nice background
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange.opacity(0.3))
                    Text("Live Stats")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.3))
                }
            )
        } else if recordingManager.isSimulator {
            LinearGradient(
                colors: [Color(white: 0.92), Color(white: 0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    Text("Simulator Mode")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.primary)
            )
        } else if recordingManager.isSessionReady, let session = recordingManager.captureSession {
            CameraPreviewView(session: session)
                .ignoresSafeArea()
        } else {
            Color.black
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Starting camera...")
                            .foregroundColor(.white)
                    }
                )
        }
    }

    // MARK: - REC Indicator

    private var recIndicator: some View {
        Group {
            if appState.isStatsOnly {
                // Stats-only mode indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(isClockRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isClockRunning ? .green : .orange)
                }
            } else if isClockRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
            } else {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Smart Scoreboard

    private var smartScoreboard: some View {
        HStack(spacing: 0) {
            // LEFT: My team (display only - tap on screen to score)
            VStack(spacing: 2) {
                Text((appState.currentGame?.teamName ?? "WLD").prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text("\(myScore)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            // CENTER: Clock (tap to pause/play)
            Button(action: { toggleClock() }) {
                VStack(spacing: 2) {
                    Text(period)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)

                    Text(clockTime)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(clockColor)

                    Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(width: 80)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // RIGHT: Opponent (display only - tap on screen to score)
            VStack(spacing: 2) {
                Text((appState.currentGame?.opponent ?? "OPP").prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                Text("\(opponentScore)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 3)
    }

    private var clockColor: Color {
        if !isClockRunning { return .orange }
        if isCrunchTime { return .red }
        return .primary
    }

    // MARK: - Tap Feedback

    private func tapFeedback(count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("+\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(color)

            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .fill(i <= count ? color : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10)
    }

    // MARK: - Tap Handling

    private func handleMyTeamTap() {
        let newCount = min(myTapCount + 1, 3)
        myTapCount = newCount

        myTapTimer?.cancel()
        myTapTimer = Timer.publish(every: 0.6, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                addScore(points: myTapCount, isMyTeam: true)
                myTapCount = 0
            }
    }

    private func handleOpponentTap() {
        let newCount = min(oppTapCount + 1, 3)
        oppTapCount = newCount

        oppTapTimer?.cancel()
        oppTapTimer = Timer.publish(every: 0.6, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                addScore(points: oppTapCount, isMyTeam: false)
                oppTapCount = 0
            }
    }

    // MARK: - Score Actions

    private func addScore(points: Int, isMyTeam: Bool) {
        if isMyTeam {
            myScore += points
        } else {
            opponentScore += points
        }

        // Log score event
        let event = ScoreEvent(
            timestamp: recordingManager.recordingDuration,
            team: isMyTeam ? .my : .opponent,
            points: points,
            quarter: period == "1st" ? 1 : 2,
            myScoreAfter: myScore,
            opponentScoreAfter: opponentScore
        )
        appState.currentGame?.scoreEvents.append(event)

        updateOverlayState()
        sendScoreToWatch()

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    // MARK: - Clock

    private func toggleClock() {
        debugPrint("🕐 [toggleClock] called - isClockRunning: \(isClockRunning)")

        // Simple toggle - recording is already started when entering landscape
        isClockRunning.toggle()
        if isClockRunning {
            startTimerIfNeeded()
        } else {
            stopTimer()
        }
        updateOverlayState()
        sendClockToWatch()
    }

    private func startTimerIfNeeded() {
        guard isClockRunning, remainingSeconds > 0 else { return }
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.cancel()
        guard isClockRunning, remainingSeconds > 0 else {
            if remainingSeconds == 0 {
                isClockRunning = false
                sendClockToWatch()
            }
            return
        }

        timer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                // Last minute runs 2x faster (2 seconds per real second)
                let decrement = self.remainingSeconds <= 60 ? 2 : 1
                if self.remainingSeconds > decrement {
                    self.remainingSeconds -= decrement
                } else {
                    self.remainingSeconds = 0
                    self.isClockRunning = false
                }
                self.updateOverlayState()

                // Send clock update to watch every second for real-time sync
                self.sendClockToWatch()

                if self.isClockRunning {
                    self.scheduleNextTick()
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Recording

    private func stopRecording() {
        timer?.cancel()
        gimbalManager.stopTracking()
        if recordingManager.isRecording {
            recordingManager.stopRecording()
        }
    }

    private func updateOverlayState() {
        recordingManager.updateOverlay(
            homeTeam: appState.currentGame?.teamName ?? "Home",
            awayTeam: appState.currentGame?.opponent ?? "Away",
            homeScore: myScore,
            awayScore: opponentScore,
            period: period,
            clockTime: clockTime,
            isClockRunning: isClockRunning,
            eventName: ""
        )
    }

    // MARK: - Orientation

    private func updateOrientationState() {
        let orientation = UIDevice.current.orientation
        var newIsPortrait = isPortrait

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            newIsPortrait = false
        case .portrait, .portraitUpsideDown:
            newIsPortrait = true
        default:
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let interfaceOrientation = windowScene.effectiveGeometry.interfaceOrientation
                newIsPortrait = interfaceOrientation.isPortrait
            }
        }

        // Start recording when entering landscape (pre-game footage with initial overlay)
        // Skip if in stats-only mode
        if !newIsPortrait && isPortrait && !hasStartedRecording && !appState.isStatsOnly {
            if recordingManager.isSessionReady && !recordingManager.isSimulator {
                debugPrint("📹 Starting recording on landscape entry")
                hasStartedRecording = true
                updateOverlayState()  // Set initial overlay state (paused clock at full time)
                recordingManager.startRecording()
                gimbalManager.startTracking()
            }
        }

        withAnimation { isPortrait = newIsPortrait }
    }

    // MARK: - Rotate Prompt

    private var rotatePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "rotate.right.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(-90))

                Text("Rotate to Landscape")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Hold your phone horizontally\nto start recording")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - End Game Confirmation

    private var endGameConfirmation: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if isFinishingRecording {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text(appState.isStatsOnly ? "Saving stats..." : "Finishing recording...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Text("End Game?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("\(appState.currentGame?.teamName ?? "Home") \(myScore) - \(opponentScore) \(appState.currentGame?.opponent ?? "Away")")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    HStack(spacing: 20) {
                        Button("Cancel") {
                            showEndConfirmation = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button(appState.isStatsOnly ? "Save Stats" : "End & Save") {
                            endGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private func endGame() {
        isFinishingRecording = true
        timer?.cancel()

        // Notify Watch that game has ended
        watchService.sendEndGame()

        // Sync player stats
        syncPlayerStats()

        // Update game
        appState.currentGame?.myScore = myScore
        appState.currentGame?.opponentScore = opponentScore
        appState.currentGame?.playerStats = playerStats
        appState.currentGame?.completedAt = Date()

        if appState.isStatsOnly {
            // Stats-only mode: just save the game, no video to process
            if let game = appState.currentGame {
                persistenceManager.saveGame(game)
            }
            isFinishingRecording = false
            appState.isStatsOnly = false  // Reset for next game
            appState.goHome()
        } else {
            // Recording mode: stop recording and save
            gimbalManager.stopTracking()

            Task {
                let videoURL = await recordingManager.stopRecordingAndWait()

                await MainActor.run {
                    // Save to persistence
                    if let game = appState.currentGame {
                        persistenceManager.saveGame(game)
                    }

                    // Auto-save video to Photos
                    if let url = videoURL {
                        saveVideoToPhotos(url: url)
                    }

                    isFinishingRecording = false
                    appState.goHome()
                }
            }
        }
    }

    private func saveVideoToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                debugPrint("📹 Photo library access denied")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    debugPrint("📹 Video saved to Photos")
                } else if let error = error {
                    debugPrint("📹 Failed to save video: \(error.localizedDescription)")
                }
            }
        }
    }

    private func syncPlayerStats() {
        playerStats.fg2Made = fg2Made
        playerStats.fg2Attempted = fg2Att
        playerStats.fg3Made = fg3Made
        playerStats.fg3Attempted = fg3Att
        playerStats.ftMade = ftMade
        playerStats.ftAttempted = ftAtt
    }

    // MARK: - Stats Overlay

    private var sahilStatsOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showSahilStats = false }

            VStack(spacing: 14) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.orange)
                        Text("Sahil")
                            .font(.system(size: 18, weight: .bold))
                    }

                    Spacer()

                    Text("\(sahilPoints) pts")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.orange)

                    Spacer()

                    Button(action: { showSahilStats = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Shooting stats
                HStack(spacing: 12) {
                    shootingTile("2PT", made: $fg2Made, att: $fg2Att, pts: 2, color: .blue)
                    shootingTile("3PT", made: $fg3Made, att: $fg3Att, pts: 3, color: .purple)
                    shootingTile("FT", made: $ftMade, att: $ftAtt, pts: 1, color: .cyan)
                }

                // Other stats
                HStack(spacing: 8) {
                    statTile("AST", $playerStats.assists, .green)
                    statTile("REB", $playerStats.rebounds, .orange)
                    statTile("STL", $playerStats.steals, .teal)
                    statTile("BLK", $playerStats.blocks, .indigo)
                    statTile("TO", $playerStats.turnovers, .red)
                    statTile("PF", $playerStats.fouls, .gray)
                }

                Divider()

                // Game Controls
                HStack(spacing: 10) {
                    // Next Period
                    Button(action: { advancePeriod() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                            Text(nextPeriodLabel)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }

                    // Add Time (Overtime)
                    Button(action: { addOvertime() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("+1:00 OT")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(10)
                    }

                    // End Game
                    Button(action: {
                        showSahilStats = false
                        showEndConfirmation = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16))
                            Text("End")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 5)
            .padding(.horizontal, 40)
        }
    }

    private var nextPeriodLabel: String {
        switch period {
        case "1st Half": return "2nd Half"
        case "2nd Half": return "End Game"
        case "OT": return "End Game"
        default: return "Next"
        }
    }

    private func advancePeriod() {
        switch period {
        case "1st Half":
            period = "2nd Half"
            remainingSeconds = halfLength * 60
            isClockRunning = false
            stopTimer()
        case "2nd Half", "OT":
            showSahilStats = false
            showEndConfirmation = true
        default:
            break
        }
        updateOverlayState()
        sendPeriodToWatch()
    }

    private func addOvertime() {
        period = "OT"
        remainingSeconds += 60
        if !isClockRunning {
            isClockRunning = true
            startTimerIfNeeded()
        }
        showSahilStats = false
        updateOverlayState()
        sendPeriodToWatch()
    }

    private func shootingTile(_ label: String, made: Binding<Int>, att: Binding<Int>, pts: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)

            Text("\(made.wrappedValue)/\(att.wrappedValue)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            HStack(spacing: 6) {
                Button(action: {
                    made.wrappedValue += 1
                    att.wrappedValue += 1
                    myScore += pts
                    addScore(points: 0, isMyTeam: true) // Log event (score already added)
                }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color.green)
                        .cornerRadius(6)
                }

                Button(action: { att.wrappedValue += 1 }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private func statTile(_ label: String, _ value: Binding<Int>, _ color: Color) -> some View {
        Button(action: { value.wrappedValue += 1 }) {
            VStack(spacing: 2) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: { if value.wrappedValue > 0 { value.wrappedValue -= 1 } }) {
                Label("Subtract 1", systemImage: "minus")
            }
            Button(action: { value.wrappedValue = 0 }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
    }

}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)

        view.updatePreviewOrientation()

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? CameraPreviewUIView else { return }
        view.previewLayer?.frame = view.bounds
        view.updatePreviewOrientation()
    }
}

class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection else { return }

        let deviceOrientation = UIDevice.current.orientation
        let rotationAngle: CGFloat

        switch deviceOrientation {
        case .portrait:
            rotationAngle = 90
        case .portraitUpsideDown:
            rotationAngle = 270
        case .landscapeLeft:
            rotationAngle = 0
        case .landscapeRight:
            rotationAngle = 180
        default:
            if let windowScene = window?.windowScene {
                switch windowScene.effectiveGeometry.interfaceOrientation {
                case .portrait:
                    rotationAngle = 90
                case .portraitUpsideDown:
                    rotationAngle = 270
                case .landscapeLeft:
                    rotationAngle = 0
                case .landscapeRight:
                    rotationAngle = 180
                default:
                    rotationAngle = 0
                }
            } else {
                rotationAngle = 0
            }
        }

        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
    }
}

#Preview {
    UltraMinimalRecordingView()
        .environmentObject(AppState())
}
