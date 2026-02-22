//
//  WatchConnectivityService.swift
//  SahilStatsLite
//
//  PURPOSE: iPhone-side WatchConnectivity handler. Sends game state, scores,
//           clock, and period updates to Watch. Receives scoring, clock toggle,
//           period advance, stat updates, and end game commands from Watch.
//           Must be initialized at app launch (AppDelegate) or WCSession fails.
//  KEY TYPES: WatchConnectivityService (singleton), WatchMessage, WatchGame
//  DEPENDS ON: WatchConnectivity
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import Combine
import WatchConnectivity

// MARK: - Message Keys

struct WatchMessage {
    static let scoreUpdate = "scoreUpdate"
    static let clockUpdate = "clockUpdate"
    static let periodUpdate = "periodUpdate"
    static let statUpdate = "statUpdate"
    static let gameState = "gameState"
    static let endGame = "endGame"
    static let startGame = "startGame"  // Start game from watch
    static let upcomingGames = "upcomingGames"  // Calendar games sync
    static let requestState = "requestState" // Watch asks for current state

    // Score update keys
    static let myScore = "myScore"
    static let oppScore = "oppScore"
    static let team = "team" // "my" or "opp"
    static let points = "points"
    static let isSubtract = "isSubtract"  // For subtracting scores

    // Clock keys
    static let isRunning = "isRunning"
    static let remainingSeconds = "remainingSeconds"

    // Period keys
    static let period = "period"
    static let periodIndex = "periodIndex"

    // Stat keys
    static let statType = "statType"
    static let statValue = "statValue"

    // Game state keys
    static let teamName = "teamName"
    static let opponent = "opponent"
    static let halfLength = "halfLength"
    static let location = "location"
    static let startTime = "startTime"
    static let gameId = "gameId"
    static let games = "games"
}

// MARK: - Watch Game (lightweight game for Watch sync)

struct WatchGame: Codable, Identifiable, Equatable {
    let id: String
    let opponent: String
    let teamName: String
    let location: String
    let startTime: Date
    let halfLength: Int

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(startTime)
    }

    var dayString: String {
        if Calendar.current.isDateInToday(startTime) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(startTime) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: startTime)
        }
    }
}

// MARK: - iOS App Service

@MainActor
class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isWatchReachable: Bool = false
    @Published var isWatchAppInstalled: Bool = false

    // Publisher for when Watch requests to start a game (for remote triggering recording)
    @Published var pendingGameFromWatch: WatchGame?

    // Callbacks for when watch sends updates
    var onScoreUpdate: ((_ team: String, _ points: Int, _ isSubtract: Bool) -> Void)?
    var onClockToggle: (() -> Void)?
    var onPeriodAdvance: (() -> Void)?
    var onStatUpdate: ((_ statType: String, _ value: Int) -> Void)?
    var onEndGame: (() -> Void)?
    var onStartGame: ((_ game: WatchGame) -> Void)?
    var onRequestState: (() -> Void)?

    private var session: WCSession?

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            debugPrint("[WatchConnectivity] WCSession not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send to Watch

    /// Send full game state to watch (when game starts)
    func sendGameState(teamName: String, opponent: String, myScore: Int, oppScore: Int,
                       remainingSeconds: Int, isClockRunning: Bool, period: String, periodIndex: Int) {
        let message: [String: Any] = [
            WatchMessage.gameState: true,
            WatchMessage.teamName: teamName,
            WatchMessage.opponent: opponent,
            WatchMessage.myScore: myScore,
            WatchMessage.oppScore: oppScore,
            WatchMessage.remainingSeconds: remainingSeconds,
            WatchMessage.isRunning: isClockRunning,
            WatchMessage.period: period,
            WatchMessage.periodIndex: periodIndex
        ]
        
        // Use BOTH sendMessage (immediate) and updateApplicationContext (reliable/sticky)
        sendMessage(message)
        updateContext(message)
    }

    /// Send score update to watch
    func sendScoreUpdate(myScore: Int, oppScore: Int) {
        let message: [String: Any] = [
            WatchMessage.scoreUpdate: true,
            WatchMessage.myScore: myScore,
            WatchMessage.oppScore: oppScore
        ]
        sendMessage(message)
        updateContext(message)
    }

    /// Send clock update to watch
    func sendClockUpdate(remainingSeconds: Int, isRunning: Bool) {
        let message: [String: Any] = [
            WatchMessage.clockUpdate: true,
            WatchMessage.remainingSeconds: remainingSeconds,
            WatchMessage.isRunning: isRunning
        ]
        sendMessage(message)
        updateContext(message)
    }

    /// Send period update to watch
    func sendPeriodUpdate(period: String, periodIndex: Int, remainingSeconds: Int, isRunning: Bool) {
        let message: [String: Any] = [
            WatchMessage.periodUpdate: true,
            WatchMessage.period: period,
            WatchMessage.periodIndex: periodIndex,
            WatchMessage.remainingSeconds: remainingSeconds,
            WatchMessage.isRunning: isRunning
        ]
        sendMessage(message)
        updateContext(message)
    }

    /// Send end game to watch (resets watch to waiting state)
    func sendEndGame() {
        let message: [String: Any] = [
            WatchMessage.endGame: true
        ]
        sendMessage(message)
        
        // When ending a game, we want to CLEAR the game-specific keys from context
        // Instead of merging, we replace with just the endGame signal
        guard let session = session else { return }
        do {
            try session.updateApplicationContext(message)
            debugPrint("[WatchConnectivity] Game ended - context cleared of active game state")
        } catch {
            debugPrint("[WatchConnectivity] Error clearing context: \(error)")
        }
    }

    /// Send upcoming games from calendar to watch
    func sendUpcomingGames(_ games: [WatchGame]) {
        // Encode games as JSON data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let gamesData = try encoder.encode(games)
            let gamesString = String(data: gamesData, encoding: .utf8) ?? "[]"

            let message: [String: Any] = [
                WatchMessage.upcomingGames: true,
                WatchMessage.games: gamesString
            ]
            
            // For games list, use sendMessage if reachable, but context is better for syncing
            if let session = session, session.isReachable {
                sendMessage(message)
            }
            updateContext(message)
            debugPrint("[WatchConnectivity] Sent/Updated \(games.count) games in context")
        } catch {
            debugPrint("[WatchConnectivity] Error encoding games: \(error)")
        }
    }

    /// Convert calendar games to watch games and send
    func syncCalendarGames() {
        let calendarManager = GameCalendarManager.shared

        // Check calendar access
        guard calendarManager.hasCalendarAccess else {
            debugPrint("[WatchConnectivity] Cannot sync games - no calendar access")
            return
        }

        // Ensure games are loaded first
        calendarManager.loadUpcomingGames()

        let calendarGames = calendarManager.upcomingGames.prefix(10) // Limit to 10 games

        debugPrint("[WatchConnectivity] Syncing \(calendarGames.count) calendar games to Watch context")
        
        let defaultHalfLength = UserDefaults.standard.integer(forKey: "defaultHalfLength")
        let halfLength = defaultHalfLength > 0 ? defaultHalfLength : 18

        let watchGames = calendarGames.map { game in
            return WatchGame(
                id: game.id,
                opponent: game.opponent,
                teamName: game.detectedTeam ?? "Home",
                location: game.location,
                startTime: game.startTime,
                halfLength: halfLength
            )
        }

        sendUpcomingGames(Array(watchGames))
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isReachable else {
            // Silently fail, updateContext will handle it when Watch wakes up
            return
        }

        session.sendMessage(message, replyHandler: nil) { error in
            debugPrint("[WatchConnectivity] Error sending message: \(error)")
        }
    }
    
    private func updateContext(_ message: [String: Any]) {
        guard let session = session else { return }
        
        do {
            // merge with existing context if possible
            var newContext = session.applicationContext
            for (key, value) in message {
                newContext[key] = value
            }
            try session.updateApplicationContext(newContext)
        } catch {
            debugPrint("[WatchConnectivity] Error updating context: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            debugPrint("[WatchConnectivity] Activation complete: \(activationState.rawValue)")
            debugPrint("[WatchConnectivity] Watch reachable: \(session.isReachable), installed: \(session.isWatchAppInstalled)")
            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled

            // Sync calendar games on activation if Watch is reachable
            if session.isReachable {
                // Small delay to ensure Watch app is ready
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                self.syncCalendarGames()
                
                // Also request state resync in case we are mid-game
                self.onRequestState?()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        debugPrint("[WatchConnectivity] Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        debugPrint("[WatchConnectivity] Session deactivated")
        // Reactivate for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            debugPrint("[WatchConnectivity] Reachability changed: \(session.isReachable)")

            // Sync calendar games when Watch becomes reachable
            if session.isReachable {
                self.syncCalendarGames()
                
                // Also request state resync in case we are mid-game
                self.onRequestState?()
            }
        }
    }

    // Receive messages from watch
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }

    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        // Score update from watch (add or subtract)
        if message[WatchMessage.scoreUpdate] != nil,
           let team = message[WatchMessage.team] as? String,
           let points = message[WatchMessage.points] as? Int {
            let isSubtract = message[WatchMessage.isSubtract] as? Bool ?? false
            onScoreUpdate?(team, points, isSubtract)
        }

        // Clock toggle from watch
        if message[WatchMessage.clockUpdate] != nil {
            onClockToggle?()
        }

        // Period advance from watch
        if message[WatchMessage.periodUpdate] != nil {
            onPeriodAdvance?()
        }

        // Stat update from watch
        if message[WatchMessage.statUpdate] != nil,
           let statType = message[WatchMessage.statType] as? String,
           let value = message[WatchMessage.statValue] as? Int {
            onStatUpdate?(statType, value)
        }

        // End game from watch
        if message[WatchMessage.endGame] != nil {
            onEndGame?()
        }
        
        // Request state from watch
        if message[WatchMessage.requestState] != nil {
            debugPrint("[WatchConnectivity] ⌚️ Watch requested game state sync")
            onRequestState?()
        }

        // Start game from watch (triggers recording on phone)
        if message[WatchMessage.startGame] != nil {
            let gameId = message[WatchMessage.gameId] as? String ?? UUID().uuidString
            let opponent = message[WatchMessage.opponent] as? String ?? "Away"
            let teamName = message[WatchMessage.teamName] as? String ?? "Home"
            let location = message[WatchMessage.location] as? String ?? ""
            let halfLength = message[WatchMessage.halfLength] as? Int ?? 18
            let startTimeInterval = message[WatchMessage.startTime] as? TimeInterval ?? Date().timeIntervalSince1970

            let game = WatchGame(
                id: gameId,
                opponent: opponent,
                teamName: teamName,
                location: location,
                startTime: Date(timeIntervalSince1970: startTimeInterval),
                halfLength: halfLength
            )

            debugPrint("[WatchConnectivity] 📱 Received START GAME from Watch: \(teamName) vs \(opponent)")

            // Set pending game - ContentView will react to this
            pendingGameFromWatch = game

            // Also call callback if set
            onStartGame?(game)
        }
    }
}
