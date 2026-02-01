//
//  AutoZoomManager.swift
//  SahilStatsLite
//
//  Intelligent Vision-based auto-zoom for basketball recording
//  Works independently of gimbal - uses on-device ML to track players
//

import Foundation
import AVFoundation
import Vision
import Combine

// MARK: - Auto Zoom Mode

enum AutoZoomMode: String, CaseIterable, Sendable {
    case off = "Off"
    case smooth = "Smooth"
    case responsive = "Responsive"

    var icon: String {
        switch self {
        case .off: return "viewfinder"
        case .smooth: return "viewfinder.circle"
        case .responsive: return "viewfinder.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .off: return "Manual zoom only"
        case .smooth: return "Gentle, cinematic zoom"
        case .responsive: return "Quick follow action"
        }
    }

    // How fast zoom approaches target (0.0 - 1.0)
    var smoothingFactor: CGFloat {
        switch self {
        case .off: return 0
        case .smooth: return 0.03      // Very smooth, cinematic
        case .responsive: return 0.12  // Quick reaction
        }
    }

    // Minimum change before triggering zoom adjustment
    var hysteresis: CGFloat {
        switch self {
        case .off: return 999
        case .smooth: return 0.3   // Larger deadzone = less jitter
        case .responsive: return 0.15
        }
    }
}

// MARK: - Auto Zoom Manager

@MainActor
final class AutoZoomManager: ObservableObject {
    static let shared = AutoZoomManager()

    // MARK: - Published State

    @Published var mode: AutoZoomMode = .smooth
    @Published var isProcessing: Bool = false
    @Published var currentZoom: CGFloat = 1.0
    @Published var targetZoom: CGFloat = 1.0
    @Published var detectedPlayerCount: Int = 0
    @Published var actionZoneCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // Debug visualization (for AI Lab)
    @Published var debugActionZone: CGRect = .zero
    @Published var showDebugOverlay: Bool = false

    // MARK: - Zoom Limits

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    // MARK: - Processing State (nonisolated for background thread access)

    private nonisolated(unsafe) var lastProcessTime: CFAbsoluteTime = 0
    private let processInterval: CFAbsoluteTime = 0.25  // 4 FPS for detection
    private var smoothZoomTimer: Timer?
    private var recentZoomTargets: [CGFloat] = []  // Rolling average for stability
    private let rollingAverageCount = 5

    // MARK: - Vision (created fresh each time to avoid threading issues)

    private func createHumanDetectionRequest() -> VNDetectHumanRectanglesRequest {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Control

    func start() {
        guard mode != .off else { return }
        isProcessing = true
        currentZoom = RecordingManager.shared.getCurrentZoom()
        targetZoom = currentZoom
        recentZoomTargets = []
        startSmoothZoomLoop()
        debugPrint("🔍 [AutoZoom] Started in \(mode.rawValue) mode")
    }

    func stop() {
        isProcessing = false
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = nil
        debugPrint("🔍 [AutoZoom] Stopped")
    }

    // MARK: - Frame Processing

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Throttle processing
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessTime >= processInterval else { return }
        lastProcessTime = now

        // Create fresh request for this frame (thread-safe)
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        // Run Vision detection
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results, !results.isEmpty else {
                Task { @MainActor in
                    self.handleNoPlayers()
                }
                return
            }

            let boxes = results.map { $0.boundingBox }

            Task { @MainActor in
                self.analyzePlayerPositions(boxes)
            }

        } catch {
            debugPrint("🔍 [AutoZoom] Vision error: \(error)")
        }
    }

    // MARK: - Analysis

    private func analyzePlayerPositions(_ boxes: [CGRect]) {
        guard mode != .off else { return }

        detectedPlayerCount = boxes.count

        guard !boxes.isEmpty else {
            handleNoPlayers()
            return
        }

        // Calculate action zone - bounding box containing all players
        let actionZone = calculateActionZone(boxes)
        debugActionZone = actionZone

        // Find centroid of all players
        let centroid = calculateCentroid(boxes)
        actionZoneCenter = centroid

        // Calculate optimal zoom based on player spread and position
        let optimalZoom = calculateOptimalZoom(
            actionZone: actionZone,
            centroid: centroid,
            playerCount: boxes.count
        )

        // Add to rolling average for stability
        updateTargetZoom(optimalZoom)
    }

    private func handleNoPlayers() {
        detectedPlayerCount = 0
        // When no players detected, slowly drift toward wide shot
        // Don't immediately zoom out - might be momentary detection gap
        if recentZoomTargets.count > 3 {
            updateTargetZoom(max(minZoom, currentZoom - 0.1))
        }
    }

    private func calculateActionZone(_ boxes: [CGRect]) -> CGRect {
        guard !boxes.isEmpty else { return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for box in boxes {
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }

        // Add margin (10% on each side)
        let margin: CGFloat = 0.1
        minX = max(0, minX - margin)
        minY = max(0, minY - margin)
        maxX = min(1, maxX + margin)
        maxY = min(1, maxY + margin)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func calculateCentroid(_ boxes: [CGRect]) -> CGPoint {
        guard !boxes.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for box in boxes {
            sumX += box.midX
            sumY += box.midY
        }

        return CGPoint(
            x: sumX / CGFloat(boxes.count),
            y: sumY / CGFloat(boxes.count)
        )
    }

    private func calculateOptimalZoom(actionZone: CGRect, centroid: CGPoint, playerCount: Int) -> CGFloat {
        // Key insight: Zoom is inversely proportional to action zone size
        // Large spread = zoom out, tight cluster = zoom in

        // Use the larger dimension (usually width for basketball)
        let spread = max(actionZone.width, actionZone.height)

        // Basketball-specific logic:
        // - Full court action (spread > 0.7) → stay wide at 1.0x
        // - Half court (spread 0.4-0.7) → moderate zoom 1.3-1.8x
        // - Around the key (spread < 0.4) → tighter zoom 1.8-2.5x

        let optimalZoom: CGFloat

        if spread > 0.7 {
            // Wide spread - full court action
            optimalZoom = 1.0
        } else if spread > 0.5 {
            // Medium spread - transition zone
            let t = (spread - 0.5) / 0.2  // 0 to 1
            optimalZoom = 1.5 - (t * 0.5)  // 1.5 down to 1.0
        } else if spread > 0.3 {
            // Moderate cluster - half court
            let t = (spread - 0.3) / 0.2  // 0 to 1
            optimalZoom = 2.0 - (t * 0.5)  // 2.0 down to 1.5
        } else {
            // Tight cluster - around the basket
            let t = spread / 0.3  // 0 to 1
            optimalZoom = 2.5 - (t * 0.5)  // 2.5 down to 2.0
        }

        // Player count modifier:
        // More players usually means more action spread
        // Fewer players = can zoom in more
        let playerModifier: CGFloat
        if playerCount <= 2 {
            playerModifier = 1.15  // Zoom in more for 1-2 players
        } else if playerCount >= 6 {
            playerModifier = 0.9   // Zoom out a bit for many players
        } else {
            playerModifier = 1.0
        }

        let finalZoom = (optimalZoom * playerModifier).clamped(to: minZoom...maxZoom)

        return finalZoom
    }

    // MARK: - Zoom Control

    private func updateTargetZoom(_ newTarget: CGFloat) {
        // Add to rolling average for stability
        recentZoomTargets.append(newTarget)
        if recentZoomTargets.count > rollingAverageCount {
            recentZoomTargets.removeFirst()
        }

        // Calculate smoothed target
        let smoothedTarget = recentZoomTargets.reduce(0, +) / CGFloat(recentZoomTargets.count)

        // Apply hysteresis - only update if change is significant
        guard abs(smoothedTarget - targetZoom) > mode.hysteresis else { return }

        targetZoom = smoothedTarget
        debugPrint("🔍 [AutoZoom] Target: \(String(format: "%.1f", targetZoom))x (players: \(detectedPlayerCount))")
    }

    private func startSmoothZoomLoop() {
        smoothZoomTimer?.invalidate()

        // 60 FPS smooth zoom updates
        smoothZoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateZoomSmooth()
            }
        }
    }

    private func updateZoomSmooth() {
        guard isProcessing, mode != .off else { return }

        let diff = targetZoom - currentZoom

        // If close enough, snap to target
        if abs(diff) < 0.01 {
            if currentZoom != targetZoom {
                currentZoom = targetZoom
                _ = RecordingManager.shared.setZoom(factor: currentZoom)
            }
            return
        }

        // Ease toward target
        let easedZoom = currentZoom + (diff * mode.smoothingFactor)
        currentZoom = easedZoom.clamped(to: minZoom...maxZoom)

        _ = RecordingManager.shared.setZoom(factor: currentZoom)
    }

    // MARK: - Manual Override

    /// Temporarily override auto-zoom (e.g., user pinch gesture)
    func manualZoomOverride(_ zoom: CGFloat) {
        currentZoom = zoom.clamped(to: minZoom...maxZoom)
        targetZoom = currentZoom
        recentZoomTargets = [currentZoom]  // Reset history
    }
}

// MARK: - CGFloat Extension

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
