//
//  CollapsiblePiPPrototype.swift
//  SahilStatsLite
//
//  Prototype: Collapsible split-view like UniFi app
//  Right panel expands/collapses, left side adjusts accordingly
//

import SwiftUI
import UIKit

struct CollapsiblePiPPrototype: View {
    // Panel state
    @State private var isExpanded: Bool = false
    @State private var showStats: Bool = false

    // Game state
    @State private var myScore: Int = 12
    @State private var opponentScore: Int = 8
    @State private var clockTime: String = "14:32"
    @State private var period: String = "1st"
    @State private var isClockRunning: Bool = true

    // Sahil's stats
    @State private var sahilPoints: Int = 8
    @State private var sahilAssists: Int = 2
    @State private var sahilRebounds: Int = 3
    @State private var sahilSteals: Int = 1
    @State private var sahilFGMade: Int = 3
    @State private var sahilFGMiss: Int = 2
    @State private var sahil3PT: Int = 1
    @State private var sahilFouls: Int = 1

    // Animation
    private var expandedRatio: CGFloat { isExpanded ? 0.45 : 0.15 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                HStack(spacing: 0) {
                    // LEFT: Camera + Score (grows/shrinks)
                    leftPanel(geo: geo)
                        .frame(width: geo.size.width * (1 - expandedRatio))

                    // RIGHT: Collapsible control panel
                    rightPanel(geo: geo)
                        .frame(width: geo.size.width * expandedRatio)
                }

                // Stats overlay
                if showStats {
                    statsOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Left Panel (Camera + Scores)

    private func leftPanel(geo: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            // Camera preview
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))

                Image(systemName: "video.fill")
                    .font(.system(size: isExpanded ? 24 : 40))
                    .foregroundColor(.white.opacity(0.3))

                // REC indicator
                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("REC")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                }

                // Mini scoreboard (burned into video)
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("WLD").font(.system(size: 8, weight: .bold))
                        Text("\(myScore)").font(.system(size: 10, weight: .bold))
                        Text("-").font(.system(size: 8)).foregroundColor(.gray)
                        Text("\(opponentScore)").font(.system(size: 10, weight: .bold))
                        Text("OPP").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .padding(8)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Score display (compact when collapsed)
            if isExpanded {
                compactScoreRow
                    .padding(.horizontal, 12)
            } else {
                expandedScoreDisplay
                    .padding(.horizontal, 12)
            }

            Spacer()

            // Scoring buttons
            scoringButtons
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Right Panel (Collapsible)

    private func rightPanel(geo: GeometryProxy) -> some View {
        ZStack {
            // Background
            Color(white: 0.1)

            if isExpanded {
                // Full control panel
                expandedControls
            } else {
                // Minimal collapsed strip
                collapsedStrip
            }

            // Expand/collapse handle
            VStack {
                Spacer()
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.right.2" : "chevron.left.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 30, height: 50)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .offset(x: isExpanded ? -15 : 15)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .trailing)
        }
    }

    // MARK: - Collapsed Strip

    private var collapsedStrip: some View {
        VStack(spacing: 16) {
            // Clock
            VStack(spacing: 2) {
                Text(period)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
                Text(clockTime)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Play/Pause
            Button(action: { isClockRunning.toggle() }) {
                Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 36)
                    .background(isClockRunning ? Color.yellow : Color.green)
                    .cornerRadius(8)
            }

            Spacer()

            // Sahil quick access
            Button(action: { showStats = true }) {
                VStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                    Text("\(sahilPoints)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.orange)
                .frame(width: 40, height: 44)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }

            Spacer()

            // End game
            Button(action: {}) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 36)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Expanded Controls

    private var expandedControls: some View {
        VStack(spacing: 20) {
            // Clock section
            VStack(spacing: 6) {
                Text(period)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text(clockTime)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    Button(action: { isClockRunning.toggle() }) {
                        Image(systemName: isClockRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 40)
                            .background(isClockRunning ? Color.yellow : Color.green)
                            .cornerRadius(10)
                    }

                    Button(action: {}) {
                        Text("2nd")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 40)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.top, 16)

            Divider().background(Color.gray.opacity(0.3)).padding(.horizontal)

            // Sahil's stats button
            Button(action: { showStats = true }) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.orange)
                    Text("Sahil's Stats")
                    Spacer()
                    Text("\(sahilPoints) pts")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
            }
            .padding(.horizontal, 12)

            Spacer()

            // End game
            Button(action: {}) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("End Game")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.8))
                .cornerRadius(10)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Score Displays

    private var expandedScoreDisplay: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("WILDCATS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Text("\(myScore)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)

            Text("-")
                .font(.system(size: 28))
                .foregroundColor(.gray)

            VStack(spacing: 2) {
                Text("THUNDER")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                Text("\(opponentScore)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var compactScoreRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text("WLD")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                Text("\(myScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            Text("-")
                .font(.system(size: 20))
                .foregroundColor(.gray)

            Spacer()

            HStack(spacing: 8) {
                Text("\(opponentScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("THU")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Scoring Buttons

    private var scoringButtons: some View {
        HStack(spacing: 8) {
            // My team
            HStack(spacing: 6) {
                scoreBtn(pts: 1, color: .orange, isMyTeam: true)
                scoreBtn(pts: 2, color: .orange, isMyTeam: true)
                scoreBtn(pts: 3, color: .orange, isMyTeam: true)
            }

            Spacer()

            // Opponent
            HStack(spacing: 6) {
                scoreBtn(pts: 1, color: .blue, isMyTeam: false)
                scoreBtn(pts: 2, color: .blue, isMyTeam: false)
                scoreBtn(pts: 3, color: .blue, isMyTeam: false)
            }
        }
    }

    private func scoreBtn(pts: Int, color: Color, isMyTeam: Bool) -> some View {
        Button(action: {
            if isMyTeam { myScore += pts } else { opponentScore += pts }
        }) {
            Text("+\(pts)")
                .font(.system(size: isExpanded ? 16 : 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: isExpanded ? 44 : 52, height: isExpanded ? 44 : 52)
                .background(color)
                .cornerRadius(10)
        }
    }

    // MARK: - Stats Overlay

    private var statsOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showStats = false }

            VStack(spacing: 14) {
                HStack {
                    Label("Sahil's Stats", systemImage: "person.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { showStats = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.gray)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    statTile("Points", $sahilPoints, .orange)
                    statTile("Assists", $sahilAssists, .green)
                    statTile("Rebounds", $sahilRebounds, .purple)
                    statTile("Steals", $sahilSteals, .cyan)
                    statTile("FG Made", $sahilFGMade, .blue)
                    statTile("FG Miss", $sahilFGMiss, .red)
                    statTile("3PT", $sahil3PT, .yellow)
                    statTile("Fouls", $sahilFouls, .gray)
                }

                Button(action: { showStats = false }) {
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
            .background(Color(white: 0.12))
            .cornerRadius(18)
            .padding(.horizontal, 50)
        }
    }

    private func statTile(_ label: String, _ value: Binding<Int>, _ color: Color) -> some View {
        Button(action: { value.wrappedValue += 1 }) {
            VStack(spacing: 4) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
        }
    }
}

// MARK: - Preview

struct CollapsiblePiPPrototype_Previews: PreviewProvider {
    static var previews: some View {
        CollapsiblePiPPrototype()
            .previewInterfaceOrientation(.landscapeRight)
    }
}
