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

struct UltraMinimalRecordingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var gimbalManager = GimbalTrackingManager.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared

    // Game state
    @State private var myScore: Int = 0
    @State private var opponentScore: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var period: String = "1st"
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
    @State private var showStatsDashboard: Bool = false
    @State private var selectedGame: Game? = nil
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
        remainingSeconds < 60 ? 1.0 : 10.0
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

    // Career stats from persistence
    private var pastGames: [Game] {
        persistenceManager.savedGames
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

                    // Menu button
                    Button(action: { showSahilStats = true }) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.trailing, 12)
                }
                .padding(.top, 12)
                Spacer()
            }

            // Smart Scoreboard at bottom (only in landscape)
            if !isPortrait || recordingManager.isSimulator {
                VStack {
                    Spacer()
                    smartScoreboard
                        .padding(.horizontal, 50)
                        .padding(.bottom, 20)
                }
            }

            // Tap feedback overlays
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
            .padding(.horizontal, 30)
            .animation(.spring(response: 0.2), value: myTapCount)
            .animation(.spring(response: 0.2), value: oppTapCount)

            // Stats overlay
            if showSahilStats {
                sahilStatsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Stats dashboard
            if showStatsDashboard {
                statsDashboard
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // End game confirmation
            if showEndConfirmation {
                endGameConfirmation
            }

            // Rotate to landscape prompt
            if isPortrait && !recordingManager.isSimulator {
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
            recordingManager.reset()
            updateOverlayState()
            await recordingManager.requestPermissionsAndSetup()

            if !isPortrait && recordingManager.isSessionReady && !recordingManager.isSimulator {
                startRecording()
                hasStartedRecording = true
            }
        }
        .onChange(of: isPortrait) { wasPortrait, nowPortrait in
            if wasPortrait && !nowPortrait && !hasStartedRecording {
                if recordingManager.isSessionReady && !recordingManager.isSimulator {
                    startRecording()
                    hasStartedRecording = true
                }
            }
        }
        .onDisappear {
            stopRecording()
            recordingManager.stopSession()
        }
        .animation(.spring(response: 0.3), value: showSahilStats)
        .animation(.spring(response: 0.3), value: showStatsDashboard)
        .animation(.spring(response: 0.3), value: selectedGame?.id)
    }

    // MARK: - Initialize Game State

    private func initializeGameState() {
        remainingSeconds = halfLength * 60
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreview: some View {
        if recordingManager.isSimulator {
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
            if isClockRunning {
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
            // LEFT: My team (tap to score)
            Button(action: { handleMyTeamTap() }) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // CENTER: Clock (tap to pause)
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

            // RIGHT: Opponent (tap to score)
            Button(action: { handleOpponentTap() }) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    // MARK: - Clock

    private func toggleClock() {
        isClockRunning.toggle()
        if isClockRunning {
            startTimerIfNeeded()
        } else {
            stopTimer()
        }
    }

    private func startTimerIfNeeded() {
        guard isClockRunning, remainingSeconds > 0 else { return }
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.cancel()
        guard isClockRunning, remainingSeconds > 0 else {
            if remainingSeconds == 0 { isClockRunning = false }
            return
        }

        timer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                let decrement = self.remainingSeconds < 60 ? 1 : 10
                if self.remainingSeconds > decrement {
                    self.remainingSeconds -= decrement
                } else {
                    self.remainingSeconds = 0
                    self.isClockRunning = false
                }
                self.updateOverlayState()
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

    private func startRecording() {
        updateOverlayState()
        recordingManager.startRecording()
        gimbalManager.startTracking()
    }

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
            eventName: ""
        )
    }

    // MARK: - Orientation

    private func updateOrientationState() {
        let orientation = UIDevice.current.orientation

        switch orientation {
        case .landscapeLeft, .landscapeRight:
            withAnimation { isPortrait = false }
        case .portrait, .portraitUpsideDown:
            withAnimation { isPortrait = true }
        default:
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let interfaceOrientation = windowScene.effectiveGeometry.interfaceOrientation
                withAnimation { isPortrait = interfaceOrientation.isPortrait }
            }
        }
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

                    Text("Finishing recording...")
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

                        Button("End & Save") {
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
        gimbalManager.stopTracking()

        // Sync player stats
        syncPlayerStats()

        // Update game
        appState.currentGame?.myScore = myScore
        appState.currentGame?.opponentScore = opponentScore
        appState.currentGame?.playerStats = playerStats
        appState.currentGame?.completedAt = Date()

        Task {
            let _ = await recordingManager.stopRecordingAndWait()

            await MainActor.run {
                // Save to persistence
                if let game = appState.currentGame {
                    persistenceManager.saveGame(game)
                }

                isFinishingRecording = false
                appState.endGame()
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
                    // Dashboard
                    Button(action: {
                        showSahilStats = false
                        showStatsDashboard = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 16))
                            Text("Stats")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }

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
        case "1st": return "2nd Half"
        case "2nd": return "End"
        case "OT": return "End"
        default: return "Next"
        }
    }

    private func advancePeriod() {
        switch period {
        case "1st":
            period = "2nd"
            remainingSeconds = halfLength * 60
            isClockRunning = false
            stopTimer()
        case "2nd", "OT":
            showSahilStats = false
            showEndConfirmation = true
        default:
            break
        }
        updateOverlayState()
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

    // MARK: - Stats Dashboard

    private var statsDashboard: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showStatsDashboard = false }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        showStatsDashboard = false
                        showSahilStats = true
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    Text("Game Stats")
                        .font(.system(size: 18, weight: .bold))

                    Spacer()

                    Button(action: { showStatsDashboard = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Content
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // Today's points
                        dashboardCard {
                            VStack(spacing: 10) {
                                Text("TODAY")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                Text("\(sahilPoints)")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)

                                Text("POINTS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Today's shooting
                        dashboardCard {
                            VStack(spacing: 8) {
                                Text("SHOOTING")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 10) {
                                    shootingCircle("FG", pct: fgPct, color: .blue)
                                    shootingCircle("3PT", pct: fg3Pct, color: .purple)
                                    shootingCircle("FT", pct: ftPct, color: .cyan)
                                }
                            }
                        }

                        // Career averages
                        if pastGames.count > 0 {
                            dashboardCard {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("CAREER AVG")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(persistenceManager.careerGames) games")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 8) {
                                        careerAvgItem("PPG", value: persistenceManager.careerPPG, color: .orange)
                                        careerAvgItem("RPG", value: persistenceManager.careerRPG, color: .blue)
                                        careerAvgItem("APG", value: persistenceManager.careerAPG, color: .green)
                                    }

                                    Text("W-L: \(persistenceManager.careerRecord)")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }

                            // Game log
                            VStack(spacing: 6) {
                                HStack {
                                    Text("GAME LOG")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(pastGames.count) games")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(spacing: 4) {
                                        ForEach(pastGames) { game in
                                            Button(action: { selectedGame = game }) {
                                                gameLogRow(game)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(maxHeight: 140)
                            }
                            .frame(width: 180)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // Game detail overlay
                if let game = selectedGame {
                    gameDetailOverlay(game)
                }
            }
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 5)
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
        }
    }

    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 180)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(14)
    }

    private func shootingCircle(_ label: String, pct: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 44, height: 44)

                Circle()
                    .trim(from: 0, to: min(pct / 100, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f", pct))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private func careerAvgItem(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", value))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func gameLogRow(_ game: Game) -> some View {
        HStack(spacing: 8) {
            Text(game.resultString)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(game.isWin ? Color.green : (game.isLoss ? Color.red : Color.orange))
                .cornerRadius(4)

            Text(game.opponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text(game.scoreString)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    private func gameDetailOverlay(_ game: Game) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { selectedGame = nil }

            VStack(spacing: 12) {
                HStack {
                    Button(action: { selectedGame = nil }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("vs \(game.opponent)")
                            .font(.system(size: 16, weight: .bold))
                        Text(game.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { selectedGame = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Text(game.resultString)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(game.isWin ? .green : (game.isLoss ? .red : .orange))

                    Text(game.scoreString)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }

                Divider()

                Text("Sahil: \(game.playerStats.points) pts")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)

                HStack(spacing: 12) {
                    gameDetailStat("REB", value: game.playerStats.rebounds, color: .blue)
                    gameDetailStat("AST", value: game.playerStats.assists, color: .green)
                    gameDetailStat("STL", value: game.playerStats.steals, color: .teal)
                    gameDetailStat("BLK", value: game.playerStats.blocks, color: .indigo)
                }
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.15), radius: 15, y: 5)
            .frame(width: 320)
        }
    }

    private func gameDetailStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    UltraMinimalRecordingView()
        .environmentObject(AppState())
}
