//
//  WatchConnectivityClient.swift
//  SahilStatsLiteWatch
//
//  PURPOSE: Watch-side WCSession handler. Sends score/stat/clock/period
//           updates to iPhone, receives game state sync back. Manages
//           all published state (scores, clock, period, player stats).
//           Optimistic local updates for responsive UI.
//  KEY TYPES: WatchConnectivityClient (singleton), WatchMessage
//  DEPENDS ON: WatchConnectivity framework
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import WatchConnectivity
import Combine

// Reuse message keys from iOS app
struct WatchMessage {
    static let scoreUpdate = "scoreUpdate"
    static let clockUpdate = "clockUpdate"
    static let periodUpdate = "periodUpdate"
    static let statUpdate = "statUpdate"
    static let gameState = "gameState"
    static let endGame = "endGame"
    static let startGame = "startGame"
    static let upcomingGames = "upcomingGames"
    static let requestState = "requestState"

    // Score update keys
    static let myScore = "myScore"
    static let oppScore = "oppScore"
    static let team = "team" // "my" or "opp"
    static let points = "points"
    static let isSubtract = "isSubtract"

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

struct WatchGame: Codable, Identifiable {
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

@MainActor
class WatchConnectivityClient: NSObject, ObservableObject {
    static let shared = WatchConnectivityClient()

    // Connection state
    @Published var isPhoneReachable: Bool = false
    @Published var hasActiveGame: Bool = false

    // Upcoming games from calendar (synced from phone)
    @Published var upcomingGames: [WatchGame] = []

    // Game state (received from phone)
    @Published var teamName: String = "MY TEAM"
    @Published var opponent: String = "OPP"
    @Published var myScore: Int = 0
    @Published var oppScore: Int = 0
    @Published var remainingSeconds: Int = 18 * 60
    @Published var isClockRunning: Bool = false
    @Published var period: String = "1st Half"
    @Published var periodIndex: Int = 0
    @Published var halfLength: Int = 18
    @Published var isEnding: Bool = false

    // Player stats (received from phone)
    @Published var fg2Made: Int = 0
    @Published var fg2Att: Int = 0
    @Published var fg3Made: Int = 0
    @Published var fg3Att: Int = 0
    @Published var ftMade: Int = 0
    @Published var ftAtt: Int = 0
    @Published var assists: Int = 0
    @Published var rebounds: Int = 0
    @Published var steals: Int = 0
    @Published var blocks: Int = 0
    @Published var turnovers: Int = 0

    private var session: WCSession?

    private override init() {
        super.init()
        setupSession()
    }

    /// Configure shared instance with sample data for Xcode Canvas previews
    static func configureForPreview() {
        let client = shared
        client.hasActiveGame = true
        client.teamName = "LAVA"
        client.opponent = "WARRIORS"
        client.myScore = 42
        client.oppScore = 38
        client.remainingSeconds = 7 * 60 + 34  // 7:34
        client.isClockRunning = true
        client.period = "2nd Half"
        client.periodIndex = 1
        client.fg2Made = 3
        client.fg2Att = 5
        client.fg3Made = 1
        client.fg3Att = 4
        client.ftMade = 2
        client.ftAtt = 3
        client.assists = 2
        client.rebounds = 4
        client.steals = 1
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            debugPrint("[Watch] WCSession not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send to Phone

    /// Add score (team: "my" or "opp", points: 1, 2, or 3)
    func addScore(team: String, points: Int) {
        // Update local state immediately for responsiveness
        if team == "my" {
            myScore += points
        } else {
            oppScore += points
        }

        let message: [String: Any] = [
            WatchMessage.scoreUpdate: true,
            WatchMessage.team: team,
            WatchMessage.points: points
        ]
        sendMessage(message)
    }

    /// Subtract score (for fixing mistakes)
    func subtractScore(team: String, points: Int) {
        // Update local state immediately for responsiveness
        if team == "my" {
            myScore = max(0, myScore - points)
        } else {
            oppScore = max(0, oppScore - points)
        }

        let message: [String: Any] = [
            WatchMessage.scoreUpdate: true,
            WatchMessage.team: team,
            WatchMessage.points: points,
            WatchMessage.isSubtract: true
        ]
        sendMessage(message)
    }

    /// Start a new game from watch with full game details
    func startGame(_ game: WatchGame) {
        hasActiveGame = true
        myScore = 0
        oppScore = 0
        halfLength = game.halfLength
        remainingSeconds = game.halfLength * 60
        isClockRunning = false
        period = "1st Half"
        periodIndex = 0
        self.opponent = game.opponent
        self.teamName = game.teamName

        let message: [String: Any] = [
            WatchMessage.startGame: true,
            WatchMessage.gameId: game.id,
            WatchMessage.opponent: game.opponent,
            WatchMessage.teamName: game.teamName,
            WatchMessage.location: game.location,
            WatchMessage.halfLength: game.halfLength,
            WatchMessage.startTime: game.startTime.timeIntervalSince1970
        ]
        sendMessage(message)
    }

    /// Start a quick game with just opponent name (fallback)
    func startQuickGame(opponent: String = "Away") {
        let game = WatchGame(
            id: UUID().uuidString,
            opponent: opponent,
            teamName: "Home",
            location: "",
            startTime: Date(),
            halfLength: 18
        )
        startGame(game)
    }

    /// Toggle clock (pause/play)
    func toggleClock() {
        isClockRunning.toggle()

        let message: [String: Any] = [
            WatchMessage.clockUpdate: true
        ]
        sendMessage(message)
    }

    /// Advance period
    func advancePeriod() {
        let message: [String: Any] = [
            WatchMessage.periodUpdate: true
        ]
        sendMessage(message)
    }

    /// Update a stat (sent to phone)
    func updateStat(_ statType: String, value: Int) {
        // Update local state immediately
        switch statType {
        case "fg2Made": fg2Made += value
        case "fg2Att": fg2Att += value
        case "fg3Made": fg3Made += value
        case "fg3Att": fg3Att += value
        case "ftMade": ftMade += value
        case "ftAtt": ftAtt += value
        case "assists": assists += value
        case "rebounds": rebounds += value
        case "steals": steals += value
        case "blocks": blocks += value
        case "turnovers": turnovers += value
        default: break
        }

        let message: [String: Any] = [
            WatchMessage.statUpdate: true,
            WatchMessage.statType: statType,
            WatchMessage.statValue: value
        ]
        sendMessage(message)
    }

    /// End game
    func endGame() {
        isEnding = true
        
        let message: [String: Any] = [
            WatchMessage.endGame: true
        ]
        sendMessage(message)
        
        // Timeout safeguard: Force end if phone doesn't reply in 5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isEnding {
                self.hasActiveGame = false
                self.isEnding = false
            }
        }
    }
    
    /// Request current game state from phone (called on connect)
    func requestState() {
        debugPrint("[Watch] Requesting game state from phone...")
        let message: [String: Any] = [
            WatchMessage.requestState: true
        ]
        sendMessage(message)
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isReachable else {
            debugPrint("[Watch] Phone not reachable")
            return
        }

        session.sendMessage(message, replyHandler: nil) { error in
            debugPrint("[Watch] Error sending message: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityClient: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            debugPrint("[Watch] Activation complete: \(activationState.rawValue)")
            self.isPhoneReachable = session.isReachable
            
            // Request state immediately on activation
            if session.isReachable {
                self.requestState()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            debugPrint("[Watch] Reachability changed: \(session.isReachable)")
            
            // Request state when phone becomes reachable
            if session.isReachable {
                self.requestState()
            }
        }
    }

    // Receive messages from phone
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }

    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        // Full game state from phone (when game starts)
        if message[WatchMessage.gameState] != nil {
            hasActiveGame = true
            if let name = message[WatchMessage.teamName] as? String {
                teamName = name
            }
            if let opp = message[WatchMessage.opponent] as? String {
                opponent = opp
            }
            if let my = message[WatchMessage.myScore] as? Int {
                myScore = my
            }
            if let opp = message[WatchMessage.oppScore] as? Int {
                oppScore = opp
            }
            if let secs = message[WatchMessage.remainingSeconds] as? Int {
                remainingSeconds = secs
            }
            if let running = message[WatchMessage.isRunning] as? Bool {
                isClockRunning = running
            }
            if let per = message[WatchMessage.period] as? String {
                period = per
            }
            if let idx = message[WatchMessage.periodIndex] as? Int {
                periodIndex = idx
            }
            debugPrint("[Watch] Received game state: \(teamName) vs \(opponent)")
        }

        // Score update from phone
        if message[WatchMessage.scoreUpdate] != nil {
            if let my = message[WatchMessage.myScore] as? Int {
                myScore = my
            }
            if let opp = message[WatchMessage.oppScore] as? Int {
                oppScore = opp
            }
        }

        // Clock update from phone
        if message[WatchMessage.clockUpdate] != nil {
            if let secs = message[WatchMessage.remainingSeconds] as? Int {
                remainingSeconds = secs
            }
            if let running = message[WatchMessage.isRunning] as? Bool {
                isClockRunning = running
            }
        }

        // Period update from phone
        if message[WatchMessage.periodUpdate] != nil {
            if let per = message[WatchMessage.period] as? String {
                period = per
            }
            if let idx = message[WatchMessage.periodIndex] as? Int {
                periodIndex = idx
            }
            if let secs = message[WatchMessage.remainingSeconds] as? Int {
                remainingSeconds = secs
            }
            if let running = message[WatchMessage.isRunning] as? Bool {
                isClockRunning = running
            }
        }

        // End game from phone
        if message[WatchMessage.endGame] != nil {
            hasActiveGame = false
            isEnding = false
        }

        // Upcoming games from phone (calendar sync)
        if message[WatchMessage.upcomingGames] != nil,
           let gamesString = message[WatchMessage.games] as? String,
           let gamesData = gamesString.data(using: .utf8) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let games = try decoder.decode([WatchGame].self, from: gamesData)
                upcomingGames = games
                debugPrint("[Watch] Received \(games.count) upcoming games")
            } catch {
                debugPrint("[Watch] Error decoding games: \(error)")
            }
        }
    }
}
