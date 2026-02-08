//
//  PersonClassifier.swift
//  SahilStatsLite
//
//  PURPOSE: Vision-based person classification for Skynet. Detects humans via
//           VNDetectHumanRectanglesRequest, classifies as player/ref/coach/bench.
//           Calculates momentum-weighted action center from tracked objects.
//           Court bounds and height baselines learned during warmup are preserved
//           across resetTrackingState() calls.
//  KEY TYPES: PersonClassifier, ClassifiedPerson, PersonType
//  DEPENDS ON: Vision, CoreImage
//
//  CLASSIFICATION: Kid/adult by height ratio, refs by stripe detection,
//                  court position via heat map, momentum attention via Kalman velocity.
//
//  NOTE: Keep this header updated when modifying this file.
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
    
    // Visual Re-ID: Hue-Saturation histogram (16 hue bins + 4 saturation bins = 20 float vector)
    let colorHistogram: [Float]?

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

    // MARK: - State Reset

    /// Reset tracking state for game start (keeps learned court bounds + height stats from warmup)
    func resetTrackingState() {
        centroidHistory.removeAll()
        currentFocusHint = CGPoint(x: 0.5, y: 0.5)
        // courtBounds, baselineKidHeight, recentHeights are KEPT (warmup calibration)
    }

    // MARK: - Main Classification

    /// Classify people from a CVPixelBuffer (convenience overload)
    func classifyPeople(in pixelBuffer: CVPixelBuffer) -> [ClassifiedPerson] {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return []
        }
        return classifyPeople(in: cgImage)
    }

    /// Classify people from a CGImage (primary method, supports low-res AI input)
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
        
        // Get pixel data once for all classifications (efficiency)
        let pixelData = getPixelData(from: image)

        // Classify each person
        return observations.map { observation in
            classifyPerson(observation: observation, in: image, pixelData: pixelData)
        }
    }

    // MARK: - Individual Classification

    private func classifyPerson(observation: VNHumanObservation, in image: CGImage, pixelData: [UInt8]?) -> ClassifiedPerson {
        let box = observation.boundingBox

        // 1. Check if on court (within heat map bounds)
        let isOnCourt = courtBounds.contains(CGPoint(x: box.midX, y: box.midY))

        // 2. Check for ref jersey (striped pattern)
        let (isRef, refConfidence) = checkForRefJersey(in: image, box: box, pixelData: pixelData)
        
        // 3. Extract visual appearance (Color Histogram) for Re-ID tracking continuity
        let histogram = extractColorHistogram(in: image, box: box, pixelData: pixelData)

        if isRef {
            return ClassifiedPerson(
                boundingBox: box,
                classification: .referee,
                confidence: refConfidence,
                isOnCourt: isOnCourt,
                colorHistogram: histogram
            )
        }

        // 4. Classify as kid or adult
        let (isKid, kidConfidence) = classifyAge(box: box)

        // 5. Determine final classification
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
            isOnCourt: isOnCourt,
            colorHistogram: histogram
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

    private func checkForRefJersey(in image: CGImage, box: CGRect, pixelData: [UInt8]?) -> (isRef: Bool, confidence: Float) {
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

        // Use cached pixel data if available
        guard let data = pixelData else {
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
                pixelData: data,
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
            pixelData: data,
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
    
    // MARK: - Visual Re-ID (Histogram Extraction)
    
    /// Extract a Hue-Saturation histogram from the person's bounding box
    /// Used to distinguish teams and identify specific players for tracking continuity
    private func extractColorHistogram(in image: CGImage, box: CGRect, pixelData: [UInt8]?) -> [Float]? {
        guard let data = pixelData else { return nil }
        
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        // Sample center 50% of the box (focus on jersey, avoid background)
        let roi = CGRect(
            x: box.minX * width + box.width * width * 0.25,
            y: (1 - box.maxY) * height + box.height * height * 0.25,
            width: box.width * width * 0.5,
            height: box.height * height * 0.5
        )
        
        let startX = max(0, Int(roi.minX))
        let endX = min(image.width - 1, Int(roi.maxX))
        let startY = max(0, Int(roi.minY))
        let endY = min(image.height - 1, Int(roi.maxY))
        
        guard endX > startX && endY > startY else { return nil }
        
        // Histogram bins: 16 Hue bins, 4 Saturation bins
        // Hue: 0-360 mapped to 0-15
        // Sat: 0-1 mapped to 0-3
        var histogram = [Float](repeating: 0, count: 20)
        var totalPixels = 0
        
        // Stride for performance (sample every 4th pixel)
        let strideStep = 4
        let bytesPerPixel = 4
        let rowStride = image.width * bytesPerPixel
        
        for y in stride(from: startY, to: endY, by: strideStep) {
            for x in stride(from: startX, to: endX, by: strideStep) {
                let offset = y * rowStride + x * bytesPerPixel
                guard offset + 2 < data.count else { continue }
                
                let r = CGFloat(data[offset]) / 255.0
                let g = CGFloat(data[offset + 1]) / 255.0
                let b = CGFloat(data[offset + 2]) / 255.0
                
                // Convert to HSV
                let (h, s, v) = rgbToHSV(r: r, g: g, b: b)
                
                // Ignore very dark or very bright pixels (noise/shadows)
                if v < 0.1 || v > 0.95 { continue }
                
                // Binning
                let hueBin = min(15, Int(h / 22.5)) // 360 / 16 = 22.5
                let satBin = min(3, Int(s * 4))
                
                histogram[hueBin] += 1.0
                histogram[16 + satBin] += 1.0
                totalPixels += 1
            }
        }
        
        guard totalPixels > 0 else { return nil }
        
        // Normalize
        for i in 0..<histogram.count {
            histogram[i] /= Float(totalPixels)
        }
        
        return histogram
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

        return (h, s, v)
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

// MARK: - Action Center Calculators

extension PersonClassifier {

    /// v3.1: Calculate action center from Kalman-filtered TrackedObjects with Momentum Attention
    /// Uses DeepTracker's Kalman velocity instead of naive frame-to-frame matching.
    /// Moving players are weighted 1x-3x higher than stationary ones.
    func calculateActionCenter(from tracks: [TrackedObject]) -> CGPoint {
        let trackable = tracks.filter { $0.classification == .player || $0.classification == .referee }
        guard !trackable.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }

        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0

        for track in trackable {
            // Base weight: bounding box area (bigger = closer = more important)
            var weight = track.boundingBox.width * track.boundingBox.height * 100

            // Ref penalty
            if track.classification == .referee { weight *= 0.3 }

            // Reliability from Kalman filter (replaces raw confidence)
            weight *= CGFloat(track.reliabilityScore)

            // Proximity weighting: players near current focus weigh more
            let box = track.predictedBoundingBox
            let dx = box.midX - currentFocusHint.x
            let dy = box.midY - currentFocusHint.y
            let proxWeight = max(0.1, 1.0 - sqrt(dx * dx + dy * dy) * 2.0)
            weight *= proxWeight

            // Momentum Attention: moving players are 1x-3x more important
            // Uses Kalman-filtered velocity (much smoother than naive matching)
            let vel = track.kalman.velocity
            let velocityMag = sqrt(vel.x * vel.x + vel.y * vel.y)
            let momentumWeight = min(3.0, 1.0 + velocityMag * 20.0)
            weight *= CGFloat(momentumWeight)

            weightedX += box.midX * weight
            weightedY += box.midY * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return CGPoint(x: 0.5, y: 0.5) }

        let rawCenter = CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)

        // Rolling centroid average to smooth out detection flickering
        centroidHistory.append(rawCenter)
        if centroidHistory.count > centroidHistorySize { centroidHistory.removeFirst() }

        let avgX = centroidHistory.reduce(0.0) { $0 + $1.x } / CGFloat(centroidHistory.count)
        let avgY = centroidHistory.reduce(0.0) { $0 + $1.y } / CGFloat(centroidHistory.count)
        return CGPoint(x: avgX, y: avgY)
    }

    /// v3: Calculate action center from raw ClassifiedPerson detections (no Kalman velocity)
    /// Used when TrackedObjects aren't available (e.g., standalone testing)
    func calculateActionCenter(from people: [ClassifiedPerson]) -> CGPoint {
        let trackable = people.filter { person in
            person.classification == .player || person.classification == .referee
        }

        guard !trackable.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0

        for person in trackable {
            var weight = person.boundingBox.width * person.boundingBox.height * 100
            if person.classification == .referee { weight *= 0.3 }
            weight *= CGFloat(person.confidence)

            let dx = person.boundingBox.midX - currentFocusHint.x
            let dy = person.boundingBox.midY - currentFocusHint.y
            let distance = sqrt(dx * dx + dy * dy)
            let proximityWeight = max(0.1, 1.0 - distance * 2.0)
            weight *= proximityWeight

            weightedX += person.boundingBox.midX * weight
            weightedY += person.boundingBox.midY * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return CGPoint(x: 0.5, y: 0.5) }

        let rawCenter = CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)

        centroidHistory.append(rawCenter)
        if centroidHistory.count > centroidHistorySize { centroidHistory.removeFirst() }

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
