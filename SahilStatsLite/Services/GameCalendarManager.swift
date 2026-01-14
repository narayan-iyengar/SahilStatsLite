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

        // Parse events into games
        upcomingGames = events.compactMap { event -> CalendarGame? in
            // Try to extract opponent from title
            let opponent = parseOpponent(from: event.title ?? "")
            guard !opponent.isEmpty else { return nil }

            return CalendarGame(
                id: event.eventIdentifier,
                title: event.title ?? "",
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

    private func parseOpponent(from title: String) -> String {
        let lowercased = title.lowercased()

        // Common patterns: "vs Team", "@ Team", "Team Game"
        let patterns = ["vs ", "vs. ", "@ ", "at "]

        for pattern in patterns {
            if let range = lowercased.range(of: pattern) {
                let afterPattern = title[range.upperBound...]
                // Take first word or phrase until common endings
                let opponent = String(afterPattern)
                    .components(separatedBy: CharacterSet(charactersIn: "-–("))
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !opponent.isEmpty {
                    return opponent
                }
            }
        }

        // If title contains "basketball" or "game", use what comes before
        if lowercased.contains("basketball") || lowercased.contains("game") {
            let words = title.components(separatedBy: " ")
            if let firstWord = words.first, !["basketball", "game"].contains(firstWord.lowercased()) {
                return firstWord
            }
        }

        return ""
    }

    // MARK: - Refresh

    func refresh() {
        loadUpcomingGames()
    }
}
