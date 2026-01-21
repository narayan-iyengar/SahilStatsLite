//
//  WatchScoringView.swift
//  SahilStatsLiteWatch
//
//  Main scoring screen - tap scores to add points, tap clock to pause/play
//

import SwiftUI

struct WatchScoringView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @State private var showEndGame: Bool = false
    @State private var myFeedback: Int? = nil
    @State private var oppFeedback: Int? = nil
    @State private var colonVisible: Bool = true

    private var clockTime: String {
        let mins = connectivity.remainingSeconds / 60
        let secs = connectivity.remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var clockMinutes: String {
        String(connectivity.remainingSeconds / 60)
    }

    private var clockSeconds: String {
        String(format: "%02d", connectivity.remainingSeconds % 60)
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
                    connectivity.advancePeriod()
                } label: {
                    Text(connectivity.period)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                // Score area
                HStack(spacing: 0) {
                    // My team
                    scoreZone(
                        score: connectivity.myScore,
                        name: connectivity.teamName,
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
                        score: connectivity.oppScore,
                        name: connectivity.opponent,
                        isMyTeam: false,
                        feedback: oppFeedback
                    ) {
                        handleOppTeamTap()
                    }
                }
                .frame(maxHeight: .infinity)

                // Clock area
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
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            // Blink colon when clock is paused
            if !connectivity.isClockRunning {
                colonVisible.toggle()
            } else {
                colonVisible = true
            }
        }
    }

    // MARK: - Live Indicator

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectivity.isClockRunning ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(connectivity.isClockRunning ? "LIVE" : "PAUSED")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(connectivity.isClockRunning ? .green : .orange)
        }
    }

    // MARK: - Score Zone

    private func scoreZone(
        score: Int,
        name: String,
        isMyTeam: Bool,
        feedback: Int?,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Button(action: onTap) {
                    Text("\(score)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 60)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                if let points = feedback {
                    Text("+\(points)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.orange)
                        .offset(y: -30)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Truncate team name for watch display
            Text(String(name.prefix(4)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isMyTeam ? .orange : .white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clock Area

    private var clockArea: some View {
        VStack(spacing: 4) {
            clockButton

            Text(connectivity.isClockRunning ? "running" : "hold to end")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .allowsHitTesting(false)
        }
        .padding(.vertical, 6)
    }

    private var clockButton: some View {
        HStack(spacing: 0) {
            Text(clockMinutes)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
            Text(":")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .opacity(connectivity.isClockRunning ? 1.0 : (colonVisible ? 1.0 : 0.0))
            Text(clockSeconds)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(connectivity.isClockRunning ? .white : .orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            connectivity.toggleClock()
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

                Text("\(connectivity.myScore) - \(connectivity.oppScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(connectivity.myScore > connectivity.oppScore ? .green : (connectivity.myScore < connectivity.oppScore ? .red : .white))

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
                        connectivity.endGame()
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

    private func handleMyTeamTap() {
        connectivity.addScore(team: "my", points: 1)
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
        connectivity.addScore(team: "opp", points: 1)
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

#Preview {
    WatchScoringView()
        .environmentObject(WatchConnectivityClient.shared)
}
