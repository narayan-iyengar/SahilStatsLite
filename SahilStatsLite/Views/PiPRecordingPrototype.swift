//
//  PiPRecordingPrototype.swift
//  SahilStatsLite
//
//  Prototype: PiP-style recording view with large controls
//  Preview this in Xcode canvas to evaluate the layout
//

import SwiftUI

struct PiPRecordingPrototype: View {
    @State private var myScore: Int = 12
    @State private var opponentScore: Int = 8
    @State private var clockTime: String = "14:32"
    @State private var period: String = "1st"
    @State private var isClockRunning: Bool = true
    @State private var showStats: Bool = false

    // Sahil's stats
    @State private var sahilPoints: Int = 8
    @State private var sahilAssists: Int = 2
    @State private var sahilRebounds: Int = 3
    @State private var sahilSteals: Int = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(white: 0.12).ignoresSafeArea()

                HStack(spacing: 0) {
                    // LEFT SIDE: Camera + Scores
                    leftPanel
                        .frame(width: geo.size.width * 0.55)

                    // RIGHT SIDE: Clock + Controls
                    rightPanel
                        .frame(width: geo.size.width * 0.45)
                }

                // Floating stats panel (collapsible)
                if showStats {
                    statsOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Left Panel (Camera + Scores)

    private var leftPanel: some View {
        VStack(spacing: 12) {
            // Camera preview (larger, better positioned)
            cameraPreview
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Score display below camera
            compactScoreDisplay
                .padding(.horizontal, 12)

            Spacer()

            // Scoring buttons
            scoringControls
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Right Panel (Clock + Game Controls)

    private var rightPanel: some View {
        VStack(spacing: 20) {
            // Period & Clock
            VStack(spacing: 4) {
                Text(period)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)

                Text(clockTime)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.top, 20)

            // Clock controls
            HStack(spacing: 12) {
                Button(action: { isClockRunning.toggle() }) {
                    Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 44)
                        .background(isClockRunning ? Color.yellow : Color.green)
                        .cornerRadius(10)
                }

                Button(action: {}) {
                    Text("2nd Half")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(10)
                }
            }

            Spacer()

            // Sahil's stats button (opens overlay)
            Button(action: { withAnimation(.spring(response: 0.3)) { showStats.toggle() } }) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.orange)
                    Text("Sahil's Stats")
                    Spacer()
                    // Show current points as badge
                    Text("\(sahilPoints) pts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)

            Spacer()

            // End game button
            Button(action: {}) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("End Game")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.8))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        ZStack {
            // Camera placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))

            Image(systemName: "video.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))

            // Recording indicator
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("REC")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    Spacer()
                }
                .padding(8)
                Spacer()
            }

            // Mini scoreboard (burned into video)
            VStack {
                Spacer()
                miniScoreboard
                    .padding(8)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var miniScoreboard: some View {
        HStack(spacing: 6) {
            Text("WLD")
                .font(.system(size: 9, weight: .bold))
            Text("\(myScore)")
                .font(.system(size: 11, weight: .bold))
            Text("|")
                .font(.system(size: 9))
                .foregroundColor(.gray)
            Text("\(opponentScore)")
                .font(.system(size: 11, weight: .bold))
            Text("OPP")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.75))
        .cornerRadius(6)
    }

    // MARK: - Compact Score Display

    private var compactScoreDisplay: some View {
        HStack(spacing: 0) {
            // My team
            VStack(spacing: 2) {
                Text("WILDCATS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text("\(myScore)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)

            Text("-")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.gray)
                .padding(.horizontal, 8)

            // Opponent
            VStack(spacing: 2) {
                Text("THUNDER")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                Text("\(opponentScore)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }

    // MARK: - Scoring Controls

    private var scoringControls: some View {
        HStack(spacing: 12) {
            // My team scoring
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    scoringButton(points: 1, color: .orange)
                    scoringButton(points: 2, color: .orange)
                    scoringButton(points: 3, color: .orange)
                }
            }

            Spacer()

            // Opponent scoring
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    scoringButton(points: 1, color: .blue)
                    scoringButton(points: 2, color: .blue)
                    scoringButton(points: 3, color: .blue)
                }
            }
        }
    }

    private func scoringButton(points: Int, color: Color) -> some View {
        Button(action: {
            if color == .orange {
                myScore += points
            } else {
                opponentScore += points
            }
        }) {
            Text("+\(points)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(color)
                .cornerRadius(10)
        }
    }

    // MARK: - Stats Overlay (Collapsible)

    @State private var sahilFGMade: Int = 3
    @State private var sahilFGMiss: Int = 2
    @State private var sahil3PT: Int = 1
    @State private var sahilFouls: Int = 1
    @State private var sahilTurnovers: Int = 0
    @State private var sahilBlocks: Int = 0

    private var statsOverlay: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) { showStats = false }
                }

            // Stats panel
            VStack(spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.orange)
                        Text("Sahil's Stats")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    Spacer()
                    Button(action: { withAnimation(.spring(response: 0.3)) { showStats = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray)
                    }
                }

                // Main stats - tap to increment
                HStack(spacing: 12) {
                    tappableStatCard(label: "Points", value: $sahilPoints, color: .orange)
                    tappableStatCard(label: "Assists", value: $sahilAssists, color: .green)
                    tappableStatCard(label: "Rebounds", value: $sahilRebounds, color: .purple)
                    tappableStatCard(label: "Steals", value: $sahilSteals, color: .cyan)
                }

                // Shooting stats
                HStack(spacing: 12) {
                    tappableStatCard(label: "FG Made", value: $sahilFGMade, color: .blue)
                    tappableStatCard(label: "FG Miss", value: $sahilFGMiss, color: .red)
                    tappableStatCard(label: "3-Pointers", value: $sahil3PT, color: .yellow)
                }

                // Other stats
                HStack(spacing: 12) {
                    tappableStatCard(label: "Fouls", value: $sahilFouls, color: .gray)
                    tappableStatCard(label: "Turnovers", value: $sahilTurnovers, color: .pink)
                    tappableStatCard(label: "Blocks", value: $sahilBlocks, color: .mint)
                }

                // Done button
                Button(action: { withAnimation(.spring(response: 0.3)) { showStats = false } }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
            .padding(20)
            .background(Color(white: 0.12))
            .cornerRadius(20)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }

    private func tappableStatCard(label: String, value: Binding<Int>, color: Color) -> some View {
        Button(action: { value.wrappedValue += 1 }) {
            VStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .contextMenu {
            Button(action: { if value.wrappedValue > 0 { value.wrappedValue -= 1 } }) {
                Label("Subtract 1", systemImage: "minus")
            }
            Button(action: { value.wrappedValue = 0 }) {
                Label("Reset to 0", systemImage: "arrow.counterclockwise")
            }
        }
    }
}

// MARK: - Preview

struct PiPRecordingPrototype_Previews: PreviewProvider {
    static var previews: some View {
        PiPRecordingPrototype()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
