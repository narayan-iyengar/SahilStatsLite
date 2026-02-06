//
//  PersonClassifier.swift
//  SahilStatsLite
//
//  Improved person classification for Skynet mode
//  - Kid vs Adult: Multiple heuristics, not just median height
//  - Ref detection: Multi-sample stripe analysis
//  - Court position: Heat map based filtering
//

import Foundation
import Vision
import UIKit
import CoreImage

// MARK: - Classification Result

struct ClassifiedPerson {
    let boundingBox: CGRect  // Normalized 0-1
    let classification: PersonType
    let confidence: Float    // 0-1
    let isOnCourt: Bool

    enum PersonType {
        case player      // Kid on court (TRACK)
        case referee     // Striped jersey (TRACK but filter from action center)
        case coach       // Adult on sideline (IGNORE)
        case benchPlayer // Kid on sideline (IGNORE)
        case spectator   // Unknown/other (IGNORE)
    }
}

// MARK: - Person Classifier

class PersonClassifier {

    // MARK: - Configuration

    /// Expected kid height as fraction of frame (youth basketball ~8-12 year olds)
    /// At typical gym camera distance, kids are roughly 15-30% of frame height
    private let kidHeightRange: ClosedRange<CGFloat> = 0.10...0.35

    /// Adults are typically 20%+ taller than kids at same distance
    private let adultHeightMultiplier: CGFloat = 1.20

    /// Minimum stripe transitions to classify as ref
    private let minStripeTransitions = 3

    /// Court bounds (learned from heat map, updated dynamically)
    var courtBounds: CGRect = CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.60)

    // MARK: - Rolling Statistics

    /// Track heights over multiple frames to establish baseline
    private var recentHeights: [CGFloat] = []
    private let maxHeightHistory = 50

    /// Baseline kid height (25th percentile of all detections)
    private var baselineKidHeight: CGFloat = 0.20

    // MARK: - Broadcast-Quality Centroid Smoothing (v3)

    /// Rolling centroid history for jitter elimination
    private var centroidHistory: [CGPoint] = []
    private let centroidHistorySize = 8  // Average over ~8 detection cycles

    /// Current focus hint for proximity weighting (set by AutoZoomManager)
    var currentFocusHint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // MARK: - Main Classification

    func classifyPeople(in pixelBuffer: CVPixelBuffer) -> [ClassifiedPerson] {
        // Convert to CGImage for Vision
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return []
        }

        return classifyPeople(in: cgImage)
    }

    func classifyPeople(in image: CGImage) -> [ClassifiedPerson] {
        // Detect all humans
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        // Update height statistics
        updateHeightStatistics(from: observations)

        // Classify each person
        return observations.map { observation in
            classifyPerson(observation: observation, in: image)
        }
    }

    // MARK: - Individual Classification

    private func classifyPerson(observation: VNHumanObservation, in image: CGImage) -> ClassifiedPerson {
        let box = observation.boundingBox

        // 1. Check if on court (within heat map bounds)
        let isOnCourt = courtBounds.contains(CGPoint(x: box.midX, y: box.midY))

        // 2. Check for ref jersey (striped pattern)
        let (isRef, refConfidence) = checkForRefJersey(in: image, box: box)

        if isRef {
            return ClassifiedPerson(
                boundingBox: box,
                classification: .referee,
                confidence: refConfidence,
                isOnCourt: isOnCourt
            )
        }

        // 3. Classify as kid or adult
        let (isKid, kidConfidence) = classifyAge(box: box)

        // 4. Determine final classification
        let classification: ClassifiedPerson.PersonType
        let confidence: Float

        if isOnCourt {
            if isKid {
                classification = .player
                confidence = kidConfidence
            } else {
                // Adult on court - could be ref without visible stripes, or coach
                classification = .coach  // Default to ignore
                confidence = kidConfidence
            }
        } else {
            if isKid {
                classification = .benchPlayer
                confidence = kidConfidence
            } else {
                classification = .coach
                confidence = kidConfidence
            }
        }

        return ClassifiedPerson(
            boundingBox: box,
            classification: classification,
            confidence: confidence,
            isOnCourt: isOnCourt
        )
    }

    // MARK: - Age Classification (Kid vs Adult)

    private func classifyAge(box: CGRect) -> (isKid: Bool, confidence: Float) {
        let height = box.height

        // Method 1: Compare to baseline kid height
        let heightRatio = height / baselineKidHeight

        // Method 2: Check if within expected kid height range
        let inKidRange = kidHeightRange.contains(height)

        // Method 3: Check aspect ratio (kids tend to be more square-ish)
        let aspectRatio = box.width / box.height
        let kidAspectRange: ClosedRange<CGFloat> = 0.25...0.55
        let hasKidAspect = kidAspectRange.contains(aspectRatio)

        // Combine heuristics
        var kidScore: Float = 0
        var totalWeight: Float = 0

        // Height ratio (weight: 3)
        if heightRatio < 1.15 {
            kidScore += 3.0
        } else if heightRatio > 1.30 {
            kidScore += 0
        } else {
            kidScore += 1.5  // Uncertain
        }
        totalWeight += 3.0

        // Absolute height range (weight: 2)
        if inKidRange {
            kidScore += 2.0
        } else if height > kidHeightRange.upperBound * 1.3 {
            kidScore += 0  // Definitely too tall
        } else {
            kidScore += 1.0  // Might be close kid
        }
        totalWeight += 2.0

        // Aspect ratio (weight: 1)
        if hasKidAspect {
            kidScore += 1.0
        }
        totalWeight += 1.0

        let normalizedScore = kidScore / totalWeight
        let isKid = normalizedScore > 0.5

        return (isKid, normalizedScore)
    }

    // MARK: - Ref Jersey Detection (Improved)

    private func checkForRefJersey(in image: CGImage, box: CGRect) -> (isRef: Bool, confidence: Float) {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Get torso region (upper 40% of bounding box, which is the jersey)
        let torsoRect = CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height + box.height * height * 0.25,
            width: box.width * width,
            height: box.height * height * 0.40
        )

        // Clamp to image bounds
        let sampleStartX = max(0, Int(torsoRect.minX))
        let sampleEndX = min(image.width - 1, Int(torsoRect.maxX))
        let sampleStartY = max(0, Int(torsoRect.minY))
        let sampleEndY = min(image.height - 1, Int(torsoRect.maxY))

        guard sampleEndX > sampleStartX + 10 && sampleEndY > sampleStartY + 10 else {
            return (false, 0)
        }

        // Create bitmap to read pixels
        guard let pixelData = getPixelData(from: image) else {
            return (false, 0)
        }

        // Sample MULTIPLE vertical lines (not just center)
        let sampleLines = 5
        var totalTransitions = 0
        var validSamples = 0

        for i in 0..<sampleLines {
            let xOffset = CGFloat(i) / CGFloat(sampleLines - 1)
            let sampleX = sampleStartX + Int(CGFloat(sampleEndX - sampleStartX) * xOffset)

            let transitions = countStripeTransitions(
                pixelData: pixelData,
                imageWidth: image.width,
                x: sampleX,
                startY: sampleStartY,
                endY: sampleEndY
            )

            if transitions > 0 {
                totalTransitions += transitions
                validSamples += 1
            }
        }

        // Also check horizontal stripes (refs have horizontal black/white pattern)
        let horizontalTransitions = countHorizontalStripes(
            pixelData: pixelData,
            imageWidth: image.width,
            startX: sampleStartX,
            endX: sampleEndX,
            y: (sampleStartY + sampleEndY) / 2
        )

        // Combine vertical and horizontal stripe detection
        let avgVerticalTransitions = validSamples > 0 ? totalTransitions / validSamples : 0
        let hasVerticalStripes = avgVerticalTransitions >= minStripeTransitions
        let hasHorizontalStripes = horizontalTransitions >= minStripeTransitions

        // Ref if either pattern detected with sufficient confidence
        let isRef = hasVerticalStripes || hasHorizontalStripes

        // Confidence based on how many stripes detected
        let maxTransitions = max(avgVerticalTransitions, horizontalTransitions)
        let confidence = min(1.0, Float(maxTransitions) / 6.0)

        return (isRef, confidence)
    }

    private func countStripeTransitions(pixelData: [UInt8], imageWidth: Int, x: Int, startY: Int, endY: Int) -> Int {
        var transitions = 0
        var lastWasLight: Bool? = nil
        let bytesPerPixel = 4

        for y in stride(from: startY, to: endY, by: 3) {
            let offset = (y * imageWidth + x) * bytesPerPixel
            guard offset + 2 < pixelData.count else { continue }

            let r = Int(pixelData[offset])
            let g = Int(pixelData[offset + 1])
            let b = Int(pixelData[offset + 2])

            // Calculate brightness and saturation
            let brightness = (r + g + b) / 3
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) * 100 / maxC : 0

            // Only count if low saturation (black/white, not colored)
            let isBlackOrWhite = saturation < 30
            let isLight = brightness > 130

            if isBlackOrWhite {
                if let last = lastWasLight, last != isLight {
                    transitions += 1
                }
                lastWasLight = isLight
            }
        }

        return transitions
    }

    private func countHorizontalStripes(pixelData: [UInt8], imageWidth: Int, startX: Int, endX: Int, y: Int) -> Int {
        var transitions = 0
        var lastWasLight: Bool? = nil
        let bytesPerPixel = 4

        for x in stride(from: startX, to: endX, by: 3) {
            let offset = (y * imageWidth + x) * bytesPerPixel
            guard offset + 2 < pixelData.count else { continue }

            let r = Int(pixelData[offset])
            let g = Int(pixelData[offset + 1])
            let b = Int(pixelData[offset + 2])

            let brightness = (r + g + b) / 3
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) * 100 / maxC : 0

            let isBlackOrWhite = saturation < 30
            let isLight = brightness > 130

            if isBlackOrWhite {
                if let last = lastWasLight, last != isLight {
                    transitions += 1
                }
                lastWasLight = isLight
            }
        }

        return transitions
    }

    private func getPixelData(from image: CGImage) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * image.width
        var pixelData = [UInt8](repeating: 0, count: image.height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixelData
    }

    // MARK: - Statistics Update

    private func updateHeightStatistics(from observations: [VNHumanObservation]) {
        for obs in observations {
            recentHeights.append(obs.boundingBox.height)
        }

        // Keep only recent history
        if recentHeights.count > maxHeightHistory {
            recentHeights = Array(recentHeights.suffix(maxHeightHistory))
        }

        // Update baseline (25th percentile = typical kid height)
        if recentHeights.count >= 10 {
            let sorted = recentHeights.sorted()
            let p25Index = sorted.count / 4
            baselineKidHeight = sorted[p25Index]
        }
    }

    // MARK: - Court Bounds Update

    func updateCourtBounds(from heatMap: [[Int]], threshold: Double = 0.40) {
        let gridSize = heatMap.count
        guard gridSize > 0 else { return }

        let maxVal = heatMap.flatMap { $0 }.max() ?? 1
        let cutoff = Int(Double(maxVal) * threshold)

        // Skip top 30% (ceiling) and bottom 5% (camera operator feet)
        let minYSearch = Int(Double(gridSize) * 0.05)
        let maxYSearch = Int(Double(gridSize) * 0.70)

        var minX = gridSize, maxX = 0
        var minY = gridSize, maxY = 0

        for y in minYSearch..<maxYSearch {
            for x in 0..<gridSize {
                if heatMap[y][x] > cutoff {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX < gridSize else { return }

        let padding: CGFloat = 0.05
        courtBounds = CGRect(
            x: max(0, CGFloat(minX) / CGFloat(gridSize) - padding),
            y: max(0, CGFloat(minY) / CGFloat(gridSize) - padding),
            width: min(1, CGFloat(maxX - minX + 1) / CGFloat(gridSize) + padding * 2),
            height: min(1, CGFloat(maxY - minY + 1) / CGFloat(gridSize) + padding * 2)
        )
    }
}

// MARK: - Action Center Calculator

extension PersonClassifier {

    /// Calculate weighted center of trackable people (players + refs on court)
    /// Uses proximity weighting (players near current focus weigh more) and
    /// rolling centroid averaging to eliminate jitter from detection flickering.
    func calculateActionCenter(from people: [ClassifiedPerson]) -> CGPoint {
        let trackable = people.filter { person in
            switch person.classification {
            case .player:
                return true
            case .referee:
                return true  // Include refs but with lower weight
            default:
                return false
            }
        }

        guard !trackable.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)  // Default to center
        }

        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0

        for person in trackable {
            // Weight by bounding box area (bigger = closer = more important)
            var weight = person.boundingBox.width * person.boundingBox.height * 100

            // Reduce ref weight (they run around but aren't the action)
            if person.classification == .referee {
                weight *= 0.3
            }

            // Boost high-confidence detections
            weight *= CGFloat(person.confidence)

            // Proximity weighting: players closer to current focus get MORE weight.
            // This prevents distant players from yanking the camera around.
            let dx = person.boundingBox.midX - currentFocusHint.x
            let dy = person.boundingBox.midY - currentFocusHint.y
            let distance = sqrt(dx * dx + dy * dy)
            let proximityWeight = max(0.1, 1.0 - distance * 2.0)
            weight *= proximityWeight

            weightedX += person.boundingBox.midX * weight
            weightedY += person.boundingBox.midY * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let rawCenter = CGPoint(
            x: weightedX / totalWeight,
            y: weightedY / totalWeight
        )

        // Rolling centroid average to smooth out detection flickering
        centroidHistory.append(rawCenter)
        if centroidHistory.count > centroidHistorySize {
            centroidHistory.removeFirst()
        }

        let avgX = centroidHistory.reduce(0.0) { $0 + $1.x } / CGFloat(centroidHistory.count)
        let avgY = centroidHistory.reduce(0.0) { $0 + $1.y } / CGFloat(centroidHistory.count)
        return CGPoint(x: avgX, y: avgY)
    }

    /// Calculate recommended zoom based on player spread
    func calculateZoomFactor(from people: [ClassifiedPerson], minZoom: CGFloat = 1.0, maxZoom: CGFloat = 1.5) -> CGFloat {
        let players = people.filter { $0.classification == .player }

        guard players.count >= 2 else {
            return 1.0  // Not enough players, stay wide
        }

        // Calculate spread (distance between furthest players)
        let xs = players.map { $0.boundingBox.midX }
        let spread = (xs.max() ?? 0.5) - (xs.min() ?? 0.5)

        // Wide spread = zoom out, tight cluster = zoom in
        // spread of 0.7+ = full court = 1.0x
        // spread of 0.2 = clustered = 1.5x
        let normalizedSpread = (spread - 0.2) / 0.5  // 0 = clustered, 1 = spread
        let clampedSpread = max(0, min(1, normalizedSpread))

        return maxZoom - (clampedSpread * (maxZoom - minZoom))
    }
}
