//
//  HomeView.swift
//  SahilStatsLite
//
//  Main home screen with recent games and new game button
//

import SwiftUI
import Combine
import Charts

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = GameCalendarManager.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @State private var showStatsSheet = false
    @State private var selectedGame: Game? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // New Game Button
                newGameButton

                // Career Stats Card (if we have games)
                if persistenceManager.careerGames > 0 {
                    careerStatsCard
                }

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
        .sheet(isPresented: $showStatsSheet) {
            CareerStatsSheet(selectedGame: $selectedGame)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Spacer()

            VStack(spacing: 4) {
                Text("Sahil Stats")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Record. Track. Share.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Settings button (placeholder for future)
            Button(action: { /* TODO: Show settings */ }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
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

    // MARK: - Career Stats Card

    private var careerStatsCard: some View {
        Button(action: { showStatsSheet = true }) {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Career Stats")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(persistenceManager.careerGames) games")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Stats row
                HStack(spacing: 0) {
                    statItem(value: String(format: "%.1f", persistenceManager.careerPPG), label: "PPG", color: .orange)
                    statItem(value: String(format: "%.1f", persistenceManager.careerRPG), label: "RPG", color: .blue)
                    statItem(value: String(format: "%.1f", persistenceManager.careerAPG), label: "APG", color: .green)
                    statItem(value: persistenceManager.careerRecord, label: "W-L", color: .primary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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

// MARK: - Career Stats Sheet

struct CareerStatsSheet: View {
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @Binding var selectedGame: Game?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrendStat: TrendStat = .points

    // Sahil's birthday for age calculation
    private let birthday = Calendar.current.date(from: DateComponents(year: 2016, month: 11, day: 1))!

    enum TrendStat: String, CaseIterable {
        case points = "Points"
        case rebounds = "Rebounds"
        case defense = "Defense"

        var color: Color {
            switch self {
            case .points: return .orange
            case .rebounds: return .blue
            case .defense: return .green
            }
        }

        var label: String {
            switch self {
            case .points: return "PPG"
            case .rebounds: return "RPG"
            case .defense: return "STL+BLK"
            }
        }
    }

    // Calculate age at a given date
    private func ageAtDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthday, to: date)
        return ageComponents.year ?? 0
    }

    // Group games by age and calculate stat averages
    private func statsByAge(for stat: TrendStat) -> [(age: Int, value: Double)] {
        let games = persistenceManager.savedGames
        guard !games.isEmpty else { return [] }

        // Group games by age
        var gamesByAge: [Int: [Game]] = [:]
        for game in games {
            let age = ageAtDate(game.date)
            gamesByAge[age, default: []].append(game)
        }

        // Calculate average for each age
        return gamesByAge.keys.sorted().compactMap { age in
            guard let gamesAtAge = gamesByAge[age], !gamesAtAge.isEmpty else { return nil }
            let total: Int
            switch stat {
            case .points:
                total = gamesAtAge.reduce(0) { $0 + $1.playerStats.points }
            case .rebounds:
                total = gamesAtAge.reduce(0) { $0 + $1.playerStats.rebounds }
            case .defense:
                total = gamesAtAge.reduce(0) { $0 + $1.playerStats.steals + $1.playerStats.blocks }
            }
            let avg = Double(total) / Double(gamesAtAge.count)
            return (age: age, value: avg)
        }
    }

    private var currentTrendData: [(age: Int, value: Double)] {
        statsByAge(for: selectedTrendStat)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Career Averages
                    careerAveragesCard

                    // Trend by Age (only show if we have data from multiple ages)
                    if currentTrendData.count >= 2 {
                        trendCard
                    }

                    // Shooting Stats
                    shootingStatsCard

                    // Game Log
                    gameLogSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Career Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedGame) { game in
                GameDetailSheet(game: game)
            }
        }
    }

    // MARK: - Trend Card

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress by Age")
                    .font(.headline)
                Spacer()
            }

            // Stat picker
            Picker("Stat", selection: $selectedTrendStat) {
                ForEach(TrendStat.allCases, id: \.self) { stat in
                    Text(stat.rawValue).tag(stat)
                }
            }
            .pickerStyle(.segmented)

            // Current value label
            if let latest = currentTrendData.last {
                HStack {
                    Spacer()
                    Text("Age \(latest.age): \(String(format: "%.1f", latest.value)) \(selectedTrendStat.label)")
                        .font(.caption)
                        .foregroundColor(selectedTrendStat.color)
                }
            }

            Chart {
                ForEach(currentTrendData, id: \.age) { dataPoint in
                    LineMark(
                        x: .value("Age", "Age \(dataPoint.age)"),
                        y: .value(selectedTrendStat.label, dataPoint.value)
                    )
                    .foregroundStyle(selectedTrendStat.color.gradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))

                    PointMark(
                        x: .value("Age", "Age \(dataPoint.age)"),
                        y: .value(selectedTrendStat.label, dataPoint.value)
                    )
                    .foregroundStyle(selectedTrendStat.color)
                    .symbolSize(60)

                    AreaMark(
                        x: .value("Age", "Age \(dataPoint.age)"),
                        y: .value(selectedTrendStat.label, dataPoint.value)
                    )
                    .foregroundStyle(selectedTrendStat.color.opacity(0.1).gradient)
                }
            }
            .frame(height: 150)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(String(format: "%.1f", doubleValue))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let stringValue = value.as(String.self) {
                            Text(stringValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedTrendStat)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    // MARK: - Career Averages Card

    private var careerAveragesCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Career Averages")
                    .font(.headline)
                Spacer()
                Text("\(persistenceManager.careerGames) games")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 0) {
                careerStat(value: String(format: "%.1f", persistenceManager.careerPPG), label: "PPG", color: .orange)
                careerStat(value: String(format: "%.1f", persistenceManager.careerRPG), label: "RPG", color: .blue)
                careerStat(value: String(format: "%.1f", persistenceManager.careerAPG), label: "APG", color: .green)
                careerStat(value: String(format: "%.1f", persistenceManager.careerSPG), label: "SPG", color: .teal)
                careerStat(value: String(format: "%.1f", persistenceManager.careerBPG), label: "BPG", color: .purple)
            }

            // Record
            HStack(spacing: 20) {
                Label(persistenceManager.careerRecord, systemImage: "trophy.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if persistenceManager.careerGames > 0 {
                    let winPct = Double(persistenceManager.careerWins) / Double(persistenceManager.careerGames) * 100
                    Text(String(format: "%.0f%% Win Rate", winPct))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private func careerStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shooting Stats Card

    private var shootingStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Shooting")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 20) {
                shootingCircle(
                    label: "FG",
                    made: persistenceManager.careerFGMade,
                    attempted: persistenceManager.careerFGAttempted,
                    pct: persistenceManager.careerFGPercentage,
                    color: .blue
                )
                shootingCircle(
                    label: "3PT",
                    made: persistenceManager.career3PMade,
                    attempted: persistenceManager.career3PAttempted,
                    pct: persistenceManager.career3PPercentage,
                    color: .purple
                )
                shootingCircle(
                    label: "FT",
                    made: persistenceManager.careerFTMade,
                    attempted: persistenceManager.careerFTAttempted,
                    pct: persistenceManager.careerFTPercentage,
                    color: .cyan
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private func shootingCircle(label: String, made: Int, attempted: Int, pct: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: min(pct / 100, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text("\(made)/\(attempted)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Game Log Section

    private var gameLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Log")
                .font(.headline)

            if persistenceManager.savedGames.isEmpty {
                Text("No games recorded yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(persistenceManager.savedGames) { game in
                    Button(action: { selectedGame = game }) {
                        GameLogRow(game: game)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Game Log Row

struct GameLogRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            // Result badge
            Text(game.resultString)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(game.isWin ? Color.green : (game.isLoss ? Color.red : Color.orange))
                .cornerRadius(6)

            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(game.opponent)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(game.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Score and points
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.scoreString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text("\(game.playerStats.points) pts")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Game Detail Sheet

struct GameDetailSheet: View {
    let game: Game
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Result Header
                    VStack(spacing: 8) {
                        Text(game.isWin ? "Victory" : (game.isLoss ? "Defeat" : "Tie"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(game.isWin ? .green : (game.isLoss ? .red : .orange))

                        Text(game.scoreString)
                            .font(.system(size: 48, weight: .bold, design: .rounded))

                        Text("vs \(game.opponent)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(game.date.formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    // Player Stats
                    VStack(spacing: 16) {
                        Text("Sahil's Stats")
                            .font(.headline)

                        HStack(spacing: 0) {
                            statBox(value: "\(game.playerStats.points)", label: "PTS", color: .orange)
                            statBox(value: "\(game.playerStats.rebounds)", label: "REB", color: .blue)
                            statBox(value: "\(game.playerStats.assists)", label: "AST", color: .green)
                            statBox(value: "\(game.playerStats.steals)", label: "STL", color: .teal)
                            statBox(value: "\(game.playerStats.blocks)", label: "BLK", color: .purple)
                        }

                        // Shooting
                        HStack(spacing: 20) {
                            shootingStat(label: "2PT", made: game.playerStats.fg2Made, attempted: game.playerStats.fg2Attempted)
                            shootingStat(label: "3PT", made: game.playerStats.fg3Made, attempted: game.playerStats.fg3Attempted)
                            shootingStat(label: "FT", made: game.playerStats.ftMade, attempted: game.playerStats.ftAttempted)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Game Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statBox(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func shootingStat(label: String, made: Int, attempted: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(made)/\(attempted)")
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
