//
//  WatchGameConfirmationView.swift
//  SahilStatsLiteWatch
//
//  Confirmation screen before starting a game from Watch
//  Shows game details and Start Recording / Cancel buttons
//

import SwiftUI

struct WatchGameConfirmationView: View {
    let game: WatchGame
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @Environment(\.dismiss) private var dismiss

    @State private var isStarting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Game info card
                VStack(spacing: 8) {
                    // Opponent (big)
                    Text("vs \(game.opponent)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    // Your team
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text(game.teamName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                    }

                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 4)

                    // Time
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))

                        if game.isToday {
                            Text(game.timeString)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        } else {
                            Text("\(game.dayString) \(game.timeString)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }

                    // Location (if available)
                    if !game.location.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                            Text(game.location)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    // Half length
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(game.halfLength) min halves")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)

                Spacer(minLength: 8)

                // Buttons
                if isStarting {
                    // Starting state
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.orange)
                        Text("Starting...")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 10) {
                        // Start Recording button
                        Button(action: startGame) {
                            HStack(spacing: 6) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Start Recording")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)

                        // Cancel button
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startGame() {
        isStarting = true

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)

        // Send to phone - this will trigger recording mode
        connectivity.startGame(game)

        // Brief delay to show starting state, then dismiss
        // The main view will switch to scoring mode when hasActiveGame becomes true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// Quick game confirmation (for games without calendar details)
struct WatchQuickGameConfirmationView: View {
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @Environment(\.dismiss) private var dismiss

    @State private var opponent: String = "Away"
    @State private var halfLength: Int = 18
    @State private var isStarting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Opponent picker (simplified)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Opponent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    TextField("Team name", text: $opponent)
                        .font(.system(size: 14, weight: .semibold))
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }

                // Half length picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Half Length")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Picker("Half", selection: $halfLength) {
                        Text("18 min").tag(18)
                        Text("20 min").tag(20)
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 50)
                }

                Spacer(minLength: 8)

                // Buttons
                if isStarting {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.orange)
                        Text("Starting...")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    VStack(spacing: 10) {
                        Button(action: startQuickGame) {
                            HStack(spacing: 6) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Start Recording")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)

                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Quick Game")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startQuickGame() {
        isStarting = true
        WKInterfaceDevice.current().play(.click)

        let game = WatchGame(
            id: UUID().uuidString,
            opponent: opponent.isEmpty ? "Away" : opponent,
            teamName: "Home",
            location: "",
            startTime: Date(),
            halfLength: halfLength
        )

        connectivity.startGame(game)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

#Preview {
    WatchGameConfirmationView(
        game: WatchGame(
            id: "1",
            opponent: "Warriors Elite",
            teamName: "Bay Area Lava",
            location: "Main Gym",
            startTime: Date(),
            halfLength: 18
        )
    )
    .environmentObject(WatchConnectivityClient.shared)
}
