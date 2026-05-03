//
//  CourtQuad.swift
//  SahilStatsLite
//
//  PURPOSE: Perspective-correct quadrilateral representing the basketball court
//           boundary as the camera sees it. Replaces the axis-aligned CGRect
//           (courtBounds) which failed from bleachers/corners where the court
//           appears as a trapezoid.
//
//  COORDINATE SYSTEM: Vision normalized (x,y ∈ [0,1], y=0 at BOTTOM).
//  Points are stored clockwise: bottomLeft, topLeft, topRight, bottomRight
//  where "top" = further from camera (far end of court) and "bottom" = near.
//
//  DEPENDS ON: CoreGraphics

import CoreGraphics

struct CourtQuad {

    // Corners in Vision normalized coords (y=0 at bottom).
    // Named by position relative to camera (not absolute court position):
    //   near = closer to camera, far = further away
    var nearLeft:  CGPoint
    var farLeft:   CGPoint
    var farRight:  CGPoint
    var nearRight: CGPoint

    /// True once enough warmup data has produced a calibrated quad.
    /// False = still using the default fallback rectangle.
    var isCalibrated: Bool = false

    // MARK: - Default

    /// Fallback when no calibration has run yet. Matches the previous
    /// courtBounds default but expressed as a quad.
    static func defaultBounds() -> CourtQuad {
        CourtQuad(
            nearLeft:  CGPoint(x: 0.15, y: 0.10),
            farLeft:   CGPoint(x: 0.15, y: 0.65),
            farRight:  CGPoint(x: 0.85, y: 0.65),
            nearRight: CGPoint(x: 0.85, y: 0.10),
            isCalibrated: false
        )
    }

    // MARK: - Containment

    /// Returns true if point p is inside this convex quadrilateral.
    /// Uses cross-product sign test — all four edges must have the same winding.
    /// O(1), no allocations. Safe to call at 15fps per detection.
    func contains(_ p: CGPoint) -> Bool {
        // Edges in clockwise order
        let edges: [(CGPoint, CGPoint)] = [
            (nearLeft,  farLeft),
            (farLeft,   farRight),
            (farRight,  nearRight),
            (nearRight, nearLeft)
        ]
        // Point is inside if it's on the left side of every clockwise edge
        // (cross product < 0 for all, since we're clockwise)
        for (a, b) in edges {
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross > 0 { return false }  // outside this edge
        }
        return true
    }

    // MARK: - Legacy shim

    /// Axis-aligned bounding rect — used as fallback for any callers that
    /// still expect a CGRect (e.g., heatmap visualization).
    var boundingRect: CGRect {
        let xs = [nearLeft.x, farLeft.x, farRight.x, nearRight.x]
        let ys = [nearLeft.y, farLeft.y, farRight.y, nearRight.y]
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// CGPath for debug overlay rendering.
    var cgPath: CGPath {
        let path = CGMutablePath()
        path.move(to: nearLeft)
        path.addLine(to: farLeft)
        path.addLine(to: farRight)
        path.addLine(to: nearRight)
        path.closeSubpath()
        return path
    }
}
