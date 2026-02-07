//
//  AutoZoomManager.swift
//  SahilStatsLite
//
//  PURPOSE: AI-powered auto-zoom orchestrator (Skynet v4.1). Receives SD frames
//           from RecordingManager, runs Vision detection, calculates optimal zoom.
//           Starts during warmup for calibration; resets tracking on game start.
//  KEY TYPES: AutoZoomManager (singleton), UltraSmoothZoomController, AutoZoomMode
//  DEPENDS ON: PersonClassifier, DeepTracker, RecordingManager
//
//  FEATURES:
//  - v3.1 Golden Smoothing for broadcast-quality motion
//  - Momentum-Weighted Attention via TrackedObject velocities (1x-3x capped)
//  - Timeout Detection (60%+ players at edges → zoom out)
//  - Warmup calibration (resetTrackingState keeps court bounds)
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import AVFoundation
import Vision
import Combine

// MARK: - Ultra-Smooth Zoom Controller

/// Broadcast-quality zoom smoothing that prevents jarring zoom changes
class UltraSmoothZoomController {

    private var smoothZoom: Double = 1.0
    private var zoomVelocity: Double = 0
    private var targetZoom: Double = 1.0

    // Configuration - BROADCAST QUALITY (v3.1)
    private let zoomSmoothing: Double = 0.005
    private let velocityDamping: Double = 0.9
    private let deadZone: Double = 0.04
    private let maxZoomSpeed: Double = 0.004

    let minZoom: Double
    let maxZoom: Double

    private var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 6

    var isTimeoutMode: Bool = false

    init(minZoom: Double = 1.0, maxZoom: Double = 1.5) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.smoothZoom = minZoom
    }

    func update(target: Double, confidence: Float) -> Double {
        if confidence > 0.4 {
            highConfidenceStreak += 1
        } else {
            highConfidenceStreak = max(0, highConfidenceStreak - 2)
        }

        if highConfidenceStreak >= minStreakForUpdate {
            // In timeout mode, we force zoom out to 1.0
            targetZoom = isTimeoutMode ? 1.0 : max(minZoom, min(maxZoom, target))
        }

        let delta = targetZoom - smoothZoom

        if abs(delta) < deadZone {
            zoomVelocity *= velocityDamping
        } else {
            let direction = delta > 0 ? 1.0 : -1.0
            zoomVelocity += direction * zoomSmoothing
            zoomVelocity *= velocityDamping
            if abs(zoomVelocity) > maxZoomSpeed {
                zoomVelocity = direction * maxZoomSpeed
            }
        }

        smoothZoom += zoomVelocity
        smoothZoom = max(1.0, min(maxZoom, smoothZoom))

        return smoothZoom
    }

    func reset() {
        smoothZoom = minZoom
        zoomVelocity = 0
        targetZoom = minZoom
        highConfidenceStreak = 0
        isTimeoutMode = false
    }
}

// MARK: - Auto Zoom Mode

enum AutoZoomMode: String, CaseIterable, Sendable {
    case off = "Off"
    case auto = "Auto"

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

    var smoothingFactor: CGFloat {
        switch self {
        case .off: return 0
        case .auto: return 0.08
        }
    }

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
    @Published var isTimeoutMode: Bool = false

    // Debug visualization
    @Published var debugActionZone: CGRect = .zero
    @Published var showDebugOverlay: Bool = false

    // MARK: - Zoom Limits

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    // MARK: - Processing State

    private nonisolated(unsafe) var lastProcessTime: CFAbsoluteTime = 0
    private let processInterval: CFAbsoluteTime = 0.25
    private var smoothZoomTimer: Timer?
    private var recentZoomTargets: [CGFloat] = []
    private let rollingAverageCount = 5

    private let personClassifier = PersonClassifier()
    private let deepTracker = DeepTracker()
    private let smoothZoomController = UltraSmoothZoomController(minZoom: 1.0, maxZoom: 1.6)

    @Published var trackingReliability: Float = 0
    @Published var confirmedTracks: Int = 0

    private nonisolated(unsafe) var lastFrameTime: CFAbsoluteTime = 0
    private nonisolated(unsafe) var isCurrentlyProcessing: Bool = false
    private var frameCount: Int = 0

    // MARK: - Initialization

    private init() {}

    // MARK: - Control

    func start() {
        guard mode != .off else { return }
        isProcessing = true
        isCurrentlyProcessing = false
        currentZoom = RecordingManager.shared.getCurrentZoom()
        targetZoom = currentZoom
        recentZoomTargets = []
        frameCount = 0
        smoothZoomController.reset()
        startSmoothZoomLoop()
        debugPrint("🔍 [AutoZoom] Started v4.1 (Momentum Mind enabled)")
    }

    func stop() {
        isProcessing = false
        isCurrentlyProcessing = false
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = nil
        deepTracker.reset()
        trackingReliability = 0
        confirmedTracks = 0
        smoothZoomController.reset()
        frameCount = 0
        debugPrint("🔍 [AutoZoom] Stopped")
    }

    /// Reset tracking state for game start (keeps learned court bounds from warmup)
    /// Call this when the game clock starts to get fresh tracking without losing calibration
    func resetTrackingState() {
        // Reset tracking (fresh SORT state)
        deepTracker.reset()
        trackingReliability = 0
        confirmedTracks = 0
        isTimeoutMode = false

        // Reset zoom to wide
        smoothZoomController.reset()
        currentZoom = 1.0
        targetZoom = 1.0
        recentZoomTargets = []

        // Reset action center
        actionZoneCenter = CGPoint(x: 0.5, y: 0.5)

        // Reset PersonClassifier tracking but KEEP court bounds + height stats
        personClassifier.resetTrackingState()

        debugPrint("🔍 [AutoZoom] Tracking state reset for game start (court bounds preserved)")
    }

    // MARK: - Frame Processing

    private struct UnsafeSendableBuffer: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessTime >= processInterval else { return }
        guard !isCurrentlyProcessing else { return }

        lastProcessTime = now
        isCurrentlyProcessing = true

        let sendableBuffer = UnsafeSendableBuffer(buffer: pixelBuffer)

        Task { @MainActor in
            self.processFrameWithSkynet(sendableBuffer.buffer)
            self.isCurrentlyProcessing = false
        }
    }

    private func processFrameWithSkynet(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1

        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime > 0 ? now - lastFrameTime : 1.0/30.0
        lastFrameTime = now

        // 1. Vision hint
        personClassifier.currentFocusHint = actionZoneCenter

        // 2. Classify (AI receives SD buffer from RecordingManager)
        let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)
        let players = classifiedPeople.filter { $0.classification == .player }
        
        // 3. Update SORT Tracker
        let activeTracks = deepTracker.update(detections: classifiedPeople, dt: dt)

        // 4. Momentum-Weighted Action Center
        let actionCenter = personClassifier.calculateActionCenter(from: activeTracks)

        // 5. Timeout Detection (Bench Rush)
        let edgePlayers = players.filter { $0.boundingBox.midX < 0.15 || $0.boundingBox.midX > 0.85 }
        let isTimeout = players.count >= 3 && Float(edgePlayers.count) / Float(players.count) > 0.6
        self.isTimeoutMode = isTimeout
        smoothZoomController.isTimeoutMode = isTimeout

        // 6. Calculate zoom
        var recommendedZoom = deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 2.0)
        if isTimeout { recommendedZoom = 1.0 }

        // Update stats
        trackingReliability = deepTracker.averageReliability
        confirmedTracks = deepTracker.confirmedTrackCount
        detectedPlayerCount = deepTracker.playerTrackCount
        actionZoneCenter = actionCenter
        debugActionZone = deepTracker.getGroupBoundingBox(filterPlayers: true)

        if players.isEmpty && !isTimeout {
            handleNoPlayers()
        } else {
            let smoothedZoom = smoothZoomController.update(
                target: Double(recommendedZoom),
                confidence: trackingReliability
            )
            updateTargetZoom(CGFloat(smoothedZoom))

            if frameCount % 30 == 0 {
                let status = isTimeout ? "⌛️ TIMEOUT" : "✅ TRACKING"
                debugPrint("🤖 [Skynet] \(status) | Players: \(players.count) | Reliability: \(String(format: "%.0f%%", trackingReliability * 100)) | Zoom: \(String(format: "%.2f", smoothedZoom))x")
            }
        }
    }

    // MARK: - Helpers

    private func handleNoPlayers() {
        detectedPlayerCount = 0
        if recentZoomTargets.count > 3 {
            updateTargetZoom(max(minZoom, currentZoom - 0.1))
        }
    }

    private func updateTargetZoom(_ newTarget: CGFloat) {
        recentZoomTargets.append(newTarget)
        if recentZoomTargets.count > rollingAverageCount {
            recentZoomTargets.removeFirst()
        }
        let smoothedTarget = recentZoomTargets.reduce(0, +) / CGFloat(recentZoomTargets.count)
        guard abs(smoothedTarget - targetZoom) > mode.hysteresis else { return }
        targetZoom = smoothedTarget
    }

    private func startSmoothZoomLoop() {
        smoothZoomTimer?.invalidate()
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
        if abs(diff) < 0.01 {
            if currentZoom != targetZoom {
                currentZoom = targetZoom
                _ = RecordingManager.shared.setZoom(factor: currentZoom)
            }
            return
        }
        let easedZoom = currentZoom + (diff * mode.smoothingFactor)
        currentZoom = easedZoom.clamped(to: minZoom...maxZoom)
        _ = RecordingManager.shared.setZoom(factor: currentZoom)
    }

    func manualZoomOverride(_ zoom: CGFloat) {
        currentZoom = zoom.clamped(to: minZoom...maxZoom)
        targetZoom = currentZoom
        recentZoomTargets = [currentZoom]
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}