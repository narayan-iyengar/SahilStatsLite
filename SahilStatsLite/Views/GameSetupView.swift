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

    // Teams loaded from UserDefaults
    @State private var teams: [String] = []
    @State private var selectedTeam: String = ""

    @State private var opponent: String = ""
    @State private var location: String = ""
    @State private var halfLength: Int = 18  // AAU: 18 or 20 minute halves
    @State private var recordVideo: Bool = true  // Toggle for video recording

    @FocusState private var isOpponentFocused: Bool

    private let teamsKey = "myTeams"

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

                Text(appState.isLogOnly ? "Log Game" : "New Game")
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

                        if teams.count > 1 {
                            Picker("Team", selection: $selectedTeam) {
                                ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                                    Text(team).tag(team)
                                }
                            }
                            .pickerStyle(.segmented)
                        } else {
                            // Single team - just show it
                            Text(selectedTeam.isEmpty ? "No team configured" : selectedTeam)
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
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

                    // Record Video Toggle (only show when not in log-only mode)
                    if !appState.isLogOnly {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Record Video")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(recordVideo ? "Game will be recorded" : "Stats only, no video")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Toggle("", isOn: $recordVideo)
                                .tint(.orange)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }

                    // Gimbal Status (only show if recording video)
                    if recordVideo && !appState.isLogOnly {
                        gimbalStatusCard
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }

            // Start Button
            Button {
                startGame()
            } label: {
                HStack {
                    Image(systemName: appState.isLogOnly ? "pencil.line" : (recordVideo ? "video.fill" : "sportscourt.fill"))
                    Text(appState.isLogOnly ? "Enter Stats" : (recordVideo ? "Start Recording" : "Start Live Stats"))
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
            // Load teams from UserDefaults
            loadTeams()

            // Pre-fill from calendar if available
            if let pending = appState.pendingCalendarGame {
                opponent = pending.opponent
                location = pending.location

                // Auto-select team if detected from calendar
                if let detectedTeam = pending.team {
                    // Find matching team (case-insensitive)
                    if let matchingTeam = teams.first(where: { $0.lowercased() == detectedTeam.lowercased() }) {
                        selectedTeam = matchingTeam
                    } else if let matchingTeam = teams.first(where: { $0.lowercased().contains(detectedTeam.lowercased()) || detectedTeam.lowercased().contains($0.lowercased()) }) {
                        selectedTeam = matchingTeam
                    }
                }

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

    private func loadTeams() {
        if let data = UserDefaults.standard.data(forKey: teamsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            teams = decoded
        } else {
            // Fallback: check old single team key or use default
            if let oldTeam = UserDefaults.standard.string(forKey: "myTeamName"), !oldTeam.isEmpty {
                teams = [oldTeam]
            } else {
                teams = ["Wildcats"]
            }
        }
        // Select first team by default
        if selectedTeam.isEmpty, let first = teams.first {
            selectedTeam = first
        }
    }

    private func startGame() {
        var game = Game(
            opponent: opponent,
            teamName: selectedTeam,
            location: location.isEmpty ? nil : location
        )
        game.halfLength = halfLength
        appState.currentGame = game

        // Navigate based on mode
        if appState.isLogOnly {
            appState.currentScreen = .statsEntry
        } else {
            appState.isStatsOnly = !recordVideo
            appState.currentScreen = .recording
        }
    }
}

#Preview {
    GameSetupView()
        .environmentObject(AppState())
}
