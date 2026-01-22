//
//  GameCalendarManager.swift
//  SahilStatsLite
//
//  Calendar integration for upcoming games
//

import Foundation
import EventKit
import SwiftUI
import Combine

class GameCalendarManager: ObservableObject {
    static let shared = GameCalendarManager()

    private let eventStore = EKEventStore()

    @MainActor @Published var hasCalendarAccess = false
    @MainActor @Published var upcomingGames: [CalendarGame] = []
    @MainActor @Published var selectedCalendars: [String] = []
    @MainActor @Published var knownTeamNames: [String] = []
    @MainActor @Published var ignoredEventIDs: Set<String> = []

    private let selectedCalendarsKey = "selectedCalendars"
    private let knownTeamNamesKey = "knownTeamNames"
    private let ignoredEventsKey = "ignoredEventIDs"

    // Default team names for Sahil's teams (normalized - no duplicates)
    private let defaultTeamNames = ["Uneqld", "Lava", "Elements"]

    // MARK: - Calendar Game Model

    struct CalendarGame: Identifiable {
        let id: String
        let title: String
        let opponent: String
        let detectedTeam: String?  // Which of our teams is playing (e.g., "Lava")
        let location: String
        let startTime: Date
        let endTime: Date
        let calendarTitle: String

        var timeString: String {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: startTime)
        }

        var dateString: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: startTime)
        }

        var isToday: Bool {
            Calendar.current.isDateInToday(startTime)
        }
    }

    // MARK: - Initialization

    private init() {
        loadSelectedCalendars()
        loadKnownTeamNames()
        loadIgnoredEvents()
        checkCalendarAccess()
    }

    // MARK: - Ignored Events

    private func loadIgnoredEvents() {
        if let saved = UserDefaults.standard.array(forKey: ignoredEventsKey) as? [String] {
            ignoredEventIDs = Set(saved)
        }
    }

    func ignoreEvent(_ eventID: String) {
        ignoredEventIDs.insert(eventID)
        UserDefaults.standard.set(Array(ignoredEventIDs), forKey: ignoredEventsKey)
        loadUpcomingGames() // Refresh to remove from list
    }

    func unignoreEvent(_ eventID: String) {
        ignoredEventIDs.remove(eventID)
        UserDefaults.standard.set(Array(ignoredEventIDs), forKey: ignoredEventsKey)
        loadUpcomingGames()
    }

    func clearIgnoredEvents() {
        ignoredEventIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: ignoredEventsKey)
        loadUpcomingGames()
    }

    // MARK: - Known Team Names

    private func loadKnownTeamNames() {
        if let saved = UserDefaults.standard.array(forKey: knownTeamNamesKey) as? [String], !saved.isEmpty {
            // Normalize: remove case-insensitive duplicates, keep first occurrence
            knownTeamNames = normalizeTeamNames(saved)
            // Save back if we removed duplicates
            if knownTeamNames.count != saved.count {
                UserDefaults.standard.set(knownTeamNames, forKey: knownTeamNamesKey)
            }
        } else {
            // Use defaults on first launch
            knownTeamNames = defaultTeamNames
            UserDefaults.standard.set(defaultTeamNames, forKey: knownTeamNamesKey)
        }
    }

    /// Removes case-insensitive duplicates, keeping the first occurrence
    private func normalizeTeamNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let lowercased = name.lowercased()
            if !seen.contains(lowercased) {
                seen.insert(lowercased)
                result.append(name)
            }
        }
        return result
    }

    func saveKnownTeamNames(_ names: [String]) {
        // Normalize to remove case-insensitive duplicates
        knownTeamNames = normalizeTeamNames(names)
        UserDefaults.standard.set(knownTeamNames, forKey: knownTeamNamesKey)
        loadUpcomingGames() // Re-parse with new team names
    }

    func addKnownTeamName(_ name: String) {
        guard !name.isEmpty, !knownTeamNames.contains(where: { $0.lowercased() == name.lowercased() }) else { return }
        knownTeamNames.append(name)
        UserDefaults.standard.set(knownTeamNames, forKey: knownTeamNamesKey)
        loadUpcomingGames()
    }

    func removeKnownTeamName(_ name: String) {
        knownTeamNames.removeAll { $0.lowercased() == name.lowercased() }
        UserDefaults.standard.set(knownTeamNames, forKey: knownTeamNamesKey)
        loadUpcomingGames()
    }

    // MARK: - Calendar Access

    func checkCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, *) {
            hasCalendarAccess = (status == .fullAccess || status == .writeOnly)
        } else {
            hasCalendarAccess = (status == .authorized)
        }

        if hasCalendarAccess {
            loadUpcomingGames()
        }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            await MainActor.run {
                self.hasCalendarAccess = granted
                if granted {
                    self.loadUpcomingGames()
                }
            }
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Calendar Selection

    func getAvailableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    func saveSelectedCalendars(_ identifiers: [String]) {
        selectedCalendars = identifiers
        UserDefaults.standard.set(identifiers, forKey: selectedCalendarsKey)
        loadUpcomingGames()
    }

    private func loadSelectedCalendars() {
        if let saved = UserDefaults.standard.array(forKey: selectedCalendarsKey) as? [String] {
            selectedCalendars = saved
        }
    }

    // MARK: - Load Games

    func loadUpcomingGames() {
        guard hasCalendarAccess else { return }

        let calendars: [EKCalendar]
        if selectedCalendars.isEmpty {
            calendars = eventStore.calendars(for: .event)
        } else {
            calendars = eventStore.calendars(for: .event).filter {
                selectedCalendars.contains($0.calendarIdentifier)
            }
        }

        guard !calendars.isEmpty else {
            upcomingGames = []
            return
        }

        // Look ahead 30 days
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 30, to: startDate)!

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )

        let events = eventStore.events(matching: predicate)

        // Filter to GAMES only (not practices), containing known team names, exclude ignored
        upcomingGames = events
            .filter { event in
                guard let title = event.title else { return false }
                let lowercasedTitle = title.lowercased()

                // Skip ignored events
                if ignoredEventIDs.contains(event.eventIdentifier) { return false }

                // Skip practices
                if lowercasedTitle.contains("practice") { return false }

                // Only include events with known team names
                return knownTeamNames.contains { teamName in
                    lowercasedTitle.contains(teamName.lowercased())
                }
            }
            .filter { event in
                // Only show future games (or games happening now)
                event.endDate > Date()
            }
            .map { event -> CalendarGame in
                let title = event.title ?? "Game"
                let (opponent, detectedTeam) = parseOpponentAndTeam(from: title)

                return CalendarGame(
                    id: event.eventIdentifier,
                    title: title,
                    opponent: opponent,
                    detectedTeam: detectedTeam,
                    location: event.location ?? "",
                    startTime: event.startDate,
                    endTime: event.endDate,
                    calendarTitle: event.calendar.title
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Helper: Games for Today

    func gamesToday() -> [CalendarGame] {
        let calendar = Calendar.current
        return upcomingGames.filter { calendar.isDateInToday($0.startTime) }
    }

    func gamesAfterToday() -> [CalendarGame] {
        let calendar = Calendar.current
        return upcomingGames.filter { !calendar.isDateInToday($0.startTime) }
    }

    // MARK: - Parse Opponent and Team

    /// Parses event title to extract opponent name and detect which of our teams is playing.
    /// Returns (opponent, detectedTeam) tuple.
    private func parseOpponentAndTeam(from title: String) -> (opponent: String, detectedTeam: String?) {
        let lowercased = title.lowercased()

        // First, find which of our teams is mentioned
        var detectedTeam: String? = nil
        for teamName in knownTeamNames {
            if lowercased.contains(teamName.lowercased()) {
                detectedTeam = teamName
                break
            }
        }

        // Common separators between team names
        let separators = [" vs ", " vs. ", " @ ", " at ", " - ", " – "]

        // Try to split the title by separators
        for separator in separators {
            if let range = lowercased.range(of: separator) {
                let before = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                var after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)

                // Clean up the "after" part - remove trailing location/time info
                if let parenRange = after.range(of: "(") {
                    after = String(after[..<parenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }

                // Check which side is our team and return the other as opponent
                let beforeIsOurs = knownTeamNames.contains { before.lowercased().contains($0.lowercased()) }
                let afterIsOurs = knownTeamNames.contains { after.lowercased().contains($0.lowercased()) }

                if beforeIsOurs && !afterIsOurs && !after.isEmpty {
                    return (opponent: after, detectedTeam: detectedTeam)
                } else if afterIsOurs && !beforeIsOurs && !before.isEmpty {
                    return (opponent: before, detectedTeam: detectedTeam)
                }
            }
        }

        // Fallback: If we detected our team, try to remove it from the title
        if let team = detectedTeam {
            var remaining = title

            // Remove our team name (case insensitive)
            if let range = remaining.range(of: team, options: .caseInsensitive) {
                remaining.removeSubrange(range)
            }

            // Also try common variations like "Bay Area Lava" for "Lava"
            let teamVariations = [
                "bay area \(team.lowercased())",
                "\(team.lowercased()) basketball",
                "\(team.lowercased()) hoops"
            ]
            for variation in teamVariations {
                if let range = remaining.lowercased().range(of: variation) {
                    let startIdx = remaining.index(remaining.startIndex, offsetBy: remaining.distance(from: remaining.startIndex, to: range.lowerBound))
                    let endIdx = remaining.index(remaining.startIndex, offsetBy: remaining.distance(from: remaining.startIndex, to: range.upperBound))
                    remaining.removeSubrange(startIdx..<endIdx)
                }
            }

            // Clean up separators and whitespace
            remaining = remaining
                .replacingOccurrences(of: " vs ", with: " ")
                .replacingOccurrences(of: " vs. ", with: " ")
                .replacingOccurrences(of: " - ", with: " ")
                .replacingOccurrences(of: " – ", with: " ")
                .replacingOccurrences(of: " @ ", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-–"))
                .trimmingCharacters(in: .whitespaces)

            if !remaining.isEmpty && remaining.count < 50 {
                return (opponent: remaining, detectedTeam: detectedTeam)
            }
        }

        // Last resort: return the full title
        return (opponent: title, detectedTeam: detectedTeam)
    }

    // MARK: - Refresh

    func refresh() {
        loadUpcomingGames()
    }

    // MARK: - Games for Date

    func games(for date: Date) -> [CalendarGame] {
        upcomingGames.filter { game in
            Calendar.current.isDate(game.startTime, inSameDayAs: date)
        }
    }

    // MARK: - Dates with Games

    func datesWithGames() -> Set<Date> {
        let calendar = Calendar.current
        return Set(upcomingGames.map { calendar.startOfDay(for: $0.startTime) })
    }
}
