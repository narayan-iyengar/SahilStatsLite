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

    /// Minimum stripe transitions to classify as ref
    private let minStripeTransitions = 3

    /// Court bounds (learned from heat map, updated dynamically)
    var courtBounds: CGRect = CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.60)

    // Reuse CIContext across frames — creating one per frame costs GPU allocations at 15fps.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // YOLOv8n CoreML detector — primary path when model is in bundle.
    // Falls back to rectRequest if model absent (no code changes needed).
    private let yoloDetector = YOLODetector()

    // Reuse Vision request objects — avoids allocation overhead at 15fps.
    // rectRequest is fallback only when YOLO model is not present.
    private let rectRequest: VNDetectHumanRectanglesRequest = {
        let r = VNDetectHumanRectanglesRequest()
        r.upperBodyOnly = false
        return r
    }()
    // poseRequest runs in both YOLO and fallback paths for ankle-based court contact.
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    // MARK: - Team Jersey Color Learning

    // Histograms accumulated during warmup (before game clock starts)
    private var warmupHistograms: [[Float]] = []
    // Two learned team color profiles (home + away). Empty until finalizeTeamColors() is called.
    private(set) var teamColorProfiles: [[Float]] = []

    // MARK: - Broadcast-Quality Centroid Smoothing (v3)

    /// Rolling centroid history for jitter elimination
    private var centroidHistory: [CGPoint] = []
    private let centroidHistorySize = 8  // Average over ~8 detection cycles

    /// Current focus hint for proximity weighting (set by AutoZoomManager)
    nonisolated(unsafe) var currentFocusHint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    nonisolated init() {}

    // MARK: - State Reset

    /// Reset tracking state for game start (keeps learned court bounds from warmup)
    nonisolated func resetTrackingState() {
        centroidHistory.removeAll()
        currentFocusHint = CGPoint(x: 0.5, y: 0.5)
        // courtBounds and teamColorProfiles are KEPT (warmup calibration)
    }

    // MARK: - Team Color Learning

    /// Accumulate a player color histogram during warmup.
    /// Called for every player detection before the game clock starts.
    nonisolated func accumulateWarmupHistogram(_ histogram: [Float]) {
        warmupHistograms.append(histogram)
        if warmupHistograms.count > 600 { warmupHistograms.removeFirst() }
    }

    /// Called at game start (clock tap). Clusters warmup histograms into 2 team color profiles.
    /// Uses dominant-hue bucketing — basketball jerseys always have a strong, distinct hue.
    nonisolated func finalizeTeamColors() {
        guard warmupHistograms.count >= 8 else {
            debugPrint("[PersonClassifier] Too few warmup samples for color learning (\(warmupHistograms.count))")
            return
        }

        // Find dominant hue bin (0-15, covering 360° / 16 = 22.5° each) per histogram
        let dominantHues: [Int] = warmupHistograms.map { hist in
            hist.prefix(16).enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        }

        // Count occurrences of each dominant hue
        var hueCounts = [Int: Int]()
        for hue in dominantHues { hueCounts[hue, default: 0] += 1 }

        // Top 2 hue peaks = two team colors
        let topHues = hueCounts.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
        guard !topHues.isEmpty else { return }

        // Group histograms by nearest team hue
        var groups: [[Int]] = Array(repeating: [], count: topHues.count)
        for (idx, hue) in dominantHues.enumerated() {
            let nearest = topHues.enumerated().min(by: { abs($0.element - hue) < abs($1.element - hue) })?.offset ?? 0
            groups[nearest].append(idx)
        }

        // Average histogram per group = team color profile
        teamColorProfiles = groups.compactMap { indices -> [Float]? in
            guard !indices.isEmpty else { return nil }
            var avg = [Float](repeating: 0, count: 20)
            for i in indices {
                for j in 0..<20 { avg[j] += warmupHistograms[i][j] }
            }
            return avg.map { $0 / Float(indices.count) }
        }

        debugPrint("[PersonClassifier] ✅ Team colors learned: \(teamColorProfiles.count) profiles from \(warmupHistograms.count) samples")
    }

    /// Histogram intersection score vs learned team profiles (0 = stranger, 1 = perfect team match).
    /// Returns 0.5 (neutral) if no profiles have been learned yet.
    nonisolated func teamColorScore(for histogram: [Float]) -> Float {
        guard !teamColorProfiles.isEmpty else { return 0.5 }
        return teamColorProfiles.map { profile -> Float in
            zip(histogram, profile).reduce(0) { $0 + min($1.0, $1.1) }
        }.max() ?? 0.5
    }

    // MARK: - Body Pose

    private struct PersonPose {
        /// Actual ankle position in Vision coords (Y=0 at bottom). Nil if not detected.
        let floorContactPoint: CGPoint?
        /// True if knee is detectably above ankle (standing), false if likely seated/crouching.
        let isStanding: Bool
    }

    private func extractPose(_ obs: VNHumanBodyPoseObservation) -> PersonPose {
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = try? obs.recognizedPoint(name), p.confidence > 0.3 else { return nil }
            return p.location
        }
        let leftAnkle  = joint(.leftAnkle)
        let rightAnkle = joint(.rightAnkle)
        let leftKnee   = joint(.leftKnee)
        let rightKnee  = joint(.rightKnee)

        // Floor contact: midpoint of visible ankles at the lowest Y (Vision: Y=0 is floor)
        let floorPoint: CGPoint? = {
            switch (leftAnkle, rightAnkle) {
            case let (l?, r?):
                return CGPoint(x: (l.x + r.x) / 2, y: min(l.y, r.y))
            case let (l?, nil): return l
            case let (nil, r?): return r
            default: return nil
            }
        }()

        // Standing: knee Y must be meaningfully above ankle Y in Vision space.
        // Seated people have knees near hip level or folded; this threshold filters them.
        var isStanding = true
        if let lK = leftKnee, let lA = leftAnkle {
            isStanding = (lK.y - lA.y) > 0.04
        } else if let rK = rightKnee, let rA = rightAnkle {
            isStanding = (rK.y - rA.y) > 0.04
        }
        return PersonPose(floorContactPoint: floorPoint, isStanding: isStanding)
    }

    private func findMatchingPoseByRect(_ box: CGRect,
                                        in poses: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        let center = CGPoint(x: box.midX, y: box.midY)
        // VNHumanBodyPoseObservation has no boundingBox — estimate position from torso joints.
        return poses.min(by: { a, b in
            poseDistance(a, to: center) < poseDistance(b, to: center)
        }).flatMap { pose in
            poseDistance(pose, to: center) < 0.15 ? pose : nil
        }
    }

    /// Estimate the center of a body pose from available torso joints (neck, hips, shoulders).
    /// Falls back to a simple average of all recognized points if torso joints are unavailable.
    private func poseDistance(_ pose: VNHumanBodyPoseObservation, to point: CGPoint) -> CGFloat {
        let torsoJoints: [VNHumanBodyPoseObservation.JointName] = [.neck, .leftHip, .rightHip, .leftShoulder, .rightShoulder]
        let points = torsoJoints.compactMap { name -> CGPoint? in
            guard let p = try? pose.recognizedPoint(name), p.confidence > 0.2 else { return nil }
            return p.location
        }
        guard !points.isEmpty else { return CGFloat.greatestFiniteMagnitude }
        let cx = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let cy = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return hypot(point.x - cx, point.y - cy)
    }

    // MARK: - Main Classification

    /// Primary entry point. Uses YOLOv8n when the model is present in the bundle.
    nonisolated
    /// falls back to VNDetectHumanRectanglesRequest otherwise. Body pose runs in both paths.
    func classifyPeople(in pixelBuffer: CVPixelBuffer) -> [ClassifiedPerson] {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return [] }

        // YOLO disabled — coordinate mapping produces 0 detections. Using Vision until debugged.
        // TODO: debug YOLO with recorded game footage (letterbox coords, confidence threshold)
        return classifyPeople(in: cgImage)
    }

    /// Fallback classification using VNDetectHumanRectanglesRequest.
    /// Used when yolov8n.mlpackage is not in the bundle.
    func classifyPeople(in image: CGImage) -> [ClassifiedPerson] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([rectRequest, poseRequest])

        guard let observations = rectRequest.results, !observations.isEmpty else { return [] }
        let poseObservations = poseRequest.results ?? []
        let pixelData = getPixelData(from: image)

        return observations.map { obs in
            let pose = findMatchingPoseByRect(obs.boundingBox, in: poseObservations).map { extractPose($0) }
            return classifyPersonFromRect(obs.boundingBox, confidence: Float(obs.confidence),
                                         pose: pose, in: image, pixelData: pixelData)
        }
    }

    /// Shared classification engine for both YOLO and Vision-detected boxes.
    /// Runs body pose once, gets pixel data once, then classifies each box.
    private func classifyFromBoxes(_ boxes: [(CGRect, Float)], image: CGImage) -> [ClassifiedPerson] {
        guard !boxes.isEmpty else { return [] }

        // Body pose runs alongside YOLO — gives ankle positions for accurate court contact
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([poseRequest])
        let poseObservations = poseRequest.results ?? []

        let pixelData = getPixelData(from: image)

        return boxes.map { (box, confidence) in
            let pose = findMatchingPoseByRect(box, in: poseObservations).map { extractPose($0) }
            return classifyPersonFromRect(box, confidence: confidence,
                                         pose: pose, in: image, pixelData: pixelData)
        }
    }

    // MARK: - Individual Classification

    private func classifyPersonFromRect(_ box: CGRect,
                                        confidence: Float,
                                        pose: PersonPose?,
                                        in image: CGImage,
                                        pixelData: [UInt8]?) -> ClassifiedPerson {

        // Foreground rejection: person taller than 50% of frame is too close to be on court.
        let isMassiveForegroundObject = box.height > 0.50

        // Court masking via pose (preferred) or bounding box bottom (fallback).
        // Pose ankle positions are actual foot contact points — much more accurate than box.minY,
        // which can be the bottom of a bleacher or a bag on the floor.
        let isOnCourt: Bool
        if let pose = pose, let anklePoint = pose.floorContactPoint {
            // Pose-based: actual ankle touches court AND person is standing (not seated in stands)
            isOnCourt = courtBounds.contains(anklePoint) && pose.isStanding && !isMassiveForegroundObject
        } else {
            // Fallback: bounding box bottom as approximate floor contact
            let feetOnCourt = courtBounds.contains(CGPoint(x: box.midX, y: box.minY))
            let centerOnCourt = courtBounds.contains(CGPoint(x: box.midX, y: box.midY))
            isOnCourt = (feetOnCourt || centerOnCourt) && !isMassiveForegroundObject
        }

        // Extract appearance histogram for Re-ID continuity
        let histogram = extractColorHistogram(in: image, box: box, pixelData: pixelData)

        // Accumulate histogram during warmup for team color learning.
        // teamColorProfiles is empty until finalizeTeamColors() is called at game start.
        if isOnCourt, let hist = histogram, teamColorProfiles.isEmpty {
            accumulateWarmupHistogram(hist)
        }

        // Ref detection: stripe pattern check
        let (isRef, refConfidence) = checkForRefJersey(in: image, box: box, pixelData: pixelData)
        if isRef {
            return ClassifiedPerson(
                boundingBox: box,
                classification: .referee,
                confidence: refConfidence,
                isOnCourt: isOnCourt,
                colorHistogram: histogram
            )
        }

        // Court bounds + standing = player. No age heuristic.
        // DeepTracker appearance matching filters non-team members over time.
        let classification: ClassifiedPerson.PersonType = isOnCourt ? .player : .spectator
        return ClassifiedPerson(
            boundingBox: box,
            classification: classification,
            confidence: confidence,
            isOnCourt: isOnCourt,
            colorHistogram: histogram
        )
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
    nonisolated func calculateActionCenter(from tracks: [TrackedObject]) -> CGPoint {
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
            let vel = track.kalman.velocity
            let velocityMag = sqrt(vel.x * vel.x + vel.y * vel.y)
            let momentumWeight = min(3.0, 1.0 + velocityMag * 20.0)
            weight *= CGFloat(momentumWeight)

            // Team color alignment: players whose jersey matches a learned team profile
            // get up to 1.5x weight. Random passers-by with no matching jersey get 0.5x.
            // Has no effect during warmup (teamColorProfiles is empty until game start).
            if let histogram = track.colorHistogram {
                let colorScore = teamColorScore(for: histogram)
                weight *= CGFloat(0.5 + colorScore)
            }

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
