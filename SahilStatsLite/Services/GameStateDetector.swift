//
//  GameStateDetector.swift
//  SahilStatsLite
//
//  Basketball game state detection using heuristics
//  No training required - uses basketball domain knowledge
//
//  Game States:
//  - fastBreak: Ball moving quickly toward basket, players spread/running
//  - halfCourt: Set offense, players relatively stationary, ball handler probing
//  - transition: Ball crossing half court, teams setting up
//  - deadBall: No active play (timeout, foul, out of bounds)
//
//  Detection is based on:
//  - Ball position and velocity
//  - Player positions relative to court geometry
//  - Player velocities (running vs stationary)
//  - Historical patterns (state transitions)
//

import Foundation
import CoreGraphics

// MARK: - Game State

enum GameState: String {
    case fastBreak = "Fast Break"
    case halfCourt = "Half Court"
    case transition = "Transition"
    case deadBall = "Dead Ball"
    case unknown = "Unknown"

    var emoji: String {
        switch self {
        case .fastBreak: return "🏃"
        case .halfCourt: return "🎯"
        case .transition: return "↔️"
        case .deadBall: return "⏸️"
        case .unknown: return "❓"
        }
    }

    /// Recommended zoom behavior for this state
    var zoomBehavior: ZoomBehavior {
        switch self {
        case .fastBreak:
            return ZoomBehavior(minZoom: 1.0, maxZoom: 1.5, responsiveness: 0.2)
        case .halfCourt:
            return ZoomBehavior(minZoom: 1.3, maxZoom: 2.2, responsiveness: 0.08)
        case .transition:
            return ZoomBehavior(minZoom: 1.0, maxZoom: 1.8, responsiveness: 0.12)
        case .deadBall:
            return ZoomBehavior(minZoom: 1.2, maxZoom: 1.8, responsiveness: 0.05)
        case .unknown:
            return ZoomBehavior(minZoom: 1.0, maxZoom: 2.0, responsiveness: 0.1)
        }
    }
}

struct ZoomBehavior {
    let minZoom: CGFloat
    let maxZoom: CGFloat
    let responsiveness: CGFloat  // How fast to adjust zoom (0-1)
}

// MARK: - Game State Detector

class GameStateDetector {

    // MARK: - State History

    private var stateHistory: [GameState] = []
    private let historySize = 30  // ~1 second at 30fps
    private var currentState: GameState = .unknown

    // MARK: - Timing

    private var lastStateChange: Date = Date()
    private let minStateDuration: TimeInterval = 0.5  // Don't change state faster than this

    // MARK: - Thresholds

    /// Ball speed threshold for fast break detection (normalized units per second)
    private let fastBreakBallSpeedThreshold: CGFloat = 0.15

    /// Player speed threshold for running (normalized units per second)
    private let playerRunningThreshold: CGFloat = 0.05

    /// How much of the court players need to span to be "spread out"
    private let spreadOutThreshold: CGFloat = 0.4

    /// How clustered players need to be for half-court (max distance from center)
    private let clusteredThreshold: CGFloat = 0.25

    // MARK: - Detection

    /// Detect the current game state
    /// - Parameters:
    ///   - ball: Ball detection
    ///   - players: Player tracks
    ///   - court: Court detection
    ///   - dt: Time since last frame
    /// - Returns: Detected game state
    func detectState(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection,
        dt: Double = 1.0/30.0
    ) -> GameState {

        let detectedState = analyzeScene(ball: ball, players: players, court: court)

        // Add to history
        stateHistory.append(detectedState)
        if stateHistory.count > historySize {
            stateHistory.removeFirst()
        }

        // Only change state if:
        // 1. Minimum duration has passed since last change
        // 2. New state is dominant in recent history
        let timeSinceChange = Date().timeIntervalSince(lastStateChange)

        if timeSinceChange >= minStateDuration {
            let dominantState = findDominantState()
            if dominantState != currentState {
                currentState = dominantState
                lastStateChange = Date()
                debugPrint("🏀 [GameState] Changed to: \(currentState.emoji) \(currentState.rawValue)")
            }
        }

        return currentState
    }

    // MARK: - Scene Analysis

    private func analyzeScene(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection
    ) -> GameState {

        // If no ball detected for a while, likely dead ball
        guard let ball = ball, ball.confidence > 0.2 else {
            return .deadBall
        }

        let activePlayers = players.filter { $0.state == .confirmed }

        // If very few players detected, might be dead ball
        if activePlayers.count < 3 {
            return .unknown
        }

        // Analyze ball movement
        let ballSpeed = hypot(ball.velocity.x, ball.velocity.y)
        let ballMovingFast = ballSpeed > fastBreakBallSpeedThreshold

        // Analyze player movement
        var runningPlayerCount = 0
        var totalPlayerSpeed: CGFloat = 0

        for player in activePlayers {
            let speed = hypot(player.kalman.velocity.x, player.kalman.velocity.y)
            totalPlayerSpeed += speed
            if speed > playerRunningThreshold {
                runningPlayerCount += 1
            }
        }

        let avgPlayerSpeed = totalPlayerSpeed / CGFloat(max(1, activePlayers.count))
        let mostPlayersRunning = runningPlayerCount > activePlayers.count / 2

        // Analyze player spread
        let positions = activePlayers.map { $0.kalman.position }
        let spread = calculateSpread(positions)
        let playersSpreadOut = spread > spreadOutThreshold

        // Analyze ball position relative to court
        let ballNearHalfCourt = isBallNearHalfCourt(ball: ball, court: court)
        let ballInOffensiveZone = isBallInOffensiveZone(ball: ball, court: court)

        // Decision logic based on basketball knowledge

        // FAST BREAK: Ball moving fast toward basket, players spread and running
        if ballMovingFast && mostPlayersRunning && playersSpreadOut {
            return .fastBreak
        }

        // FAST BREAK: Ball deep in offensive zone, moving fast, players running
        if ballInOffensiveZone && ballSpeed > fastBreakBallSpeedThreshold * 0.7 && runningPlayerCount >= 2 {
            return .fastBreak
        }

        // TRANSITION: Ball near half court, players moving to positions
        if ballNearHalfCourt && avgPlayerSpeed > playerRunningThreshold * 0.5 {
            return .transition
        }

        // HALF COURT: Ball in offensive zone, players relatively stationary
        if ballInOffensiveZone && !mostPlayersRunning && !playersSpreadOut {
            return .halfCourt
        }

        // HALF COURT: Ball stationary or slow, players clustered
        if ballSpeed < fastBreakBallSpeedThreshold * 0.3 && !playersSpreadOut {
            return .halfCourt
        }

        // Default: If ball is moving but not fast break criteria, it's transition
        if ballSpeed > 0.02 {
            return .transition
        }

        return .unknown
    }

    // MARK: - Helpers

    private func calculateSpread(_ positions: [CGPoint]) -> CGFloat {
        guard !positions.isEmpty else { return 0 }

        // Calculate bounding box of all positions
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0
        let minY = positions.map { $0.y }.min() ?? 0
        let maxY = positions.map { $0.y }.max() ?? 0

        // Spread is diagonal of bounding box
        return hypot(maxX - minX, maxY - minY)
    }

    private func isBallNearHalfCourt(ball: BallDetection, court: CourtDetection) -> Bool {
        guard let halfCourt = court.halfCourtLine else {
            // Assume half court is at 0.5
            return abs(ball.position.x - 0.5) < 0.1
        }
        return abs(ball.position.x - halfCourt) < 0.1
    }

    private func isBallInOffensiveZone(ball: BallDetection, court: CourtDetection) -> Bool {
        // Ball is in offensive zone if it's past half court on either side
        // We consider both sides since we don't know which way the offense is going

        guard let halfCourt = court.halfCourtLine else {
            // Assume 0.5 is half court
            // If ball is in outer 40% of court, it's in offensive zone
            return ball.position.x < 0.3 || ball.position.x > 0.7
        }

        // Check if ball is significantly past half court
        let distanceFromHalf = abs(ball.position.x - halfCourt)
        return distanceFromHalf > 0.15
    }

    private func findDominantState() -> GameState {
        guard !stateHistory.isEmpty else { return .unknown }

        // Count occurrences of each state in recent history
        var counts: [GameState: Int] = [:]
        for state in stateHistory {
            counts[state, default: 0] += 1
        }

        // Find the most common state
        let dominant = counts.max(by: { $0.value < $1.value })?.key ?? .unknown

        // Require at least 40% dominance to change state
        let threshold = historySize * 4 / 10
        if (counts[dominant] ?? 0) >= threshold {
            return dominant
        }

        return currentState  // Keep current if no clear winner
    }

    // MARK: - Predictions

    /// Predict if a scoring attempt is likely soon
    func scoringAttemptLikely(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection
    ) -> Float {
        guard let ball = ball else { return 0 }

        var probability: Float = 0

        // Factor 1: Ball near basket
        let distToBasket = court.distanceToNearestBasket(from: ball.position)
        probability += Float(max(0, 0.3 - distToBasket))

        // Factor 2: Fast break in progress
        if currentState == .fastBreak {
            probability += 0.3
        }

        // Factor 3: Ball in paint
        if court.isInPaint(position: ball.position) {
            probability += 0.3
        }

        // Factor 4: Multiple players converging near basket
        let nearBasketPlayers = players.filter {
            court.distanceToNearestBasket(from: $0.kalman.position) < 0.15
        }
        probability += Float(nearBasketPlayers.count) * 0.1

        return min(1.0, probability)
    }

    /// Predict if a turnover/transition is likely
    func transitionLikely(
        ball: BallDetection?,
        players: [TrackedObject]
    ) -> Float {
        guard let ball = ball else { return 0 }

        // Sudden change in ball direction often indicates turnover
        let ballSpeed = hypot(ball.velocity.x, ball.velocity.y)

        // If ball is moving fast but state was half court, likely transition
        if ballSpeed > fastBreakBallSpeedThreshold && currentState == .halfCourt {
            return 0.7
        }

        return 0.2
    }

    // MARK: - Reset

    func reset() {
        stateHistory = []
        currentState = .unknown
        lastStateChange = Date()
    }
}
