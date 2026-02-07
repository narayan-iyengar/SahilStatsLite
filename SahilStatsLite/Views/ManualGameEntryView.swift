//
//  ManualGameEntryView.swift
//  SahilStatsLite
//
//  PURPOSE: Manual post-game stats entry without video recording. Input final
//           scores and individual player stats. Saves to persistence manager.
//  KEY TYPES: ManualGameEntryView
//  DEPENDS ON: GamePersistenceManager, AppState
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI

struct ManualGameEntryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared

    // Scores
    @State private var myScore: Int = 0
    @State private var opponentScore: Int = 0

    // Player stats
    @State private var fg2Made: Int = 0
    @State private var fg2Att: Int = 0
    @State private var fg3Made: Int = 0
    @State private var fg3Att: Int = 0
    @State private var ftMade: Int = 0
    @State private var ftAtt: Int = 0
    @State private var assists: Int = 0
    @State private var rebounds: Int = 0
    @State private var steals: Int = 0
    @State private var blocks: Int = 0
    @State private var turnovers: Int = 0
    @State private var fouls: Int = 0

    // Computed
    private var sahilPoints: Int {
        (fg2Made * 2) + (fg3Made * 3) + ftMade
    }

    private var teamName: String {
        appState.currentGame?.teamName ?? "My Team"
    }

    private var opponent: String {
        appState.currentGame?.opponent ?? "Opponent"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView {
                VStack(spacing: 20) {
                    // Score Entry
                    scoreSection

                    // Sahil's Stats
                    statsSection

                    Spacer(minLength: 20)
                }
                .padding()
            }

            // Save Button
            saveButton
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                appState.isLogOnly = false
                appState.currentScreen = .home
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Log Game")
                .font(.headline)

            Spacer()

            // Placeholder for balance
            Image(systemName: "xmark")
                .font(.title2)
                .foregroundColor(.clear)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Score Section

    private var scoreSection: some View {
        VStack(spacing: 16) {
            Text("Final Score")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                // My Team
                VStack(spacing: 8) {
                    Text(teamName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    scoreInput(value: $myScore)
                }
                .frame(maxWidth: .infinity)

                Text("vs")
                    .font(.title3)
                    .foregroundColor(.secondary)

                // Opponent
                VStack(spacing: 8) {
                    Text(opponent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    scoreInput(value: $opponentScore)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private func scoreInput(value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Button {
                if value.wrappedValue > 0 {
                    value.wrappedValue -= 1
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            Text("\(value.wrappedValue)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .frame(minWidth: 60)

            Button {
                value.wrappedValue += 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sahil's Stats")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(sahilPoints) pts")
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            // Shooting stats
            HStack(spacing: 12) {
                shootingTile("2PT", made: $fg2Made, att: $fg2Att, color: .blue)
                shootingTile("3PT", made: $fg3Made, att: $fg3Att, color: .purple)
                shootingTile("FT", made: $ftMade, att: $ftAtt, color: .cyan)
            }

            // Other stats
            HStack(spacing: 8) {
                statTile("AST", $assists, .green)
                statTile("REB", $rebounds, .orange)
                statTile("STL", $steals, .teal)
                statTile("BLK", $blocks, .indigo)
                statTile("TO", $turnovers, .red)
                statTile("PF", $fouls, .gray)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Reusable Tiles (same pattern as UltraMinimalRecordingView)

    private func shootingTile(_ label: String, made: Binding<Int>, att: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)

            Text("\(made.wrappedValue)/\(att.wrappedValue)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            HStack(spacing: 6) {
                // Make button
                Button {
                    made.wrappedValue += 1
                    att.wrappedValue += 1
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color.green)
                        .cornerRadius(6)
                }

                // Miss button
                Button {
                    att.wrappedValue += 1
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 26)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private func statTile(_ label: String, _ value: Binding<Int>, _ color: Color) -> some View {
        Button {
            value.wrappedValue += 1
        } label: {
            VStack(spacing: 2) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveGame()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Game")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.orange)
            .cornerRadius(16)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func saveGame() {
        guard var game = appState.currentGame else { return }

        // Update scores
        game.myScore = myScore
        game.opponentScore = opponentScore

        // Update player stats
        game.playerStats = PlayerStats(
            fg2Made: fg2Made,
            fg2Attempted: fg2Att,
            fg3Made: fg3Made,
            fg3Attempted: fg3Att,
            ftMade: ftMade,
            ftAttempted: ftAtt,
            assists: assists,
            rebounds: rebounds,
            steals: steals,
            blocks: blocks,
            turnovers: turnovers,
            fouls: fouls
        )

        // Mark as completed
        game.completedAt = Date()

        // Save
        appState.currentGame = game
        persistenceManager.saveGame(game)

        // Reset log-only mode and go to summary
        appState.isLogOnly = false
        appState.currentScreen = .summary
    }
}

#Preview {
    ManualGameEntryView()
        .environmentObject(AppState())
}
