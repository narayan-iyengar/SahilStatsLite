//
//  CourtDetector.swift
//  SahilStatsLite
//
//  Zero-training court detection using classical computer vision
//  - Edge detection (Canny-style)
//  - Hough transform for line detection
//  - Court boundary estimation
//  - Homography to standard court template
//
//  Court Geometry (Youth Basketball):
//  - Full court: 84ft x 50ft (high school) or 74ft x 42ft (youth)
//  - Key/paint width: 12ft
//  - 3-point line: 19.75ft from basket (high school)
//  - Free throw line: 15ft from backboard
//

import Foundation
import CoreGraphics
import CoreImage
import Accelerate

// MARK: - Court Detection Result

struct CourtDetection {
    let bounds: CGRect              // Detected court bounds (normalized 0-1)
    let halfCourtLine: CGFloat?     // X position of half court (normalized)
    let leftBasket: CGPoint?        // Left basket position (normalized)
    let rightBasket: CGPoint?       // Right basket position (normalized)
    let confidence: Float           // Detection confidence
    let isCalibrated: Bool          // True if homography computed

    // Normalized court positions (0 = left baseline, 1 = right baseline)
    func courtX(for screenX: CGFloat) -> CGFloat? {
        guard bounds.width > 0 else { return nil }
        return (screenX - bounds.minX) / bounds.width
    }

    func courtY(for screenY: CGFloat) -> CGFloat? {
        guard bounds.height > 0 else { return nil }
        return (screenY - bounds.minY) / bounds.height
    }

    /// Returns distance to nearest basket (normalized)
    func distanceToNearestBasket(from position: CGPoint) -> CGFloat {
        var minDist: CGFloat = 1.0

        if let left = leftBasket {
            let dist = hypot(position.x - left.x, position.y - left.y)
            minDist = min(minDist, dist)
        }

        if let right = rightBasket {
            let dist = hypot(position.x - right.x, position.y - right.y)
            minDist = min(minDist, dist)
        }

        return minDist
    }

    /// Returns true if position is in the paint/key area
    func isInPaint(position: CGPoint) -> Bool {
        let courtX = (position.x - bounds.origin.x) / bounds.size.width
        let courtY = (position.y - bounds.origin.y) / bounds.size.height

        // Paint is roughly 0-18% or 82-100% of court length, and 35-65% of width
        let inLeftPaint = courtX < 0.18 && courtY > 0.35 && courtY < 0.65
        let inRightPaint = courtX > 0.82 && courtY > 0.35 && courtY < 0.65

        return inLeftPaint || inRightPaint
    }

    /// Returns the nearest basket position
    func nearestBasket(from position: CGPoint) -> CGPoint? {
        guard let left = leftBasket, let right = rightBasket else {
            return leftBasket ?? rightBasket
        }

        let leftDist = hypot(position.x - left.x, position.y - left.y)
        let rightDist = hypot(position.x - right.x, position.y - right.y)

        return leftDist < rightDist ? left : right
    }
}

// MARK: - Standard Court Template

struct CourtTemplate {
    // Youth basketball court dimensions (normalized to 1.0 x 0.6 aspect ratio)
    static let aspectRatio: CGFloat = 84.0 / 50.0  // 1.68

    // Key positions (normalized 0-1 along court length)
    static let halfCourt: CGFloat = 0.5
    static let leftFreeThrow: CGFloat = 15.0 / 84.0  // ~0.18
    static let rightFreeThrow: CGFloat = 1.0 - (15.0 / 84.0)  // ~0.82
    static let leftThreePoint: CGFloat = 19.75 / 84.0  // ~0.24
    static let rightThreePoint: CGFloat = 1.0 - (19.75 / 84.0)  // ~0.76

    // Key positions (normalized 0-1 along court width)
    static let paintTop: CGFloat = 0.5 - (6.0 / 50.0)  // Paint is 12ft wide
    static let paintBottom: CGFloat = 0.5 + (6.0 / 50.0)
}

// MARK: - Court Detector

class CourtDetector {

    // MARK: - Calibration State

    private var isCalibrated: Bool = false
    private var calibrationFrameCount: Int = 0
    private let calibrationFramesNeeded: Int = 30

    // Detected features (accumulated during calibration)
    private var detectedLines: [DetectedLine] = []
    private var horizontalLines: [CGFloat] = []  // Y positions
    private var verticalLines: [CGFloat] = []    // X positions

    // Stable court bounds (after calibration)
    private var stableCourtBounds: CGRect = CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.6)
    private var stableHalfCourt: CGFloat? = nil
    private var stableLeftBasket: CGPoint? = nil
    private var stableRightBasket: CGPoint? = nil

    // MARK: - Line Detection Thresholds

    private let edgeThresholdLow: Float = 50
    private let edgeThresholdHigh: Float = 150
    private let houghThreshold: Int = 50

    // MARK: - Detection

    func detectCourt(in pixelBuffer: CVPixelBuffer) -> CourtDetection {
        // If already calibrated, return stable detection
        if isCalibrated {
            return CourtDetection(
                bounds: stableCourtBounds,
                halfCourtLine: stableHalfCourt,
                leftBasket: stableLeftBasket,
                rightBasket: stableRightBasket,
                confidence: 0.9,
                isCalibrated: true
            )
        }

        // Calibration phase - detect lines
        let lines = detectLines(in: pixelBuffer)
        detectedLines.append(contentsOf: lines)

        calibrationFrameCount += 1

        if calibrationFrameCount >= calibrationFramesNeeded {
            // Perform calibration
            calibrate()
        }

        // Return current best estimate
        return CourtDetection(
            bounds: stableCourtBounds,
            halfCourtLine: stableHalfCourt,
            leftBasket: stableLeftBasket,
            rightBasket: stableRightBasket,
            confidence: Float(calibrationFrameCount) / Float(calibrationFramesNeeded) * 0.5,
            isCalibrated: false
        )
    }

    // MARK: - Line Detection (Simplified Hough Transform)

    private struct DetectedLine {
        let start: CGPoint  // Normalized
        let end: CGPoint    // Normalized
        let angle: CGFloat  // Radians
        let length: CGFloat

        var isHorizontal: Bool {
            let angleDeg = abs(angle * 180 / .pi)
            return angleDeg < 20 || angleDeg > 160
        }

        var isVertical: Bool {
            let angleDeg = abs(angle * 180 / .pi)
            return angleDeg > 70 && angleDeg < 110
        }
    }

    private func detectLines(in pixelBuffer: CVPixelBuffer) -> [DetectedLine] {
        var lines: [DetectedLine] = []

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Downsample for speed
        let scale = 4
        let smallWidth = width / scale
        let smallHeight = height / scale

        // Create grayscale + edge detection buffer
        var grayscale = [Float](repeating: 0, count: smallWidth * smallHeight)
        var edges = [Float](repeating: 0, count: smallWidth * smallHeight)

        // Convert to grayscale (downsampled)
        for y in 0..<smallHeight {
            for x in 0..<smallWidth {
                let px = x * scale
                let py = y * scale
                let offset = py * bytesPerRow + px * 4
                let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

                // BGRA format
                let b = Float(ptr[0])
                let g = Float(ptr[1])
                let r = Float(ptr[2])

                // Grayscale
                grayscale[y * smallWidth + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        // Simple edge detection (Sobel-like)
        for y in 1..<(smallHeight - 1) {
            for x in 1..<(smallWidth - 1) {
                let idx = y * smallWidth + x

                // Horizontal gradient
                let gx = grayscale[idx + 1] - grayscale[idx - 1]

                // Vertical gradient
                let gy = grayscale[idx + smallWidth] - grayscale[idx - smallWidth]

                // Edge magnitude
                edges[idx] = sqrt(gx * gx + gy * gy)
            }
        }

        // Find edge pixels above threshold
        var edgePixels: [(x: Int, y: Int)] = []
        for y in 1..<(smallHeight - 1) {
            for x in 1..<(smallWidth - 1) {
                if edges[y * smallWidth + x] > edgeThresholdHigh {
                    edgePixels.append((x, y))
                }
            }
        }

        // Look for white/bright line pixels specifically (court lines are usually white/light)
        var linePixels: [(x: Int, y: Int)] = []
        for y in 1..<(smallHeight - 1) {
            for x in 1..<(smallWidth - 1) {
                let brightness = grayscale[y * smallWidth + x]
                let edgeMag = edges[y * smallWidth + x]

                // High brightness + edge = likely court line
                if brightness > 180 && edgeMag > edgeThresholdLow {
                    linePixels.append((x, y))
                }
            }
        }

        // Simplified Hough: Find dominant horizontal and vertical lines
        // by clustering edge pixels

        // Horizontal lines: cluster by Y position
        var yHistogram = [Int](repeating: 0, count: smallHeight)
        for pixel in linePixels {
            yHistogram[pixel.y] += 1
        }

        // Find peaks in Y histogram (horizontal lines)
        for y in 5..<(smallHeight - 5) {
            let count = yHistogram[y]
            if count > smallWidth / 10 {  // At least 10% of width
                // Check if local maximum
                let isMax = yHistogram[(y-2)...(y+2)].max() == count
                if isMax {
                    let normalizedY = CGFloat(y) / CGFloat(smallHeight)
                    horizontalLines.append(normalizedY)

                    lines.append(DetectedLine(
                        start: CGPoint(x: 0, y: normalizedY),
                        end: CGPoint(x: 1, y: normalizedY),
                        angle: 0,
                        length: 1.0
                    ))
                }
            }
        }

        // Vertical lines: cluster by X position
        var xHistogram = [Int](repeating: 0, count: smallWidth)
        for pixel in linePixels {
            xHistogram[pixel.x] += 1
        }

        // Find peaks in X histogram (vertical lines)
        for x in 5..<(smallWidth - 5) {
            let count = xHistogram[x]
            if count > smallHeight / 8 {  // At least 12.5% of height
                let isMax = xHistogram[(x-2)...(x+2)].max() == count
                if isMax {
                    let normalizedX = CGFloat(x) / CGFloat(smallWidth)
                    verticalLines.append(normalizedX)

                    lines.append(DetectedLine(
                        start: CGPoint(x: normalizedX, y: 0),
                        end: CGPoint(x: normalizedX, y: 1),
                        angle: .pi / 2,
                        length: 1.0
                    ))
                }
            }
        }

        return lines
    }

    // MARK: - Calibration

    private func calibrate() {
        guard !horizontalLines.isEmpty || !verticalLines.isEmpty else {
            // No lines detected - use default court bounds
            isCalibrated = true
            debugPrint("🏀 [CourtDetector] Calibrated with defaults (no lines detected)")
            return
        }

        // Find court boundaries from accumulated line detections

        // Horizontal lines: Find top and bottom of court
        let sortedHorizontal = horizontalLines.sorted()
        if sortedHorizontal.count >= 2 {
            // Court top is likely one of the upper lines
            // Court bottom is likely one of the lower lines
            let topCandidates = sortedHorizontal.filter { $0 < 0.5 }
            let bottomCandidates = sortedHorizontal.filter { $0 > 0.5 }

            if let top = topCandidates.first, let bottom = bottomCandidates.last {
                stableCourtBounds.origin.y = top
                stableCourtBounds.size.height = bottom - top
            }
        }

        // Vertical lines: Find left, right, and half court
        let sortedVertical = verticalLines.sorted()
        if sortedVertical.count >= 2 {
            // Left baseline
            if let left = sortedVertical.first {
                stableCourtBounds.origin.x = left
            }

            // Right baseline
            if let right = sortedVertical.last {
                stableCourtBounds.size.width = right - stableCourtBounds.origin.x
            }

            // Half court line (should be roughly in the middle)
            let midX = stableCourtBounds.origin.x + stableCourtBounds.size.width / 2
            let halfCourtCandidates = sortedVertical.filter {
                abs($0 - midX) < stableCourtBounds.size.width * 0.15
            }
            if let halfCourt = halfCourtCandidates.first {
                stableHalfCourt = halfCourt
            }
        }

        // Estimate basket positions (at each end of court, vertically centered)
        let courtCenterY = stableCourtBounds.origin.y + stableCourtBounds.size.height / 2
        stableLeftBasket = CGPoint(
            x: stableCourtBounds.origin.x + stableCourtBounds.size.width * 0.02,
            y: courtCenterY
        )
        stableRightBasket = CGPoint(
            x: stableCourtBounds.origin.x + stableCourtBounds.size.width * 0.98,
            y: courtCenterY
        )

        isCalibrated = true
        debugPrint("🏀 [CourtDetector] Calibrated - Bounds: \(stableCourtBounds), HalfCourt: \(stableHalfCourt ?? -1)")
    }

    // MARK: - Court Position Helpers

    /// Returns which zone the position is in (0 = left side, 1 = right side)
    func courtSide(for position: CGPoint) -> Int {
        guard let halfCourt = stableHalfCourt else {
            return position.x < 0.5 ? 0 : 1
        }
        return position.x < halfCourt ? 0 : 1
    }

    /// Returns true if position is in the paint/key area
    func isInPaint(position: CGPoint) -> Bool {
        let courtX = (position.x - stableCourtBounds.origin.x) / stableCourtBounds.size.width
        let courtY = (position.y - stableCourtBounds.origin.y) / stableCourtBounds.size.height

        // Paint is roughly 0-18% or 82-100% of court length, and 35-65% of width
        let inLeftPaint = courtX < 0.18 && courtY > 0.35 && courtY < 0.65
        let inRightPaint = courtX > 0.82 && courtY > 0.35 && courtY < 0.65

        return inLeftPaint || inRightPaint
    }

    /// Returns distance to nearest basket (normalized)
    func distanceToNearestBasket(from position: CGPoint) -> CGFloat {
        var minDist: CGFloat = 1.0

        if let left = stableLeftBasket {
            let dist = hypot(position.x - left.x, position.y - left.y)
            minDist = min(minDist, dist)
        }

        if let right = stableRightBasket {
            let dist = hypot(position.x - right.x, position.y - right.y)
            minDist = min(minDist, dist)
        }

        return minDist
    }

    /// Returns the nearest basket position
    func nearestBasket(from position: CGPoint) -> CGPoint? {
        guard let left = stableLeftBasket, let right = stableRightBasket else {
            return stableLeftBasket ?? stableRightBasket
        }

        let leftDist = hypot(position.x - left.x, position.y - left.y)
        let rightDist = hypot(position.x - right.x, position.y - right.y)

        return leftDist < rightDist ? left : right
    }

    // MARK: - Reset

    func reset() {
        isCalibrated = false
        calibrationFrameCount = 0
        detectedLines = []
        horizontalLines = []
        verticalLines = []
        stableCourtBounds = CGRect(x: 0.05, y: 0.1, width: 0.9, height: 0.6)
        stableHalfCourt = nil
        stableLeftBasket = nil
        stableRightBasket = nil
    }
}
