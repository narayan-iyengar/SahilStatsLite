//
//  WatchConnectivityService.swift
//  SahilStatsLite
//
//  Handles communication between iPhone and Apple Watch
//  Used by both iOS app and watchOS app
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

// MARK: - iOS App Service

@MainActor
class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isWatchReachable: Bool = false
    @Published var isWatchAppInstalled: Bool = false

    // Callbacks for when watch sends updates
    var onScoreUpdate: ((_ team: String, _ points: Int) -> Void)?
    var onClockToggle: (() -> Void)?
    var onPeriodAdvance: (() -> Void)?
    var onStatUpdate: ((_ statType: String, _ value: Int) -> Void)?
    var onEndGame: (() -> Void)?

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
            self.isWatchReachable = session.isReachable
            self.isWatchAppInstalled = session.isWatchAppInstalled
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
        // Score update from watch
        if message[WatchMessage.scoreUpdate] != nil,
           let team = message[WatchMessage.team] as? String,
           let points = message[WatchMessage.points] as? Int {
            onScoreUpdate?(team, points)
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
    }
}
