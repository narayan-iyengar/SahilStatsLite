//
//  VideoAnalysisPipeline.swift
//  SahilStatsLite
//
//  Main orchestrator for the Skynet vision pipeline
//  Combines all detection and prediction algorithms:
//  - BallDetector: HSV color + Kalman tracking
//  - CourtDetector: Hough transform + homography
//  - PersonClassifier: Kid/adult/ref classification
//  - DeepTracker: SORT-style multi-object tracking
//  - ActionProbabilityField: Novel predictive focus
//  - GameStateDetector: Basketball heuristics
//
//  Zero training required - all algorithms use:
//  - Classical computer vision
//  - Apple Vision pre-trained APIs
//  - Basketball domain knowledge as heuristics
//  - Online adaptation/calibration
//

import Foundation
import CoreGraphics
import AVFoundation
import Vision

// MARK: - Ultra-Smooth Focus Tracker

/// Broadcast-quality focus smoothing that prevents jittery camera movements
/// Uses velocity-based smoothing with dead zones and confidence streak requirements
class UltraSmoothFocusTracker {

    // Current smoothed position
    private var smoothX: Double = 0.5
    private var smoothY: Double = 0.5

    // Velocity for momentum-based smoothing
    private var velocityX: Double = 0
    private var velocityY: Double = 0

    // Configuration (validated through testing)
    private let positionSmoothing: Double = 0.02    // 2% per frame - very smooth
    private let velocityDamping: Double = 0.85      // Momentum decay
    private let deadZone: Double = 0.02             // 2% dead zone - ignore tiny movements
    private let maxSpeed: Double = 0.015            // Max movement per frame

    // Confidence streak tracking - only update after consistent detections
    private var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 2         // Require 2 consecutive frames

    // Target from detection
    private var targetX: Double = 0.5
    private var targetY: Double = 0.5

    /// Update with new detection target
    /// - Parameters:
    ///   - target: Detected focus point (0-1 normalized)
    ///   - confidence: Detection confidence (0-1)
    /// - Returns: Smoothed focus point
    func update(target: CGPoint, confidence: Float) -> CGPoint {
        // Track confidence streak
        if confidence > 0.3 {
            highConfidenceStreak += 1
        } else {
            highConfidenceStreak = max(0, highConfidenceStreak - 1)
        }

        // Only update target if we have consistent high-confidence detections
        if highConfidenceStreak >= minStreakForUpdate {
            targetX = Double(target.x)
            targetY = Double(target.y)
        }

        // Calculate distance to target
        let dx = targetX - smoothX
        let dy = targetY - smoothY
        let distance = sqrt(dx * dx + dy * dy)

        // Dead zone - ignore tiny movements
        if distance < deadZone {
            // Just decay velocity
            velocityX *= velocityDamping
            velocityY *= velocityDamping
        } else {
            // Calculate new velocity toward target
            let dirX = dx / distance
            let dirY = dy / distance

            // Smooth acceleration toward target
            velocityX += dirX * positionSmoothing
            velocityY += dirY * positionSmoothing

            // Apply velocity damping
            velocityX *= velocityDamping
            velocityY *= velocityDamping

            // Clamp velocity to max speed
            let speed = sqrt(velocityX * velocityX + velocityY * velocityY)
            if speed > maxSpeed {
                velocityX = (velocityX / speed) * maxSpeed
                velocityY = (velocityY / speed) * maxSpeed
            }
        }

        // Apply velocity to position
        smoothX += velocityX
        smoothY += velocityY

        // Clamp to valid range
        smoothX = max(0.1, min(0.9, smoothX))
        smoothY = max(0.1, min(0.9, smoothY))

        return CGPoint(x: smoothX, y: smoothY)
    }

    /// Reset to center position
    func reset() {
        smoothX = 0.5
        smoothY = 0.5
        velocityX = 0
        velocityY = 0
        targetX = 0.5
        targetY = 0.5
        highConfidenceStreak = 0
    }
}

// MARK: - Pipeline Result

struct PipelineResult {
    // Frame info
    let frameNumber: Int
    let timestamp: Double

    // Detections
    let ball: BallDetection?
    let court: CourtDetection
    let players: [TrackedObject]
    let gameState: GameState

    // Action prediction (novel)
    let actionProbability: ActionProbability

    // Camera recommendations
    let recommendedFocusPoint: CGPoint  // Where to point camera
    let recommendedZoom: CGFloat        // Zoom level

    // Debug info
    let processingTimeMs: Double
}

// MARK: - Video Analysis Pipeline

class VideoAnalysisPipeline {

    // MARK: - Components

    private let ballDetector = BallDetector()
    private let courtDetector = CourtDetector()
    private let personClassifier = PersonClassifier()
    private let deepTracker = DeepTracker()
    private let actionField = ActionProbabilityField()
    private let gameStateDetector = GameStateDetector()

    // Ultra-smooth focus tracking (validated through testing)
    private let smoothFocusTracker = UltraSmoothFocusTracker()

    // MARK: - State

    private var frameCount: Int = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var isCalibrated: Bool = false

    // MARK: - Configuration

    struct Config {
        var enableBallDetection: Bool = true
        var enableCourtDetection: Bool = true
        var enablePlayerTracking: Bool = true
        var enableGameStateDetection: Bool = true
        var enableActionPrediction: Bool = true
        var debugMode: Bool = false
    }

    var config = Config()

    // MARK: - Processing

    /// Process a single video frame through the entire pipeline
    /// - Parameters:
    ///   - pixelBuffer: The video frame
    ///   - timestamp: Frame timestamp in seconds
    /// - Returns: Complete pipeline result with all detections and recommendations
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double) -> PipelineResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Calculate dt for Kalman filters
        let dt = lastFrameTime > 0 ? CFAbsoluteTimeGetCurrent() - lastFrameTime : 1.0/30.0
        lastFrameTime = CFAbsoluteTimeGetCurrent()

        frameCount += 1

        // 1. Court Detection (calibrates in first ~30 frames)
        var courtDetection = CourtDetection(
            bounds: CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.6),
            halfCourtLine: 0.5,
            leftBasket: CGPoint(x: 0.05, y: 0.5),
            rightBasket: CGPoint(x: 0.95, y: 0.5),
            confidence: 0.5,
            isCalibrated: false
        )

        if config.enableCourtDetection {
            courtDetection = courtDetector.detectCourt(in: pixelBuffer)
        }

        // 2. Ball Detection (color segmentation + Kalman)
        var ballDetection: BallDetection? = nil

        if config.enableBallDetection {
            ballDetection = ballDetector.detectBall(in: pixelBuffer, dt: dt)
        }

        // 3. Player Detection & Classification
        var players: [TrackedObject] = []

        if config.enablePlayerTracking {
            // Use PersonClassifier to detect and classify people
            let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)

            // Use DeepTracker for Kalman-smoothed tracking
            players = deepTracker.update(detections: classifiedPeople, dt: dt)
        }

        // 4. Game State Detection
        var gameState: GameState = .unknown

        if config.enableGameStateDetection {
            gameState = gameStateDetector.detectState(
                ball: ballDetection,
                players: players,
                court: courtDetection,
                dt: dt
            )
        }

        // 5. Action Probability Field (novel predictive focus)
        var actionProbability = ActionProbability(
            center: CGPoint(x: 0.5, y: 0.5),
            predictedCenter: CGPoint(x: 0.5, y: 0.5),
            spread: 0.3,
            confidence: 0.5,
            dominantFactor: "default"
        )

        if config.enableActionPrediction {
            actionProbability = actionField.compute(
                ball: ballDetection,
                players: players,
                court: courtDetection,
                gameState: gameState
            )
        }

        // 6. Camera Recommendations (with ultra-smooth tracking)
        // Raw focus from action probability field
        let rawFocusPoint = actionProbability.center

        // Apply ultra-smooth tracking to eliminate jitter
        let focusPoint = smoothFocusTracker.update(
            target: rawFocusPoint,
            confidence: actionProbability.confidence
        )

        let zoom = calculateRecommendedZoom(
            actionProbability: actionProbability,
            gameState: gameState
        )

        let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        if config.debugMode && frameCount % 30 == 0 {
            debugPrint("🎬 [Pipeline] Frame \(frameCount) | State: \(gameState.emoji) | Ball: \(ballDetection != nil ? "✓" : "✗") | Players: \(players.count) | Focus: (\(String(format: "%.2f", focusPoint.x)), \(String(format: "%.2f", focusPoint.y))) | Zoom: \(String(format: "%.1f", zoom))x | \(String(format: "%.1f", processingTime))ms")
        }

        return PipelineResult(
            frameNumber: frameCount,
            timestamp: timestamp,
            ball: ballDetection,
            court: courtDetection,
            players: players,
            gameState: gameState,
            actionProbability: actionProbability,
            recommendedFocusPoint: focusPoint,
            recommendedZoom: zoom,
            processingTimeMs: processingTime
        )
    }

    // MARK: - Zoom Calculation

    private func calculateRecommendedZoom(
        actionProbability: ActionProbability,
        gameState: GameState
    ) -> CGFloat {
        let behavior = gameState.zoomBehavior

        // Base zoom from action probability
        var zoom = actionProbability.recommendedZoom

        // Clamp to game state limits
        zoom = max(behavior.minZoom, min(behavior.maxZoom, zoom))

        return zoom
    }

    // MARK: - Calibration Status

    var calibrationProgress: Float {
        // Court detector calibrates in first 30 frames
        let courtProgress = courtDetector.detectCourt(in: CVPixelBuffer.create()!).confidence
        return courtProgress
    }

    // MARK: - Reset

    func reset() {
        frameCount = 0
        lastFrameTime = 0
        isCalibrated = false

        ballDetector.reset()
        courtDetector.reset()
        deepTracker.reset()
        actionField.reset()
        gameStateDetector.reset()
        smoothFocusTracker.reset()
    }
}

// MARK: - CVPixelBuffer Helper

extension CVPixelBuffer {
    /// Create a minimal pixel buffer (for default court detection)
    static func create(width: Int = 100, height: Int = 100) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        return pixelBuffer
    }
}

// MARK: - Pipeline Statistics

extension VideoAnalysisPipeline {

    struct Statistics {
        var totalFrames: Int = 0
        var avgProcessingTimeMs: Double = 0
        var ballDetectionRate: Float = 0
        var avgPlayerCount: Float = 0
        var gameStateBreakdown: [GameState: Int] = [:]
    }

    /// Accumulator for gathering statistics over a video
    class StatisticsAccumulator {
        private var processingTimes: [Double] = []
        private var ballDetected: [Bool] = []
        private var playerCounts: [Int] = []
        private var gameStates: [GameState] = []

        func add(result: PipelineResult) {
            processingTimes.append(result.processingTimeMs)
            ballDetected.append(result.ball != nil)
            playerCounts.append(result.players.count)
            gameStates.append(result.gameState)
        }

        func getStatistics() -> Statistics {
            var stats = Statistics()

            stats.totalFrames = processingTimes.count

            if !processingTimes.isEmpty {
                stats.avgProcessingTimeMs = processingTimes.reduce(0, +) / Double(processingTimes.count)
            }

            if !ballDetected.isEmpty {
                stats.ballDetectionRate = Float(ballDetected.filter { $0 }.count) / Float(ballDetected.count)
            }

            if !playerCounts.isEmpty {
                stats.avgPlayerCount = Float(playerCounts.reduce(0, +)) / Float(playerCounts.count)
            }

            for state in gameStates {
                stats.gameStateBreakdown[state, default: 0] += 1
            }

            return stats
        }
    }
}
