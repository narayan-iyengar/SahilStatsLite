//
//  BallDetector.swift
//  SahilStatsLite
//
//  PURPOSE: Basketball detection using HSV color segmentation and Kalman tracking.
//           Zero training required. Detects orange/brown ball, filters hoop false
//           positives, validates trajectory with physics, adapts to gym lighting.
//  KEY TYPES: BallDetector, BallDetection, TrajectoryPoint
//  DEPENDS ON: CoreImage, Vision
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import CoreImage
import CoreGraphics
import Accelerate
import UIKit

// MARK: - Ball Detection Result

struct BallDetection {
    let position: CGPoint       // Normalized 0-1
    let radius: CGFloat         // Normalized radius
    let confidence: Float       // 0-1 detection confidence
    let velocity: CGPoint       // Normalized velocity (from Kalman)
    let predictedPosition: CGPoint  // Where ball will be in ~0.3s
    let isTracked: Bool         // True if Kalman is tracking, false if new detection
}

// MARK: - Trajectory Point (for motion history)

struct TrajectoryPoint {
    let position: CGPoint
    let timestamp: Double
    let radius: CGFloat
    let confidence: Float
}

// MARK: - Ball Detector

class BallDetector {

    // MARK: - Kalman Filter for Ball

    private var kalman: BallKalmanFilter?
    private var consecutiveMisses: Int = 0
    private let maxMissesBeforeReset = 15  // ~0.5s at 30fps

    // MARK: - Trajectory History (for motion-based validation)

    private var trajectoryHistory: [TrajectoryPoint] = []
    private let maxTrajectoryHistory = 20  // ~0.7s at 30fps
    private var lastProcessedTime: Double = 0

    // MARK: - Color Thresholds (HSV)

    // Basketball orange/brown - will be adapted online
    private var hueMin: CGFloat = 5
    private var hueMax: CGFloat = 25
    private var satMin: CGFloat = 0.4
    private var satMax: CGFloat = 1.0
    private var valMin: CGFloat = 0.3
    private var valMax: CGFloat = 1.0

    // Online color learning
    private var colorSamples: [(h: CGFloat, s: CGFloat, v: CGFloat)] = []
    private let maxColorSamples = 50
    private var isCalibrated: Bool = false

    // MARK: - Size Constraints

    // Ball should be roughly 1-8% of frame width depending on distance/zoom
    private let minBallRadiusRatio: CGFloat = 0.005
    private let maxBallRadiusRatio: CGFloat = 0.08

    // MARK: - Hoop Filtering (avoid false positives from basketball hoop rim)

    // Reject detections in upper portion of frame where hoops are located
    private let hoopZoneMaxY: CGFloat = 0.25  // Upper 25% is hoop zone

    // Track recent positions for motion-based filtering
    private var recentDetectionPositions: [CGPoint] = []
    private let motionHistorySize = 10

    // MARK: - Physics Constants (normalized to frame coordinates)

    // Gravity acceleration in normalized units (based on typical game footage)
    private let gravity: CGFloat = 0.5  // ~0.5 frame heights per second^2
    private let maxReasonableSpeed: CGFloat = 2.0  // Max 2x frame width per second

    // MARK: - Detection

    /// Detect the basketball in a frame
    /// - Parameters:
    ///   - pixelBuffer: The video frame
    ///   - dt: Time since last frame (for Kalman prediction)
    /// - Returns: Ball detection if found, nil otherwise
    func detectBall(in pixelBuffer: CVPixelBuffer, dt: Double = 1.0/30.0) -> BallDetection? {
        let currentTime = lastProcessedTime + dt
        lastProcessedTime = currentTime

        // Get candidate ball regions using color segmentation
        var candidates = findBallCandidates(in: pixelBuffer)

        // Apply trajectory-based filtering to reject unlikely candidates
        candidates = filterCandidatesByTrajectory(candidates, currentTime: currentTime)

        // If we have a Kalman prediction, use it to select best candidate
        if let kalman = kalman {
            kalman.predict(dt: dt)
            let predicted = kalman.position

            // Find candidate closest to prediction
            var bestCandidate: (center: CGPoint, radius: CGFloat, confidence: Float)?
            var bestDistance: CGFloat = .infinity

            for candidate in candidates {
                let distance = hypot(candidate.center.x - predicted.x,
                                    candidate.center.y - predicted.y)
                // Weight by both distance to prediction AND confidence
                let score = distance / CGFloat(candidate.confidence + 0.1)
                if score < bestDistance {
                    bestDistance = score
                    bestCandidate = candidate
                }
            }

            // If best candidate is close enough to prediction, update Kalman
            if let best = bestCandidate, bestDistance < 0.15 {
                kalman.update(measurement: best.center)
                consecutiveMisses = 0

                // Add to trajectory history for future validation
                addToTrajectoryHistory(position: best.center, radius: best.radius, confidence: best.confidence, timestamp: currentTime)

                // Learn color from confirmed detection
                learnColorFromRegion(pixelBuffer, center: best.center, radius: best.radius)

                let velocity = kalman.velocity
                let predictedPos = CGPoint(
                    x: kalman.position.x + velocity.x * 0.3,
                    y: kalman.position.y + velocity.y * 0.3
                )

                return BallDetection(
                    position: kalman.position,
                    radius: best.radius,
                    confidence: best.confidence,
                    velocity: velocity,
                    predictedPosition: predictedPos,
                    isTracked: true
                )
            } else {
                // No good match - use prediction only
                consecutiveMisses += 1

                if consecutiveMisses > maxMissesBeforeReset {
                    // Lost the ball - reset Kalman
                    self.kalman = nil
                    consecutiveMisses = 0
                } else {
                    // Return predicted position with lower confidence
                    let velocity = kalman.velocity
                    let predictedPos = CGPoint(
                        x: kalman.position.x + velocity.x * 0.3,
                        y: kalman.position.y + velocity.y * 0.3
                    )

                    return BallDetection(
                        position: kalman.position,
                        radius: 0.02,
                        confidence: max(0.1, 0.8 - Float(consecutiveMisses) * 0.1),
                        velocity: velocity,
                        predictedPosition: predictedPos,
                        isTracked: true
                    )
                }
            }
        }

        // No Kalman tracker - find best candidate to initialize
        if let best = candidates.max(by: { $0.confidence < $1.confidence }) {
            // Initialize Kalman filter with this detection
            kalman = BallKalmanFilter(initialPosition: best.center)
            consecutiveMisses = 0

            return BallDetection(
                position: best.center,
                radius: best.radius,
                confidence: best.confidence,
                velocity: .zero,
                predictedPosition: best.center,
                isTracked: false
            )
        }

        return nil
    }

    // MARK: - Trajectory Validation

    /// Add confirmed detection to trajectory history
    private func addToTrajectoryHistory(position: CGPoint, radius: CGFloat, confidence: Float, timestamp: Double) {
        let point = TrajectoryPoint(position: position, timestamp: timestamp, radius: radius, confidence: confidence)
        trajectoryHistory.append(point)

        // Trim old history
        if trajectoryHistory.count > maxTrajectoryHistory {
            trajectoryHistory.removeFirst()
        }
    }

    /// Filter candidates based on trajectory consistency
    /// Uses motion history to reject impossible ball positions
    private func filterCandidatesByTrajectory(_ candidates: [(center: CGPoint, radius: CGFloat, confidence: Float)], currentTime: Double) -> [(center: CGPoint, radius: CGFloat, confidence: Float)] {
        guard trajectoryHistory.count >= 3 else {
            // Not enough history - accept all candidates
            return candidates
        }

        // Get recent trajectory for motion analysis
        let recentHistory = trajectoryHistory.suffix(5)
        guard let lastPoint = recentHistory.last else { return candidates }

        // Calculate average velocity from recent history
        var avgVelocity = CGPoint.zero
        var count = 0
        for i in 1..<recentHistory.count {
            let historyArray = Array(recentHistory)
            let p1 = historyArray[i - 1]
            let p2 = historyArray[i]
            let dt = p2.timestamp - p1.timestamp
            if dt > 0.001 {  // Avoid division by zero
                avgVelocity.x += (p2.position.x - p1.position.x) / CGFloat(dt)
                avgVelocity.y += (p2.position.y - p1.position.y) / CGFloat(dt)
                count += 1
            }
        }
        if count > 0 {
            avgVelocity.x /= CGFloat(count)
            avgVelocity.y /= CGFloat(count)
        }

        // Filter candidates
        return candidates.filter { candidate in
            let dt = CGFloat(currentTime - lastPoint.timestamp)
            if dt < 0.001 { return true }  // Accept if no time elapsed

            // Predict position using constant velocity + gravity
            let predictedX = lastPoint.position.x + avgVelocity.x * dt
            let predictedY = lastPoint.position.y + avgVelocity.y * dt + 0.5 * gravity * dt * dt

            // Check if candidate is within reasonable distance of prediction
            let dx = candidate.center.x - predictedX
            let dy = candidate.center.y - predictedY
            let distance = sqrt(dx * dx + dy * dy)

            // Allow larger deviation for fast-moving balls
            let speed = sqrt(avgVelocity.x * avgVelocity.x + avgVelocity.y * avgVelocity.y)
            let allowedDeviation = max(0.1, min(0.3, speed * 0.1 + 0.05))

            return distance < allowedDeviation
        }
    }

    /// Check if a position is physically plausible given trajectory history
    func isPhysicallyPlausible(_ position: CGPoint, currentTime: Double) -> Bool {
        guard let lastPoint = trajectoryHistory.last else { return true }

        let dt = CGFloat(currentTime - lastPoint.timestamp)
        if dt < 0.001 { return true }

        // Calculate required velocity to reach this position
        let velocity = CGPoint(
            x: (position.x - lastPoint.position.x) / dt,
            y: (position.y - lastPoint.position.y) / dt
        )

        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)

        // Reject if speed is impossibly high
        return speed <= maxReasonableSpeed
    }

    // MARK: - Color Segmentation

    private func findBallCandidates(in pixelBuffer: CVPixelBuffer) -> [(center: CGPoint, radius: CGFloat, confidence: Float)] {
        var candidates: [(center: CGPoint, radius: CGFloat, confidence: Float)] = []

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        // We'll use a grid-based approach to find orange clusters
        // This is faster than per-pixel analysis
        let gridSize = 20  // 20x20 grid
        let cellWidth = width / gridSize
        let cellHeight = height / gridSize

        var orangeGrid = [[Int]](repeating: [Int](repeating: 0, count: gridSize), count: gridSize)

        // Sample pixels in each grid cell
        let samplesPerCell = 16

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                var orangeCount = 0

                for _ in 0..<samplesPerCell {
                    let px = gx * cellWidth + Int.random(in: 0..<cellWidth)
                    let py = gy * cellHeight + Int.random(in: 0..<cellHeight)

                    if isOrangePixel(baseAddress: baseAddress, x: px, y: py,
                                     bytesPerRow: bytesPerRow, pixelFormat: pixelFormat) {
                        orangeCount += 1
                    }
                }

                orangeGrid[gy][gx] = orangeCount
            }
        }

        // Find clusters of orange cells (potential balls)
        var visited = [[Bool]](repeating: [Bool](repeating: false, count: gridSize), count: gridSize)

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                if orangeGrid[gy][gx] > samplesPerCell / 3 && !visited[gy][gx] {
                    // Found an orange cell - flood fill to find cluster
                    var clusterCells: [(x: Int, y: Int)] = []
                    var queue: [(x: Int, y: Int)] = [(gx, gy)]

                    while !queue.isEmpty {
                        let (cx, cy) = queue.removeFirst()
                        if cx < 0 || cx >= gridSize || cy < 0 || cy >= gridSize { continue }
                        if visited[cy][cx] { continue }
                        if orangeGrid[cy][cx] < samplesPerCell / 4 { continue }

                        visited[cy][cx] = true
                        clusterCells.append((cx, cy))

                        queue.append((cx + 1, cy))
                        queue.append((cx - 1, cy))
                        queue.append((cx, cy + 1))
                        queue.append((cx, cy - 1))
                    }

                    // Analyze cluster
                    if clusterCells.count >= 1 && clusterCells.count <= 25 {
                        // Calculate centroid
                        let sumX = clusterCells.reduce(0) { $0 + $1.x }
                        let sumY = clusterCells.reduce(0) { $0 + $1.y }
                        let centerX = CGFloat(sumX) / CGFloat(clusterCells.count) / CGFloat(gridSize)
                        let centerY = CGFloat(sumY) / CGFloat(clusterCells.count) / CGFloat(gridSize)

                        // HOOP FILTER: Skip detections in upper portion of frame
                        // This avoids false positives from the orange basketball hoop rim
                        if centerY < hoopZoneMaxY {
                            continue  // Skip - likely the hoop
                        }

                        // EDGE FILTER: Skip detections at extreme horizontal edges
                        if centerX < 0.05 || centerX > 0.95 {
                            continue  // Skip - likely sideline/out of bounds
                        }

                        // Estimate radius from cluster size
                        let minX = clusterCells.min(by: { $0.x < $1.x })!.x
                        let maxX = clusterCells.max(by: { $0.x < $1.x })!.x
                        let minY = clusterCells.min(by: { $0.y < $1.y })!.y
                        let maxY = clusterCells.max(by: { $0.y < $1.y })!.y

                        let clusterWidth = CGFloat(maxX - minX + 1) / CGFloat(gridSize)
                        let clusterHeight = CGFloat(maxY - minY + 1) / CGFloat(gridSize)
                        let radius = (clusterWidth + clusterHeight) / 4.0

                        // Check size constraints
                        if radius >= minBallRadiusRatio && radius <= maxBallRadiusRatio {
                            // Calculate circularity (balls are round)
                            let aspectRatio = clusterWidth / max(clusterHeight, 0.001)

                            // TIGHTER circularity check (0.5 to 2.0)
                            guard aspectRatio > 0.5 && aspectRatio < 2.0 else { continue }

                            let circularity = 1.0 - abs(aspectRatio - 1.0) * 0.5

                            // Confidence based on orange density and circularity
                            let totalOrange = clusterCells.reduce(0) { $0 + orangeGrid[$1.y][$1.x] }
                            let density = Float(totalOrange) / Float(clusterCells.count * samplesPerCell)

                            // SIZE PENALTY: Large clusters are more likely hoop, not ball
                            let sizePenalty: Float = clusterCells.count > 15 ? Float(clusterCells.count - 15) * 0.02 : 0

                            let confidence = density * Float(circularity) - sizePenalty

                            if confidence > 0.2 {
                                candidates.append((
                                    center: CGPoint(x: centerX, y: centerY),
                                    radius: radius,
                                    confidence: confidence
                                ))
                            }
                        }
                    }
                }
            }
        }

        return candidates
    }

    private func isOrangePixel(baseAddress: UnsafeMutableRawPointer, x: Int, y: Int,
                               bytesPerRow: Int, pixelFormat: OSType) -> Bool {
        // Handle different pixel formats
        let offset: Int
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0

        if pixelFormat == kCVPixelFormatType_32BGRA {
            offset = y * bytesPerRow + x * 4
            let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            b = CGFloat(ptr[0]) / 255.0
            g = CGFloat(ptr[1]) / 255.0
            r = CGFloat(ptr[2]) / 255.0
        } else if pixelFormat == kCVPixelFormatType_32ARGB {
            offset = y * bytesPerRow + x * 4
            let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            r = CGFloat(ptr[1]) / 255.0
            g = CGFloat(ptr[2]) / 255.0
            b = CGFloat(ptr[3]) / 255.0
        } else {
            // Assume BGRA
            offset = y * bytesPerRow + x * 4
            let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            b = CGFloat(ptr[0]) / 255.0
            g = CGFloat(ptr[1]) / 255.0
            r = CGFloat(ptr[2]) / 255.0
        }

        // Convert RGB to HSV
        let (h, s, v) = rgbToHSV(r: r, g: g, b: b)

        // Check if pixel is in basketball orange range
        return h >= hueMin && h <= hueMax &&
               s >= satMin && s <= satMax &&
               v >= valMin && v <= valMax
    }

    private func rgbToHSV(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var h: CGFloat = 0
        let s: CGFloat = maxC == 0 ? 0 : delta / maxC
        let v: CGFloat = maxC

        if delta > 0 {
            if maxC == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }

        if h < 0 { h += 360 }

        // Normalize hue to 0-60 scale (we're looking for orange ~10-30)
        // Actually let's use 0-360 and adjust our thresholds
        return (h, s, v)
    }

    // MARK: - Online Color Learning

    private func learnColorFromRegion(_ pixelBuffer: CVPixelBuffer, center: CGPoint, radius: CGFloat) {
        guard !isCalibrated || colorSamples.count < maxColorSamples else { return }

        // Sample the center region of the detected ball
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        let centerX = Int(center.x * CGFloat(width))
        let centerY = Int(center.y * CGFloat(height))
        let sampleRadius = Int(radius * CGFloat(width) * 0.3)  // Sample inner 30%

        var hSum: CGFloat = 0
        var sSum: CGFloat = 0
        var vSum: CGFloat = 0
        var count = 0

        for dy in -sampleRadius...sampleRadius {
            for dx in -sampleRadius...sampleRadius {
                let px = centerX + dx
                let py = centerY + dy

                if px >= 0 && px < width && py >= 0 && py < height {
                    let offset = py * bytesPerRow + px * 4
                    let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

                    let r: CGFloat, g: CGFloat, b: CGFloat
                    if pixelFormat == kCVPixelFormatType_32BGRA {
                        b = CGFloat(ptr[0]) / 255.0
                        g = CGFloat(ptr[1]) / 255.0
                        r = CGFloat(ptr[2]) / 255.0
                    } else {
                        r = CGFloat(ptr[1]) / 255.0
                        g = CGFloat(ptr[2]) / 255.0
                        b = CGFloat(ptr[3]) / 255.0
                    }

                    let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                    hSum += h
                    sSum += s
                    vSum += v
                    count += 1
                }
            }
        }

        if count > 0 {
            let avgH = hSum / CGFloat(count)
            let avgS = sSum / CGFloat(count)
            let avgV = vSum / CGFloat(count)

            colorSamples.append((avgH, avgS, avgV))

            // Once we have enough samples, update thresholds
            if colorSamples.count >= 20 {
                updateColorThresholds()
            }
        }
    }

    private func updateColorThresholds() {
        guard colorSamples.count >= 10 else { return }

        let hues = colorSamples.map { $0.h }.sorted()
        let sats = colorSamples.map { $0.s }.sorted()
        let vals = colorSamples.map { $0.v }.sorted()

        // Use 10th-90th percentile to set thresholds
        let p10 = Int(Double(colorSamples.count) * 0.1)
        let p90 = Int(Double(colorSamples.count) * 0.9)

        hueMin = max(0, hues[p10] - 10)
        hueMax = min(60, hues[p90] + 10)  // Orange is roughly 0-60 in HSV
        satMin = max(0.2, sats[p10] - 0.1)
        satMax = min(1.0, sats[p90] + 0.1)
        valMin = max(0.2, vals[p10] - 0.1)
        valMax = 1.0

        isCalibrated = true
        debugPrint("🏀 [BallDetector] Calibrated - H: \(hueMin)-\(hueMax), S: \(satMin)-\(satMax), V: \(valMin)-\(valMax)")
    }

    // MARK: - Reset

    func reset() {
        kalman = nil
        consecutiveMisses = 0
        colorSamples = []
        isCalibrated = false
        trajectoryHistory = []
        lastProcessedTime = 0

        // Reset to default orange thresholds
        hueMin = 5
        hueMax = 25
        satMin = 0.4
        satMax = 1.0
        valMin = 0.3
        valMax = 1.0
    }
}

// MARK: - Ball Kalman Filter (Basketball-tuned)

/// Specialized Kalman filter for basketball tracking
/// State: [x, y, vx, vy] - position and velocity
/// Tuned for basketball physics:
/// - High velocity uncertainty (rapid acceleration from shots, passes, bounces)
/// - Gravity affects vertical motion
/// - Horizontal motion is mostly constant (minimal air resistance)
class BallKalmanFilter {

    private var state: [Double]  // [x, y, vx, vy]
    private var P: [[Double]]    // Covariance matrix

    // Process noise (tuned for basketball dynamics)
    // Higher values = more responsive to sudden changes (good for shots, passes)
    // Lower values = smoother tracking (good for rolling ball)
    private var Q: [[Double]]

    // Measurement noise (detection uncertainty from color segmentation)
    // HSV detection has ~1-2% position error in normalized coords
    private let R: [[Double]] = [
        [0.003, 0],     // ~0.3% position noise
        [0, 0.003]
    ]

    // Gravity constant (normalized, positive = down in screen coords)
    private let gravity: Double = 0.5  // ~0.5 screen heights per second^2

    // Track if ball is likely in free flight (for gravity compensation)
    private var isInFlight: Bool = false
    private var flightStartTime: Double = 0

    init(initialPosition: CGPoint) {
        state = [Double(initialPosition.x), Double(initialPosition.y), 0, 0]

        // Initial covariance - moderate position uncertainty, high velocity uncertainty
        P = [
            [0.01, 0, 0, 0],
            [0, 0.01, 0, 0],
            [0, 0, 0.5, 0],    // High initial velocity uncertainty
            [0, 0, 0, 0.5]
        ]

        // Process noise tuned for basketball:
        // - Position noise relatively low (ball follows physics)
        // - Velocity noise high for horizontal (passes, shots)
        // - Velocity noise very high for vertical (gravity, bounces)
        Q = [
            [0.0005, 0, 0, 0],     // Position x
            [0, 0.0005, 0, 0],     // Position y
            [0, 0, 0.08, 0],       // Velocity x (handles passes)
            [0, 0, 0, 0.15]        // Velocity y (handles shots, bounces)
        ]
    }

    var position: CGPoint {
        CGPoint(x: state[0], y: state[1])
    }

    var velocity: CGPoint {
        CGPoint(x: state[2], y: state[3])
    }

    /// Predict next state with optional gravity compensation
    func predict(dt: Double) {
        // Horizontal motion: constant velocity (air resistance negligible)
        state[0] += state[2] * dt

        // Vertical motion: check if ball is in flight (moving upward or fast downward)
        let verticalSpeed = abs(state[3])
        let movingUp = state[3] < -0.1  // Negative = up in screen coords

        // Detect flight (shot or pass in air)
        if movingUp || verticalSpeed > 0.5 {
            isInFlight = true
        }

        // Apply gravity during flight
        if isInFlight {
            // y' = y + vy*dt + 0.5*g*dt^2
            state[1] += state[3] * dt + 0.5 * gravity * dt * dt
            // vy' = vy + g*dt
            state[3] += gravity * dt
        } else {
            // Ball on ground or in hands - simple velocity model
            state[1] += state[3] * dt
        }

        // End flight if ball is slow and near middle of screen (in player's hands)
        if state[3] > 0 && state[3] < 0.3 && state[1] > 0.3 && state[1] < 0.8 {
            isInFlight = false
        }

        // Update covariance: P = F*P*F' + Q
        P[0][0] += Q[0][0] + dt * dt * P[2][2]
        P[1][1] += Q[1][1] + dt * dt * P[3][3]
        P[2][2] += Q[2][2]
        P[3][3] += Q[3][3]

        // Clamp covariance to prevent numerical explosion
        P[0][0] = min(P[0][0], 1.0)
        P[1][1] = min(P[1][1], 1.0)
        P[2][2] = min(P[2][2], 5.0)
        P[3][3] = min(P[3][3], 5.0)
    }

    func update(measurement: CGPoint) {
        let z = [Double(measurement.x), Double(measurement.y)]

        // Innovation (measurement residual)
        let y0 = z[0] - state[0]
        let y1 = z[1] - state[1]

        // Large innovation in vertical direction might indicate bounce
        if abs(y1) > 0.1 && state[3] > 0.3 {
            // Possible bounce - increase vertical velocity uncertainty
            P[3][3] = min(P[3][3] * 2, 5.0)
            isInFlight = true  // Bounce = start of new flight
        }

        // Innovation covariance: S = H*P*H' + R
        let S0 = P[0][0] + R[0][0]
        let S1 = P[1][1] + R[1][1]

        // Kalman gain: K = P*H' * S^-1
        let K0 = P[0][0] / S0
        let K1 = P[1][1] / S1
        let K2 = P[2][0] / S0 * 0.8  // Slightly damped velocity update
        let K3 = P[3][1] / S1 * 0.8

        // Update state
        state[0] += K0 * y0
        state[1] += K1 * y1
        state[2] += K2 * y0 * 30.0  // Convert position error to velocity estimate
        state[3] += K3 * y1 * 30.0

        // Update covariance: P = (I - K*H) * P
        P[0][0] *= (1 - K0)
        P[1][1] *= (1 - K1)
        // Also reduce velocity uncertainty on successful measurement
        P[2][2] *= 0.9
        P[3][3] *= 0.9
    }

    /// Reset flight state (call when ball is caught or dribbled)
    func resetFlightState() {
        isInFlight = false
    }
}
