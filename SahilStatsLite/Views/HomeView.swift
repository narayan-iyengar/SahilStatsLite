//
//  HomeView.swift
//  SahilStatsLite
//
//  Main home screen with recent games and new game button
//

import SwiftUI
import Combine
import Charts
import EventKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var calendarManager = GameCalendarManager.shared
    @ObservedObject private var persistenceManager = GamePersistenceManager.shared
    @State private var showStatsSheet = false
    @State private var showAllGames = false
    @State private var showSettings = false
    @State private var selectedDate: Date = Date()
    @State private var navigateToDay = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Calendar (primary - this is how games are discovered)
                    if calendarManager.hasCalendarAccess {
                        calendarSection
                    } else {
                        calendarAccessCard
                    }

                    // Career Stats Card (if we have games)
                    if persistenceManager.careerGames > 0 {
                        careerStatsCard
                    }

                    // Game Log Card
                    gameLogCard

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $navigateToDay) {
                DayGamesView(date: selectedDate, calendarManager: calendarManager)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showStatsSheet) {
                CareerStatsSheet()
            }
            .sheet(isPresented: $showAllGames) {
                AllGamesView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
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

            // New Game button (+ icon for recording)
            Button {
                appState.isLogOnly = false
                appState.currentScreen = .setup
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.top, 20)
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
        HStack(spacing: 12) {
            // Main card - tap to view all games
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

            // Add game button (manual entry)
            Button {
                appState.isLogOnly = true
                appState.currentScreen = .setup
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Add")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 56)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Schedule")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Text("Calendars")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            CalendarMonthView(
                selectedDate: $selectedDate,
                calendarManager: calendarManager,
                onDateTap: { date in
                    selectedDate = date
                    let games = calendarManager.games(for: date)
                    if !games.isEmpty {
                        navigateToDay = true
                    }
                }
            )
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
    }

    private var calendarAccessCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Connect Calendar")
                .font(.headline)

            Text("See upcoming games from your calendar")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await calendarManager.requestCalendarAccess()
                }
            } label: {
                Text("Allow Access")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Calendar Month View

struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    @ObservedObject var calendarManager: GameCalendarManager
    var onDateTap: (Date) -> Void

    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [Date?] = []
        var currentDate = monthFirstWeek.start

        // Add days for 6 weeks (covers all possible month layouts)
        for _ in 0..<42 {
            if calendar.isDate(currentDate, equalTo: displayedMonth, toGranularity: .month) {
                days.append(currentDate)
            } else if days.isEmpty || days.last != nil {
                days.append(nil)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // Trim trailing nils
        while days.last == nil && days.count > 0 {
            days.removeLast()
        }

        return days
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button {
                    withAnimation {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.orange)
                }

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            hasGames: !calendarManager.games(for: date).isEmpty,
                            onTap: { onDateTap(date) }
                        )
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let hasGames: Bool
    let onTap: () -> Void

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(hasGames ? .bold : .regular)
                    .foregroundColor(foregroundColor)

                // Game indicator dot
                Circle()
                    .fill(hasGames ? Color.orange : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .orange
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return .orange
        } else {
            return .clear
        }
    }
}

// MARK: - Day Games View (iOS Calendar-style navigation)

struct DayGamesView: View {
    let date: Date
    @ObservedObject var calendarManager: GameCalendarManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var games: [GameCalendarManager.CalendarGame] {
        calendarManager.games(for: date)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    private var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Large date header (like iOS Calendar day view)
                VStack(spacing: 4) {
                    Text(dayNumber)
                        .font(.system(size: 72, weight: .light, design: .rounded))
                        .foregroundColor(Calendar.current.isDateInToday(date) ? .orange : .primary)

                    Text(dateTitle)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.systemBackground))

                Divider()

                // Games list
                if games.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No Games Scheduled")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(games) { game in
                            Button {
                                appState.pendingCalendarGame = (opponent: game.opponent, location: game.location)
                                appState.currentScreen = .setup
                            } label: {
                                gameRow(game)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                    .background(Color(.systemBackground))
                }

                Spacer(minLength: 100)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(yearString)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func gameRow(_ game: GameCalendarManager.CalendarGame) -> some View {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.timeString)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(width: 60, alignment: .trailing)

            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 4)

            // Game details
            VStack(alignment: .leading, spacing: 4) {
                Text(game.opponent)
                    .font(.headline)
                    .foregroundColor(.primary)

                if !game.location.isEmpty {
                    Label(game.location, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(game.calendarTitle)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            // Play button
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
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
    @State private var selectedTimePeriod: TimePeriod = .byWeek

    // Sahil's birthday for age calculation
    private let birthday = Calendar.current.date(from: DateComponents(year: 2016, month: 11, day: 1))!

    enum TimePeriod: String, CaseIterable {
        case byAge = "By Age"
        case byMonth = "By Month"
        case byWeek = "By Week"

        var icon: String {
            switch self {
            case .byAge: return "person.fill"
            case .byMonth: return "calendar"
            case .byWeek: return "calendar.day.timeline.left"
            }
        }
    }

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

    // Calculate stat value for a group of games
    private func calculateStatValue(for stat: TrendStat, games: [Game]) -> Double {
        guard !games.isEmpty else { return 0 }

        switch stat {
        case .points:
            let total = games.reduce(0) { $0 + $1.playerStats.points }
            return Double(total) / Double(games.count)
        case .rebounds:
            let total = games.reduce(0) { $0 + $1.playerStats.rebounds }
            return Double(total) / Double(games.count)
        case .assists:
            let total = games.reduce(0) { $0 + $1.playerStats.assists }
            return Double(total) / Double(games.count)
        case .defense:
            let total = games.reduce(0) { $0 + $1.playerStats.steals + $1.playerStats.blocks }
            return Double(total) / Double(games.count)
        case .shooting:
            let made = games.reduce(0) { $0 + $1.playerStats.fg2Made + $1.playerStats.fg3Made }
            let attempted = games.reduce(0) { $0 + $1.playerStats.fg2Attempted + $1.playerStats.fg3Attempted }
            return attempted > 0 ? (Double(made) / Double(attempted)) * 100 : 0
        case .winRate:
            let wins = games.filter { $0.isWin }.count
            return (Double(wins) / Double(games.count)) * 100
        }
    }

    // Group games by age and calculate stat averages
    private func statsByAge(for stat: TrendStat) -> [(label: String, value: Double)] {
        let games = persistenceManager.savedGames
        guard !games.isEmpty else { return [] }

        var gamesByAge: [Int: [Game]] = [:]
        for game in games {
            let age = ageAtDate(game.date)
            gamesByAge[age, default: []].append(game)
        }

        return gamesByAge.keys.sorted().compactMap { age in
            guard let gamesAtAge = gamesByAge[age], !gamesAtAge.isEmpty else { return nil }
            return (label: "Age \(age)", value: calculateStatValue(for: stat, games: gamesAtAge))
        }
    }

    // Group games by week and calculate stat averages
    private func statsByWeek(for stat: TrendStat) -> [(label: String, value: Double)] {
        let games = persistenceManager.savedGames
        guard !games.isEmpty else { return [] }

        let calendar = Calendar.current
        var gamesByWeek: [String: [Game]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd"

        for game in games {
            let weekOfYear = calendar.component(.weekOfYear, from: game.date)
            let year = calendar.component(.year, from: game.date)
            let key = "\(year)-W\(weekOfYear)"
            gamesByWeek[key, default: []].append(game)
        }

        // Sort by date and take last 12 weeks for readability
        let sortedKeys = gamesByWeek.keys.sorted()
        let recentKeys = sortedKeys.suffix(12)

        return recentKeys.compactMap { key in
            guard let gamesInWeek = gamesByWeek[key], !gamesInWeek.isEmpty else { return nil }
            let weekStart = gamesInWeek.first!.date
            let label = dateFormatter.string(from: weekStart)
            return (label: label, value: calculateStatValue(for: stat, games: gamesInWeek))
        }
    }

    // Group games by month and calculate stat averages
    private func statsByMonth(for stat: TrendStat) -> [(label: String, value: Double)] {
        let games = persistenceManager.savedGames
        guard !games.isEmpty else { return [] }

        let calendar = Calendar.current
        var gamesByMonth: [String: [Game]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yy"

        for game in games {
            let month = calendar.component(.month, from: game.date)
            let year = calendar.component(.year, from: game.date)
            let key = "\(year)-\(month)"
            gamesByMonth[key, default: []].append(game)
        }

        // Sort by date
        let sortedKeys = gamesByMonth.keys.sorted()

        return sortedKeys.compactMap { key in
            guard let gamesInMonth = gamesByMonth[key], !gamesInMonth.isEmpty else { return nil }
            let label = dateFormatter.string(from: gamesInMonth.first!.date)
            return (label: label, value: calculateStatValue(for: stat, games: gamesInMonth))
        }
    }

    private var currentTrendData: [(label: String, value: Double)] {
        switch selectedTimePeriod {
        case .byAge:
            return statsByAge(for: selectedTrendStat)
        case .byWeek:
            return statsByWeek(for: selectedTrendStat)
        case .byMonth:
            return statsByMonth(for: selectedTrendStat)
        }
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
                Text("Progress")
                    .font(.headline)
                Spacer()
            }

            // Time period picker - pill style
            HStack(spacing: 0) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTimePeriod = period
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: period.icon)
                                .font(.caption2)
                            Text(period.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedTimePeriod == period ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedTimePeriod == period
                                ? selectedTrendStat.color
                                : Color.clear
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(.systemGray5))
            .cornerRadius(16)

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
                    Text("\(latest.label): \(formattedValue) \(selectedTrendStat.isPercentage ? "" : selectedTrendStat.label)")
                        .font(.caption)
                        .foregroundColor(selectedTrendStat.color)
                }
            }

            Chart {
                ForEach(currentTrendData, id: \.label) { dataPoint in
                    LineMark(
                        x: .value("Period", dataPoint.label),
                        y: .value(selectedTrendStat.label, dataPoint.value)
                    )
                    .foregroundStyle(selectedTrendStat.color.gradient)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))

                    PointMark(
                        x: .value("Period", dataPoint.label),
                        y: .value(selectedTrendStat.label, dataPoint.value)
                    )
                    .foregroundStyle(selectedTrendStat.color)
                    .symbolSize(60)

                    AreaMark(
                        x: .value("Period", dataPoint.label),
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
            .animation(.easeInOut(duration: 0.3), value: selectedTimePeriod)
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
    @Environment(\.dismiss) private var dismiss

    // Game detail state (local, not binding to avoid double-sheet bug)
    @State private var selectedGameForDetail: Game? = nil

    // Delete confirmation state
    @State private var gameToDelete: Game? = nil
    @State private var showDeleteConfirmation = false

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
                                selectedGameForDetail = game
                            } label: {
                                GameRow(game: game)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    selectedGameForDetail = game
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }

                                Button(role: .destructive) {
                                    gameToDelete = game
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Game", systemImage: "trash")
                                }
                            }
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
            .sheet(item: $selectedGameForDetail) { game in
                GameDetailSheet(game: game)
            }
            .alert("Delete Game?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    gameToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let game = gameToDelete {
                        persistenceManager.deleteGame(game)
                        gameToDelete = nil
                    }
                }
            } message: {
                if let game = gameToDelete {
                    Text("Delete the game vs \(game.opponent) on \(game.date.formatted(date: .abbreviated, time: .omitted))? This cannot be undone.")
                }
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
    @ObservedObject private var calendarManager = GameCalendarManager.shared
    @ObservedObject private var youtubeService = YouTubeService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newTeamName: String = ""
    @State private var showAddTeam: Bool = false

    var body: some View {
        NavigationView {
            List {
                // YouTube Section
                Section {
                    Toggle("Auto-upload to YouTube", isOn: $youtubeService.isEnabled)

                    if youtubeService.isAuthorized {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("YouTube Connected")
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Disconnect") {
                                youtubeService.revokeAccess()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    } else {
                        Button {
                            Task {
                                do {
                                    try await youtubeService.authorize()
                                } catch {
                                    debugPrint("YouTube auth error: \(error)")
                                }
                            }
                        } label: {
                            Label("Connect YouTube", systemImage: "play.rectangle.fill")
                        }
                    }
                } header: {
                    Text("YouTube")
                } footer: {
                    Text("Videos are uploaded as unlisted to your YouTube channel for easy sharing with coaches.")
                }

                // My Teams Section (for smart opponent detection)
                Section {
                    ForEach(calendarManager.knownTeamNames, id: \.self) { team in
                        Text(team)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let team = calendarManager.knownTeamNames[index]
                            calendarManager.removeKnownTeamName(team)
                        }
                    }

                    // Add team row
                    if showAddTeam {
                        HStack {
                            TextField("Team name", text: $newTeamName)
                                .textFieldStyle(.plain)
                                .autocapitalization(.words)

                            Button {
                                let trimmed = newTeamName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    calendarManager.addKnownTeamName(trimmed)
                                    newTeamName = ""
                                    showAddTeam = false
                                }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                showAddTeam = false
                                newTeamName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Button {
                            showAddTeam = true
                        } label: {
                            Label("Add Team", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("My Teams")
                } footer: {
                    Text("Sahil's teams (Uneqld, Lava, etc). Calendar events with these names will auto-detect the opponent.")
                }

                // Calendar Section
                if calendarManager.hasCalendarAccess {
                    Section {
                        let availableCalendars = calendarManager.getAvailableCalendars()
                        if availableCalendars.isEmpty {
                            Text("No calendars found")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(Color(cgColor: calendar.cgColor))
                                        .frame(width: 12, height: 12)

                                    Text(calendar.title)

                                    Spacer()

                                    if isCalendarSelected(calendar) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.orange)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleCalendar(calendar)
                                }
                            }
                        }
                    } header: {
                        Text("Calendars")
                    } footer: {
                        Text("Select calendars to show games from. Leave all unchecked to show all calendars.")
                    }
                }

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

    // MARK: - Calendar Selection Helpers

    private func isCalendarSelected(_ calendar: EKCalendar) -> Bool {
        // If no calendars are selected, all are effectively "selected"
        if calendarManager.selectedCalendars.isEmpty {
            return false // Show no checkmarks when "show all" is active
        }
        return calendarManager.selectedCalendars.contains(calendar.calendarIdentifier)
    }

    private func toggleCalendar(_ calendar: EKCalendar) {
        var selected = calendarManager.selectedCalendars

        if selected.contains(calendar.calendarIdentifier) {
            selected.removeAll { $0 == calendar.calendarIdentifier }
        } else {
            // If this is the first selection and we had none, just add this one
            selected.append(calendar.calendarIdentifier)
        }

        calendarManager.saveSelectedCalendars(selected)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
