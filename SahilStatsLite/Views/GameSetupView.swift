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

    @State private var opponent: String = ""
    @State private var teamName: String = "Wildcats"
    @State private var location: String = ""
    @State private var quarterLength: Int = 6

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

                    // Quarter Length
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quarter Length")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Quarter Length", selection: $quarterLength) {
                            Text("5 min").tag(5)
                            Text("6 min").tag(6)
                            Text("8 min").tag(8)
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
            isOpponentFocused = true
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
        game.quarterLength = quarterLength
        appState.currentGame = game
        appState.currentScreen = .recording
    }
}

#Preview {
    GameSetupView()
        .environmentObject(AppState())
}
