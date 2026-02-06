#!/usr/bin/env swift
//
//  SkynetVideoTest.swift
//
//  ULTRA-SMOOTH Skynet vision pipeline with broadcast-quality camera motion.
//
//  Key insight: Professional broadcast cameras move SLOWLY and DELIBERATELY.
//  They don't chase every ball movement - they anticipate and glide.
//
//  Smoothing strategies:
//  1. Very low process noise Kalman (trust predictions over measurements)
//  2. Exponential moving average on top of Kalman
//  3. Zoom changes interpolated over 60+ frames
//  4. Focus only updates on sustained high-confidence detections
//  5. Strong momentum/inertia - resist sudden direction changes
//  6. Dead zone - ignore small movements entirely
//
//  v2: Added person detection (VNDetectHumanRectanglesRequest) for combined
//      ball + player tracking. Fixed pixel buffer pool leak (was stopping at 9%).
//
//  Usage: swift SkynetVideoTest.swift "/path/to/video.mp4"
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import Vision

// MARK: - Ultra-Smooth Focus Tracker

class UltraSmoothFocusTracker {

    // Current smoothed position
    private var smoothX: Double = 0.5
    private var smoothY: Double = 0.5

    // Velocity (for momentum)
    private var velocityX: Double = 0
    private var velocityY: Double = 0

    // Target position (where we want to go)
    private var targetX: Double = 0.5
    private var targetY: Double = 0.5

    // Smoothing parameters - BROADCAST QUALITY
    // Key insight: real broadcast cameras barely move. They anticipate, not chase.
    private let positionSmoothing: Double = 0.008  // 0.8% per frame (was 1.2%)
    private let velocityDamping: Double = 0.75     // Stronger decay = less momentum carry
    private let deadZone: Double = 0.06            // 6% dead zone (was 3.5%) - ignore centroid jitter
    private let maxSpeed: Double = 0.006           // 0.6% per frame max (was 1%) - very slow pan

    // Confidence tracking
    private var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 8  // Require 8 consistent frames (~0.13s at 60fps)

    var position: CGPoint {
        CGPoint(x: smoothX, y: smoothY)
    }

    func update(detectedPosition: CGPoint?, confidence: Float,
                playerCenter: CGPoint?, playerConfidence: Float,
                dt: Double) {

        // Combine ball + player signals for target position
        // Ball has priority when detected with high confidence
        // Players provide stable background signal
        var combinedPosition: CGPoint? = nil
        var combinedConfidence: Float = 0

        if let ballPos = detectedPosition, confidence > 0.4, let pCenter = playerCenter, playerConfidence > 0.3 {
            // Both available with high-confidence ball: 30% ball, 70% player
            // Players are far more reliable (89% vs 10% detection rate)
            let ballWeight: CGFloat = 0.3
            let playerWeight: CGFloat = 0.7
            combinedPosition = CGPoint(
                x: ballPos.x * ballWeight + pCenter.x * playerWeight,
                y: ballPos.y * ballWeight + pCenter.y * playerWeight
            )
            combinedConfidence = confidence * 0.3 + playerConfidence * 0.7
        } else if let pCenter = playerCenter, playerConfidence > 0.3 {
            // Players detected (with or without low-confidence ball) - trust players
            combinedPosition = pCenter
            combinedConfidence = playerConfidence * 0.9
        } else if let ballPos = detectedPosition, confidence > 0.2 {
            // Ball only, no players (rare) - use ball
            combinedPosition = ballPos
            combinedConfidence = confidence
        }

        // Track high-confidence streaks
        if let combined = combinedPosition, combinedConfidence > 0.2 {
            highConfidenceStreak += 1

            // Only update target if we have sustained detection
            if highConfidenceStreak >= minStreakForUpdate {
                let dx = Double(combined.x) - targetX
                let dy = Double(combined.y) - targetY

                // Apply dead zone - ignore small movements
                if abs(dx) > deadZone || abs(dy) > deadZone {
                    targetX = Double(combined.x)
                    targetY = Double(combined.y)
                }
            }
        } else {
            highConfidenceStreak = max(0, highConfidenceStreak - 2)  // Decay faster than build
        }

        // Calculate desired movement toward target
        let dx = targetX - smoothX
        let dy = targetY - smoothY

        // Add to velocity with smoothing
        velocityX += dx * positionSmoothing
        velocityY += dy * positionSmoothing

        // Apply velocity damping (momentum decay)
        velocityX *= velocityDamping
        velocityY *= velocityDamping

        // Clamp velocity to max speed
        let speed = sqrt(velocityX * velocityX + velocityY * velocityY)
        if speed > maxSpeed {
            let scale = maxSpeed / speed
            velocityX *= scale
            velocityY *= scale
        }

        // Update position
        smoothX += velocityX
        smoothY += velocityY

        // Clamp to valid range
        smoothX = max(0.15, min(0.85, smoothX))
        smoothY = max(0.15, min(0.85, smoothY))
    }

    func reset() {
        smoothX = 0.5
        smoothY = 0.5
        targetX = 0.5
        targetY = 0.5
        velocityX = 0
        velocityY = 0
        highConfidenceStreak = 0
    }
}

// MARK: - Ultra-Smooth Zoom Controller

class UltraSmoothZoomController {

    private var currentZoom: Double = 1.3
    private var targetZoom: Double = 1.3

    // Zoom changes VERY smoothly - zoom jitter feels worse than pan jitter
    private let zoomSmoothing: Double = 0.005  // 0.5% per frame (was 1%) - ultra slow zoom
    private let minZoom: Double = 1.2
    private let maxZoom: Double = 1.5  // Tighter range (was 1.6) - less zoom variation

    var zoom: CGFloat {
        CGFloat(currentZoom)
    }

    func update(ballDetected: Bool, confidence: Float, actionSpread: Float,
                personCount: Int, focusPosition: CGPoint? = nil) {
        if personCount > 0 {
            // Use player spread to inform zoom
            if actionSpread > 0.15 {
                // Players spread wide - zoom out
                targetZoom = 1.2
            } else if actionSpread < 0.05 && ballDetected && confidence > 0.3 {
                // Clustered action with ball - zoom in
                targetZoom = 1.5
            } else if ballDetected && confidence > 0.3 {
                // Have ball detection - moderate zoom
                targetZoom = 1.4
            } else {
                // Default moderate
                targetZoom = 1.3
            }
        } else if ballDetected && confidence > 0.3 {
            // No people detected but have ball
            targetZoom = 1.5
        } else {
            // No detection - stay at moderate zoom
            targetZoom = 1.3
        }

        // Smoothly interpolate toward target
        let diff = targetZoom - currentZoom
        currentZoom += diff * zoomSmoothing
        currentZoom = max(minZoom, min(maxZoom, currentZoom))
    }

    func reset() {
        currentZoom = 1.3
        targetZoom = 1.3
    }
}

// MARK: - Simple Ball Detector (with hoop filtering)

class SimpleBallDetector {

    // Color thresholds (basketball orange - tighter to avoid hoop)
    private var minR: Float = 0.55
    private var maxR: Float = 0.92
    private var minG: Float = 0.25
    private var maxG: Float = 0.55
    private var minB: Float = 0.05
    private var maxB: Float = 0.35

    // Position history for motion detection
    private var lastPositions: [CGPoint] = []
    private let motionHistorySize = 10

    struct Detection {
        let position: CGPoint
        let confidence: Float
        let radius: CGFloat
    }

    func detect(in pixelBuffer: CVPixelBuffer) -> Detection? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Grid-based detection
        let gridSize = 28  // Finer grid for better precision
        let cellWidth = width / gridSize
        let cellHeight = height / gridSize

        var orangeGrid = [[Int]](repeating: [Int](repeating: 0, count: gridSize), count: gridSize)

        // Sample each grid cell
        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                var orangeCount = 0

                for sy in 0..<3 {
                    for sx in 0..<3 {
                        let px = min(width - 1, gx * cellWidth + sx * (cellWidth / 3))
                        let py = min(height - 1, gy * cellHeight + sy * (cellHeight / 3))

                        let offset = py * bytesPerRow + px * 4
                        let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

                        let b = Float(ptr[0]) / 255.0
                        let g = Float(ptr[1]) / 255.0
                        let r = Float(ptr[2]) / 255.0

                        // Stricter basketball orange check
                        // Basketball is orange-brown, hoop rim is more red-orange
                        if r >= minR && r <= maxR &&
                           g >= minG && g <= maxG &&
                           b >= minB && b <= maxB &&
                           r > g * 1.3 &&      // Red must dominate green more
                           r > b * 2.0 &&      // Red must strongly dominate blue
                           g > b * 1.2 {       // Green > blue (basketball leather has some green)
                            orangeCount += 1
                        }
                    }
                }

                orangeGrid[gy][gx] = orangeCount
            }
        }

        // Find all valid clusters
        var visited = [[Bool]](repeating: [Bool](repeating: false, count: gridSize), count: gridSize)
        var candidates: [(center: CGPoint, size: Int, confidence: Float)] = []

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                if orangeGrid[gy][gx] >= 2 && !visited[gy][gx] {
                    var cluster: [(x: Int, y: Int)] = []
                    var queue: [(x: Int, y: Int)] = [(gx, gy)]
                    var totalOrange = 0

                    while !queue.isEmpty {
                        let (cx, cy) = queue.removeFirst()
                        if cx < 0 || cx >= gridSize || cy < 0 || cy >= gridSize { continue }
                        if visited[cy][cx] { continue }
                        if orangeGrid[cy][cx] < 1 { continue }

                        visited[cy][cx] = true
                        cluster.append((cx, cy))
                        totalOrange += orangeGrid[cy][cx]

                        queue.append((cx + 1, cy))
                        queue.append((cx - 1, cy))
                        queue.append((cx, cy + 1))
                        queue.append((cx, cy - 1))
                    }

                    // Ball size filter - TIGHTER range (ball is small, hoop is big)
                    // At 28 grid, ball should be about 2-8 cells
                    if cluster.count >= 2 && cluster.count <= 12 {
                        let sumX = cluster.reduce(0.0) { $0 + Double($1.x) }
                        let sumY = cluster.reduce(0.0) { $0 + Double($1.y) }
                        let centerX = (sumX / Double(cluster.count) + 0.5) / Double(gridSize)
                        let centerY = (sumY / Double(cluster.count) + 0.5) / Double(gridSize)

                        // FILTER 1: Reject detections in upper 25% of frame (hoop area)
                        if centerY < 0.25 {
                            continue  // Skip - likely the hoop
                        }

                        // FILTER 2: Reject detections at extreme edges (sideline/baseline areas)
                        if centerX < 0.05 || centerX > 0.95 {
                            continue
                        }

                        // Aspect ratio check
                        let minX = cluster.min(by: { $0.x < $1.x })!.x
                        let maxX = cluster.max(by: { $0.x < $1.x })!.x
                        let minY = cluster.min(by: { $0.y < $1.y })!.y
                        let maxY = cluster.max(by: { $0.y < $1.y })!.y

                        let clusterW = maxX - minX + 1
                        let clusterH = maxY - minY + 1
                        let aspectRatio = Float(clusterW) / Float(max(1, clusterH))

                        // FILTER 3: Tighter aspect ratio for ball (more circular)
                        if aspectRatio > 0.5 && aspectRatio < 2.0 {
                            let avgOrange = Float(totalOrange) / Float(cluster.count * 9)
                            let shapeScore = 1.0 - abs(aspectRatio - 1.0) * 0.4

                            // FILTER 4: Penalize large detections (hoop is big)
                            let sizePenalty = cluster.count > 8 ? Float(cluster.count - 8) * 0.05 : 0

                            let confidence = avgOrange * shapeScore - sizePenalty

                            if confidence > 0.15 {
                                candidates.append((
                                    center: CGPoint(x: centerX, y: centerY),
                                    size: cluster.count,
                                    confidence: confidence
                                ))
                            }
                        }
                    }
                }
            }
        }

        // FILTER 5: Prefer detections that show motion (ball moves, hoop doesn't)
        var bestCandidate: (center: CGPoint, size: Int, confidence: Float)? = nil

        for candidate in candidates {
            var motionBonus: Float = 0

            // Check if this position is different from recent history
            if !lastPositions.isEmpty {
                let avgHistoryX = lastPositions.reduce(0.0) { $0 + $1.x } / CGFloat(lastPositions.count)
                let avgHistoryY = lastPositions.reduce(0.0) { $0 + $1.y } / CGFloat(lastPositions.count)

                let dx = abs(candidate.center.x - avgHistoryX)
                let dy = abs(candidate.center.y - avgHistoryY)
                let distance = sqrt(dx * dx + dy * dy)

                // If detection is in a different spot than history, it's more likely the ball
                if distance > 0.05 && distance < 0.4 {
                    motionBonus = 0.1  // Boost for reasonable motion
                } else if distance < 0.02 {
                    motionBonus = -0.1  // Penalty for stationary (might be hoop)
                }
            }

            let adjustedConfidence = candidate.confidence + motionBonus

            if bestCandidate == nil || adjustedConfidence > bestCandidate!.confidence {
                bestCandidate = (candidate.center, candidate.size, adjustedConfidence)
            }
        }

        // Update position history
        if let best = bestCandidate {
            lastPositions.append(best.center)
            if lastPositions.count > motionHistorySize {
                lastPositions.removeFirst()
            }
        }

        if let cluster = bestCandidate, cluster.confidence > 0.2 {
            return Detection(
                position: cluster.center,
                confidence: cluster.confidence,
                radius: CGFloat(cluster.size) / CGFloat(gridSize) * 0.4
            )
        }

        return nil
    }
}

// MARK: - Person Detector (Vision framework)

class SimplePersonDetector {

    // Cached results (Vision is expensive, run every N frames)
    private var cachedBoxes: [CGRect] = []
    private var framesSinceDetection = 0
    private let detectionInterval = 6  // Every 6 frames (~10fps at 60fps)

    // Rolling height statistics for kid/adult classification
    private var heightHistory: [CGFloat] = []
    private let historySize = 100
    private var medianHeight: CGFloat = 0.15

    // Rolling centroid smoother - averages recent centroids to eliminate jitter
    private var centroidHistory: [CGPoint] = []
    private let centroidHistorySize = 8  // Average over ~8 detection cycles = ~0.8s

    // Current focus point for proximity weighting (updated externally)
    var currentFocusHint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    struct PersonDetection {
        let boundingBox: CGRect      // In normalized coords (0-1), Vision convention (origin bottom-left)
        let displayBox: CGRect       // In normalized coords (0-1), display convention (origin top-left)
        let isLikelyPlayer: Bool     // true = kid-sized (player), false = adult-sized (coach/parent)
    }

    var lastDetections: [PersonDetection] = []

    func detect(in pixelBuffer: CVPixelBuffer) -> [PersonDetection] {
        framesSinceDetection += 1
        if framesSinceDetection < detectionInterval {
            return lastDetections
        }
        framesSinceDetection = 0

        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return lastDetections
        }

        guard let results = request.results, !results.isEmpty else {
            lastDetections = []
            return lastDetections
        }

        // Collect heights for classification
        let heights = results.map { $0.boundingBox.height }
        for h in heights {
            heightHistory.append(h)
            if heightHistory.count > historySize {
                heightHistory.removeFirst()
            }
        }

        // Update median height
        if heightHistory.count >= 5 {
            let sorted = heightHistory.sorted()
            medianHeight = sorted[sorted.count / 2]
        }

        // Classify each detection
        let adultThreshold = medianHeight * 1.25
        lastDetections = results.map { obs in
            let box = obs.boundingBox
            let isKid = box.height < adultThreshold
            // Convert Vision coords (bottom-left origin) to display coords (top-left origin)
            let displayBox = CGRect(
                x: box.origin.x,
                y: 1.0 - box.origin.y - box.height,
                width: box.width,
                height: box.height
            )
            return PersonDetection(
                boundingBox: box,
                displayBox: displayBox,
                isLikelyPlayer: isKid
            )
        }

        return lastDetections
    }

    /// Center of mass of detected players, proximity-weighted and rolling-averaged.
    /// Players closer to current focus have MORE weight (prevents distant players from yanking camera).
    /// Result is averaged over last ~0.8s of detections to eliminate jitter.
    var playerCenter: CGPoint? {
        let candidates = lastDetections.filter { $0.isLikelyPlayer }
        let people = candidates.isEmpty ? lastDetections : candidates
        guard !people.isEmpty else { return nil }

        // Proximity-weighted centroid: closer to focus = higher weight
        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0

        for person in people {
            let px = person.displayBox.midX
            let py = person.displayBox.midY
            let dx = px - currentFocusHint.x
            let dy = py - currentFocusHint.y
            let distance = sqrt(dx * dx + dy * dy)

            // Weight: 1.0 at focus center, decays with distance
            // Players within 20% of focus get full weight, far players get less
            let weight = max(0.1, 1.0 - distance * 2.0)

            weightedX += px * weight
            weightedY += py * weight
            totalWeight += weight
        }

        let rawCenter = CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)

        // Add to rolling history and return smoothed average
        centroidHistory.append(rawCenter)
        if centroidHistory.count > centroidHistorySize {
            centroidHistory.removeFirst()
        }

        let avgX = centroidHistory.reduce(0.0) { $0 + $1.x } / CGFloat(centroidHistory.count)
        let avgY = centroidHistory.reduce(0.0) { $0 + $1.y } / CGFloat(centroidHistory.count)
        return CGPoint(x: avgX, y: avgY)
    }

    /// Player spread (variance of positions) - higher = players more spread out
    var playerSpread: Float {
        let players = lastDetections.filter { $0.isLikelyPlayer }
        guard players.count >= 2 else { return 0.1 }

        let avgX = players.reduce(0.0) { $0 + $1.displayBox.midX } / CGFloat(players.count)
        let avgY = players.reduce(0.0) { $0 + $1.displayBox.midY } / CGFloat(players.count)

        var variance: CGFloat = 0
        for p in players {
            let dx = p.displayBox.midX - avgX
            let dy = p.displayBox.midY - avgY
            variance += dx * dx + dy * dy
        }
        variance /= CGFloat(players.count)
        return Float(sqrt(variance))
    }

    var playerCount: Int {
        lastDetections.filter { $0.isLikelyPlayer }.count
    }

    var totalCount: Int {
        lastDetections.count
    }
}

// MARK: - Action Spread Calculator

class ActionSpreadCalculator {

    private var recentPositions: [CGPoint] = []
    private let windowSize = 30  // Track last 30 detections

    func update(position: CGPoint?) {
        if let pos = position {
            recentPositions.append(pos)
            if recentPositions.count > windowSize {
                recentPositions.removeFirst()
            }
        }
    }

    var spread: Float {
        guard recentPositions.count >= 5 else { return 0.3 }

        // Calculate variance of positions
        let avgX = recentPositions.reduce(0.0) { $0 + $1.x } / CGFloat(recentPositions.count)
        let avgY = recentPositions.reduce(0.0) { $0 + $1.y } / CGFloat(recentPositions.count)

        var variance: CGFloat = 0
        for pos in recentPositions {
            let dx = pos.x - avgX
            let dy = pos.y - avgY
            variance += dx * dx + dy * dy
        }
        variance /= CGFloat(recentPositions.count)

        return Float(sqrt(variance))
    }

    func reset() {
        recentPositions.removeAll()
    }
}

// MARK: - Frame Analysis

struct FrameAnalysis {
    let frameNumber: Int
    let timestamp: Double
    let ballPosition: CGPoint?
    let ballConfidence: Float
    let ballRadius: CGFloat
    let focusPoint: CGPoint
    let zoom: CGFloat
    let gameState: String
    let actionSpread: Float
    let personBoxes: [SimplePersonDetector.PersonDetection]
    let playerCenter: CGPoint?
    let playerCount: Int
    let totalPersonCount: Int
}

// MARK: - Video Analyzer (Ultra-Smooth)

class VideoAnalyzer {

    private let ballDetector = SimpleBallDetector()
    private let personDetector = SimplePersonDetector()
    private let focusTracker = UltraSmoothFocusTracker()
    private let zoomController = UltraSmoothZoomController()
    private let spreadCalculator = ActionSpreadCalculator()
    private var frameCount = 0

    func analyzeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, dt: Double) -> FrameAnalysis {
        frameCount += 1

        // Detect ball
        let detection = ballDetector.detect(in: pixelBuffer)

        // Feed current focus to person detector for proximity weighting
        personDetector.currentFocusHint = focusTracker.position

        // Detect people (runs every 6th frame internally, caches between)
        let personDetections = personDetector.detect(in: pixelBuffer)
        let playerCenter = personDetector.playerCenter
        let playerSpread = personDetector.playerSpread

        // Update action spread (combine ball movement + player spread)
        spreadCalculator.update(position: detection?.position)
        let ballSpread = spreadCalculator.spread
        let combinedSpread = max(ballSpread, playerSpread)

        // Update focus tracker with both ball and player signals
        let playerConfidence: Float = personDetector.playerCount >= 2 ? 0.7 : (personDetector.totalCount > 0 ? 0.4 : 0.0)

        focusTracker.update(
            detectedPosition: detection?.position,
            confidence: detection?.confidence ?? 0,
            playerCenter: playerCenter,
            playerConfidence: playerConfidence,
            dt: dt
        )

        // Update zoom controller with person awareness
        zoomController.update(
            ballDetected: detection != nil,
            confidence: detection?.confidence ?? 0,
            actionSpread: combinedSpread,
            personCount: personDetector.playerCount,
            focusPosition: focusTracker.position
        )

        // Determine game state
        var gameState = "Scanning"
        if let det = detection {
            if det.confidence > 0.5 {
                gameState = "Tracking \(personDetector.playerCount)P"
            } else if det.confidence > 0.25 {
                gameState = "Detected \(personDetector.playerCount)P"
            }
        } else if personDetector.playerCount > 0 {
            gameState = "Players \(personDetector.playerCount)"
        }

        return FrameAnalysis(
            frameNumber: frameCount,
            timestamp: timestamp,
            ballPosition: detection?.position,
            ballConfidence: detection?.confidence ?? 0,
            ballRadius: detection?.radius ?? 0,
            focusPoint: focusTracker.position,
            zoom: zoomController.zoom,
            gameState: gameState,
            actionSpread: combinedSpread,
            personBoxes: personDetections,
            playerCenter: playerCenter,
            playerCount: personDetector.playerCount,
            totalPersonCount: personDetector.totalCount
        )
    }

    func reset() {
        focusTracker.reset()
        zoomController.reset()
        spreadCalculator.reset()
        frameCount = 0
    }
}

// MARK: - Crop Info (for coordinate transform between input and output frames)

struct CropInfo {
    let cropRect: CGRect    // In CIImage pixel coords (bottom-left origin)
    let inputSize: CGSize   // Full input frame size
    let outputSize: CGSize  // Output (cropped) frame size

    /// Transform a point from input display coords (0-1, top-left origin) to output pixel coords (top-left origin)
    func toOutput(_ point: CGPoint) -> CGPoint {
        // Input display -> CIImage pixel coords
        let ciX = point.x * inputSize.width
        let ciY = (1.0 - point.y) * inputSize.height

        // CIImage pixel -> position within crop
        let localX = ciX - cropRect.origin.x
        let localY = ciY - cropRect.origin.y

        // Scale to output size
        let scaleX = outputSize.width / cropRect.width
        let scaleY = outputSize.height / cropRect.height
        let outCIX = localX * scaleX
        let outCIY = localY * scaleY

        // CIImage -> display (flip Y back to top-left origin)
        return CGPoint(x: outCIX, y: outputSize.height - outCIY)
    }

    /// Transform a rect from input display coords to output pixel coords
    func toOutputRect(_ rect: CGRect) -> CGRect {
        let topLeft = toOutput(CGPoint(x: rect.minX, y: rect.minY))
        let bottomRight = toOutput(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
}

// MARK: - Debug Overlay Drawing

func drawDebugOverlay(
    on pixelBuffer: CVPixelBuffer,
    analysis: FrameAnalysis,
    cropInfo: CropInfo
) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

    func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        guard x >= 0 && x < width && y >= 0 && y < height else { return }
        let offset = y * bytesPerRow + x * 4
        let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        ptr[0] = b
        ptr[1] = g
        ptr[2] = r
        ptr[3] = a
    }

    func drawLine(x1: Int, y1: Int, x2: Int, y2: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 2) {
        let dx = abs(x2 - x1)
        let dy = abs(y2 - y1)
        let sx = x1 < x2 ? 1 : -1
        let sy = y1 < y2 ? 1 : -1
        var err = dx - dy
        var x = x1
        var y = y1

        while true {
            for t in -thickness...thickness {
                setPixel(x: x + t, y: y, r: r, g: g, b: b)
                setPixel(x: x, y: y + t, r: r, g: g, b: b)
            }
            if x == x2 && y == y2 { break }
            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx { err += dx; y += sy }
        }
    }

    func drawCircle(cx: Int, cy: Int, radius: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 2) {
        for angle in stride(from: 0.0, to: Double.pi * 2, by: 0.04) {
            let px = cx + Int(Double(radius) * cos(angle))
            let py = cy + Int(Double(radius) * sin(angle))
            for t in -thickness...thickness {
                setPixel(x: px + t, y: py, r: r, g: g, b: b)
                setPixel(x: px, y: py + t, r: r, g: g, b: b)
            }
        }
    }

    func drawRect(x: Int, y: Int, w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 200) {
        for py in y..<(y + h) {
            for px in x..<(x + w) {
                setPixel(x: px, y: py, r: r, g: g, b: b, a: a)
            }
        }
    }

    func drawRectOutline(x: Int, y: Int, w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 2) {
        // Top and bottom edges
        for px in x..<(x + w) {
            for t in 0..<thickness {
                setPixel(x: px, y: y + t, r: r, g: g, b: b)
                setPixel(x: px, y: y + h - 1 - t, r: r, g: g, b: b)
            }
        }
        // Left and right edges
        for py in y..<(y + h) {
            for t in 0..<thickness {
                setPixel(x: x + t, y: py, r: r, g: g, b: b)
                setPixel(x: x + w - 1 - t, y: py, r: r, g: g, b: b)
            }
        }
    }

    // Person detection boxes (transformed from input to crop space)
    for person in analysis.personBoxes {
        let outRect = cropInfo.toOutputRect(person.displayBox)
        let bx = Int(outRect.origin.x)
        let by = Int(outRect.origin.y)
        let bw = Int(outRect.width)
        let bh = Int(outRect.height)

        // Skip if mostly off-screen
        if bx + bw < 0 || bx > width || by + bh < 0 || by > height { continue }

        if person.isLikelyPlayer {
            // Green = player (kid)
            drawRectOutline(x: bx, y: by, w: bw, h: bh, r: 0, g: 255, b: 100, thickness: 2)
        } else {
            // Red = adult (coach/parent)
            drawRectOutline(x: bx, y: by, w: bw, h: bh, r: 255, g: 80, b: 80, thickness: 1)
        }
    }

    // Player center of mass (magenta diamond) - transformed to crop space
    if let pc = analysis.playerCenter {
        let outPt = cropInfo.toOutput(pc)
        let px = Int(outPt.x)
        let py = Int(outPt.y)
        let size = 15
        drawLine(x1: px, y1: py - size, x2: px + size, y2: py, r: 255, g: 0, b: 255, thickness: 2)
        drawLine(x1: px + size, y1: py, x2: px, y2: py + size, r: 255, g: 0, b: 255, thickness: 2)
        drawLine(x1: px, y1: py + size, x2: px - size, y2: py, r: 255, g: 0, b: 255, thickness: 2)
        drawLine(x1: px - size, y1: py, x2: px, y2: py - size, r: 255, g: 0, b: 255, thickness: 2)
    }

    // Ball detection (orange circle) - transformed to crop space
    if let ballPos = analysis.ballPosition, analysis.ballConfidence > 0.15 {
        let outPt = cropInfo.toOutput(ballPos)
        let bx = Int(outPt.x)
        let by = Int(outPt.y)
        let radius = max(12, Int(analysis.ballRadius * CGFloat(width)))

        drawCircle(cx: bx, cy: by, radius: radius, r: 255, g: 140, b: 0, thickness: 3)
        let confColor: (UInt8, UInt8, UInt8) = analysis.ballConfidence > 0.5 ? (0, 255, 0) : (255, 255, 0)
        drawCircle(cx: bx, cy: by, radius: radius + 5, r: confColor.0, g: confColor.1, b: confColor.2, thickness: 1)
    }

    // Focus crosshair (cyan) - drawn at CENTER of output since focus IS the crop center
    let fx = width / 2
    let fy = height / 2
    drawLine(x1: fx - 50, y1: fy, x2: fx - 20, y2: fy, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx + 20, y1: fy, x2: fx + 50, y2: fy, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx, y1: fy - 50, x2: fx, y2: fy - 20, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx, y1: fy + 20, x2: fx, y2: fy + 50, r: 0, g: 255, b: 255, thickness: 3)

    // Status panel (top-left) - HUD elements stay in output space
    drawRect(x: 10, y: 10, w: 220, h: 95, r: 0, g: 0, b: 0, a: 180)

    // Status indicator
    let statusColor: (r: UInt8, g: UInt8, b: UInt8)
    switch true {
    case analysis.gameState.hasPrefix("Tracking"): statusColor = (0, 255, 0)
    case analysis.gameState.hasPrefix("Detected"): statusColor = (255, 255, 0)
    case analysis.gameState.hasPrefix("Players"):  statusColor = (100, 200, 255)
    default: statusColor = (255, 80, 80)
    }
    drawRect(x: 15, y: 15, w: 20, h: 20, r: statusColor.r, g: statusColor.g, b: statusColor.b)

    // Person count indicator (green dots for players, red for adults)
    let players = analysis.personBoxes.filter { $0.isLikelyPlayer }.count
    let adults = analysis.personBoxes.count - players
    for i in 0..<min(players, 12) {
        drawRect(x: 40 + i * 10, y: 17, w: 7, h: 7, r: 0, g: 255, b: 100)
    }
    for i in 0..<min(adults, 6) {
        drawRect(x: 40 + (players + i) * 10, y: 17, w: 7, h: 7, r: 255, g: 80, b: 80)
    }

    // Action spread indicator (blue bar)
    let spreadWidth = Int(analysis.actionSpread * 300)
    drawRect(x: 15, y: 45, w: max(5, min(180, spreadWidth)), h: 8, r: 100, g: 150, b: 255)

    // Zoom indicator (green bar)
    let zoomWidth = Int((analysis.zoom - 1.0) * 300)
    drawRect(x: 15, y: 58, w: max(5, zoomWidth), h: 8, r: 150, g: 255, b: 150)

    // Player spread indicator (magenta bar)
    let pSpreadWidth = Int(analysis.actionSpread * 500)
    drawRect(x: 15, y: 71, w: max(5, min(180, pSpreadWidth)), h: 8, r: 200, g: 100, b: 255)

    // Frame progress
    let progressWidth = (analysis.frameNumber % 1000) * 200 / 1000
    drawRect(x: 15, y: 88, w: progressWidth, h: 4, r: 255, g: 255, b: 255)
}

// MARK: - Video Processor

class MacVideoProcessor {

    private let analyzer = VideoAnalyzer()
    private var enableDebugOverlay = true

    func processVideo(inputPath: String, outputPath: String, debug: Bool = true, maxDuration: Double = 0, completion: @escaping (Bool, String) -> Void) {
        enableDebugOverlay = debug

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        print("🎬 Processing: \(inputURL.lastPathComponent)")
        print("   Output: \(outputURL.lastPathComponent)")
        print("   Debug overlay: \(debug ? "ON" : "OFF")")

        let asset = AVURLAsset(url: inputURL)

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(false, "No video track found")
            return
        }

        let naturalSize = videoTrack.naturalSize
        let fps = videoTrack.nominalFrameRate
        let duration = CMTimeGetSeconds(asset.duration)
        let totalFrames = Int(duration * Double(fps))

        print("   Size: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
        print("   FPS: \(fps), Duration: \(String(format: "%.1f", duration))s, Frames: \(totalFrames)")

        guard let reader = try? AVAssetReader(asset: asset) else {
            completion(false, "Cannot create reader")
            return
        }

        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(readerOutput) else {
            completion(false, "Cannot add reader output")
            return
        }
        reader.add(readerOutput)

        let transform = videoTrack.preferredTransform
        let outputWidth = abs(naturalSize.width * transform.a + naturalSize.height * transform.c)
        let outputHeight = abs(naturalSize.width * transform.b + naturalSize.height * transform.d)
        let outputSize = CGSize(width: outputWidth, height: outputHeight)

        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            completion(false, "Cannot create writer")
            return
        }

        // Adaptive bitrate based on resolution
        let pixelCount = Int(outputSize.width) * Int(outputSize.height)
        let bitrate = max(4_000_000, min(20_000_000, pixelCount * Int(fps) / 1000))

        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )

        guard writer.canAdd(writerInput) else {
            completion(false, "Cannot add writer input")
            return
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            completion(false, "Cannot start reading: \(reader.error?.localizedDescription ?? "unknown")")
            return
        }

        guard writer.startWriting() else {
            completion(false, "Cannot start writing: \(writer.error?.localizedDescription ?? "unknown")")
            return
        }

        writer.startSession(atSourceTime: .zero)

        var frameNumber = 0
        var ballDetectedFrames = 0
        var personDetectedFrames = 0
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let startTime = Date()
        var lastTimestamp: Double = 0

        // Limit processing duration (default 120s / 2 min)
        let maxSeconds: Double = maxDuration > 0 ? maxDuration : duration
        let maxFrames = Int(maxSeconds * Double(fps))

        print("\n🔄 Processing frames...")
        print("   Mode: ULTRA-SMOOTH v3 (broadcast-quality)")
        print("   - Processing: \(String(format: "%.0f", maxSeconds))s of \(String(format: "%.0f", duration))s (\(maxFrames) frames)")
        print("   - Focus: 0.8%/frame, 6% dead zone, 8-frame streak")
        print("   - Zoom: 0.5%/frame, range 1.2-1.5x")
        print("   - Centroid: proximity-weighted, 8-sample rolling avg")
        print("   - Person detection: every 6 frames (~10fps)")
        print("   - Bitrate: \(bitrate / 1_000_000)Mbps")

        while reader.status == .reading && frameNumber < maxFrames {
            // Use autoreleasepool to prevent memory buildup
            autoreleasepool {
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    return  // Will exit while loop since reader.status changes
                }

                frameNumber += 1

                if frameNumber % 500 == 0 {
                    let progress = Float(frameNumber) / Float(totalFrames) * 100
                    let elapsed = Date().timeIntervalSince(startTime)
                    let currentFps = Double(frameNumber) / elapsed
                    let eta = (Double(totalFrames - frameNumber) / currentFps)
                    let etaMin = Int(eta) / 60
                    let etaSec = Int(eta) % 60
                    print("   \(Int(progress))% (\(frameNumber)/\(totalFrames)) \(String(format: "%.0f", currentFps))fps ETA:\(etaMin)m\(etaSec)s P:\(personDetectedFrames)")
                }

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return
                }

                // Calculate actual dt from timestamps
                let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                let dt: Double
                if lastTimestamp > 0 {
                    dt = max(0.001, min(0.1, timestamp - lastTimestamp))  // Clamp to sane range
                } else {
                    dt = 1.0 / Double(fps)
                }
                lastTimestamp = timestamp

                let analysis = analyzer.analyzeFrame(pixelBuffer, timestamp: timestamp, dt: dt)

                if analysis.ballPosition != nil && analysis.ballConfidence > 0.2 {
                    ballDetectedFrames += 1
                }
                if analysis.totalPersonCount > 0 {
                    personDetectedFrames += 1
                }

                // Use pixel buffer pool from adaptor (prevents memory leak!)
                if let outputBuffer = createOutputFrame(
                    input: pixelBuffer,
                    analysis: analysis,
                    outputSize: outputSize,
                    context: ciContext,
                    pool: adaptor.pixelBufferPool
                ) {
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.001)
                    }

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    if !adaptor.append(outputBuffer, withPresentationTime: presentationTime) {
                        print("   ⚠️ Failed to append frame \(frameNumber): \(writer.error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }

        // Check reader status
        if reader.status == .failed {
            print("   ⚠️ Reader failed at frame \(frameNumber): \(reader.error?.localizedDescription ?? "unknown")")
        } else if reader.status == .cancelled {
            print("   ⚠️ Reader was cancelled at frame \(frameNumber)")
        }

        writerInput.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        group.wait()

        if writer.status == .failed {
            print("   ⚠️ Writer failed: \(writer.error?.localizedDescription ?? "unknown")")
        }

        let processingTime = Date().timeIntervalSince(startTime)
        let ballRate = Float(ballDetectedFrames) / Float(max(1, frameNumber)) * 100
        let personRate = Float(personDetectedFrames) / Float(max(1, frameNumber)) * 100

        print("\n✅ Complete!")
        print("   Frames processed: \(frameNumber)")
        print("   Ball detection rate: \(String(format: "%.1f", ballRate))%")
        print("   Person detection rate: \(String(format: "%.1f", personRate))%")
        print("   Processing time: \(String(format: "%.1f", processingTime))s")
        print("   Speed: \(String(format: "%.1f", Double(frameNumber) / processingTime)) fps")
        print("\n📁 Output: \(outputURL.path)")

        completion(true, "Processed \(frameNumber) frames, ball:\(ballDetectedFrames) persons:\(personDetectedFrames)")
    }

    private func createOutputFrame(
        input: CVPixelBuffer,
        analysis: FrameAnalysis,
        outputSize: CGSize,
        context: CIContext,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {

        let inputWidth = CGFloat(CVPixelBufferGetWidth(input))
        let inputHeight = CGFloat(CVPixelBufferGetHeight(input))

        var ciImage = CIImage(cvPixelBuffer: input)

        // Smart crop/zoom with smooth focus
        let zoom = analysis.zoom
        let focus = analysis.focusPoint

        let cropWidth = inputWidth / zoom
        let cropHeight = inputHeight / zoom

        var cropX = (focus.x * inputWidth) - (cropWidth / 2)
        var cropY = ((1 - focus.y) * inputHeight) - (cropHeight / 2)

        cropX = max(0, min(inputWidth - cropWidth, cropX))
        cropY = max(0, min(inputHeight - cropHeight, cropY))

        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        ciImage = ciImage.cropped(to: cropRect)

        let scaleX = outputSize.width / cropRect.width
        let scaleY = outputSize.height / cropRect.height
        ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -cropRect.origin.x * scaleX, y: -cropRect.origin.y * scaleY))

        // Use pixel buffer pool (recycled buffers) instead of allocating new ones
        var outputBuffer: CVPixelBuffer?
        if let pool = pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
            if status != kCVReturnSuccess {
                // Fallback to manual allocation
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    Int(outputSize.width),
                    Int(outputSize.height),
                    kCVPixelFormatType_32BGRA,
                    nil,
                    &outputBuffer
                )
            }
        } else {
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(outputSize.width),
                Int(outputSize.height),
                kCVPixelFormatType_32BGRA,
                nil,
                &outputBuffer
            )
        }

        guard let output = outputBuffer else { return nil }

        context.render(ciImage, to: output)

        if enableDebugOverlay {
            let cropInfo = CropInfo(
                cropRect: cropRect,
                inputSize: CGSize(width: inputWidth, height: inputHeight),
                outputSize: outputSize
            )
            drawDebugOverlay(on: output, analysis: analysis, cropInfo: cropInfo)
        }

        return output
    }
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 {
    print("🧠 Skynet Vision Pipeline v2 (ULTRA-SMOOTH + PLAYER TRACKING)")
    print("===============================================================")
    print("\nBroadcast-quality camera motion with person detection:")
    print("  • Focus combines ball (60%) + player center (40%)")
    print("  • Vision-based human detection every 6 frames")
    print("  • Kid/adult classification (green=player, red=adult)")
    print("  • Zoom adapts to player spread")
    print("  • Dead zone ignores movements < 3.5%")
    print("  • Requires 4 consecutive high-confidence frames")
    print("  • Strong momentum/damping for smooth motion")
    print("\nUsage: swift SkynetVideoTest.swift \"/path/to/video.mp4\" [seconds] [--no-debug] [--full]")
    print("  Default: processes first 120 seconds. Use --full for entire video.")
    print("\nAvailable videos:")

    let gamesPath = NSString(string: "~/Downloads/Sahil games").expandingTildeInPath
    if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesPath) {
        for file in files.sorted() where !file.hasPrefix(".") {
            print("  \(gamesPath)/\(file)")
        }
    }
    exit(1)
}

let inputPath = args[1]
let enableDebug = !args.contains("--no-debug")

// Parse optional duration limit (seconds). Default: 120s (2 min)
// Usage: swift SkynetVideoTest.swift video.mp4 [seconds] [--no-debug] [--full]
var maxDuration: Double = 120  // Default 2 minutes
let processFullVideo = args.contains("--full")
if processFullVideo {
    maxDuration = 0  // 0 = no limit
} else if args.count >= 3, let secs = Double(args[2]) {
    maxDuration = secs
}

let inputURL = URL(fileURLWithPath: inputPath)
let suffix = enableDebug ? "_ultrasmooth" : "_ultrasmooth_clean"
let outputName = inputURL.deletingPathExtension().lastPathComponent + suffix + ".mp4"
let outputPath = inputURL.deletingLastPathComponent().appendingPathComponent(outputName).path

print("🧠 Skynet Vision Pipeline v2 (ULTRA-SMOOTH + PLAYER TRACKING)")
print("===============================================================\n")

let processor = MacVideoProcessor()
let semaphore = DispatchSemaphore(value: 0)

processor.processVideo(inputPath: inputPath, outputPath: outputPath, debug: enableDebug, maxDuration: maxDuration) { success, message in
    if !success {
        print("❌ Error: \(message)")
    }
    semaphore.signal()
}

semaphore.wait()
