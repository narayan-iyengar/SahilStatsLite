//
//  HomeView.swift
//  SahilStatsLite
//
//  Main home screen with recent games and new game button
//

import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = GameCalendarManager.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // New Game Button
                newGameButton

                // Upcoming from Calendar
                if !calendarManager.upcomingGames.isEmpty {
                    upcomingGamesSection
                }

                // Recent Games
                if !appState.recentGames.isEmpty {
                    recentGamesSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Sahil Stats")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Record. Track. Share.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - New Game Button

    private var newGameButton: some View {
        Button {
            appState.currentScreen = .setup
        } label: {
            HStack {
                Image(systemName: "video.fill")
                    .font(.title2)
                Text("New Game")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.orange)
            .cornerRadius(16)
        }
    }

    // MARK: - Upcoming Games

    private var upcomingGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming")
                .font(.headline)
                .foregroundColor(.secondary)

            ForEach(calendarManager.upcomingGames.prefix(3)) { game in
                CalendarGameRow(game: game) {
                    appState.startNewGame(
                        opponent: game.opponent,
                        teamName: "Wildcats", // TODO: Get from settings
                        location: game.location
                    )
                }
            }
        }
    }

    // MARK: - Recent Games

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(.headline)
                .foregroundColor(.secondary)

            ForEach(appState.recentGames.prefix(5)) { game in
                GameRow(game: game)
            }
        }
    }
}

// MARK: - Calendar Game Row

struct CalendarGameRow: View {
    let game: GameCalendarManager.CalendarGame
    let onStart: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(game.dateString, systemImage: "calendar")
                    Label(game.timeString, systemImage: "clock")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if !game.location.isEmpty {
                    Label(game.location, systemImage: "location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Start") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Game Row

struct GameRow: View {
    let game: Game

    var body: some View {
        HStack {
            // Result indicator
            Text(game.resultString)
                .font(.headline)
                .foregroundColor(game.isWin ? .green : game.isLoss ? .red : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("vs \(game.opponent)")
                    .font(.headline)

                Text(game.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(game.scoreString)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
