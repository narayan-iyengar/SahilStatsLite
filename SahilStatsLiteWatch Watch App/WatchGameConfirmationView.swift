//
//  WatchGameConfirmationView.swift
//  SahilStatsLiteWatch
//
//  PURPOSE: Pre-game confirmation screen on Watch. Shows opponent, team,
//           and time for a selected upcoming game. Start Recording button
//           sends startGame message to iPhone via WatchConnectivity.
//  KEY TYPES: WatchGameConfirmationView
//  DEPENDS ON: WatchConnectivityClient, WatchGame
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI

struct WatchGameConfirmationView: View {
    let game: WatchGame
    @EnvironmentObject var connectivity: WatchConnectivityClient
    @Environment(\.dismiss) private var dismiss

    @State private var isStarting = false
    @State private var selectedHalfLength: Int = 18

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

                    // Half length (Tappable to change)
                    Button(action: {
                        // Toggle between 18 and 20
                        if selectedHalfLength == 18 {
                            selectedHalfLength = 20
                        } else {
                            selectedHalfLength = 18
                        }
                        WKInterfaceDevice.current().play(.click)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            Text("\(selectedHalfLength) min halves")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.orange.opacity(0.7))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
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
        .onAppear {
            selectedHalfLength = game.halfLength
        }
    }

    private func startGame() {
        isStarting = true

        // Haptic feedback
        WKInterfaceDevice.current().play(.click)

        // Create updated game object with selected half length
        let updatedGame = WatchGame(
            id: game.id,
            opponent: game.opponent,
            teamName: game.teamName,
            location: game.location,
            startTime: game.startTime,
            halfLength: selectedHalfLength
        )

        // Send to phone - this will trigger recording mode
        connectivity.startGame(updatedGame)

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
