//
//  ActionProbabilityField.swift
//  SahilStatsLite
//
//  NOVEL APPROACH: Predictive Action Probability Field
//
//  Instead of tracking where the action IS, we compute where
//  the action WILL BE in the next 0.3-0.5 seconds.
//
//  This mimics how expert basketball players/coaches see the game:
//  - They look at empty space where they PREDICT the action will occur
//  - They anticipate based on ball movement, player velocities, court geometry
//
//  The Action Probability Field combines:
//  - Ball position & velocity (primary weight)
//  - Player positions & velocities (weighted by proximity to ball)
//  - Basket locations (the eventual target of offense)
//  - Game state (fast break, half court, transition)
//  - Court geometry (paint, 3pt line, half court)
//
//  Zero training required - uses basketball domain knowledge as heuristics.
//

import Foundation
import CoreGraphics

// MARK: - Action Probability Result

struct ActionProbability {
    let center: CGPoint              // Where camera should focus (normalized 0-1)
    let predictedCenter: CGPoint     // Predicted position in 0.3-0.5s
    let spread: CGFloat              // How spread out the action is (affects zoom)
    let confidence: Float            // Overall confidence
    let dominantFactor: String       // What's driving the prediction ("ball", "players", "basket")

    // Recommended zoom level based on action spread
    var recommendedZoom: CGFloat {
        // Spread of 0.1 = tight (zoom in), 0.5 = wide (zoom out)
        let baseZoom: CGFloat = 1.5
        let zoomAdjust = (0.3 - spread) * 2  // Higher spread = zoom out
        return max(1.0, min(2.5, baseZoom + zoomAdjust))
    }
}

// MARK: - Action Probability Field

class ActionProbabilityField {

    // MARK: - Weights (can be tuned)

    struct Weights {
        // How much each factor contributes to the probability field
        var ball: CGFloat = 0.50          // Ball position is primary
        var ballVelocity: CGFloat = 0.15  // Where ball is heading
        var players: CGFloat = 0.20       // Player cluster center
        var basket: CGFloat = 0.15        // Eventual target

        // Adjustments based on game state
        mutating func adjustForFastBreak() {
            ball = 0.35
            ballVelocity = 0.30  // Velocity matters more
            players = 0.15
            basket = 0.20        // Basket matters more
        }

        mutating func adjustForHalfCourt() {
            ball = 0.55
            ballVelocity = 0.10
            players = 0.25       // Players matter more in half court
            basket = 0.10
        }

        mutating func adjustForTransition() {
            ball = 0.40
            ballVelocity = 0.25
            players = 0.20
            basket = 0.15
        }

        mutating func reset() {
            ball = 0.50
            ballVelocity = 0.15
            players = 0.20
            basket = 0.15
        }
    }

    private var weights = Weights()

    // MARK: - Prediction Time Horizon

    private let predictionHorizon: Double = 0.3  // Predict 0.3 seconds ahead

    // MARK: - Smoothing (Kalman-like)

    private var smoothedCenter: CGPoint?
    private let smoothingFactor: CGFloat = 0.15  // How fast to move toward new prediction

    // MARK: - Computation

    /// Compute the action probability field
    /// - Parameters:
    ///   - ball: Ball detection (position, velocity, prediction)
    ///   - players: Player tracks from DeepTracker
    ///   - court: Court detection (bounds, baskets)
    ///   - gameState: Current game state
    /// - Returns: Action probability with focus point and zoom recommendation
    func compute(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection,
        gameState: GameState
    ) -> ActionProbability {

        // Adjust weights based on game state
        adjustWeights(for: gameState)

        // 1. Ball contribution (highest weight)
        var ballContribution: CGPoint = CGPoint(x: 0.5, y: 0.5)
        var ballVelocityContribution: CGPoint = .zero
        var hasBall = false

        if let ball = ball, ball.confidence > 0.3 {
            ballContribution = ball.position
            hasBall = true

            // Predict where ball will be
            let predictedBall = ball.predictedPosition
            ballVelocityContribution = CGPoint(
                x: (predictedBall.x - ball.position.x),
                y: (predictedBall.y - ball.position.y)
            )
        }

        // 2. Player contribution (weighted by proximity to ball)
        var playerContribution: CGPoint = .zero
        var playerWeightSum: CGFloat = 0
        var actionSpread: CGFloat = 0

        let activePlayers = players.filter { $0.state == .confirmed }

        if !activePlayers.isEmpty {
            // Calculate player cluster center, weighted by proximity to ball
            for player in activePlayers {
                let pos = player.kalman.position

                // Weight by proximity to ball (closer = higher weight)
                var weight: CGFloat = 1.0
                if hasBall {
                    let distToBall = hypot(pos.x - ballContribution.x, pos.y - ballContribution.y)
                    weight = max(0.1, 1.0 - distToBall * 2)  // Closer = higher weight
                }

                // Extra weight for players moving toward ball or basket
                let velocity = player.kalman.velocity
                let speed = hypot(velocity.x, velocity.y)
                if speed > 0.01 {
                    weight *= 1.0 + speed * 5  // Moving players are more important
                }

                playerContribution.x += pos.x * weight
                playerContribution.y += pos.y * weight
                playerWeightSum += weight
            }

            if playerWeightSum > 0 {
                playerContribution.x /= playerWeightSum
                playerContribution.y /= playerWeightSum
            }

            // Calculate action spread (standard deviation of player positions)
            var varianceX: CGFloat = 0
            var varianceY: CGFloat = 0
            for player in activePlayers {
                let pos = player.kalman.position
                varianceX += (pos.x - playerContribution.x) * (pos.x - playerContribution.x)
                varianceY += (pos.y - playerContribution.y) * (pos.y - playerContribution.y)
            }
            varianceX /= CGFloat(activePlayers.count)
            varianceY /= CGFloat(activePlayers.count)
            actionSpread = sqrt(varianceX + varianceY)
        }

        // 3. Basket contribution (eventual target)
        var basketContribution: CGPoint = CGPoint(x: 0.5, y: 0.5)

        if hasBall {
            // Find which basket the offense is attacking
            if let nearestBasket = court.nearestBasket(from: ballContribution) {
                // If ball is moving toward basket, weight it more
                let ballTravelDir = CGPoint(
                    x: ballVelocityContribution.x,
                    y: ballVelocityContribution.y
                )
                let toBasket = CGPoint(
                    x: nearestBasket.x - ballContribution.x,
                    y: nearestBasket.y - ballContribution.y
                )

                // Dot product to check if moving toward basket
                let dot = ballTravelDir.x * toBasket.x + ballTravelDir.y * toBasket.y
                if dot > 0 {
                    basketContribution = nearestBasket
                } else {
                    // Ball moving away from nearest basket - likely attacking other basket
                    if let leftBasket = court.leftBasket, let rightBasket = court.rightBasket {
                        basketContribution = nearestBasket == leftBasket ? rightBasket : leftBasket
                    }
                }
            }
        }

        // 4. Combine contributions with weights
        var center = CGPoint(
            x: ballContribution.x * weights.ball +
               ballVelocityContribution.x * weights.ballVelocity +
               playerContribution.x * weights.players +
               basketContribution.x * weights.basket,
            y: ballContribution.y * weights.ball +
               ballVelocityContribution.y * weights.ballVelocity +
               playerContribution.y * weights.players +
               basketContribution.y * weights.basket
        )

        // 5. Add "lead space" - bias toward direction of movement
        if hasBall, let ball = ball {
            let velocity = ball.velocity
            let speed = hypot(velocity.x, velocity.y)
            if speed > 0.02 {
                // Add lead space proportional to speed
                center.x += velocity.x * 0.5
                center.y += velocity.y * 0.5
            }
        }

        // 6. Clamp to court bounds
        center.x = max(court.bounds.minX, min(court.bounds.maxX, center.x))
        center.y = max(court.bounds.minY, min(court.bounds.maxY, center.y))

        // 7. Smooth the output to prevent jitter
        if let prev = smoothedCenter {
            center = CGPoint(
                x: prev.x + (center.x - prev.x) * smoothingFactor,
                y: prev.y + (center.y - prev.y) * smoothingFactor
            )
        }
        smoothedCenter = center

        // 8. Predict future position
        var predictedCenter = center
        if hasBall, let ball = ball {
            predictedCenter.x += ball.velocity.x * CGFloat(predictionHorizon)
            predictedCenter.y += ball.velocity.y * CGFloat(predictionHorizon)
        }

        // 9. Determine dominant factor
        let dominantFactor: String
        if hasBall && weights.ball >= weights.players {
            dominantFactor = "ball"
        } else if !activePlayers.isEmpty && weights.players > weights.ball {
            dominantFactor = "players"
        } else {
            dominantFactor = "basket"
        }

        // 10. Calculate confidence
        var confidence: Float = 0.5
        if hasBall { confidence += 0.3 }
        if !activePlayers.isEmpty { confidence += 0.2 }
        confidence = min(1.0, confidence)

        return ActionProbability(
            center: center,
            predictedCenter: predictedCenter,
            spread: actionSpread,
            confidence: confidence,
            dominantFactor: dominantFactor
        )
    }

    // MARK: - Weight Adjustment

    private func adjustWeights(for gameState: GameState) {
        switch gameState {
        case .fastBreak:
            weights.adjustForFastBreak()
        case .halfCourt:
            weights.adjustForHalfCourt()
        case .transition:
            weights.adjustForTransition()
        case .deadBall, .unknown:
            weights.reset()
        }
    }

    // MARK: - Reset

    func reset() {
        smoothedCenter = nil
        weights.reset()
    }
}

// MARK: - Extended Prediction with Basketball Knowledge

extension ActionProbabilityField {

    /// Predict if a shot is likely based on current state
    func shotProbability(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection
    ) -> Float {
        guard let ball = ball else { return 0 }

        var probability: Float = 0

        // Factor 1: Ball in shooting range (near basket)
        let distToBasket = court.distanceToNearestBasket(from: ball.position)
        if distToBasket < 0.25 {  // Within ~20ft
            probability += 0.3
        }

        // Factor 2: Ball in paint (very close)
        if court.isInPaint(position: ball.position) {
            probability += 0.3
        }

        // Factor 3: Ball stopped or moving slowly (set shot)
        let ballSpeed = hypot(ball.velocity.x, ball.velocity.y)
        if ballSpeed < 0.02 {
            probability += 0.2
        }

        // Factor 4: Players clustered near basket
        let nearBasketPlayers = players.filter { player in
            court.distanceToNearestBasket(from: player.kalman.position) < 0.2
        }
        if nearBasketPlayers.count >= 3 {
            probability += 0.2
        }

        return min(1.0, probability)
    }

    /// Determine which basket the offense is attacking
    func attackingBasket(
        ball: BallDetection?,
        players: [TrackedObject],
        court: CourtDetection
    ) -> CGPoint? {
        guard let ball = ball else { return nil }

        // If ball is on one half, likely attacking the basket on that half
        if let halfCourt = court.halfCourtLine {
            if ball.position.x < halfCourt {
                return court.leftBasket
            } else {
                return court.rightBasket
            }
        }

        // Fallback: use ball velocity direction
        if ball.velocity.x < -0.01 {
            return court.leftBasket
        } else if ball.velocity.x > 0.01 {
            return court.rightBasket
        }

        return court.nearestBasket(from: ball.position)
    }
}
