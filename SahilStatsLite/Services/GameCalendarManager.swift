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

    private let selectedCalendarsKey = "selectedCalendars"

    // MARK: - Calendar Game Model

    struct CalendarGame: Identifiable {
        let id: String
        let title: String
        let opponent: String
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
        checkCalendarAccess()
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

        // Parse events into games - show ALL events from selected calendars
        upcomingGames = events.map { event -> CalendarGame in
            let title = event.title ?? "Game"
            // Try to extract opponent, fall back to event title
            let opponent = parseOpponent(from: title) ?? title

            return CalendarGame(
                id: event.eventIdentifier,
                title: title,
                opponent: opponent,
                location: event.location ?? "",
                startTime: event.startDate,
                endTime: event.endDate,
                calendarTitle: event.calendar.title
            )
        }
        .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Parse Opponent

    /// Attempts to extract opponent name from event title using common patterns.
    /// Returns nil if no pattern matches (caller should fall back to full title).
    private func parseOpponent(from title: String) -> String? {
        let lowercased = title.lowercased()

        // Pattern 1: "vs Team", "vs. Team", "@ Team", "at Team"
        let vsPatterns = ["vs ", "vs. ", "@ ", "at "]
        for pattern in vsPatterns {
            if let range = lowercased.range(of: pattern) {
                let afterPattern = title[range.upperBound...]
                let opponent = String(afterPattern)
                    .components(separatedBy: CharacterSet(charactersIn: "-–("))
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !opponent.isEmpty {
                    return opponent
                }
            }
        }

        // Pattern 2: "Team vs Us" or "Team @ Location" (opponent before vs/@)
        let reversePatterns = [" vs", " @"]
        for pattern in reversePatterns {
            if let range = lowercased.range(of: pattern) {
                let beforePattern = title[..<range.lowerBound]
                let opponent = String(beforePattern)
                    .trimmingCharacters(in: .whitespaces)
                if !opponent.isEmpty && opponent.count < 30 {
                    return opponent
                }
            }
        }

        // Pattern 3: Contains team-related keywords - extract meaningful part
        let gameKeywords = ["game", "basketball", "tournament", "championship", "league", "playoffs"]
        for keyword in gameKeywords {
            if lowercased.contains(keyword) {
                // Try to find a team name before the keyword
                if let range = lowercased.range(of: keyword) {
                    let beforeKeyword = title[..<range.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
                        .trimmingCharacters(in: .whitespaces)
                    if !beforeKeyword.isEmpty && beforeKeyword.count < 30 {
                        return beforeKeyword
                    }
                }
            }
        }

        // Pattern 4: Colon separator "Tournament: Team Name" or "AAU: Wildcats vs Eagles"
        if let colonRange = title.range(of: ":") {
            let afterColon = title[colonRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            if !afterColon.isEmpty {
                // Recursively try to parse what's after the colon
                if let parsed = parseOpponent(from: String(afterColon)) {
                    return parsed
                }
                // Otherwise use what's after the colon directly
                return String(afterColon)
            }
        }

        // No pattern matched - return nil to signal fallback to full title
        return nil
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
