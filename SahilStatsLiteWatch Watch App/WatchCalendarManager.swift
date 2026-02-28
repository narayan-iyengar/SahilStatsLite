//
//  WatchCalendarManager.swift
//  SahilStatsLiteWatch
//
//  PURPOSE: Independent calendar integration for the Watch App.
//           Fetches games directly from the Watch's EventKit.
//  KEY TYPES: WatchCalendarManager (singleton)
//  DEPENDS ON: EventKit, WatchGame
//

import Foundation
import EventKit
import Combine

@MainActor
class WatchCalendarManager: ObservableObject {
    static let shared = WatchCalendarManager()

    private let eventStore = EKEventStore()
    @Published var upcomingGames: [WatchGame] = []
    @Published var hasCalendarAccess = false
    @Published var isAccessNotDetermined = false
    @Published var ignoredEventIDs: Set<String> = []

    // Default teams to look for if phone sync hasn't happened
    private let defaultTeams = ["Lava", "Uneqld", "Elements", "Wildcats"]
    private let ignoredEventsKey = "watchIgnoredEventIDs"

    private init() {
        loadIgnoredEvents()
        checkAccess()
    }
    
    // MARK: - Ignore Events
    
    private func loadIgnoredEvents() {
        if let saved = UserDefaults.standard.array(forKey: ignoredEventsKey) as? [String] {
            ignoredEventIDs = Set(saved)
        }
    }
    
    func ignoreGame(_ gameID: String) {
        ignoredEventIDs.insert(gameID)
        UserDefaults.standard.set(Array(ignoredEventIDs), forKey: ignoredEventsKey)
        // Refresh the list immediately
        loadUpcomingGames()
    }

    func checkAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            self.hasCalendarAccess = true
            self.isAccessNotDetermined = false
            self.loadUpcomingGames()
        case .notDetermined:
            self.hasCalendarAccess = false
            self.isAccessNotDetermined = true
        default:
            self.hasCalendarAccess = false
            self.isAccessNotDetermined = false
        }
    }
    
    func requestAccess() {
        Task {
            do {
                if #available(watchOS 10.0, *) {
                    let granted = try await eventStore.requestFullAccessToEvents()
                    DispatchQueue.main.async {
                        self.hasCalendarAccess = granted
                        self.isAccessNotDetermined = false
                        if granted { self.loadUpcomingGames() }
                    }
                } else {
                    let granted = try await eventStore.requestAccess(to: .event)
                    DispatchQueue.main.async {
                        self.hasCalendarAccess = granted
                        self.isAccessNotDetermined = false
                        if granted { self.loadUpcomingGames() }
                    }
                }
            } catch {
                debugPrint("[WatchCalendar] Access error: \(error)")
                DispatchQueue.main.async {
                    self.isAccessNotDetermined = false
                }
            }
        }
    }

    func loadUpcomingGames() {
        guard hasCalendarAccess else { return }

        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let oneWeekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let predicate = eventStore.predicateForEvents(withStart: now, end: oneWeekFromNow, calendars: calendars)
        
        let events = eventStore.events(matching: predicate)

        var games: [WatchGame] = []

        for event in events {
            // Skip if user ignored this event
            if ignoredEventIDs.contains(event.eventIdentifier) {
                continue
            }
            
            guard let title = event.title else { continue }
            let lowerTitle = title.lowercased()
            
            // Check if it's a game (contains team name or 'vs')
            let hasTeam = defaultTeams.contains { lowerTitle.contains($0.lowercased()) }
            let hasVS = lowerTitle.contains(" vs ") || lowerTitle.contains(" @ ")
            
            if hasTeam || hasVS {
                // Ignore practices
                if lowerTitle.contains("practice") || lowerTitle.contains("training") {
                    continue
                }
                
                let (opponent, team) = parseOpponent(from: title)
                let game = WatchGame(
                    id: event.eventIdentifier,
                    opponent: opponent,
                    teamName: team,
                    location: event.location ?? "",
                    startTime: event.startDate,
                    halfLength: 18 // Default
                )
                games.append(game)
            }
        }

        self.upcomingGames = games.sorted { $0.startTime < $1.startTime }
        debugPrint("[WatchCalendar] Loaded \(self.upcomingGames.count) independent games")
    }

    private func parseOpponent(from title: String) -> (String, String) {
        var teamName = "Home"
        for t in defaultTeams {
            if title.lowercased().contains(t.lowercased()) {
                teamName = t
                break
            }
        }

        let separators = [" vs ", " vs. ", " @ ", " at ", " - ", " – "]
        for sep in separators {
            if let range = title.lowercased().range(of: sep) {
                let before = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let after = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                if before.lowercased().contains(teamName.lowercased()) {
                    return (clean(after), teamName)
                } else {
                    return (clean(before), teamName)
                }
            }
        }
        
        // Fallback
        return (title, teamName)
    }
    
    private func clean(_ str: String) -> String {
        var result = str
        if let p = result.range(of: "(") {
            result = String(result[..<p.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
