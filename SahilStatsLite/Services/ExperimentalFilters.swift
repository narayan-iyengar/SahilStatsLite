//
//  ExperimentalFilters.swift
//  SahilStatsLite
//
//  Research algorithms for "Skynet" Phase 2.
//  Contains advanced tracking and prediction filters to layer on top of DeepTracker.
//

import Foundation
import CoreGraphics
import Vision

// MARK: - 1. Predictive "Lead" Tracker (The Cameraman Algorithm)

/// Adds "lead" to the camera movement, anticipating where action will be.
/// - Theory: Real cameramen aim ahead of fast-moving subjects.
/// - Implementation: Linear regression on recent centroid positions to project t+0.5s.
class PredictiveLeadTracker {
    
    // History of action centers for regression
    private var history: [(time: Double, point: CGPoint)] = []
    private let windowSize: Double = 0.5 // Look back 0.5 seconds
    private let predictionHorizon: Double = 0.4 // Look ahead 0.4 seconds
    
    /// Update with current action center and get predicted "Lead" point
    func update(currentCenter: CGPoint, timestamp: Double) -> CGPoint {
        // Add to history
        history.append((time: timestamp, point: currentCenter))
        
        // Prune old history
        history.removeAll { timestamp - $0.time > windowSize }
        
        guard history.count >= 3 else { return currentCenter }
        
        // Simple Linear Regression (Least Squares)
        // x = at + b
        // y = ct + d
        
        let n = Double(history.count)
        var sumT: Double = 0, sumX: Double = 0, sumY: Double = 0
        var sumT2: Double = 0, sumTX: Double = 0, sumTY: Double = 0
        
        // Normalize time to 0 start to avoid precision issues
        let t0 = history.first!.time
        
        for item in history {
            let t = item.time - t0
            sumT += t
            sumT2 += t * t
            sumX += item.point.x
            sumY += item.point.y
            sumTX += t * item.point.x
            sumTY += t * item.point.y
        }
        
        let denominator = n * sumT2 - sumT * sumT
        guard denominator != 0 else { return currentCenter }
        
        // Calculate slopes (velocity)
        let slopeX = (n * sumTX - sumT * sumX) / denominator
        let slopeY = (n * sumTY - sumT * sumY) / denominator
        
        // Calculate intercepts (starting position)
        let interceptX = (sumX - slopeX * sumT) / n
        let interceptY = (sumY - slopeY * sumT) / n
        
        // Predict future position
        // Current normalized time is (timestamp - t0)
        // Target time is (timestamp - t0) + predictionHorizon
        let targetT = (timestamp - t0) + predictionHorizon
        
        let predictedX = slopeX * targetT + interceptX
        let predictedY = slopeY * targetT + interceptY
        
        // Clamp to logical bounds (don't lead off screen)
        return CGPoint(
            x: max(0.1, min(0.9, predictedX)),
            y: max(0.1, min(0.9, predictedY))
        )
    }
    
    func reset() {
        history.removeAll()
    }
}

// MARK: - 2. Hybrid Tracking Manager (Correlation + Detection)

/// Orchestrates switching between heavy Neural Detection and fast Visual Tracking.
/// - Theory: Detect once, track visually for N frames, then re-detect to correct drift.
/// - Benefit: True 60fps tracking without running heavy ML every frame.
class HybridTrackingManager {
    
    enum Mode {
        case detecting  // Running Vision Neural Net (Slow, Accurate)
        case tracking   // Running VNTrackObjectRequest (Fast, "Sticky")
    }
    
    private var currentMode: Mode = .detecting
    private var framesSinceDetection: Int = 0
    private let maxTrackingFrames = 5 // Track for 5 frames between detections
    
    // The visual tracker request
    private var trackingRequest: VNTrackObjectRequest?
    private var lastKnownRect: CGRect?
    
    /// Process frame returning the best available bounding box
    func process(pixelBuffer: CVPixelBuffer, 
                 runDetection: () -> CGRect?) -> CGRect? {
        
        framesSinceDetection += 1
        
        // Decision: Detect or Track?
        if framesSinceDetection >= maxTrackingFrames || lastKnownRect == nil {
            // TIME TO DETECT
            currentMode = .detecting
            framesSinceDetection = 0
            
            if let detectedRect = runDetection() {
                // Initialize tracker with new detection
                let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: detectedRect))
                request.trackingLevel = .accurate
                self.trackingRequest = request
                self.lastKnownRect = detectedRect
                return detectedRect
            }
            return nil
            
        } else {
            // TIME TO TRACK
            currentMode = .tracking
            
            guard let request = trackingRequest else { return nil }
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
                
                if let observation = request.results?.first as? VNDetectedObjectObservation {
                    // Update our rect from tracker result
                    self.lastKnownRect = observation.boundingBox
                    
                    // Feed result back into tracker for next frame
                    request.inputObservation = observation
                    return observation.boundingBox
                }
            } catch {
                print("Tracking failed: \(error)")
                // Fallback to detection next frame
                framesSinceDetection = maxTrackingFrames
            }
            return lastKnownRect
        }
    }
    
    func reset() {
        trackingRequest = nil
        lastKnownRect = nil
        framesSinceDetection = maxTrackingFrames // Force detection on start
    }
}

// MARK: - 3. Scene Activity Energy (Context Awareness)

/// Calculates "Motion Energy" to determine game state (Play vs Dead Ball).
/// - Theory: High optical flow magnitude = Fast Break. Low magnitude = Set Play / Timeout.
class SceneActivityMonitor {
    
    // Accumulate motion vectors
    private var motionHistory: [Double] = []
    private let historySize = 30 // 1 second buffer
    
    var currentEnergy: Double {
        guard !motionHistory.isEmpty else { return 0 }
        return motionHistory.reduce(0, +) / Double(motionHistory.count)
    }
    
    var isHighAction: Bool {
        return currentEnergy > 0.05 // Threshold TBD
    }
    
    // Call this if you have optical flow vectors
    func update(flowMagnitude: Double) {
        motionHistory.append(flowMagnitude)
        if motionHistory.count > historySize {
            motionHistory.removeFirst()
        }
    }
    
    // Placeholder: If we don't have optical flow, estimate from centroid velocity
    func updateFromCentroid(oldPos: CGPoint, newPos: CGPoint, dt: Double) {
        let dx = newPos.x - oldPos.x
        let dy = newPos.y - oldPos.y
        let speed = sqrt(dx*dx + dy*dy) / dt // Screen widths per second
        update(flowMagnitude: speed)
    }
}
