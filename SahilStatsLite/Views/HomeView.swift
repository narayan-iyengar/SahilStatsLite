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
    @State private var selectedGameForDetail: Game? = nil
    @State private var showAllGames = false
    @State private var showSettings = false

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

                // Game Log Card
                gameLogCard

                // Upcoming from Calendar
                if !calendarManager.upcomingGames.isEmpty {
                    upcomingGamesSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(isPresented: $showStatsSheet) {
            CareerStatsSheet()
        }
        .sheet(item: $selectedGameForDetail) { game in
            GameDetailSheet(game: game)
        }
        .sheet(isPresented: $showAllGames) {
            AllGamesView(selectedGame: $selectedGameForDetail)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            // Settings button (combines profile + settings)
            Button {
                showSettings = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    // Sync/auth status indicator
                    if AuthService.shared.isSignedIn {
                        if persistenceManager.isSyncing {
                            Circle()
                                .fill(.orange)
                                .frame(width: 10, height: 10)
                                .offset(x: 2, y: 2)
                        } else if persistenceManager.syncError != nil {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                                .offset(x: 2, y: 2)
                        } else {
                            Circle()
                                .fill(.green)
                                .frame(width: 10, height: 10)
                                .offset(x: 2, y: 2)
                        }
                    }
                }
            }

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

            // Placeholder for symmetry
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.clear)
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

    // MARK: - Game Log Card

    private var gameLogCard: some View {
        Button(action: { showAllGames = true }) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 44, height: 44)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Game Log")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(persistenceManager.careerGames) games recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
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
                    .foregroundColor(.primary)

                Text(game.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Score and points
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.scoreString)
                    .font(.title3)
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

// MARK: - Career Stats Sheet

struct CareerStatsSheet: View {
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrendStat: TrendStat = .points

    // Sahil's birthday for age calculation
    private let birthday = Calendar.current.date(from: DateComponents(year: 2016, month: 11, day: 1))!

    enum TrendStat: String, CaseIterable {
        case points = "Points"
        case rebounds = "Rebounds"
        case assists = "Assists"
        case defense = "Defense"
        case shooting = "Shooting"
        case winRate = "Wins"

        var color: Color {
            switch self {
            case .points: return .orange
            case .rebounds: return .blue
            case .assists: return .purple
            case .defense: return .green
            case .shooting: return .cyan
            case .winRate: return .mint
            }
        }

        var label: String {
            switch self {
            case .points: return "PPG"
            case .rebounds: return "RPG"
            case .assists: return "APG"
            case .defense: return "STL+BLK"
            case .shooting: return "FG%"
            case .winRate: return "Win%"
            }
        }

        var isPercentage: Bool {
            switch self {
            case .shooting, .winRate: return true
            default: return false
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

        // Calculate average/percentage for each age
        return gamesByAge.keys.sorted().compactMap { age in
            guard let gamesAtAge = gamesByAge[age], !gamesAtAge.isEmpty else { return nil }

            let value: Double
            switch stat {
            case .points:
                let total = gamesAtAge.reduce(0) { $0 + $1.playerStats.points }
                value = Double(total) / Double(gamesAtAge.count)
            case .rebounds:
                let total = gamesAtAge.reduce(0) { $0 + $1.playerStats.rebounds }
                value = Double(total) / Double(gamesAtAge.count)
            case .assists:
                let total = gamesAtAge.reduce(0) { $0 + $1.playerStats.assists }
                value = Double(total) / Double(gamesAtAge.count)
            case .defense:
                let total = gamesAtAge.reduce(0) { $0 + $1.playerStats.steals + $1.playerStats.blocks }
                value = Double(total) / Double(gamesAtAge.count)
            case .shooting:
                let made = gamesAtAge.reduce(0) { $0 + $1.playerStats.fg2Made + $1.playerStats.fg3Made }
                let attempted = gamesAtAge.reduce(0) { $0 + $1.playerStats.fg2Attempted + $1.playerStats.fg3Attempted }
                value = attempted > 0 ? (Double(made) / Double(attempted)) * 100 : 0
            case .winRate:
                let wins = gamesAtAge.filter { $0.isWin }.count
                value = (Double(wins) / Double(gamesAtAge.count)) * 100
            }
            return (age: age, value: value)
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

                    // Trend by Age (show if we have any games)
                    if !currentTrendData.isEmpty {
                        trendCard
                    }

                    // Shooting Stats
                    shootingStatsCard
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
            HStack {
                Text("Stat:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Menu {
                    ForEach(TrendStat.allCases, id: \.self) { stat in
                        Button {
                            selectedTrendStat = stat
                        } label: {
                            HStack {
                                Text(stat.rawValue)
                                if stat == selectedTrendStat {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedTrendStat.rawValue)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(selectedTrendStat.color)
                }

                Spacer()
            }

            // Current value label
            if let latest = currentTrendData.last {
                HStack {
                    Spacer()
                    let formattedValue = selectedTrendStat.isPercentage
                        ? String(format: "%.0f%%", latest.value)
                        : String(format: "%.1f", latest.value)
                    Text("Age \(latest.age): \(formattedValue) \(selectedTrendStat.isPercentage ? "" : selectedTrendStat.label)")
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

// MARK: - All Games View

struct AllGamesView: View {
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @Binding var selectedGame: Game?
    @Environment(\.dismiss) private var dismiss

    // Filter state
    @State private var selectedFilter: GameFilter = .all
    @State private var searchText = ""

    // Pagination
    @State private var displayedCount = 20
    private let pageSize = 20

    enum GameFilter: String, CaseIterable {
        case all = "All"
        case wins = "Wins"
        case losses = "Losses"

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .wins: return "trophy.fill"
            case .losses: return "xmark.circle"
            }
        }
    }

    private var filteredGames: [Game] {
        var games = persistenceManager.savedGames

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .wins:
            games = games.filter { $0.isWin }
        case .losses:
            games = games.filter { $0.isLoss }
        }

        // Apply search
        if !searchText.isEmpty {
            games = games.filter { game in
                game.opponent.localizedCaseInsensitiveContains(searchText) ||
                game.teamName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return games
    }

    private var displayedGames: [Game] {
        Array(filteredGames.prefix(displayedCount))
    }

    private var hasMoreGames: Bool {
        displayedCount < filteredGames.count
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search opponent...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Stats summary for current filter
                filterSummary
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                // Games list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedGames) { game in
                            Button {
                                selectedGame = game
                            } label: {
                                GameRow(game: game)
                            }
                            .buttonStyle(.plain)
                        }

                        // Load more button
                        if hasMoreGames {
                            Button {
                                displayedCount += pageSize
                            } label: {
                                HStack {
                                    Text("Load More")
                                    Text("(\(filteredGames.count - displayedCount) remaining)")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                        }

                        // Empty state
                        if filteredGames.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "basketball")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No games found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                if !searchText.isEmpty {
                                    Text("Try a different search term")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("All Games")
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(GameFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                        displayedCount = pageSize // Reset pagination on filter change
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.caption)
                        Text(filter.rawValue)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedFilter == filter ? Color.orange : Color(.systemGray6))
                    .foregroundColor(selectedFilter == filter ? .white : .primary)
                    .cornerRadius(20)
                }
            }
            Spacer()
        }
    }

    // MARK: - Filter Summary

    private var filterSummary: some View {
        HStack {
            Text("\(filteredGames.count) games")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if selectedFilter == .all && filteredGames.count > 0 {
                let wins = filteredGames.filter { $0.isWin }.count
                let losses = filteredGames.filter { $0.isLoss }.count
                HStack(spacing: 12) {
                    Label("\(wins)W", systemImage: "trophy.fill")
                        .foregroundColor(.green)
                    Label("\(losses)L", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section {
                    if authService.isSignedIn {
                        // Signed in state
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(authService.displayName ?? "Signed In")
                                    .font(.headline)
                                if let email = authService.userEmail {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // Sync status
                            if persistenceManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if persistenceManager.syncError != nil {
                                Image(systemName: "exclamationmark.icloud.fill")
                                    .foregroundColor(.red)
                            } else {
                                Image(systemName: "checkmark.icloud.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 8)

                        // Sync button
                        Button {
                            Task {
                                await persistenceManager.forceSyncFromFirebase()
                            }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(persistenceManager.isSyncing)

                        // Sign out button
                        Button(role: .destructive) {
                            authService.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        // Not signed in
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Not Signed In")
                                    .font(.headline)
                                Text("Sign in to sync games across devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        Button {
                            Task {
                                await authService.signInWithGoogle()
                            }
                        } label: {
                            Label("Sign in with Google", systemImage: "g.circle.fill")
                        }
                        .disabled(authService.isLoading)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if let error = authService.error {
                        Text(error)
                            .foregroundColor(.red)
                    } else if let syncError = persistenceManager.syncError {
                        Text(syncError)
                            .foregroundColor(.red)
                    } else if authService.isSignedIn {
                        if let lastSync = persistenceManager.lastSyncTime {
                            Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }

                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Games Recorded")
                        Spacer()
                        Text("\(persistenceManager.careerGames)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
