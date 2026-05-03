//
//  CourtHeatmapAccumulator.swift
//  SahilStatsLite
//
//  PURPOSE: Accumulates gimbal-compensated ankle positions during warmup and
//           derives a perspective-correct CourtQuad automatically — zero user input.
//
//  HOW IT WORKS:
//    1. During warmup, every standing player's ankle point (Vision coords) is fed in
//       alongside the phone's current yaw from CMMotionManager.
//    2. Yaw compensation maps each point into a stable "world reference frame" so
//       the heatmap isn't smeared by gimbal panning:
//         worldX = clamp(cameraX + (currentYaw - referenceYaw) / hFOV, 0, 1)
//    3. After minSamples ankle points, a convex hull is computed from the hot cells.
//    4. A quadrilateral is fitted to the hull (4-direction clustering).
//    5. The quad is locked once it's stable for 10 consecutive re-computes.
//
//  GIMBAL COMPENSATION:
//    The Insta360 Flow Pro 2 physically rotates the iPhone. The iPhone's own
//    gyroscope (CMMotionManager) reads this rotation directly — no need to
//    integrate velocity commands or model gimbal lag.
//    Only yaw (pan) is compensated; tilt range is small and doesn't meaningfully
//    smear the heatmap.
//
//  COORDINATE SYSTEM: Vision normalized, y=0 at BOTTOM.
//
//  DEPENDS ON: CoreGraphics (CourtQuad)

import CoreGraphics
import Foundation

final class CourtHeatmapAccumulator {

    // MARK: - Config

    /// Grid resolution. 40×40 gives ~2.5% per cell — fine enough to distinguish
    /// court vs sideline, coarse enough not to overfit to noisy detections.
    private let gridSize = 40

    /// iPhone 16 Pro Max main (1×) camera horizontal FOV ≈ 68° = 1.19 rad.
    /// Divide by zoom level if the user has zoomed in (Skynet zoom cap is 1.3×).
    var horizontalFOV: Double = 1.19

    /// Minimum ankle samples before attempting to compute a quad.
    let minSamples = 150

    /// Lock the quad once corners are stable within this fraction of frame width.
    private let stabilityThreshold: CGFloat = 0.03

    /// How many consecutive stable re-computes before we declare calibrated.
    private let stableRunRequired = 10

    // MARK: - State

    private(set) var grid: [[Int]]
    private(set) var totalSamples: Int = 0

    /// IMU reference yaw captured at first ankle sample (radians, CMMotionManager).
    private var referenceYaw: Double?

    /// Last computed quad for stability comparison.
    private var lastQuad: CourtQuad?
    private var stableRun: Int = 0

    /// Once locked, stops accumulating and re-computing.
    private(set) var isLocked: Bool = false
    private(set) var lockedQuad: CourtQuad?

    // MARK: - Init

    init() {
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
    }

    // MARK: - Accumulation

    /// Feed one standing ankle point with the phone's current yaw (from CMMotionManager).
    /// Call from inside SkynetProcessor — already serialized.
    func accumulate(anklePoint: CGPoint, currentYaw: Double) {
        guard !isLocked else { return }

        // Capture reference yaw on first sample
        if referenceYaw == nil { referenceYaw = currentYaw }
        let yawOffset = currentYaw - referenceYaw!

        // Compensate X for gimbal pan
        let compensatedX = anklePoint.x + CGFloat(yawOffset / horizontalFOV)
        let worldPoint = CGPoint(
            x: max(0, min(1, compensatedX)),
            y: max(0, min(1, anklePoint.y))
        )

        // Accumulate into grid
        let col = min(Int(worldPoint.x * CGFloat(gridSize)), gridSize - 1)
        let row = min(Int(worldPoint.y * CGFloat(gridSize)), gridSize - 1)
        grid[row][col] += 1
        totalSamples += 1
    }

    // MARK: - Quad Computation

    /// Attempt to compute a CourtQuad from current heatmap data.
    /// Returns nil if insufficient samples or geometry is degenerate.
    /// Call every 30 frames from SkynetProcessor.
    func computeCourtQuad() -> CourtQuad? {
        guard totalSamples >= minSamples else { return nil }

        let hotCells = extractHotCells()
        guard hotCells.count >= 4 else { return nil }

        let hull = convexHull(hotCells)
        guard hull.count >= 3 else { return nil }

        guard let quad = fitQuadToHull(hull) else { return nil }

        // Stability check
        if let last = lastQuad, isStable(quad, comparedTo: last) {
            stableRun += 1
            if stableRun >= stableRunRequired {
                var calibrated = quad
                calibrated.isCalibrated = true
                isLocked = true
                lockedQuad = calibrated
                return calibrated
            }
        } else {
            stableRun = 0
        }

        lastQuad = quad
        return quad
    }

    func reset() {
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        totalSamples = 0
        referenceYaw = nil
        lastQuad = nil
        stableRun = 0
        isLocked = false
        lockedQuad = nil
    }

    // MARK: - Hot Cell Extraction

    private func extractHotCells() -> [CGPoint] {
        let flat = grid.flatMap { $0 }
        let maxVal = flat.max() ?? 1
        // Threshold: cells with at least 25% of peak activity
        let cutoff = max(1, Int(Double(maxVal) * 0.25))

        // Skip the top 25% of frame (spectators in stands)
        // and bottom 5% (camera operator's feet / near foreground)
        let rowMin = Int(Double(gridSize) * 0.05)
        let rowMax = Int(Double(gridSize) * 0.75)

        var cells: [CGPoint] = []
        for row in rowMin..<rowMax {
            for col in 0..<gridSize {
                if grid[row][col] >= cutoff {
                    // Cell center in Vision coords
                    let x = (CGFloat(col) + 0.5) / CGFloat(gridSize)
                    let y = (CGFloat(row) + 0.5) / CGFloat(gridSize)
                    cells.append(CGPoint(x: x, y: y))
                }
            }
        }
        return cells
    }

    // MARK: - Convex Hull (Andrew's Monotone Chain)

    private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { a, b in
            a.x < b.x || (a.x == b.x && a.y < b.y)
        }
        guard sorted.count >= 3 else { return sorted }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count-2], lower[lower.count-1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count-2], upper[upper.count-1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    // MARK: - Quadrilateral Fitting (4-Direction Clustering)

    /// Fits a quadrilateral to the convex hull by clustering hull points into
    /// 4 directional groups and fitting a line to each, then intersecting adjacent lines.
    private func fitQuadToHull(_ hull: [CGPoint]) -> CourtQuad? {
        guard hull.count >= 4 else { return nil }

        // Find centroid
        let cx = hull.map(\.x).reduce(0, +) / CGFloat(hull.count)
        let cy = hull.map(\.y).reduce(0, +) / CGFloat(hull.count)
        let centroid = CGPoint(x: cx, y: cy)

        // Classify each hull point into one of 4 quadrants relative to centroid
        // Q0: bottom-left (nearLeft), Q1: top-left (farLeft),
        // Q2: top-right (farRight),  Q3: bottom-right (nearRight)
        var quadrants: [[CGPoint]] = [[], [], [], []]
        for p in hull {
            let dx = p.x - centroid.x
            let dy = p.y - centroid.y  // Vision: positive y = up
            let q: Int
            if dx <= 0 && dy <= 0 { q = 0 }       // bottom-left
            else if dx <= 0 && dy > 0  { q = 1 }   // top-left
            else if dx > 0  && dy > 0  { q = 2 }   // top-right
            else                        { q = 3 }   // bottom-right
            quadrants[q].append(p)
        }

        // Corner = average of each quadrant's extreme point(s)
        // Q0 nearLeft:  min x, min y
        // Q1 farLeft:   min x, max y
        // Q2 farRight:  max x, max y
        // Q3 nearRight: max x, min y
        func extremePoint(_ pts: [CGPoint], maxX: Bool, maxY: Bool) -> CGPoint? {
            guard !pts.isEmpty else { return nil }
            if maxX && maxY  { return pts.max(by: { ($0.x + $0.y) < ($1.x + $1.y) }) }
            if !maxX && maxY { return pts.max(by: { (-$0.x + $0.y) < (-$1.x + $1.y) }) }
            if maxX && !maxY { return pts.max(by: { ($0.x - $0.y) < ($1.x - $1.y) }) }
            return pts.min(by: { ($0.x + $0.y) < ($1.x + $1.y) })
        }

        guard
            let nearLeft  = extremePoint(quadrants[0].isEmpty ? hull : quadrants[0], maxX: false, maxY: false),
            let farLeft   = extremePoint(quadrants[1].isEmpty ? hull : quadrants[1], maxX: false, maxY: true),
            let farRight  = extremePoint(quadrants[2].isEmpty ? hull : quadrants[2], maxX: true,  maxY: true),
            let nearRight = extremePoint(quadrants[3].isEmpty ? hull : quadrants[3], maxX: true,  maxY: false)
        else { return nil }

        return CourtQuad(
            nearLeft:  nearLeft,
            farLeft:   farLeft,
            farRight:  farRight,
            nearRight: nearRight
        )
    }

    // MARK: - Stability

    private func isStable(_ a: CourtQuad, comparedTo b: CourtQuad) -> Bool {
        let pairs: [(CGPoint, CGPoint)] = [
            (a.nearLeft, b.nearLeft), (a.farLeft, b.farLeft),
            (a.farRight, b.farRight), (a.nearRight, b.nearRight)
        ]
        return pairs.allSatisfy { (p, q) in
            let dx = abs(p.x - q.x)
            let dy = abs(p.y - q.y)
            return dx < stabilityThreshold && dy < stabilityThreshold
        }
    }
}
