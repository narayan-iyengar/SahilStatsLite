//
//  UpcomingGamesViews.swift
//  SahilStatsLite
//
//  PURPOSE: Calendar-based upcoming games UI components. Hero card for next game,
//           tournament day rows, upcoming games sheet with grouped list.
//  KEY TYPES: NextGameHeroCard, LaterTodaySection, LaterTodayRow,
//             UpcomingGamesSheet, UpcomingGameListRow
//  DEPENDS ON: GameCalendarManager, AppState
//
//  NOTE: Keep this header updated when modifying this file.
//

import SwiftUI

// MARK: - Next Game Hero Card

struct NextGameHeroCard: View {
    let game: GameCalendarManager.CalendarGame
    let todayCount: Int
    let appState: AppState
    let onHide: (String) -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(game.startTime)
    }

    private var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(game.startTime)
    }

    private var dayLabel: String {
        if isToday {
            return "TODAY"
        } else if isTomorrow {
            return "TOMORROW"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: game.startTime).uppercased()
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: game.startTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - NEXT GAME badge
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isToday ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("NEXT GAME")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(isToday ? .green : .orange)
                }

                Spacer()

                // Tournament day indicator
                if todayCount > 1 && isToday {
                    Text("1 of \(todayCount) today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Hide button - subtle, one tap
                Button {
                    onHide(game.id)
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.footnote)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Main content
            VStack(spacing: 16) {
                // Day and Date
                VStack(spacing: 2) {
                    Text(dayLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isToday ? .green : .orange)

                    if !isToday && !isTomorrow {
                        Text(dateLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Time - large and prominent
                Text(game.timeString)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                // Opponent - the main info
                Text(game.opponent)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Location
                if !game.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                        Text(game.location)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Record Game button
            Button {
                appState.pendingCalendarGame = (opponent: game.opponent, location: game.location, team: game.detectedTeam)
                appState.isLogOnly = false
                appState.currentScreen = .setup
            } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Record Game")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

// MARK: - Later Today Section (Tournament Days)

struct LaterTodaySection: View {
    let games: [GameCalendarManager.CalendarGame]
    let appState: AppState
    let onHide: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LATER TODAY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(games) { game in
                    LaterTodayRow(game: game, appState: appState, onHide: onHide)

                    if game.id != games.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
}

struct LaterTodayRow: View {
    let game: GameCalendarManager.CalendarGame
    let appState: AppState
    let onHide: (String) -> Void

    var body: some View {
        Button {
            appState.pendingCalendarGame = (opponent: game.opponent, location: game.location, team: game.detectedTeam)
            appState.isLogOnly = false
            appState.currentScreen = .setup
        } label: {
            HStack(spacing: 12) {
                // Time
                Text(game.timeString)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(width: 50, alignment: .leading)

                // Color indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.6))
                    .frame(width: 3, height: 32)

                // Opponent
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.opponent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if !game.location.isEmpty {
                        Text(game.location)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Subtle action indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onHide(game.id)
            } label: {
                Label("Hide this game", systemImage: "eye.slash")
            }
        }
    }
}

// MARK: - Upcoming Games Sheet

struct UpcomingGamesSheet: View {
    @ObservedObject var calendarManager: GameCalendarManager
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if calendarManager.upcomingGames.isEmpty {
                    ContentUnavailableView(
                        "No Upcoming Games",
                        systemImage: "calendar",
                        description: Text("Games with your team names will appear here")
                    )
                } else {
                    ForEach(groupedGames, id: \.0) { date, games in
                        Section(header: Text(sectionHeader(for: date))) {
                            ForEach(games) { game in
                                UpcomingGameListRow(game: game, appState: appState, dismiss: dismiss)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    calendarManager.ignoreEvent(games[index].id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upcoming Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var groupedGames: [(Date, [GameCalendarManager.CalendarGame])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: calendarManager.upcomingGames) { game in
            calendar.startOfDay(for: game.startTime)
        }
        return grouped.sorted { $0.key < $1.key }
    }

    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

struct UpcomingGameListRow: View {
    let game: GameCalendarManager.CalendarGame
    let appState: AppState
    let dismiss: DismissAction

    var body: some View {
        Button {
            appState.pendingCalendarGame = (opponent: game.opponent, location: game.location, team: game.detectedTeam)
            appState.isLogOnly = false
            appState.currentScreen = .setup
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.opponent)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if !game.location.isEmpty {
                        Text(game.location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(game.timeString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
