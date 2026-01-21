//
//  WatchConnectivityClient.swift
//  SahilStatsLiteWatch
//
//  Watch-side connectivity service for communicating with iPhone app
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

    // Score update keys
    static let myScore = "myScore"
    static let oppScore = "oppScore"
    static let team = "team" // "my" or "opp"
    static let points = "points"

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
}

@MainActor
class WatchConnectivityClient: NSObject, ObservableObject {
    static let shared = WatchConnectivityClient()

    // Connection state
    @Published var isPhoneReachable: Bool = false
    @Published var hasActiveGame: Bool = false

    // Game state (received from phone)
    @Published var teamName: String = "MY TEAM"
    @Published var opponent: String = "OPP"
    @Published var myScore: Int = 0
    @Published var oppScore: Int = 0
    @Published var remainingSeconds: Int = 18 * 60
    @Published var isClockRunning: Bool = false
    @Published var period: String = "1st Half"
    @Published var periodIndex: Int = 0

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
        hasActiveGame = false

        let message: [String: Any] = [
            WatchMessage.endGame: true
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
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            debugPrint("[Watch] Reachability changed: \(session.isReachable)")
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
        }

        // End game from phone
        if message[WatchMessage.endGame] != nil {
            hasActiveGame = false
        }
    }
}
