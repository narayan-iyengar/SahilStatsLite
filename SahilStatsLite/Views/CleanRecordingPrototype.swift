//
//  CleanRecordingPrototype.swift
//  SahilStatsLite
//
//  World-class UX: Full-screen camera with floating minimal controls
//  Only Sahil's stats are collapsible (person icon)
//

import SwiftUI
import Combine

struct CleanRecordingPrototype: View {
    // Game state
    @State private var myScore: Int = 12
    @State private var opponentScore: Int = 8
    @State private var remainingSeconds: Int = 75  // Start at 1:15 - watch it switch to 1s intervals at 0:59
    @State private var period: String = "1st"
    @State private var isClockRunning: Bool = true

    // Timer
    @State private var timer: AnyCancellable?

    // Tap-to-score state
    @State private var myTapCount: Int = 0
    @State private var oppTapCount: Int = 0
    @State private var myTapTimer: AnyCancellable?
    @State private var oppTapTimer: AnyCancellable?

    // Formatted clock time
    private var clockTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // Sahil's stats (collapsible)
    @State private var showSahilStats: Bool = false

    // Shooting stats: Made / Attempted
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

    // Computed stats
    private var sahilPoints: Int {
        (sahil2PTMade * 2) + (sahil3PTMade * 3) + sahilFTMade
    }

    private var sahilFGPct: String {
        let made = sahil2PTMade + sahil3PTMade
        let att = sahil2PTAtt + sahil3PTAtt
        guard att > 0 else { return "-" }
        return String(format: "%.0f%%", Double(made) / Double(att) * 100)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // LAYER 1: Full-screen camera preview
                cameraPreview

                // LAYER 2: Floating controls
                VStack {
                    // Top bar: REC, Sahil icon, End
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    Spacer()

                    // Bottom: Scoreboard with integrated clock
                    floatingScoreboard
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                }

                // LAYER 3: Tap-to-score zones (edges)
                HStack {
                    // My team (left edge)
                    tapScoreZone(
                        tapCount: $myTapCount,
                        tapTimer: $myTapTimer,
                        score: $myScore,
                        color: .orange,
                        label: "WLD"
                    )
                    .padding(.leading, 12)

                    Spacer()

                    // Opponent (right edge)
                    tapScoreZone(
                        tapCount: $oppTapCount,
                        tapTimer: $oppTapTimer,
                        score: $opponentScore,
                        color: .blue,
                        label: "OPP"
                    )
                    .padding(.trailing, 12)
                }

                // LAYER 4: Sahil's stats overlay (only collapsible element)
                if showSahilStats {
                    sahilStatsOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSahilStats)
        .onAppear { startTimerIfNeeded() }
        .onChange(of: isClockRunning) { _, running in
            if running {
                startTimerIfNeeded()
            } else {
                stopTimer()
            }
        }
    }

    // MARK: - Timer Control

    // Interval: 10s normally, 1s in crunch time
    private var timerInterval: TimeInterval {
        remainingSeconds < 60 ? 1.0 : 10.0
    }

    private var decrementAmount: Int {
        remainingSeconds < 60 ? 1 : 10
    }

    private func startTimerIfNeeded() {
        guard isClockRunning, remainingSeconds > 0 else { return }
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.cancel()
        guard isClockRunning, remainingSeconds > 0 else {
            isClockRunning = false
            return
        }

        timer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .first()  // Only fire once, then reschedule (interval may change)
            .sink { _ in
                let decrement = self.decrementAmount
                if self.remainingSeconds > decrement {
                    self.remainingSeconds -= decrement
                } else {
                    self.remainingSeconds = 0
                    self.isClockRunning = false
                }
                // Reschedule with potentially new interval
                if self.isClockRunning {
                    self.scheduleNextTick()
                }
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Camera Preview (Full Screen)

    private var cameraPreview: some View {
        ZStack {
            // Light mode background - simulates bright outdoor court
            LinearGradient(
                colors: [Color(white: 0.92), Color(white: 0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Placeholder for actual camera
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.3))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // REC indicator - state aware
            recordingIndicator

            Spacer()

            // Sahil's stats button (person icon) - Liquid Glass Light (No Border)
            Button(action: { showSahilStats = true }) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 46, height: 46)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)

                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            Spacer().frame(width: 12)

            // Smart control zone - changes based on clock state
            smartControlZone
        }
    }

    // MARK: - Recording Indicator (State Aware) - Liquid Glass Light

    @State private var isPulsing: Bool = false

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isClockRunning ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
                .scaleEffect(isClockRunning && isPulsing ? 1.3 : 1.0)
                .opacity(isClockRunning && !isPulsing ? 0.6 : 1.0)
                .animation(
                    isClockRunning
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
                .onAppear { isPulsing = true }

            Text(isClockRunning ? "REC" : "PAUSED")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isClockRunning ? .red : .orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isClockRunning)
    }

    // MARK: - Smart Control Zone - Liquid Glass Light (No Borders)

    private var smartControlZone: some View {
        HStack(spacing: 8) {
            if isClockRunning {
                // Clock running → show PAUSE button
                Button(action: { isClockRunning = false }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12))
                        Text("PAUSE")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)
                }
            } else {
                // Clock paused → show PLAY + END buttons
                Button(action: { isClockRunning = true }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .frame(width: 42, height: 38)
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)
                }

                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                        Text("END")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isClockRunning)
    }

    // MARK: - Floating Scoreboard

    // Check if under 1 minute remaining
    private var isCrunchTime: Bool {
        remainingSeconds < 60 && remainingSeconds > 0
    }

    private var clockColor: Color {
        if !isClockRunning {
            return .yellow  // Paused
        } else if isCrunchTime {
            return .red     // Under 1 min - urgent!
        } else {
            return .white   // Normal
        }
    }

    private var floatingScoreboard: some View {
        HStack(spacing: 0) {
            // My team
            HStack(spacing: 8) {
                Text("WLD")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
                Text("\(myScore)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)

            // Center: Period + Clock (clean, no buttons)
            VStack(spacing: 3) {
                Text(period)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)

                Text(clockTime)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(lightModeClockColor)
                    .scaleEffect(isCrunchTime && isClockRunning ? 1.1 : 1.0)
                    .animation(
                        isCrunchTime && isClockRunning
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .default,
                        value: isCrunchTime
                    )
            }
            .frame(width: 100)

            // Opponent
            HStack(spacing: 8) {
                Text("\(opponentScore)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("OPP")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(
            color: isCrunchTime && isClockRunning ? Color.red.opacity(0.3) : Color.black.opacity(0.12),
            radius: isCrunchTime && isClockRunning ? 12 : 10,
            y: 3
        )
        .animation(.easeInOut(duration: 0.3), value: isCrunchTime)
    }

    private var lightModeClockColor: Color {
        if !isClockRunning {
            return .orange  // Paused
        } else if isCrunchTime {
            return .red     // Under 1 min - urgent!
        } else {
            return .primary // Normal
        }
    }

    // MARK: - Liquid Glass Tap-to-Score Zone (Light Mode)

    private func tapScoreZone(
        tapCount: Binding<Int>,
        tapTimer: Binding<AnyCancellable?>,
        score: Binding<Int>,
        color: Color,
        label: String
    ) -> some View {
        Button(action: {
            // Increment tap count (max 3)
            let newCount = min(tapCount.wrappedValue + 1, 3)
            tapCount.wrappedValue = newCount

            // Cancel existing timer
            tapTimer.wrappedValue?.cancel()

            // Start new timer - commit score after delay
            tapTimer.wrappedValue = Timer.publish(every: 0.6, on: .main, in: .common)
                .autoconnect()
                .first()
                .sink { _ in
                    // Commit the score
                    score.wrappedValue += tapCount.wrappedValue
                    tapCount.wrappedValue = 0
                }
        }) {
            ZStack {
                // Liquid glass background - light mode (no border)
                RoundedRectangle(cornerRadius: 20)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(tapCount.wrappedValue > 0 ? 0.15 : 0.1), radius: tapCount.wrappedValue > 0 ? 12 : 8, y: 2)

                // Content
                VStack(spacing: 8) {
                    if tapCount.wrappedValue > 0 {
                        // Active state - show pending score
                        Text("+\(tapCount.wrappedValue)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(color)

                        // Dots indicator
                        HStack(spacing: 5) {
                            ForEach(1...3, id: \.self) { i in
                                Circle()
                                    .fill(i <= tapCount.wrappedValue ? color : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    } else {
                        // Idle state
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(color)

                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 64, height: 100)
        }
        .buttonStyle(.plain)
        .scaleEffect(tapCount.wrappedValue > 0 ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: tapCount.wrappedValue)
    }

    // MARK: - Sahil's Stats Overlay (Light Mode)

    private var sahilStatsOverlay: some View {
        ZStack {
            // Dim background - lighter for light mode
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { showSahilStats = false }

            // Stats card
            VStack(spacing: 14) {
                // Header with points total
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.orange)
                        Text("Sahil")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.primary)

                    Spacer()

                    // Points + FG%
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text("\(sahilPoints)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.orange)
                            Text("PTS")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange.opacity(0.7))
                        }

                        VStack(spacing: 0) {
                            Text(sahilFGPct)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                            Text("FG%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: { showSahilStats = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Shooting stats with Made/Miss buttons
                HStack(spacing: 10) {
                    shootingTile("2PT", made: $sahil2PTMade, attempted: $sahil2PTAtt, pointValue: 2, color: .blue)
                    shootingTile("3PT", made: $sahil3PTMade, attempted: $sahil3PTAtt, pointValue: 3, color: .purple)
                    shootingTile("FT", made: $sahilFTMade, attempted: $sahilFTAtt, pointValue: 1, color: .cyan)
                }

                Divider().background(Color.gray.opacity(0.3))

                // Other stats - simple tap tiles
                HStack(spacing: 10) {
                    simpleTile("AST", $sahilAssists, .green)
                    simpleTile("REB", $sahilRebounds, .orange)
                    simpleTile("STL", $sahilSteals, .teal)
                    simpleTile("BLK", $sahilBlocks, .indigo)
                    simpleTile("TO", $sahilTurnovers, .red)
                    simpleTile("PF", $sahilFouls, .gray)
                }

                // Done button
                Button(action: { showSahilStats = false }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(10)
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 5)
            .padding(.horizontal, 40)
        }
    }

    // Shooting tile: shows Made/Att with separate buttons (Light Mode)
    // Also updates team score when Sahil makes a shot
    private func shootingTile(_ label: String, made: Binding<Int>, attempted: Binding<Int>, pointValue: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            // Label
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)

            // Made / Attempted display
            Text("\(made.wrappedValue)/\(attempted.wrappedValue)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Made / Miss buttons
            HStack(spacing: 6) {
                Button(action: {
                    made.wrappedValue += 1
                    attempted.wrappedValue += 1
                    myScore += pointValue  // Also update team score!
                }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 28)
                        .background(Color.green)
                        .cornerRadius(6)
                }

                Button(action: {
                    attempted.wrappedValue += 1
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 28)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    // Simple tap-to-increment tile (Light Mode)
    private func simpleTile(_ label: String, _ value: Binding<Int>, _ color: Color) -> some View {
        Button(action: { value.wrappedValue += 1 }) {
            VStack(spacing: 2) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
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

// MARK: - Preview

struct CleanRecordingPrototype_Previews: PreviewProvider {
    static var previews: some View {
        CleanRecordingPrototype()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
