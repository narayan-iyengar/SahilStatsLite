//
//  WatchAppMockup.swift
//  SahilStatsLite
//
//  SwiftUI mockup of Apple Watch Ultra 2 scoring interface
//  Preview in Xcode Canvas to see the design
//

import SwiftUI

// MARK: - Main Scoring View

struct WatchScoringView: View {
    @State private var myScore: Int = 24
    @State private var oppScore: Int = 21
    @State private var isClockRunning: Bool = false
    @State private var remainingSeconds: Int = 754 // 12:34
    @State private var periodIndex: Int = 1 // 0=1st, 1=2nd, 2=OT, 3=OT2...
    @State private var showEndGame: Bool = false

    @State private var myFeedback: Int? = nil
    @State private var oppFeedback: Int? = nil

    private let periods = ["1st Half", "2nd Half", "OT", "OT2", "OT3"]

    private var currentPeriod: String {
        periods[min(periodIndex, periods.count - 1)]
    }

    private var clockTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Live indicator
                liveIndicator
                    .padding(.top, 4)

                // Period (tap to advance)
                Button {
                    advancePeriod()
                } label: {
                    Text(currentPeriod)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                // Score area - only scores are tappable
                HStack(spacing: 0) {
                    // My team
                    scoreZone(
                        score: myScore,
                        name: "WLD",
                        isMyTeam: true,
                        feedback: myFeedback
                    ) {
                        handleMyTeamTap()
                    }

                    // Divider
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.15), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)
                        .padding(.vertical, 10)

                    // Opponent
                    scoreZone(
                        score: oppScore,
                        name: "OPP",
                        isMyTeam: false,
                        feedback: oppFeedback
                    ) {
                        handleOppTeamTap()
                    }
                }
                .frame(maxHeight: .infinity)

                // Clock area (tap = pause/play, long press = end game)
                clockArea

                // Swipe hint
                swipeHint
                    .padding(.bottom, 4)
            }

            // End game confirmation
            if showEndGame {
                endGameOverlay
            }
        }
    }

    // MARK: - Live Indicator

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isClockRunning ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(isClockRunning ? "LIVE" : "PAUSED")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isClockRunning ? .green : .orange)
        }
    }

    // MARK: - Score Zone (only score number is tappable)

    private func scoreZone(
        score: Int,
        name: String,
        isMyTeam: Bool,
        feedback: Int?,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Tappable score
                Button(action: onTap) {
                    Text("\(score)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 60)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Feedback overlay
                if let points = feedback {
                    Text("+\(points)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.orange)
                        .offset(y: -30)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isMyTeam ? .orange : .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clock Area

    private var clockArea: some View {
        VStack(spacing: 4) {
            // Only the clock time is tappable
            clockButton

            // Status text - not tappable
            Text(isClockRunning ? "running" : "hold to end")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .allowsHitTesting(false)
        }
        .padding(.vertical, 6)
    }

    private var clockButton: some View {
        Text(clockTime)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundColor(isClockRunning ? .white : .orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isClockRunning.toggle()
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                showEndGame = true
            }
    }

    // MARK: - Swipe Hint

    private var swipeHint: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 30, height: 3)

            Text("Stats")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - End Game Overlay

    private var endGameOverlay: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("End Game?")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text("\(myScore) - \(oppScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(myScore > oppScore ? .green : (myScore < oppScore ? .red : .white))

                HStack(spacing: 12) {
                    Button {
                        showEndGame = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)

                    Button {
                        // End game action
                        showEndGame = false
                    } label: {
                        Text("End")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func advancePeriod() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if periodIndex < periods.count - 1 {
                periodIndex += 1
            }
            // Reset clock for new period (matches phone app)
            if periodIndex >= 2 {
                remainingSeconds = 60 // 1:00 OT (same as phone)
            } else {
                remainingSeconds = 18 * 60 // 18:00 half (default)
            }
        }
    }

    private func handleMyTeamTap() {
        // +1 per tap (matches iOS app behavior)
        myScore += 1
        withAnimation(.spring(response: 0.3)) {
            myFeedback = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                myFeedback = nil
            }
        }
    }

    private func handleOppTeamTap() {
        oppScore += 1
        withAnimation(.spring(response: 0.3)) {
            oppFeedback = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                oppFeedback = nil
            }
        }
    }
}

// MARK: - Stats View

struct WatchStatsView: View {
    @State private var fg2Made: Int = 2
    @State private var fg2Att: Int = 4
    @State private var fg3Made: Int = 2
    @State private var fg3Att: Int = 3
    @State private var ftMade: Int = 2
    @State private var ftAtt: Int = 2

    @State private var assists: Int = 3
    @State private var rebounds: Int = 5
    @State private var steals: Int = 2
    @State private var blocks: Int = 1
    @State private var turnovers: Int = 1

    private var points: Int {
        (fg2Made * 2) + (fg3Made * 3) + ftMade
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 6) {
                // Header
                VStack(spacing: 2) {
                    Text("SAHIL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(points) pts")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.bottom, 4)

                // Shooting stats
                HStack(spacing: 4) {
                    shootingStat(label: "2PT", made: $fg2Made, att: $fg2Att)
                    shootingStat(label: "3PT", made: $fg3Made, att: $fg3Att)
                    shootingStat(label: "FT", made: $ftMade, att: $ftAtt)
                }

                // Other stats
                HStack(spacing: 3) {
                    statButton(label: "AST", value: $assists)
                    statButton(label: "REB", value: $rebounds)
                    statButton(label: "STL", value: $steals)
                    statButton(label: "BLK", value: $blocks)
                    statButton(label: "TO", value: $turnovers)
                }

                // Back hint
                Text("↓ Score")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Shooting Stat Tile

    private func shootingStat(label: String, made: Binding<Int>, att: Binding<Int>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 3) {
                // Make button
                Button {
                    made.wrappedValue += 1
                    att.wrappedValue += 1
                } label: {
                    Text("✓")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 22, height: 22)
                        .background(Color.green)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Miss button
                Button {
                    att.wrappedValue += 1
                } label: {
                    Text("✗")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.red)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Text("\(made.wrappedValue)/\(att.wrappedValue)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Stat Button

    private func statButton(label: String, value: Binding<Int>) -> some View {
        Button {
            value.wrappedValue += 1
        } label: {
            VStack(spacing: 2) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text(label)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combined Preview with Watch Frame

struct WatchMockupPreview: View {
    @State private var showStats: Bool = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Apple Watch Ultra 2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1)

                Text("Basketball Scoring")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                // Watch frame
                watchFrame {
                    if showStats {
                        WatchStatsView()
                    } else {
                        WatchScoringView()
                    }
                }

                // Toggle button
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        showStats.toggle()
                    }
                } label: {
                    Text(showStats ? "Show Scoring" : "Show Stats")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(20)
                }
            }
        }
    }

    // MARK: - Watch Frame

    private func watchFrame<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            // Titanium case
            RoundedRectangle(cornerRadius: 52)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.45), Color(white: 0.3), Color(white: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 200, height: 240)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

            // Inner bezel
            RoundedRectangle(cornerRadius: 46)
                .fill(Color.black)
                .frame(width: 180, height: 220)

            // Screen
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.black)
                .frame(width: 168, height: 208)
                .overlay(
                    content()
                        .clipShape(RoundedRectangle(cornerRadius: 40))
                )

            // Digital Crown
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.5), Color(white: 0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 32)
                .offset(x: 100, y: -40)

            // Action Button (Orange)
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [.orange, Color(red: 0.8, green: 0.35, blue: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 12, height: 22)
                .offset(x: 100, y: 5)
                .shadow(color: .orange.opacity(0.4), radius: 4)

            // Side Button
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.35))
                .frame(width: 8, height: 18)
                .offset(x: 98, y: 40)
        }
    }
}

// MARK: - Previews

#Preview("Watch App") {
    WatchMockupPreview()
        .previewLayout(.fixed(width: 300, height: 500))
}

#Preview("Scoring") {
    WatchFramePreview {
        WatchScoringView()
    }
    .previewLayout(.fixed(width: 260, height: 320))
}

#Preview("Stats") {
    WatchFramePreview {
        WatchStatsView()
    }
    .previewLayout(.fixed(width: 260, height: 320))
}

// Standalone watch frame for individual screen previews
struct WatchFramePreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            ZStack {
                // Titanium case
                RoundedRectangle(cornerRadius: 52)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.45), Color(white: 0.3), Color(white: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 240)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)

                // Screen
                RoundedRectangle(cornerRadius: 40)
                    .fill(Color.black)
                    .frame(width: 168, height: 208)
                    .overlay(
                        content()
                            .clipShape(RoundedRectangle(cornerRadius: 40))
                    )

                // Digital Crown
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 12, height: 32)
                    .offset(x: 100, y: -40)

                // Action Button (Orange)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [.orange, Color(red: 0.8, green: 0.35, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 12, height: 22)
                    .offset(x: 100, y: 5)
                    .shadow(color: .orange.opacity(0.4), radius: 4)

                // Side Button
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.35))
                    .frame(width: 8, height: 18)
                    .offset(x: 98, y: 40)
            }
        }
    }
}
