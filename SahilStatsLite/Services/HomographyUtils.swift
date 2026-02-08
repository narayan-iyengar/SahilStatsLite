//
//  HomographyUtils.swift
//  SahilStatsLite
//
//  PURPOSE: Geometric utilities for mapping 2D screen coordinates to a virtual
//           court plane. Used for "Zone Mapping" (defining court boundaries).
//  KEY TYPES: CourtGeometry, HomographyUtils
//  DEPENDS ON: CoreGraphics
//

import Foundation
import CoreGraphics

// MARK: - Court Geometry

struct CourtGeometry: Codable, Equatable {
    // Normalized coordinates (0-1) of the 4 court corners in the camera view
    // Order: TopLeft, TopRight, BottomRight, BottomLeft
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    
    // Default: Full screen
    static let fullScreen = CourtGeometry(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 1, y: 0),
        bottomRight: CGPoint(x: 1, y: 1),
        bottomLeft: CGPoint(x: 0, y: 1)
    )
    
    // Check if a point is inside the quadrilateral (Ray Casting algorithm)
    func contains(_ point: CGPoint) -> Bool {
        let polygon = [topLeft, topRight, bottomRight, bottomLeft]
        var isInside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if (polygon[i].y > point.y) != (polygon[j].y > point.y) &&
                (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x) {
                isInside = !isInside
            }
            j = i
        }
        
        return isInside
    }
}

// MARK: - Homography Utils

class HomographyUtils {
    
    /// Calculate the centroid of a quadrilateral
    static func centroid(of geometry: CourtGeometry) -> CGPoint {
        let x = (geometry.topLeft.x + geometry.topRight.x + geometry.bottomRight.x + geometry.bottomLeft.x) / 4
        let y = (geometry.topLeft.y + geometry.topRight.y + geometry.bottomRight.y + geometry.bottomLeft.y) / 4
        return CGPoint(x: x, y: y)
    }
}
