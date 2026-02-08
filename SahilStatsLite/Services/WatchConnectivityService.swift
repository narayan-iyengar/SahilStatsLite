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
    static let calibrationCommand = "calibrationCommand"
    static let calibrationMove = "calibrationMove"

    // Calibration keys
    static let command = "command"
    static let value = "value"
    static let dx = "dx"
    static let dy = "dy"

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
    
    // Calibration Subjects (Multicast)
    let calibrationSubject = PassthroughSubject<(String, String?), Never>()
    let calibrationMoveSubject = PassthroughSubject<(Double, Double), Never>()

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
        sendMessage(message)
    }

    /// Send score update to watch
    func sendScoreUpdate(myScore: Int, oppScore: Int) {
        let message: [String: Any] = [
            WatchMessage.scoreUpdate: true,
            WatchMessage.myScore: myScore,
            WatchMessage.oppScore: oppScore
        ]
        sendMessage(message)
    }

    /// Send clock update to watch
    func sendClockUpdate(remainingSeconds: Int, isRunning: Bool) {
        let message: [String: Any] = [
            WatchMessage.clockUpdate: true,
            WatchMessage.remainingSeconds: remainingSeconds,
            WatchMessage.isRunning: isRunning
        ]
        sendMessage(message)
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
    }

    /// Send end game to watch (resets watch to waiting state)
    func sendEndGame() {
        let message: [String: Any] = [
            WatchMessage.endGame: true
        ]
        sendMessage(message)
    }

    /// Send upcoming games from calendar to watch
    func sendUpcomingGames(_ games: [WatchGame]) {
        guard let session = session, session.isReachable else {
            debugPrint("[WatchConnectivity] Watch not reachable for games sync")
            return
        }

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
            sendMessage(message)
            debugPrint("[WatchConnectivity] Sent \(games.count) games to watch")
        } catch {
            debugPrint("[WatchConnectivity] Error encoding games: \(error)")
        }
    }

    /// Convert calendar games to watch games and send
    func syncCalendarGames() {
        guard let session = session, session.isReachable else {
            debugPrint("[WatchConnectivity] Cannot sync games - Watch not reachable")
            return
        }

        let calendarManager = GameCalendarManager.shared

        // Check calendar access
        guard calendarManager.hasCalendarAccess else {
            debugPrint("[WatchConnectivity] Cannot sync games - no calendar access")
            return
        }

        // Ensure games are loaded first
        calendarManager.loadUpcomingGames()

        let calendarGames = calendarManager.upcomingGames.prefix(10) // Limit to 10 games

        debugPrint("[WatchConnectivity] Syncing \(calendarGames.count) calendar games to Watch")
        
        let defaultHalfLength = UserDefaults.standard.integer(forKey: "defaultHalfLength")
        let halfLength = defaultHalfLength > 0 ? defaultHalfLength : 18

        let watchGames = calendarGames.map { game in
            debugPrint("[WatchConnectivity]   - \(game.opponent) at \(game.startTime)")
            return WatchGame(
                id: game.id,
                opponent: game.opponent,
                teamName: game.detectedTeam ?? "Home",
                location: game.location,
                startTime: game.startTime,
                halfLength: halfLength
            )
        }

        if watchGames.isEmpty {
            debugPrint("[WatchConnectivity] No games to sync - calendar has no matching games")
        }

        sendUpcomingGames(Array(watchGames))
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isReachable else {
            debugPrint("[WatchConnectivity] Watch not reachable")
            return
        }

        session.sendMessage(message, replyHandler: nil) { error in
            debugPrint("[WatchConnectivity] Error sending message: \(error)")
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
        
        // Calibration Command
        if message[WatchMessage.calibrationCommand] != nil,
           let command = message[WatchMessage.command] as? String {
            let value = message[WatchMessage.value] as? String
            calibrationSubject.send((command, value))
        }
        
        // Calibration Move
        if message[WatchMessage.calibrationMove] != nil,
           let dx = message[WatchMessage.dx] as? Double,
           let dy = message[WatchMessage.dy] as? Double {
            calibrationMoveSubject.send((dx, dy))
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
