//
//  GameSetupView.swift
//  SahilStatsLite
//
//  Quick game setup - just opponent name and optional location
//

import SwiftUI

struct GameSetupView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var gimbalManager = GimbalTrackingManager.shared

    // Get saved team name from UserDefaults
    @AppStorage("myTeamName") private var savedTeamName: String = "Wildcats"

    @State private var opponent: String = ""
    @State private var teamName: String = ""
    @State private var location: String = ""
    @State private var halfLength: Int = 18  // AAU: 18 or 20 minute halves

    @FocusState private var isOpponentFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button {
                    appState.currentScreen = .home
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("New Game")
                    .font(.headline)

                Spacer()

                // Placeholder for balance
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.clear)
            }
            .padding()

            ScrollView {
                VStack(spacing: 20) {
                    // Opponent
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Opponent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Team name", text: $opponent)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .focused($isOpponentFocused)
                    }

                    // Your Team
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Team")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Team name", text: $teamName)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                    }

                    // Location (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("Gym or venue", text: $location)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Half Length (AAU games use halves)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Half Length")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Half Length", selection: $halfLength) {
                            Text("18 min").tag(18)
                            Text("20 min").tag(20)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Gimbal Status
                    gimbalStatusCard

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }

            // Start Button
            Button {
                startGame()
            } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Start Recording")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(opponent.isEmpty ? Color.gray : Color.orange)
                .cornerRadius(16)
            }
            .disabled(opponent.isEmpty)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            // Pre-fill team name from settings
            if teamName.isEmpty {
                teamName = savedTeamName
            }

            // Pre-fill from calendar if available
            if let pending = appState.pendingCalendarGame {
                opponent = pending.opponent
                location = pending.location
                // Clear after use
                appState.pendingCalendarGame = nil
            }
            // Focus opponent field if empty
            if opponent.isEmpty {
                isOpponentFocused = true
            }
        }
    }

    // MARK: - Gimbal Status

    private var gimbalStatusCard: some View {
        HStack {
            Image(systemName: gimbalManager.isDockKitAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(gimbalManager.isDockKitAvailable ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(gimbalManager.isDockKitAvailable ? "Gimbal Connected" : "No Gimbal Detected")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(gimbalManager.isDockKitAvailable ? "Auto-tracking ready" : "Recording will work, but no auto-tracking")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func startGame() {
        var game = Game(
            opponent: opponent,
            teamName: teamName,
            location: location.isEmpty ? nil : location
        )
        game.halfLength = halfLength
        appState.currentGame = game
        appState.currentScreen = .recording
    }
}

#Preview {
    GameSetupView()
        .environmentObject(AppState())
}
