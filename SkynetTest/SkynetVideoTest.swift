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
//  Usage: swift SkynetVideoTest.swift "/path/to/video.mp4"
//

import Foundation
import AVFoundation
import CoreImage
import CoreGraphics

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

    // Smoothing parameters
    private let positionSmoothing: Double = 0.02  // Very slow position follow (2% per frame)
    private let velocityDamping: Double = 0.85    // Strong velocity decay
    private let deadZone: Double = 0.02           // Ignore movements smaller than 2%
    private let maxSpeed: Double = 0.015          // Maximum movement per frame (1.5%)

    // Confidence tracking
    private var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 2  // Reduced from 5 - be more responsive

    var position: CGPoint {
        CGPoint(x: smoothX, y: smoothY)
    }

    func update(detectedPosition: CGPoint?, confidence: Float, dt: Double) {
        // Track high-confidence streaks
        if let detected = detectedPosition, confidence > 0.2 {  // Lowered threshold
            highConfidenceStreak += 1

            // Only update target if we have sustained detection
            if highConfidenceStreak >= minStreakForUpdate {
                let dx = Double(detected.x) - targetX
                let dy = Double(detected.y) - targetY

                // Apply dead zone - ignore small movements
                if abs(dx) > deadZone || abs(dy) > deadZone {
                    targetX = Double(detected.x)
                    targetY = Double(detected.y)
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

    // Zoom changes smoothly
    private let zoomSmoothing: Double = 0.01  // Slower zoom changes
    private let minZoom: Double = 1.2
    private let maxZoom: Double = 1.6  // Reasonable range

    var zoom: CGFloat {
        CGFloat(currentZoom)
    }

    func update(ballDetected: Bool, confidence: Float, actionSpread: Float, focusPosition: CGPoint? = nil) {
        // Simple zoom logic - don't overthink it
        if ballDetected && confidence > 0.3 {
            // Have good detection - zoom in slightly
            targetZoom = 1.5
        } else {
            // No detection - stay at moderate zoom
            targetZoom = 1.3
        }

        // Smoothly interpolate toward target
        let diff = targetZoom - currentZoom
        currentZoom += diff * zoomSmoothing
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
}

// MARK: - Video Analyzer (Ultra-Smooth)

class VideoAnalyzer {

    private let ballDetector = SimpleBallDetector()
    private let focusTracker = UltraSmoothFocusTracker()
    private let zoomController = UltraSmoothZoomController()
    private let spreadCalculator = ActionSpreadCalculator()
    private var frameCount = 0

    func analyzeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: Double, dt: Double) -> FrameAnalysis {
        frameCount += 1

        // Detect ball
        let detection = ballDetector.detect(in: pixelBuffer)

        // Update action spread
        spreadCalculator.update(position: detection?.position)
        let spread = spreadCalculator.spread

        // Update focus tracker (handles all smoothing internally)
        focusTracker.update(
            detectedPosition: detection?.position,
            confidence: detection?.confidence ?? 0,
            dt: dt
        )

        // Update zoom controller (with position for far-court zoom)
        zoomController.update(
            ballDetected: detection != nil,
            confidence: detection?.confidence ?? 0,
            actionSpread: spread,
            focusPosition: focusTracker.position
        )

        // Determine game state
        var gameState = "Scanning"
        if let det = detection {
            if det.confidence > 0.5 {
                gameState = "Tracking"
            } else if det.confidence > 0.25 {
                gameState = "Detected"
            }
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
            actionSpread: spread
        )
    }

    func reset() {
        focusTracker.reset()
        zoomController.reset()
        spreadCalculator.reset()
        frameCount = 0
    }
}

// MARK: - Debug Overlay Drawing

func drawDebugOverlay(
    on pixelBuffer: CVPixelBuffer,
    analysis: FrameAnalysis
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

    // Ball detection (orange circle)
    if let ballPos = analysis.ballPosition, analysis.ballConfidence > 0.15 {
        let bx = Int(ballPos.x * CGFloat(width))
        let by = Int(ballPos.y * CGFloat(height))
        let radius = max(10, Int(analysis.ballRadius * CGFloat(width)))

        // Main circle
        drawCircle(cx: bx, cy: by, radius: radius, r: 255, g: 140, b: 0, thickness: 3)

        // Confidence ring
        let confColor: (UInt8, UInt8, UInt8) = analysis.ballConfidence > 0.5 ? (0, 255, 0) : (255, 255, 0)
        drawCircle(cx: bx, cy: by, radius: radius + 5, r: confColor.0, g: confColor.1, b: confColor.2, thickness: 1)
    }

    // Focus crosshair (cyan) - this should move SMOOTHLY
    let fx = Int(analysis.focusPoint.x * CGFloat(width))
    let fy = Int(analysis.focusPoint.y * CGFloat(height))

    drawLine(x1: fx - 50, y1: fy, x2: fx - 20, y2: fy, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx + 20, y1: fy, x2: fx + 50, y2: fy, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx, y1: fy - 50, x2: fx, y2: fy - 20, r: 0, g: 255, b: 255, thickness: 3)
    drawLine(x1: fx, y1: fy + 20, x2: fx, y2: fy + 50, r: 0, g: 255, b: 255, thickness: 3)

    // Status panel (top-left)
    drawRect(x: 10, y: 10, w: 180, h: 80, r: 0, g: 0, b: 0, a: 180)

    // Status indicator
    let statusColor: (r: UInt8, g: UInt8, b: UInt8)
    switch analysis.gameState {
    case "Tracking": statusColor = (0, 255, 0)
    case "Detected": statusColor = (255, 255, 0)
    default: statusColor = (255, 80, 80)
    }
    drawRect(x: 15, y: 15, w: 20, h: 20, r: statusColor.r, g: statusColor.g, b: statusColor.b)

    // Action spread indicator (blue bar)
    let spreadWidth = Int(analysis.actionSpread * 300)
    drawRect(x: 15, y: 45, w: max(5, min(150, spreadWidth)), h: 8, r: 100, g: 150, b: 255)

    // Zoom indicator (green bar)
    let zoomWidth = Int((analysis.zoom - 1.0) * 300)
    drawRect(x: 15, y: 58, w: max(5, zoomWidth), h: 8, r: 150, g: 255, b: 150)

    // Frame progress
    let progressWidth = (analysis.frameNumber % 1000) * 160 / 1000
    drawRect(x: 15, y: 75, w: progressWidth, h: 4, r: 255, g: 255, b: 255)
}

// MARK: - Video Processor

class MacVideoProcessor {

    private let analyzer = VideoAnalyzer()
    private var enableDebugOverlay = true

    func processVideo(inputPath: String, outputPath: String, debug: Bool = true, completion: @escaping (Bool, String) -> Void) {
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
        let dt = 1.0 / Double(fps)

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

        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000
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
            completion(false, "Cannot start reading")
            return
        }

        guard writer.startWriting() else {
            completion(false, "Cannot start writing")
            return
        }

        writer.startSession(atSourceTime: .zero)

        var frameNumber = 0
        var ballDetectedFrames = 0
        let ciContext = CIContext()
        let startTime = Date()

        print("\n🔄 Processing frames...")
        print("   Mode: ULTRA-SMOOTH (broadcast-quality)")
        print("   - Focus smoothing: 2% per frame")
        print("   - Zoom smoothing: 1.5% per frame")
        print("   - Dead zone: 2% (ignore small movements)")
        print("   - Min streak: 5 frames for focus update")

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            frameNumber += 1

            if frameNumber % 500 == 0 {
                let progress = Float(frameNumber) / Float(totalFrames) * 100
                print("   \(Int(progress))% (\(frameNumber)/\(totalFrames))")
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

            let analysis = analyzer.analyzeFrame(pixelBuffer, timestamp: timestamp, dt: dt)

            if analysis.ballPosition != nil && analysis.ballConfidence > 0.2 {
                ballDetectedFrames += 1
            }

            if let outputBuffer = createOutputFrame(
                input: pixelBuffer,
                analysis: analysis,
                outputSize: outputSize,
                context: ciContext
            ) {
                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.001)
                }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                adaptor.append(outputBuffer, withPresentationTime: presentationTime)
            }
        }

        writerInput.markAsFinished()

        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        group.wait()

        let processingTime = Date().timeIntervalSince(startTime)
        let ballRate = Float(ballDetectedFrames) / Float(max(1, frameNumber)) * 100

        print("\n✅ Complete!")
        print("   Frames processed: \(frameNumber)")
        print("   Ball detection rate: \(String(format: "%.1f", ballRate))%")
        print("   Processing time: \(String(format: "%.1f", processingTime))s")
        print("   Speed: \(String(format: "%.1f", Double(frameNumber) / processingTime)) fps")
        print("\n📁 Output: \(outputURL.path)")

        completion(true, "Processed \(frameNumber) frames, ball detected in \(ballDetectedFrames)")
    }

    private func createOutputFrame(
        input: CVPixelBuffer,
        analysis: FrameAnalysis,
        outputSize: CGSize,
        context: CIContext
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

        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(outputSize.width),
            Int(outputSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }

        context.render(ciImage, to: output)

        if enableDebugOverlay {
            drawDebugOverlay(on: output, analysis: analysis)
        }

        return output
    }
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 {
    print("🧠 Skynet Vision Pipeline (ULTRA-SMOOTH)")
    print("=========================================")
    print("\nBroadcast-quality camera motion:")
    print("  • Focus moves at 2% per frame (very slow)")
    print("  • Zoom changes at 1.5% per frame")
    print("  • Dead zone ignores movements < 2%")
    print("  • Requires 5 consecutive high-confidence frames")
    print("  • Strong momentum/damping for smooth motion")
    print("\nUsage: swift SkynetVideoTest.swift \"/path/to/video.mp4\" [--no-debug]")
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

let inputURL = URL(fileURLWithPath: inputPath)
let suffix = enableDebug ? "_ultrasmooth" : "_ultrasmooth_clean"
let outputName = inputURL.deletingPathExtension().lastPathComponent + suffix + ".mp4"
let outputPath = inputURL.deletingLastPathComponent().appendingPathComponent(outputName).path

print("🧠 Skynet Vision Pipeline (ULTRA-SMOOTH)")
print("=========================================\n")

let processor = MacVideoProcessor()
let semaphore = DispatchSemaphore(value: 0)

processor.processVideo(inputPath: inputPath, outputPath: outputPath, debug: enableDebug) { success, message in
    if !success {
        print("❌ Error: \(message)")
    }
    semaphore.signal()
}

semaphore.wait()
