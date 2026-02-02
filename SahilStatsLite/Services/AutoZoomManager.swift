//
//  AutoZoomManager.swift
//  SahilStatsLite
//
//  Intelligent Vision-based auto-zoom for basketball recording
//  Works independently of gimbal - uses on-device ML to track players
//
//  Updated with ultra-smooth zoom controller (validated through testing):
//  - 1% per frame zoom rate for broadcast-quality smoothness
//  - Velocity-based momentum for natural movement
//  - Dead zone to prevent micro-adjustments
//  - Confidence streak requirement to avoid reacting to noise
//

import Foundation
import AVFoundation
import Vision
import Combine

// MARK: - Ultra-Smooth Zoom Controller

/// Broadcast-quality zoom smoothing that prevents jarring zoom changes
/// Uses velocity-based smoothing with configurable speed limits
class UltraSmoothZoomController {

    // Current smoothed zoom level
    private var smoothZoom: Double = 1.0

    // Velocity for momentum-based smoothing
    private var zoomVelocity: Double = 0

    // Configuration (validated through testing)
    private let zoomSmoothing: Double = 0.01    // 1% per frame - very smooth
    private let velocityDamping: Double = 0.9   // Momentum decay
    private let deadZone: Double = 0.03         // 3% dead zone for zoom
    private let maxZoomSpeed: Double = 0.008    // Max zoom change per frame

    // Zoom limits
    let minZoom: Double
    let maxZoom: Double

    // Target from detection
    private var targetZoom: Double = 1.0

    // Confidence tracking
    private var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 3     // Require 3 consistent frames for zoom

    init(minZoom: Double = 1.0, maxZoom: Double = 1.6) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.smoothZoom = minZoom
    }

    /// Update with new target zoom
    /// - Parameters:
    ///   - target: Recommended zoom level from detection
    ///   - confidence: Detection confidence (0-1)
    /// - Returns: Smoothed zoom level
    func update(target: Double, confidence: Float) -> Double {
        // Track confidence streak
        if confidence > 0.4 {
            highConfidenceStreak += 1
        } else {
            highConfidenceStreak = max(0, highConfidenceStreak - 2)  // Decay faster
        }

        // Only update target if we have consistent high-confidence detections
        if highConfidenceStreak >= minStreakForUpdate {
            // Clamp target to valid range
            targetZoom = max(minZoom, min(maxZoom, target))
        }

        // Calculate distance to target
        let delta = targetZoom - smoothZoom

        // Dead zone - ignore tiny zoom changes
        if abs(delta) < deadZone {
            // Just decay velocity
            zoomVelocity *= velocityDamping
        } else {
            // Calculate new velocity toward target
            let direction = delta > 0 ? 1.0 : -1.0

            // Smooth acceleration toward target
            zoomVelocity += direction * zoomSmoothing

            // Apply velocity damping
            zoomVelocity *= velocityDamping

            // Clamp velocity to max speed
            if abs(zoomVelocity) > maxZoomSpeed {
                zoomVelocity = direction * maxZoomSpeed
            }
        }

        // Apply velocity to zoom
        smoothZoom += zoomVelocity

        // Clamp to valid range
        smoothZoom = max(minZoom, min(maxZoom, smoothZoom))

        return smoothZoom
    }

    /// Get current smoothed zoom without updating
    var currentZoom: Double { smoothZoom }

    /// Reset to minimum zoom
    func reset() {
        smoothZoom = minZoom
        zoomVelocity = 0
        targetZoom = minZoom
        highConfidenceStreak = 0
    }
}

// MARK: - Auto Zoom Mode

enum AutoZoomMode: String, CaseIterable, Sendable {
    case off = "Off"
    case auto = "Auto"  // Skynet: Kalman tracking, filters refs/adults

    var icon: String {
        switch self {
        case .off: return "viewfinder"
        case .auto: return "brain.head.profile"
        }
    }

    var description: String {
        switch self {
        case .off: return "Manual zoom only"
        case .auto: return "AI tracks players, ignores refs/adults"
        }
    }

    // How fast zoom approaches target (0.0 - 1.0)
    var smoothingFactor: CGFloat {
        switch self {
        case .off: return 0
        case .auto: return 0.08  // Balanced - Kalman handles the smoothing
        }
    }

    // Minimum change before triggering zoom adjustment
    var hysteresis: CGFloat {
        switch self {
        case .off: return 999
        case .auto: return 0.2
        }
    }
}

// MARK: - Auto Zoom Manager

@MainActor
final class AutoZoomManager: ObservableObject {
    static let shared = AutoZoomManager()

    // MARK: - Published State

    @Published var mode: AutoZoomMode = .auto
    @Published var isProcessing: Bool = false
    @Published var currentZoom: CGFloat = 1.0
    @Published var targetZoom: CGFloat = 1.0
    @Published var detectedPlayerCount: Int = 0
    @Published var actionZoneCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

    // Debug visualization (for AI Lab)
    @Published var debugActionZone: CGRect = .zero
    @Published var showDebugOverlay: Bool = false

    // Skynet-specific stats
    @Published var filteredRefCount: Int = 0
    @Published var filteredAdultCount: Int = 0

    // MARK: - Zoom Limits

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    // MARK: - Processing State (nonisolated for background thread access)

    private nonisolated(unsafe) var lastProcessTime: CFAbsoluteTime = 0
    private let processInterval: CFAbsoluteTime = 0.25  // 4 FPS for detection
    private var smoothZoomTimer: Timer?
    private var recentZoomTargets: [CGFloat] = []  // Rolling average for stability
    private let rollingAverageCount = 5

    // MARK: - Skynet (Deep Track 4.0-inspired tracking)

    private let personClassifier = PersonClassifier()
    private let deepTracker = DeepTracker()

    // Ultra-smooth zoom controller (validated through testing)
    private let smoothZoomController = UltraSmoothZoomController(minZoom: 1.0, maxZoom: 1.6)

    // Skynet tracking stats
    @Published var trackingReliability: Float = 0
    @Published var isInRecoveryMode: Bool = false
    @Published var confirmedTracks: Int = 0

    // Frame timing for Kalman dt
    private nonisolated(unsafe) var lastFrameTime: CFAbsoluteTime = 0

    // Guard against processing pileup (skip frame if still processing previous)
    private nonisolated(unsafe) var isCurrentlyProcessing: Bool = false

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
        isCurrentlyProcessing = false  // Reset processing guard
        currentZoom = RecordingManager.shared.getCurrentZoom()
        targetZoom = currentZoom
        recentZoomTargets = []
        frameCount = 0
        smoothZoomController.reset()
        startSmoothZoomLoop()
        debugPrint("🔍 [AutoZoom] Started in \(mode.rawValue) mode (ultra-smooth enabled)")
    }

    func stop() {
        isProcessing = false
        isCurrentlyProcessing = false
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = nil

        // Reset DeepTracker for next session
        deepTracker.reset()
        trackingReliability = 0
        isInRecoveryMode = false
        confirmedTracks = 0

        // Reset smooth zoom controller
        smoothZoomController.reset()
        frameCount = 0

        debugPrint("🔍 [AutoZoom] Stopped")
    }

    // MARK: - Frame Processing

    /// Wrapper to pass CVPixelBuffer across actor boundaries (safe because buffer is retained by caller)
    private struct UnsafeSendableBuffer: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Throttle processing to 4 FPS
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessTime >= processInterval else { return }

        // Skip if still processing previous frame (prevent pileup)
        guard !isCurrentlyProcessing else { return }

        lastProcessTime = now
        isCurrentlyProcessing = true

        // Wrap buffer for safe transfer to MainActor
        let sendableBuffer = UnsafeSendableBuffer(buffer: pixelBuffer)

        // Always use Skynet (DeepTracker with Kalman filtering)
        Task { @MainActor in
            self.processFrameWithSkynet(sendableBuffer.buffer)
            self.isCurrentlyProcessing = false
        }
    }

    /// Skynet: Deep Track 4.0-inspired tracking with Kalman filtering
    private func processFrameWithSkynet(_ pixelBuffer: CVPixelBuffer) {
        // Increment frame counter
        frameCount += 1

        // Calculate dt for Kalman filter
        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime > 0 ? now - lastFrameTime : 1.0/30.0
        lastFrameTime = now

        // 1. Classify all people in frame (PersonClassifier)
        let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)

        // 2. Update DeepTracker with new detections (SORT-style tracking)
        let activeTracks = deepTracker.update(detections: classifiedPeople, dt: dt)

        // 3. Get Kalman-filtered action center (much smoother than raw detection)
        let actionCenter = deepTracker.getActionCenter(filterPlayers: true)

        // 4. Get group bounding box for debug visualization
        let groupBox = deepTracker.getGroupBoundingBox(filterPlayers: true)

        // 5. Calculate zoom with recovery awareness (zoom out if lost)
        let recommendedZoom = deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 2.0)

        // Count by classification
        let players = classifiedPeople.filter { $0.classification == .player && $0.isOnCourt }
        let refs = classifiedPeople.filter { $0.classification == .referee }
        let adults = classifiedPeople.filter {
            $0.classification == .coach || $0.classification == .spectator
        }

        // Get tracking stats
        let reliability = deepTracker.averageReliability
        let inRecovery = deepTracker.isInRecoveryMode
        let confirmed = deepTracker.confirmedTrackCount

        // Update detection counts
        detectedPlayerCount = deepTracker.playerTrackCount
        filteredRefCount = deepTracker.refTrackCount
        filteredAdultCount = adults.count

        // Update tracking stats
        trackingReliability = reliability
        isInRecoveryMode = inRecovery
        confirmedTracks = confirmed

        // Update action center (Kalman-smoothed)
        actionZoneCenter = actionCenter

        // Update debug visualization
        debugActionZone = groupBox

        if activeTracks.isEmpty {
            handleNoPlayers()
        } else {
            // Use ultra-smooth zoom controller for broadcast-quality smoothness
            let smoothedZoom = smoothZoomController.update(
                target: Double(recommendedZoom),
                confidence: reliability
            )
            updateTargetZoom(CGFloat(smoothedZoom))

            // Log with tracking info (every 30 frames to reduce spam)
            if frameCount % 30 == 0 {
                let status = inRecovery ? "🔍 RECOVERY" : "✅ TRACKING"
                debugPrint("🤖 [Skynet] \(status) | Tracks: \(confirmed) | Players: \(players.count) Refs: \(refs.count) | Reliability: \(String(format: "%.0f%%", reliability * 100)) | Zoom: \(String(format: "%.2f", smoothedZoom))x")
            }
        }
    }

    // Frame counter for throttled logging
    private var frameCount: Int = 0

    // MARK: - Helpers

    private func handleNoPlayers() {
        detectedPlayerCount = 0
        // When no players detected, slowly drift toward wide shot
        // But DeepTracker's Kalman filter will maintain prediction for ~0.5s
        if recentZoomTargets.count > 3 {
            updateTargetZoom(max(minZoom, currentZoom - 0.1))
        }
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
