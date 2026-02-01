//
//  DeepTracker.swift
//  SahilStatsLite
//
//  Deep Track 4.0-inspired tracking system
//  Implements: Kalman filtering, SORT-style tracking, reliability scoring, recovery strategies
//
//  References:
//  - Insta360 patents US11509824B2, JP2021527865A
//  - SORT: Simple Online and Realtime Tracking (Bewley et al.)
//  - Kalman Filter for visual tracking
//

import Foundation
import CoreGraphics
import Accelerate

// MARK: - Kalman Filter (2D position + velocity)

/// Kalman filter for tracking a single object's position and velocity
/// State: [x, y, vx, vy] (position and velocity)
/// Measurement: [x, y] (position only from detection)
class KalmanFilter2D {

    // State vector: [x, y, vx, vy]
    private var state: [Double]

    // State covariance matrix (4x4)
    private var P: [[Double]]

    // Process noise covariance
    private let Q: [[Double]]

    // Measurement noise covariance
    private let R: [[Double]]

    // State transition matrix (constant velocity model)
    private var F: [[Double]]

    // Measurement matrix (we only observe position)
    private let H: [[Double]] = [
        [1, 0, 0, 0],
        [0, 1, 0, 0]
    ]

    // Time step
    private var dt: Double = 1.0/30.0  // 30 FPS default

    init(initialPosition: CGPoint, initialVelocity: CGPoint = .zero) {
        // Initialize state
        state = [
            Double(initialPosition.x),
            Double(initialPosition.y),
            Double(initialVelocity.x),
            Double(initialVelocity.y)
        ]

        // Initial covariance (high uncertainty in velocity)
        P = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 100, 0],
            [0, 0, 0, 100]
        ]

        // Process noise (models acceleration uncertainty)
        let q = 0.01  // Tune based on expected motion
        Q = [
            [q, 0, 0, 0],
            [0, q, 0, 0],
            [0, 0, q * 10, 0],
            [0, 0, 0, q * 10]
        ]

        // Measurement noise (detection uncertainty)
        let r = 0.005  // ~0.5% of frame = typical detection jitter
        R = [
            [r, 0],
            [0, r]
        ]

        // State transition (updated with dt)
        F = [
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ]
    }

    /// Predict next state (call every frame, even without detection)
    func predict(dt: Double? = nil) -> CGPoint {
        if let dt = dt {
            self.dt = dt
            F[0][2] = dt
            F[1][3] = dt
        }

        // State prediction: x = F * x
        let newState = matVecMul(F, state)
        state = newState

        // Covariance prediction: P = F * P * F' + Q
        let FP = matMul(F, P)
        let FT = transpose(F)
        let FPFT = matMul(FP, FT)
        P = matAdd(FPFT, Q)

        return CGPoint(x: state[0], y: state[1])
    }

    /// Update with measurement (call when detection available)
    func update(measurement: CGPoint) -> CGPoint {
        let z = [Double(measurement.x), Double(measurement.y)]

        // Innovation: y = z - H * x
        let Hx = matVecMul(H, state)
        let y = [z[0] - Hx[0], z[1] - Hx[1]]

        // Innovation covariance: S = H * P * H' + R
        let HP = matMul(H, P)
        let HT = transpose(H)
        let HPHT = matMul(HP, HT)
        let S = matAdd(HPHT, R)

        // Kalman gain: K = P * H' * S^-1
        let PHT = matMul(P, HT)
        guard let SInv = inverse2x2(S) else {
            // Fallback: just use measurement
            state[0] = z[0]
            state[1] = z[1]
            return measurement
        }
        let K = matMul(PHT, SInv)

        // State update: x = x + K * y
        let Ky = matVecMul(K, y)
        for i in 0..<4 {
            state[i] += Ky[i]
        }

        // Covariance update: P = (I - K * H) * P
        let KH = matMul(K, H)
        let I = [[1.0,0,0,0], [0.0,1,0,0], [0.0,0,1,0], [0.0,0,0,1]]
        let IminusKH = matSub(I, KH)
        P = matMul(IminusKH, P)

        return CGPoint(x: state[0], y: state[1])
    }

    /// Get current position estimate
    var position: CGPoint {
        CGPoint(x: state[0], y: state[1])
    }

    /// Get current velocity estimate
    var velocity: CGPoint {
        CGPoint(x: state[2], y: state[3])
    }

    /// Get position uncertainty (for reliability scoring)
    var positionUncertainty: Double {
        sqrt(P[0][0] + P[1][1])
    }

    // MARK: - Matrix Operations (simple implementations)

    private func matVecMul(_ A: [[Double]], _ x: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: A.count)
        for i in 0..<A.count {
            for j in 0..<x.count {
                result[i] += A[i][j] * x[j]
            }
        }
        return result
    }

    private func matMul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        let m = A.count
        let n = B[0].count
        let k = B.count
        var result = [[Double]](repeating: [Double](repeating: 0, count: n), count: m)
        for i in 0..<m {
            for j in 0..<n {
                for p in 0..<k {
                    result[i][j] += A[i][p] * B[p][j]
                }
            }
        }
        return result
    }

    private func transpose(_ A: [[Double]]) -> [[Double]] {
        let m = A.count
        let n = A[0].count
        var result = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for i in 0..<m {
            for j in 0..<n {
                result[j][i] = A[i][j]
            }
        }
        return result
    }

    private func matAdd(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        var result = A
        for i in 0..<A.count {
            for j in 0..<A[0].count {
                result[i][j] += B[i][j]
            }
        }
        return result
    }

    private func matSub(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        var result = A
        for i in 0..<A.count {
            for j in 0..<A[0].count {
                result[i][j] -= B[i][j]
            }
        }
        return result
    }

    private func inverse2x2(_ A: [[Double]]) -> [[Double]]? {
        let det = A[0][0] * A[1][1] - A[0][1] * A[1][0]
        guard abs(det) > 1e-10 else { return nil }
        let invDet = 1.0 / det
        return [
            [A[1][1] * invDet, -A[0][1] * invDet],
            [-A[1][0] * invDet, A[0][0] * invDet]
        ]
    }
}

// MARK: - Tracked Object

/// A single tracked object with Kalman filter and reliability scoring
class TrackedObject {
    let id: Int
    let kalman: KalmanFilter2D
    var classification: ClassifiedPerson.PersonType
    var boundingBox: CGRect
    var lastSeen: Date
    var hitStreak: Int = 0      // Consecutive frames with detection
    var missStreak: Int = 0     // Consecutive frames without detection
    var reliabilityScore: Float = 1.0
    var occlusionScore: Float = 0.0

    // For re-identification (simple color histogram)
    var colorHistogram: [Float]?

    // Track state
    enum State {
        case tentative   // New track, not yet confirmed
        case confirmed   // Reliable track
        case lost        // Temporarily lost, searching
        case deleted     // Should be removed
    }
    var state: State = .tentative

    // Thresholds (inspired by Deep Track 4.0 patent)
    static let confirmHits = 3        // Frames to confirm track
    static let maxMisses = 15         // Frames before deletion (~0.5 sec at 30fps)
    static let reliabilityThreshold: Float = 0.5
    static let occlusionThreshold: Float = 0.7

    init(id: Int, detection: ClassifiedPerson) {
        self.id = id
        self.classification = detection.classification
        self.boundingBox = detection.boundingBox
        self.lastSeen = Date()

        let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        self.kalman = KalmanFilter2D(initialPosition: center)
    }

    /// Predict position for next frame
    func predict(dt: Double = 1.0/30.0) -> CGPoint {
        missStreak += 1
        hitStreak = 0

        // Update reliability based on miss streak
        reliabilityScore = max(0, 1.0 - Float(missStreak) / Float(Self.maxMisses))

        // Update state based on reliability
        if reliabilityScore < Self.reliabilityThreshold {
            state = .lost
        }
        if missStreak >= Self.maxMisses {
            state = .deleted
        }

        return kalman.predict(dt: dt)
    }

    /// Update with matched detection
    func update(detection: ClassifiedPerson) {
        let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        _ = kalman.update(measurement: center)

        boundingBox = detection.boundingBox
        classification = detection.classification
        lastSeen = Date()

        hitStreak += 1
        missStreak = 0
        reliabilityScore = min(1.0, reliabilityScore + 0.2)
        occlusionScore = max(0, occlusionScore - 0.3)

        // Confirm track after enough hits
        if state == .tentative && hitStreak >= Self.confirmHits {
            state = .confirmed
        }
        if state == .lost {
            state = .confirmed
        }
    }

    /// Calculate IoU with a detection for matching
    func iou(with detection: ClassifiedPerson) -> Float {
        let predicted = predictedBoundingBox
        let detected = detection.boundingBox

        let intersection = predicted.intersection(detected)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = predicted.width * predicted.height +
                       detected.width * detected.height - intersectionArea

        return Float(intersectionArea / unionArea)
    }

    /// Predicted bounding box based on Kalman position
    var predictedBoundingBox: CGRect {
        let center = kalman.position
        return CGRect(
            x: center.x - Double(boundingBox.width / 2),
            y: center.y - Double(boundingBox.height / 2),
            width: Double(boundingBox.width),
            height: Double(boundingBox.height)
        )
    }

    var isTrackable: Bool {
        state == .confirmed || state == .tentative
    }
}

// MARK: - Deep Tracker (SORT-style)

/// Multi-object tracker using SORT algorithm with Kalman filtering
/// Inspired by Deep Track 4.0's architecture
class DeepTracker {

    // All tracked objects
    private var tracks: [TrackedObject] = []
    private var nextTrackId = 0

    // Configuration
    private let iouThreshold: Float = 0.3  // Minimum IoU for matching
    private let maxTracks = 20             // Maximum simultaneous tracks

    // Recovery state
    private(set) var isInRecoveryMode = false
    private var recoveryStartTime: Date?
    private let recoveryTimeout: TimeInterval = 2.0  // 2 seconds max recovery

    // Group tracking (Deep Track 4.0 feature)
    var primaryTrackId: Int?

    // MARK: - Main Update

    /// Process new detections and update tracks
    /// Returns: Active tracks sorted by reliability
    func update(detections: [ClassifiedPerson], dt: Double = 1.0/30.0) -> [TrackedObject] {

        // 1. Predict all tracks forward
        for track in tracks {
            _ = track.predict(dt: dt)
        }

        // 2. Match detections to tracks using Hungarian algorithm (simplified greedy)
        let (matched, unmatchedTracks, unmatchedDetections) = matchDetectionsToTracks(detections)

        // 3. Update matched tracks
        for (trackIdx, detectionIdx) in matched {
            tracks[trackIdx].update(detection: detections[detectionIdx])
        }

        // 4. Handle unmatched tracks (potential occlusion)
        for trackIdx in unmatchedTracks {
            let track = tracks[trackIdx]
            // Increase occlusion score for unmatched confirmed tracks
            if track.state == .confirmed {
                track.occlusionScore = min(1.0, track.occlusionScore + 0.2)
            }
        }

        // 5. Create new tracks for unmatched detections
        for detectionIdx in unmatchedDetections {
            if tracks.count < maxTracks {
                let newTrack = TrackedObject(id: nextTrackId, detection: detections[detectionIdx])
                nextTrackId += 1
                tracks.append(newTrack)
            }
        }

        // 6. Remove deleted tracks
        tracks.removeAll { $0.state == .deleted }

        // 7. Update recovery mode
        updateRecoveryMode()

        // 8. Return active tracks
        return tracks.filter { $0.isTrackable }
                     .sorted { $0.reliabilityScore > $1.reliabilityScore }
    }

    // MARK: - Detection Matching (Greedy approximation of Hungarian)

    private func matchDetectionsToTracks(_ detections: [ClassifiedPerson])
        -> (matched: [(Int, Int)], unmatchedTracks: [Int], unmatchedDetections: [Int]) {

        guard !tracks.isEmpty && !detections.isEmpty else {
            return ([], Array(tracks.indices), Array(detections.indices))
        }

        // Build cost matrix (negative IoU for minimization)
        var costMatrix = [[Float]](repeating: [Float](repeating: 0, count: detections.count), count: tracks.count)

        for i in tracks.indices {
            for j in detections.indices {
                let iouScore = tracks[i].iou(with: detections[j])
                // Also consider classification match
                let classMatch: Float = tracks[i].classification == detections[j].classification ? 0.1 : 0
                costMatrix[i][j] = -(iouScore + classMatch)  // Negative for minimization
            }
        }

        // Greedy matching (simplified Hungarian)
        var matched: [(Int, Int)] = []
        var usedTracks = Set<Int>()
        var usedDetections = Set<Int>()

        // Sort all pairs by IoU (descending)
        var pairs: [(track: Int, detection: Int, iou: Float)] = []
        for i in tracks.indices {
            for j in detections.indices {
                let iou = tracks[i].iou(with: detections[j])
                if iou >= iouThreshold {
                    pairs.append((i, j, iou))
                }
            }
        }
        pairs.sort { $0.iou > $1.iou }

        // Greedily assign best matches
        for pair in pairs {
            if !usedTracks.contains(pair.track) && !usedDetections.contains(pair.detection) {
                matched.append((pair.track, pair.detection))
                usedTracks.insert(pair.track)
                usedDetections.insert(pair.detection)
            }
        }

        let unmatchedTracks = tracks.indices.filter { !usedTracks.contains($0) }
        let unmatchedDetections = detections.indices.filter { !usedDetections.contains($0) }

        return (matched, Array(unmatchedTracks), Array(unmatchedDetections))
    }

    // MARK: - Recovery Mode (Deep Track 4.0 feature)

    private func updateRecoveryMode() {
        // Enter recovery if primary track is lost
        if let primaryId = primaryTrackId,
           let primaryTrack = tracks.first(where: { $0.id == primaryId }) {

            if primaryTrack.state == .lost && !isInRecoveryMode {
                isInRecoveryMode = true
                recoveryStartTime = Date()
                debugPrint("[DeepTracker] 🔍 Entering recovery mode for track \(primaryId)")
            }

            if primaryTrack.state == .confirmed && isInRecoveryMode {
                isInRecoveryMode = false
                recoveryStartTime = nil
                debugPrint("[DeepTracker] ✅ Recovery successful for track \(primaryId)")
            }
        }

        // Timeout recovery
        if isInRecoveryMode, let start = recoveryStartTime {
            if Date().timeIntervalSince(start) > recoveryTimeout {
                isInRecoveryMode = false
                recoveryStartTime = nil
                primaryTrackId = nil
                debugPrint("[DeepTracker] ⚠️ Recovery timeout - lost primary track")
            }
        }
    }

    // MARK: - Group Tracking

    /// Get action center weighted by track reliability (Deep Track 4.0 style)
    func getActionCenter(filterPlayers: Bool = true) -> CGPoint {
        let activeTracks = tracks.filter { track in
            guard track.isTrackable else { return false }
            if filterPlayers {
                return track.classification == .player
            }
            return true
        }

        guard !activeTracks.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        var weightedX: Double = 0
        var weightedY: Double = 0
        var totalWeight: Double = 0

        for track in activeTracks {
            let pos = track.kalman.position
            var weight = Double(track.reliabilityScore)

            // Boost primary track
            if track.id == primaryTrackId {
                weight *= 2.0
            }

            // Weight by bounding box size (closer = bigger = more important)
            weight *= Double(track.boundingBox.width * track.boundingBox.height) * 100

            // Reduce weight for refs
            if track.classification == .referee {
                weight *= 0.3
            }

            weightedX += pos.x * weight
            weightedY += pos.y * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        return CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)
    }

    /// Get group bounding box (Deep Track 4.0's white envelope)
    func getGroupBoundingBox(filterPlayers: Bool = true) -> CGRect {
        let activeTracks = tracks.filter { track in
            guard track.isTrackable else { return false }
            if filterPlayers {
                return track.classification == .player
            }
            return true
        }

        guard !activeTracks.isEmpty else {
            return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for track in activeTracks {
            let box = track.predictedBoundingBox
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }

        // Add margin
        let margin: CGFloat = 0.05
        return CGRect(
            x: max(0, minX - margin),
            y: max(0, minY - margin),
            width: min(1, maxX - minX + 2 * margin),
            height: min(1, maxY - minY + 2 * margin)
        )
    }

    /// Calculate zoom based on player spread (Deep Track 4.0's Active Zoom)
    func calculateZoom(minZoom: CGFloat = 1.0, maxZoom: CGFloat = 2.0) -> CGFloat {
        let groupBox = getGroupBoundingBox()
        let spread = max(groupBox.width, groupBox.height)

        // Wide spread = zoom out, tight cluster = zoom in
        // spread of 0.8+ = full court = minZoom
        // spread of 0.2 = tight cluster = maxZoom
        let normalizedSpread = (spread - 0.2) / 0.6
        let clampedSpread = max(0, min(1, normalizedSpread))

        var zoom = maxZoom - (clampedSpread * (maxZoom - minZoom))

        // In recovery mode, zoom out to find subject (Deep Track 4.0 recovery strategy)
        if isInRecoveryMode {
            zoom = max(minZoom, zoom - 0.5)
        }

        return zoom
    }

    // MARK: - Stats

    var confirmedTrackCount: Int {
        tracks.filter { $0.state == .confirmed }.count
    }

    var playerTrackCount: Int {
        tracks.filter { $0.classification == .player && $0.isTrackable }.count
    }

    var refTrackCount: Int {
        tracks.filter { $0.classification == .referee && $0.isTrackable }.count
    }

    /// Average reliability of confirmed tracks
    var averageReliability: Float {
        let confirmed = tracks.filter { $0.state == .confirmed }
        guard !confirmed.isEmpty else { return 0 }
        return confirmed.map { $0.reliabilityScore }.reduce(0, +) / Float(confirmed.count)
    }

    // MARK: - Reset

    func reset() {
        tracks.removeAll()
        nextTrackId = 0
        primaryTrackId = nil
        isInRecoveryMode = false
        recoveryStartTime = nil
    }
}
