//
//  DeepTracker.swift
//  SahilStatsLite
//
//  PURPOSE: SORT-style multi-object tracking with Kalman filtering. Maintains
//           persistent track IDs across frames, scores reliability/occlusion,
//           and provides Kalman-smoothed action center and group bounding box.
//  KEY TYPES: KalmanFilter2D, TrackedObject, DeepTracker
//  DEPENDS ON: PersonClassifier (ClassifiedPerson), Accelerate
//
//  ALGORITHMS: Extended Kalman filter (pos+vel+accel), Hungarian matching,
//              ByteTrack low-confidence re-matching, OC-SORT recovery.
//  REFERENCES: Insta360 US11509824B2, SORT (Bewley), OC-SORT (Cao, CVPR 2023)
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import CoreGraphics
import Accelerate

// MARK: - Kalman Filter (2D position + velocity)

/// Kalman filter for tracking a single object's position and velocity
/// State: [x, y, vx, vy] (position and velocity)
/// Measurement: [x, y] (position only from detection)
/// Tuned for basketball player tracking:
/// - Players have continuous motion with gradual acceleration
/// - Detection jitter from Apple Vision is moderate (~1-2%)
/// - Players rarely exceed ~0.5 screen widths per second
class KalmanFilter2D {

    // State vector: [x, y, vx, vy]
    private var state: [Double]

    // State covariance matrix (4x4)
    private var P: [[Double]]

    // Process noise covariance (tuned for player motion)
    private var Q: [[Double]]

    // Measurement noise covariance (tuned for Vision API)
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

        // Initial covariance
        // Low position uncertainty (detection is accurate)
        // High velocity uncertainty (unknown initial motion)
        P = [
            [0.01, 0, 0, 0],
            [0, 0.01, 0, 0],
            [0, 0, 0.5, 0],
            [0, 0, 0, 0.5]
        ]

        // Process noise (tuned for player motion)
        // Players accelerate gradually - lower noise than ball
        // Horizontal: running, cutting (~0.02 acceleration noise)
        // Vertical: jumping, less common (~0.015)
        Q = [
            [0.0002, 0, 0, 0],    // Position noise
            [0, 0.0002, 0, 0],
            [0, 0, 0.02, 0],      // Velocity noise (horizontal)
            [0, 0, 0, 0.015]      // Velocity noise (vertical - less jumping)
        ]

        // Measurement noise (Apple Vision API detection uncertainty)
        // Vision API has good accuracy but some jitter between frames
        let r = 0.004  // ~0.4% of frame = typical Vision API jitter
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

        // Clamp covariance to prevent numerical explosion
        for i in 0..<4 {
            P[i][i] = min(P[i][i], i < 2 ? 0.5 : 2.0)
        }

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

/// A single tracked object with Kalman filter and OC-SORT enhancements
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

    // OC-SORT: Observation-Centric Momentum (OCM)
    // Store last observed positions instead of relying solely on Kalman predictions
    // This handles camera motion better than pure Kalman prediction
    private var observationHistory: [CGPoint] = []
    private let observationHistorySize = 5
    var lastObservedPosition: CGPoint?
    var observationMomentum: CGPoint = .zero  // Velocity from observations, not Kalman

    // Virtual trajectory for recovery (OC-SORT)
    // When track is lost, continue along observation momentum
    var virtualTrajectory: [CGPoint] = []

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
        self.lastObservedPosition = center
        self.observationHistory = [center]
    }

    /// Predict position for next frame
    /// OC-SORT enhancement: Uses observation momentum when available
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

        let kalmanPrediction = kalman.predict(dt: dt)

        // OC-SORT: Generate virtual trajectory point when lost
        // Uses observation momentum instead of Kalman prediction
        if state == .lost, let lastObs = lastObservedPosition {
            let virtualPoint = CGPoint(
                x: lastObs.x + observationMomentum.x * Double(missStreak) * dt,
                y: lastObs.y + observationMomentum.y * Double(missStreak) * dt
            )
            virtualTrajectory.append(virtualPoint)
            return virtualPoint
        }

        return kalmanPrediction
    }

    /// Update with matched detection
    /// OC-SORT enhancement: Updates observation history and momentum
    func update(detection: ClassifiedPerson) {
        let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        _ = kalman.update(measurement: center)

        boundingBox = detection.boundingBox
        classification = detection.classification
        lastSeen = Date()

        // OC-SORT: Update observation history and calculate momentum
        if let lastObs = lastObservedPosition {
            // Calculate observation-based velocity (handles camera motion better)
            observationMomentum = CGPoint(
                x: (center.x - lastObs.x) / (1.0 / 30.0),  // Velocity per second
                y: (center.y - lastObs.y) / (1.0 / 30.0)
            )
        }

        lastObservedPosition = center
        observationHistory.append(center)
        if observationHistory.count > observationHistorySize {
            observationHistory.removeFirst()
        }

        // Clear virtual trajectory on successful match
        virtualTrajectory.removeAll()

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

    /// OC-SORT: Get observation-centric bounding box for matching
    /// Uses observation momentum instead of Kalman prediction for better camera motion handling
    var observationCentricBox: CGRect {
        guard let lastObs = lastObservedPosition else {
            return predictedBoundingBox
        }

        // Predict position using observation momentum
        let dt = 1.0 / 30.0
        let predictedCenter = CGPoint(
            x: lastObs.x + observationMomentum.x * dt,
            y: lastObs.y + observationMomentum.y * dt
        )

        return CGRect(
            x: predictedCenter.x - Double(boundingBox.width / 2),
            y: predictedCenter.y - Double(boundingBox.height / 2),
            width: Double(boundingBox.width),
            height: Double(boundingBox.height)
        )
    }

    /// Calculate IoU with a detection for matching
    /// OC-SORT enhancement: Uses observation-centric box when available
    func iou(with detection: ClassifiedPerson, useObservationCentric: Bool = true) -> Float {
        // OC-SORT: Use observation-centric box for better camera motion handling
        let predicted = useObservationCentric ? observationCentricBox : predictedBoundingBox
        let detected = detection.boundingBox

        let intersection = predicted.intersection(detected)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = predicted.width * predicted.height +
                       detected.width * detected.height - intersectionArea

        return Float(intersectionArea / unionArea)
    }

    /// OC-SORT: Calculate velocity consistency score
    /// Higher score if detection's velocity matches track's observation momentum
    func velocityConsistency(with detection: ClassifiedPerson, previousDetection: CGPoint?) -> Float {
        guard let prevDet = previousDetection else { return 0.5 }

        let detectedCenter = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        let detectionVelocity = CGPoint(
            x: (detectedCenter.x - prevDet.x) * 30.0,  // Per second
            y: (detectedCenter.y - prevDet.y) * 30.0
        )

        // Compare with observation momentum
        let vDiff = hypot(
            detectionVelocity.x - observationMomentum.x,
            detectionVelocity.y - observationMomentum.y
        )

        // Normalize: 0 diff = 1.0 score, large diff = 0.0 score
        return Float(max(0, 1.0 - vDiff / 2.0))
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

// MARK: - Hungarian Algorithm (Kuhn-Munkres)

/// Optimal assignment solver for detection-to-track matching
/// O(n^3) complexity but handles typical basketball tracking (< 20 objects) easily
struct HungarianAlgorithm {

    /// Solve the linear assignment problem
    /// - Parameter costMatrix: n x m matrix where costMatrix[i][j] is cost of assigning row i to col j
    /// - Returns: Array of (row, col) assignments that minimize total cost
    static func solve(costMatrix: [[Float]]) -> [(row: Int, col: Int)] {
        guard !costMatrix.isEmpty, !costMatrix[0].isEmpty else { return [] }

        let n = costMatrix.count
        let m = costMatrix[0].count
        let size = max(n, m)

        // Pad to square matrix with high costs
        var cost = [[Float]](repeating: [Float](repeating: Float.greatestFiniteMagnitude / 2, count: size), count: size)
        for i in 0..<n {
            for j in 0..<m {
                cost[i][j] = costMatrix[i][j]
            }
        }

        // Hungarian algorithm state
        var u = [Float](repeating: 0, count: size + 1)
        var v = [Float](repeating: 0, count: size + 1)
        var p = [Int](repeating: 0, count: size + 1)  // p[j] = row assigned to col j
        var way = [Int](repeating: 0, count: size + 1)

        for i in 1...size {
            p[0] = i
            var j0 = 0
            var minv = [Float](repeating: Float.greatestFiniteMagnitude, count: size + 1)
            var used = [Bool](repeating: false, count: size + 1)

            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Float.greatestFiniteMagnitude
                var j1 = 0

                for j in 1...size {
                    if !used[j] {
                        let cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                        if cur < minv[j] {
                            minv[j] = cur
                            way[j] = j0
                        }
                        if minv[j] < delta {
                            delta = minv[j]
                            j1 = j
                        }
                    }
                }

                for j in 0...size {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }

                j0 = j1
            } while p[j0] != 0

            // Trace back
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }

        // Extract assignments
        var assignments: [(row: Int, col: Int)] = []
        for j in 1...size {
            if p[j] > 0 && p[j] <= n && j <= m {
                assignments.append((p[j] - 1, j - 1))
            }
        }

        return assignments
    }
}

// MARK: - Deep Tracker (OC-SORT enhanced)

/// Multi-object tracker using OC-SORT algorithm with Kalman filtering
/// Inspired by Deep Track 4.0's architecture with OC-SORT enhancements
class DeepTracker {

    // All tracked objects
    private var tracks: [TrackedObject] = []
    private var nextTrackId = 0

    // Configuration
    private let iouThreshold: Float = 0.3  // Minimum IoU for matching
    private let maxTracks = 20             // Maximum simultaneous tracks

    // OC-SORT: Previous frame detections for velocity matching
    private var previousDetections: [Int: CGPoint] = [:]  // trackId -> last position

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

        // 2. Match detections to tracks using Hungarian algorithm with OC-SORT
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

        // 6. Remove deleted tracks and update previous detections
        let deletedIds = Set(tracks.filter { $0.state == .deleted }.map { $0.id })
        for id in deletedIds {
            previousDetections.removeValue(forKey: id)
        }
        tracks.removeAll { $0.state == .deleted }

        // 7. OC-SORT: Store current positions for next frame's velocity matching
        for track in tracks where track.isTrackable {
            if let lastObs = track.lastObservedPosition {
                previousDetections[track.id] = lastObs
            }
        }

        // 8. Update recovery mode
        updateRecoveryMode()

        // 9. Return active tracks
        return tracks.filter { $0.isTrackable }
                     .sorted { $0.reliabilityScore > $1.reliabilityScore }
    }

    // MARK: - Detection Matching (Hungarian Algorithm with OC-SORT)

    private func matchDetectionsToTracks(_ detections: [ClassifiedPerson])
        -> (matched: [(Int, Int)], unmatchedTracks: [Int], unmatchedDetections: [Int]) {

        guard !tracks.isEmpty && !detections.isEmpty else {
            return ([], Array(tracks.indices), Array(detections.indices))
        }

        // Build cost matrix using OC-SORT-style scoring
        // Cost = 1 - (IoU + velocity_consistency + class_match) / 3
        var costMatrix = [[Float]](repeating: [Float](repeating: 1.0, count: detections.count), count: tracks.count)

        for i in tracks.indices {
            for j in detections.indices {
                // OC-SORT: Use observation-centric IoU
                let iouScore = tracks[i].iou(with: detections[j], useObservationCentric: true)

                // Velocity consistency (OC-SORT enhancement)
                let prevDetPos = previousDetections[tracks[i].id]
                let velocityScore = tracks[i].velocityConsistency(with: detections[j], previousDetection: prevDetPos)

                // Classification match bonus
                let classMatch: Float = tracks[i].classification == detections[j].classification ? 0.2 : 0

                // Combined score (higher is better, convert to cost)
                let combinedScore = (iouScore * 0.5) + (velocityScore * 0.3) + classMatch
                costMatrix[i][j] = 1.0 - combinedScore
            }
        }

        // Use Hungarian algorithm for optimal assignment
        let assignments = HungarianAlgorithm.solve(costMatrix: costMatrix)

        // Filter by threshold and classify matches
        var matched: [(Int, Int)] = []
        var usedTracks = Set<Int>()
        var usedDetections = Set<Int>()

        for (trackIdx, detectionIdx) in assignments {
            // Only accept if IoU meets threshold
            let iou = tracks[trackIdx].iou(with: detections[detectionIdx], useObservationCentric: true)
            if iou >= iouThreshold {
                matched.append((trackIdx, detectionIdx))
                usedTracks.insert(trackIdx)
                usedDetections.insert(detectionIdx)
            }
        }

        // OC-SORT: Second pass - try matching lost tracks with virtual trajectories
        let unmatchedTrackIndices = tracks.indices.filter { !usedTracks.contains($0) }
        let unmatchedDetectionIndices = detections.indices.filter { !usedDetections.contains($0) }

        // Try to recover lost tracks using virtual trajectory
        for trackIdx in unmatchedTrackIndices {
            let track = tracks[trackIdx]
            if track.state == .lost && !track.virtualTrajectory.isEmpty {
                // Find detection near virtual trajectory endpoint
                for detIdx in unmatchedDetectionIndices where !usedDetections.contains(detIdx) {
                    let detection = detections[detIdx]
                    let detCenter = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)

                    // Check distance to last virtual position
                    if let virtualPos = track.virtualTrajectory.last {
                        let distance = hypot(detCenter.x - virtualPos.x, detCenter.y - virtualPos.y)
                        if distance < 0.1 {  // Within 10% of frame
                            matched.append((trackIdx, detIdx))
                            usedTracks.insert(trackIdx)
                            usedDetections.insert(detIdx)
                            break
                        }
                    }
                }
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
        previousDetections.removeAll()
    }
}
