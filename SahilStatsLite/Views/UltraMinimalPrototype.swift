//
//  UltraMinimalPrototype.swift
//  SahilStatsLite
//
//  Ultra-minimal: ONE scoreboard element does everything
//  Tap left = my team, Tap right = opponent, Tap center = pause
//  Long-press = Sahil's stats
//

import SwiftUI
import Combine

struct UltraMinimalPrototype: View {
    // Game state
    @State private var myScore: Int = 12
    @State private var opponentScore: Int = 8
    @State private var remainingSeconds: Int = 75
    @State private var period: String = "1st"
    @State private var isClockRunning: Bool = true

    // Timer
    @State private var timer: AnyCancellable?

    // Tap-to-score
    @State private var myTapCount: Int = 0
    @State private var oppTapCount: Int = 0
    @State private var myTapTimer: AnyCancellable?
    @State private var oppTapTimer: AnyCancellable?

    // Stats overlay
    @State private var showSahilStats: Bool = false

    // Sahil's shooting stats
    @State private var sahil2PTMade: Int = 3
    @State private var sahil2PTAtt: Int = 5
    @State private var sahil3PTMade: Int = 1
    @State private var sahil3PTAtt: Int = 3
    @State private var sahilFTMade: Int = 2
    @State private var sahilFTAtt: Int = 2

    // Other stats
    @State private var sahilAssists: Int = 2
    @State private var sahilRebounds: Int = 3
    @State private var sahilSteals: Int = 1
    @State private var sahilBlocks: Int = 0
    @State private var sahilTurnovers: Int = 1
    @State private var sahilFouls: Int = 1

    // Show stats dashboard
    @State private var showStatsDashboard: Bool = false
    @State private var selectedGame: GameRecord? = nil

    // Mock historical games for prototype
    private let pastGames: [GameRecord] = [
        GameRecord(date: "Jan 15", opponent: "Thunder", myTeamScore: 45, oppScore: 38, pts: 18, reb: 5, ast: 3, stl: 2, blk: 1, to: 2, pf: 2, fg2m: 5, fg2a: 8, fg3m: 2, fg3a: 5, ftm: 2, fta: 3),
        GameRecord(date: "Jan 12", opponent: "Lakers", myTeamScore: 52, oppScore: 48, pts: 22, reb: 7, ast: 4, stl: 1, blk: 0, to: 3, pf: 3, fg2m: 6, fg2a: 10, fg3m: 3, fg3a: 6, ftm: 1, fta: 2),
        GameRecord(date: "Jan 8", opponent: "Celtics", myTeamScore: 41, oppScore: 44, pts: 14, reb: 4, ast: 5, stl: 3, blk: 0, to: 1, pf: 1, fg2m: 4, fg2a: 7, fg3m: 1, fg3a: 4, ftm: 3, fta: 4),
        GameRecord(date: "Jan 5", opponent: "Heat", myTeamScore: 55, oppScore: 50, pts: 25, reb: 6, ast: 2, stl: 2, blk: 2, to: 2, pf: 2, fg2m: 7, fg2a: 11, fg3m: 3, fg3a: 5, ftm: 2, fta: 2),
        GameRecord(date: "Jan 2", opponent: "Bulls", myTeamScore: 48, oppScore: 52, pts: 16, reb: 8, ast: 6, stl: 1, blk: 1, to: 4, pf: 4, fg2m: 5, fg2a: 9, fg3m: 1, fg3a: 5, ftm: 3, fta: 4),
        GameRecord(date: "Dec 28", opponent: "Nets", myTeamScore: 50, oppScore: 50, pts: 20, reb: 4, ast: 3, stl: 0, blk: 0, to: 2, pf: 2, fg2m: 6, fg2a: 9, fg3m: 2, fg3a: 4, ftm: 2, fta: 2),
        GameRecord(date: "Dec 22", opponent: "Knicks", myTeamScore: 62, oppScore: 55, pts: 28, reb: 9, ast: 5, stl: 3, blk: 1, to: 1, pf: 1, fg2m: 8, fg2a: 12, fg3m: 3, fg3a: 7, ftm: 3, fta: 4),
        GameRecord(date: "Dec 18", opponent: "Pacers", myTeamScore: 44, oppScore: 48, pts: 12, reb: 3, ast: 2, stl: 1, blk: 0, to: 3, pf: 3, fg2m: 3, fg2a: 8, fg3m: 2, fg3a: 6, ftm: 0, fta: 0),
        GameRecord(date: "Dec 15", opponent: "Raptors", myTeamScore: 58, oppScore: 52, pts: 24, reb: 6, ast: 7, stl: 2, blk: 0, to: 2, pf: 2, fg2m: 7, fg2a: 10, fg3m: 2, fg3a: 5, ftm: 4, fta: 5),
        GameRecord(date: "Dec 10", opponent: "Wizards", myTeamScore: 51, oppScore: 49, pts: 19, reb: 5, ast: 4, stl: 1, blk: 1, to: 1, pf: 1, fg2m: 5, fg2a: 8, fg3m: 2, fg3a: 4, ftm: 3, fta: 4),
    ]

    // Computed
    private var clockTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var sahilPoints: Int {
        (sahil2PTMade * 2) + (sahil3PTMade * 3) + sahilFTMade
    }

    private var isCrunchTime: Bool {
        remainingSeconds < 60 && remainingSeconds > 0
    }

    // Shooting percentages
    private var fg2Pct: Double {
        sahil2PTAtt > 0 ? Double(sahil2PTMade) / Double(sahil2PTAtt) * 100 : 0
    }

    private var fg3Pct: Double {
        sahil3PTAtt > 0 ? Double(sahil3PTMade) / Double(sahil3PTAtt) * 100 : 0
    }

    private var ftPct: Double {
        sahilFTAtt > 0 ? Double(sahilFTMade) / Double(sahilFTAtt) * 100 : 0
    }

    private var totalFGMade: Int { sahil2PTMade + sahil3PTMade }
    private var totalFGAtt: Int { sahil2PTAtt + sahil3PTAtt }

    private var fgPct: Double {
        totalFGAtt > 0 ? Double(totalFGMade) / Double(totalFGAtt) * 100 : 0
    }

    // Advanced stats
    private var efgPct: Double {
        // eFG% = (FGM + 0.5 * 3PM) / FGA
        totalFGAtt > 0 ? (Double(totalFGMade) + 0.5 * Double(sahil3PTMade)) / Double(totalFGAtt) * 100 : 0
    }

    private var tsPct: Double {
        // TS% = PTS / (2 * (FGA + 0.44 * FTA))
        let denominator = 2 * (Double(totalFGAtt) + 0.44 * Double(sahilFTAtt))
        return denominator > 0 ? Double(sahilPoints) / denominator * 100 : 0
    }

    // Career stats (from past games)
    private var careerGames: Int { pastGames.count }
    private var careerWins: Int { pastGames.filter { $0.result == .win }.count }
    private var careerLosses: Int { pastGames.filter { $0.result == .loss }.count }
    private var careerTies: Int { pastGames.filter { $0.result == .tie }.count }

    private var careerTotalPts: Int { pastGames.reduce(0) { $0 + $1.pts } }
    private var careerTotalReb: Int { pastGames.reduce(0) { $0 + $1.reb } }
    private var careerTotalAst: Int { pastGames.reduce(0) { $0 + $1.ast } }
    private var careerTotalStl: Int { pastGames.reduce(0) { $0 + $1.stl } }
    private var careerTotalBlk: Int { pastGames.reduce(0) { $0 + $1.blk } }

    private var careerPPG: Double { careerGames > 0 ? Double(careerTotalPts) / Double(careerGames) : 0 }
    private var careerRPG: Double { careerGames > 0 ? Double(careerTotalReb) / Double(careerGames) : 0 }
    private var careerAPG: Double { careerGames > 0 ? Double(careerTotalAst) / Double(careerGames) : 0 }
    private var careerSPG: Double { careerGames > 0 ? Double(careerTotalStl) / Double(careerGames) : 0 }
    private var careerBPG: Double { careerGames > 0 ? Double(careerTotalBlk) / Double(careerGames) : 0 }

    private var careerFGPct: Double {
        let made = pastGames.reduce(0) { $0 + $1.fg2m + $1.fg3m }
        let att = pastGames.reduce(0) { $0 + $1.fg2a + $1.fg3a }
        return att > 0 ? Double(made) / Double(att) * 100 : 0
    }

    private var career3Pct: Double {
        let made = pastGames.reduce(0) { $0 + $1.fg3m }
        let att = pastGames.reduce(0) { $0 + $1.fg3a }
        return att > 0 ? Double(made) / Double(att) * 100 : 0
    }

    private var careerFTPct: Double {
        let made = pastGames.reduce(0) { $0 + $1.ftm }
        let att = pastGames.reduce(0) { $0 + $1.fta }
        return att > 0 ? Double(made) / Double(att) * 100 : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full screen camera
                cameraPreview

                // Top bar: REC dot (left) + Menu icon (right)
                VStack {
                    HStack {
                        recDot
                            .padding(.leading, 20)

                        Spacer()

                        // Menu button - subtle, top right
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

                // The ONE element: Smart Scoreboard
                VStack {
                    Spacer()
                    smartScoreboard
                        .padding(.horizontal, 50)
                        .padding(.bottom, 20)
                }

                // Tap feedback overlays (appear on edges when tapping)
                HStack {
                    // Left tap feedback
                    if myTapCount > 0 {
                        tapFeedback(count: myTapCount, color: .orange)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    // Right tap feedback
                    if oppTapCount > 0 {
                        tapFeedback(count: oppTapCount, color: .blue)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 30)
                .animation(.spring(response: 0.2), value: myTapCount)
                .animation(.spring(response: 0.2), value: oppTapCount)

                // Sahil's stats overlay
                if showSahilStats {
                    sahilStatsOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Full stats dashboard
                if showStatsDashboard {
                    statsDashboard
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.spring(response: 0.3), value: showSahilStats)
        .animation(.spring(response: 0.3), value: showStatsDashboard)
        .animation(.spring(response: 0.3), value: selectedGame?.id)
        .onAppear { startTimerIfNeeded() }
        .onChange(of: isClockRunning) { _, running in
            if running { startTimerIfNeeded() } else { stopTimer() }
        }
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        LinearGradient(
            colors: [Color(white: 0.92), Color(white: 0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            Image(systemName: "video.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.2))
        )
    }

    // MARK: - REC Indicator

    @State private var isPulsing: Bool = false

    private var recDot: some View {
        Group {
            if isClockRunning {
                // Pulsing red dot when recording
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
                // Pause icon when paused
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Smart Scoreboard (Clean - Just Scores)

    private var smartScoreboard: some View {
        HStack(spacing: 0) {
            // LEFT: My team (tap to score)
            scoreZone(
                score: myScore,
                label: "WLD",
                color: .orange,
                tapCount: $myTapCount,
                tapTimer: $myTapTimer,
                scoreBinding: $myScore,
                alignment: .leading
            )

            // CENTER: Clock (tap to pause)
            clockZone

            // RIGHT: Opponent (tap to score)
            scoreZone(
                score: opponentScore,
                label: "OPP",
                color: .blue,
                tapCount: $oppTapCount,
                tapTimer: $oppTapTimer,
                scoreBinding: $opponentScore,
                alignment: .trailing
            )
        }
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 3)
    }

    private func scoreZone(
        score: Int,
        label: String,
        color: Color,
        tapCount: Binding<Int>,
        tapTimer: Binding<AnyCancellable?>,
        scoreBinding: Binding<Int>,
        alignment: HorizontalAlignment
    ) -> some View {
        Button(action: {
            handleScoreTap(tapCount: tapCount, tapTimer: tapTimer, score: scoreBinding)
        }) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text("\(score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var clockZone: some View {
        Button(action: {
            isClockRunning.toggle()
        }) {
            VStack(spacing: 2) {
                Text(period)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)

                Text(clockTime)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(clockColor)

                // Play/pause indicator
                Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(width: 80)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func handleScoreTap(
        tapCount: Binding<Int>,
        tapTimer: Binding<AnyCancellable?>,
        score: Binding<Int>
    ) {
        let newCount = min(tapCount.wrappedValue + 1, 3)
        tapCount.wrappedValue = newCount

        tapTimer.wrappedValue?.cancel()
        tapTimer.wrappedValue = Timer.publish(every: 0.6, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in
                score.wrappedValue += tapCount.wrappedValue
                tapCount.wrappedValue = 0
            }
    }

    // MARK: - Timer

    private var timerInterval: TimeInterval {
        remainingSeconds < 60 ? 1.0 : 10.0
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
                if self.isClockRunning {
                    self.scheduleNextTick()
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Game Menu Overlay (Stats + Controls)

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
                    shootingTile("2PT", made: $sahil2PTMade, att: $sahil2PTAtt, pts: 2, color: .blue)
                    shootingTile("3PT", made: $sahil3PTMade, att: $sahil3PTAtt, pts: 3, color: .purple)
                    shootingTile("FT", made: $sahilFTMade, att: $sahilFTAtt, pts: 1, color: .cyan)
                }

                // Other stats
                HStack(spacing: 8) {
                    statTile("AST", $sahilAssists, .green)
                    statTile("REB", $sahilRebounds, .orange)
                    statTile("STL", $sahilSteals, .teal)
                    statTile("BLK", $sahilBlocks, .indigo)
                    statTile("TO", $sahilTurnovers, .red)
                    statTile("PF", $sahilFouls, .gray)
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

                    // Next Period / Half
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
                    Button(action: { endGame() }) {
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

    // MARK: - Game Control Actions

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
            remainingSeconds = 600 // Reset to 10:00 for 2nd half
        case "2nd":
            endGame()
        case "OT":
            endGame()
        default:
            break
        }
    }

    private func addOvertime() {
        period = "OT"
        remainingSeconds += 60 // Add 1 minute
        if !isClockRunning {
            isClockRunning = true
        }
        showSahilStats = false
    }

    private func endGame() {
        isClockRunning = false
        showSahilStats = false
        // TODO: Navigate to game summary
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
                        // Current game points breakdown
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

                                Divider().padding(.horizontal, 8)

                                HStack(spacing: 12) {
                                    pointBreakdown("2PT", value: sahil2PTMade * 2)
                                    pointBreakdown("3PT", value: sahil3PTMade * 3)
                                    pointBreakdown("FT", value: sahilFTMade)
                                }
                            }
                        }

                        // Today's shooting
                        dashboardCard {
                            VStack(spacing: 8) {
                                Text("TODAY'S SHOOTING")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 10) {
                                    shootingPctCircle("FG", pct: fgPct, made: totalFGMade, att: totalFGAtt, color: .blue)
                                    shootingPctCircle("3PT", pct: fg3Pct, made: sahil3PTMade, att: sahil3PTAtt, color: .purple)
                                    shootingPctCircle("FT", pct: ftPct, made: sahilFTMade, att: sahilFTAtt, color: .cyan)
                                }

                                HStack(spacing: 16) {
                                    advancedStatMini("eFG", value: efgPct)
                                    advancedStatMini("TS", value: tsPct)
                                }
                            }
                        }

                        // Today's box score
                        dashboardCard {
                            VStack(spacing: 8) {
                                Text("TODAY'S BOX SCORE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 6) {
                                    boxScoreStat("AST", value: sahilAssists, color: .green)
                                    boxScoreStat("REB", value: sahilRebounds, color: .orange)
                                    boxScoreStat("STL", value: sahilSteals, color: .teal)
                                    boxScoreStat("BLK", value: sahilBlocks, color: .indigo)
                                    boxScoreStat("TO", value: sahilTurnovers, color: .red)
                                    boxScoreStat("PF", value: sahilFouls, color: .gray)
                                }
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 2)
                            .padding(.vertical, 8)

                        // Career averages card
                        dashboardCard {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("CAREER AVG")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(careerGames) games")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 8) {
                                    careerAvgItem("PPG", value: careerPPG, color: .orange)
                                    careerAvgItem("RPG", value: careerRPG, color: .blue)
                                    careerAvgItem("APG", value: careerAPG, color: .green)
                                }

                                HStack(spacing: 8) {
                                    careerAvgItem("SPG", value: careerSPG, color: .teal)
                                    careerAvgItem("BPG", value: careerBPG, color: .indigo)
                                }

                                HStack {
                                    Text(careerTies > 0 ? "W-L-T: \(careerWins)-\(careerLosses)-\(careerTies)" : "W-L: \(careerWins)-\(careerLosses)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                            }
                        }

                        // Career shooting card
                        dashboardCard {
                            VStack(spacing: 8) {
                                Text("CAREER SHOOTING")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 16) {
                                    careerShootingItem("FG%", value: careerFGPct, color: .blue)
                                    careerShootingItem("3P%", value: career3Pct, color: .purple)
                                    careerShootingItem("FT%", value: careerFTPct, color: .cyan)
                                }

                                Text("Career totals: \(careerTotalPts) pts")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Game history card - scrollable list
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
                                            gameLogRowSimple(game)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.trailing, 16) // Extra padding to prevent cutoff
                }
            }
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.2), radius: 20, y: 5)
            .padding(.horizontal, 30)
            .padding(.vertical, 20)

            // Game detail overlay - on top of dashboard
            if let game = selectedGame {
                gameDetailOverlay(game)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
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

    private func pointBreakdown(_ label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    private func shootingPctCircle(_ label: String, pct: Double, made: Int, att: Int, color: Color) -> some View {
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

                Text(att > 0 ? String(format: "%.0f", pct) : "-")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            Text("\(made)/\(att)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func advancedStatItem(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
        }
    }

    private func boxScoreStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func advancedStatMini(_ label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)
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

    private func careerShootingItem(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", value))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }


    // Simple game log row - just W/L/T + opponent + score
    private func gameLogRowSimple(_ game: GameRecord) -> some View {
        HStack(spacing: 8) {
            // W/L/T badge
            Text(game.result.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(game.result.color)
                .cornerRadius(4)

            // Opponent
            Text(game.opponent)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Score
            Text("\(game.myTeamScore)-\(game.oppScore)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }

    // Game detail overlay
    private func gameDetailOverlay(_ game: GameRecord) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { selectedGame = nil }

            VStack(spacing: 12) {
                // Header
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
                        Text(game.date)
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

                // Result & Score
                HStack(spacing: 16) {
                    Text(game.result.label)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(game.result.color)

                    Text("\(game.myTeamScore) - \(game.oppScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                Divider()

                // Sahil's stats for this game
                HStack {
                    Text("Sahil's Performance")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Points
                HStack {
                    Text("\(game.pts)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("PTS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Shooting breakdown
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("2PT: \(game.fg2m)/\(game.fg2a)")
                            .font(.system(size: 10))
                        Text("3PT: \(game.fg3m)/\(game.fg3a)")
                            .font(.system(size: 10))
                        Text("FT: \(game.ftm)/\(game.fta)")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }

                // Other stats grid
                HStack(spacing: 12) {
                    gameDetailStat("REB", value: game.reb, color: .blue)
                    gameDetailStat("AST", value: game.ast, color: .green)
                    gameDetailStat("STL", value: game.stl, color: .teal)
                    gameDetailStat("BLK", value: game.blk, color: .indigo)
                    gameDetailStat("TO", value: game.to, color: .red)
                    gameDetailStat("PF", value: game.pf, color: .gray)
                }

                // FG%
                HStack {
                    Text("FG%: \(String(format: "%.1f", game.fgPct))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
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

// MARK: - Game Record Model

enum GameResult {
    case win, loss, tie

    var color: Color {
        switch self {
        case .win: return .green
        case .loss: return .red
        case .tie: return .orange
        }
    }

    var label: String {
        switch self {
        case .win: return "W"
        case .loss: return "L"
        case .tie: return "T"
        }
    }
}

struct GameRecord: Identifiable {
    let id = UUID()
    let date: String
    let opponent: String
    let myTeamScore: Int
    let oppScore: Int
    let pts: Int
    let reb: Int
    let ast: Int
    let stl: Int
    let blk: Int
    let to: Int
    let pf: Int
    let fg2m: Int
    let fg2a: Int
    let fg3m: Int
    let fg3a: Int
    let ftm: Int
    let fta: Int

    var result: GameResult {
        if myTeamScore > oppScore { return .win }
        else if myTeamScore < oppScore { return .loss }
        else { return .tie }
    }

    var fgPct: Double {
        let made = fg2m + fg3m
        let att = fg2a + fg3a
        return att > 0 ? Double(made) / Double(att) * 100 : 0
    }
}

// MARK: - Preview

struct UltraMinimalPrototype_Previews: PreviewProvider {
    static var previews: some View {
        UltraMinimalPrototype()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
