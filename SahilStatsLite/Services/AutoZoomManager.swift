//
//  AutoZoomManager.swift
//  SahilStatsLite
//
//  PURPOSE: AI-powered auto-zoom orchestrator (Skynet v5.1). Receives SD frames
//           from RecordingManager, runs Vision detection on a background queue,
//           calculates optimal zoom and gimbal position.
//           Starts during warmup for calibration; resets tracking on game start.
//  KEY TYPES: AutoZoomManager (singleton, @MainActor), SkynetCore (background state)
//  DEPENDS ON: PersonClassifier, DeepTracker, RecordingManager
//
//  ARCHITECTURE:
//  - SkynetCore (file-scope, no actor isolation) owns all background tracking state.
//    Accessed only from skynetCore.queue (background) and from @MainActor resets.
//  - AutoZoomManager (@MainActor) owns all @Published UI state and coordinates
//    the handoff between background computation and UI updates.
//  - processFrame() throttles and dispatches to skynetCore.queue.
//  - computeSkynet() runs entirely on background — zero MainActor access.
//  - applySkynetResult() runs on @MainActor — only @Published writes happen here.
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

// MARK: - Skynet Core (background tracking state)

/// Owns all mutable state accessed from the background skynet queue.
/// Declared at file scope so it has NO actor isolation — calling its methods
/// from any concurrency context generates no Swift concurrency warnings.
///
/// Thread safety contract: all properties and methods are accessed exclusively
/// from skynetCore.queue, except during explicit resets which happen only when
/// no game is in flight (safe from @MainActor).
private final class SkynetCore: @unchecked Sendable {

    let personClassifier = PersonClassifier()
    let deepTracker = DeepTracker()
    let smoothZoomController = UltraSmoothZoomController(minZoom: 1.0, maxZoom: 1.3)
    let ballDetector = BallDetector()

    /// Dedicated serial queue for Vision + Kalman computation.
    let queue = DispatchQueue(label: "com.sahilstats.skynet", qos: .userInitiated)

    /// Match RecordingManager's aiFrameInterval (0.067 = 15fps).
    /// Raise to 0.1 (10fps) if phone thermals are a concern during a full game.
    let processInterval: CFAbsoluteTime = 0.067

    var bgActionCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var frameCount: Int = 0
    var lastFrameTime: CFAbsoluteTime = 0
    var lastProcessTime: CFAbsoluteTime = 0
    var isCurrentlyProcessing: Bool = false

    /// Hard reset — called from @MainActor at game start or stop.
    func resetTracking() {
        deepTracker.reset()
        smoothZoomController.reset()
        bgActionCenter = CGPoint(x: 0.5, y: 0.5)
        frameCount = 0
        lastFrameTime = 0
        isCurrentlyProcessing = false
    }
}

/// Single shared instance — file scope, no actor isolation.
private let skynetCore = SkynetCore()

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
    @Published var trackingReliability: Float = 0
    @Published var confirmedTracks: Int = 0

    // Debug visualization
    @Published var debugActionZone: CGRect = .zero
    @Published var showDebugOverlay: Bool = false

    // MARK: - Zoom Limits

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    // MARK: - UI-only State

    private var smoothZoomTimer: Timer?
    private var recentZoomTargets: [CGFloat] = []
    private let rollingAverageCount = 5

    // MARK: - Background Result Type

    /// All values computed on skynetCore.queue, applied on @MainActor in one batch.
    private struct SkynetResult {
        let newActionCenter: CGPoint?   // nil = within deadband, no gimbal update needed
        let newTargetZoom: CGFloat
        let playerCount: Int
        let trackingReliability: Float
        let confirmedTracks: Int
        let isTimeout: Bool
        let debugActionZone: CGRect
        let noPlayers: Bool
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Control

    func start() {
        guard mode != .off else { return }
        isProcessing = true
        skynetCore.isCurrentlyProcessing = false
        currentZoom = RecordingManager.shared.getCurrentZoom()
        targetZoom = currentZoom
        recentZoomTargets = []
        skynetCore.frameCount = 0
        skynetCore.smoothZoomController.reset()
        startSmoothZoomLoop()
        debugPrint("🔍 [AutoZoom] Started v5.1 (SkynetCore, zero concurrency warnings)")
    }

    func stop() {
        isProcessing = false
        skynetCore.isCurrentlyProcessing = false
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = nil
        skynetCore.resetTracking()
        trackingReliability = 0
        confirmedTracks = 0
        actionZoneCenter = CGPoint(x: 0.5, y: 0.5)
        debugPrint("🔍 [AutoZoom] Stopped")
    }

    /// Reset tracking state for game start (keeps learned court bounds + team colors from warmup).
    /// Call this when the game clock starts to get fresh tracking without losing calibration.
    func resetTrackingState() {
        // Finalize team color profiles before resetting — locks in jersey colors learned during warmup
        skynetCore.personClassifier.finalizeTeamColors()
        skynetCore.personClassifier.resetTrackingState()
        skynetCore.resetTracking()

        trackingReliability = 0
        confirmedTracks = 0
        isTimeoutMode = false
        currentZoom = 1.0
        targetZoom = 1.0
        recentZoomTargets = []
        actionZoneCenter = CGPoint(x: 0.5, y: 0.5)

        debugPrint("🔍 [AutoZoom] Tracking reset for game start (court bounds + team colors preserved)")
    }

    // MARK: - Frame Processing

    private struct UnsafeSendableBuffer: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        // skynetCore is file-scope with no actor isolation — safe to access from anywhere
        guard now - skynetCore.lastProcessTime >= skynetCore.processInterval else { return }
        guard !skynetCore.isCurrentlyProcessing else { return }

        skynetCore.lastProcessTime = now
        skynetCore.isCurrentlyProcessing = true

        let sendableBuffer = UnsafeSendableBuffer(buffer: pixelBuffer)

        skynetCore.queue.async { [weak self] in
            guard let self else { return }
            let result = computeSkynet(sendableBuffer.buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applySkynetResult(result)
                skynetCore.isCurrentlyProcessing = false
            }
        }
    }

    /// All Vision/Kalman computation — runs on skynetCore.queue, zero MainActor access.
    /// Uses skynetCore directly (file-scope, no isolation) — no concurrency warnings.
    private nonisolated func computeSkynet(_ pixelBuffer: CVPixelBuffer) -> SkynetResult {
        skynetCore.frameCount += 1

        let now = CFAbsoluteTimeGetCurrent()
        let dt = skynetCore.lastFrameTime > 0 ? now - skynetCore.lastFrameTime : 1.0/15.0
        skynetCore.lastFrameTime = now

        let currentCenter = skynetCore.bgActionCenter
        skynetCore.personClassifier.currentFocusHint = currentCenter

        // Vision detection + ball + SORT tracking
        let classifiedPeople = skynetCore.personClassifier.classifyPeople(in: pixelBuffer)
        let players = classifiedPeople.filter { $0.classification == .player }
        let ballDetection = skynetCore.ballDetector.detectBall(in: pixelBuffer, dt: dt)
        let activeTracks = skynetCore.deepTracker.update(detections: classifiedPeople, dt: dt)

        // Player cluster anchors camera; ball blends in at 60% when detected with high confidence
        let playerCenter = skynetCore.personClassifier.calculateActionCenter(from: activeTracks)
        var rawActionCenter = playerCenter

        if let ball = ballDetection, ball.confidence > 0.75 {
            // Gretzky lead: predict 0.2s ahead, capped at ±10% of frame
            let safeLeadX = max(-0.1, min(0.1, ball.velocity.x * 0.2))
            let safeLeadY = max(-0.1, min(0.1, ball.velocity.y * 0.2))
            let ballCenter = CGPoint(
                x: max(0.1, min(0.9, ball.position.x + safeLeadX)),
                y: max(0.1, min(0.9, ball.position.y + safeLeadY))
            )
            rawActionCenter = CGPoint(
                x: ballCenter.x * 0.6 + playerCenter.x * 0.4,
                y: ballCenter.y * 0.6 + playerCenter.y * 0.4
            )
        }

        // Deadband: ignore movements < 3% to stop nervous micro-panning
        let distance = hypot(rawActionCenter.x - currentCenter.x, rawActionCenter.y - currentCenter.y)
        var newActionCenter: CGPoint? = nil
        if distance > 0.03 {
            newActionCenter = rawActionCenter
            skynetCore.bgActionCenter = rawActionCenter
        }

        // Timeout detection: bench rush = 60%+ players clustered at screen edges
        let edgePlayers = players.filter { $0.boundingBox.midX < 0.15 || $0.boundingBox.midX > 0.85 }
        let isTimeout = players.count >= 3 && Float(edgePlayers.count) / Float(players.count) > 0.6
        skynetCore.smoothZoomController.isTimeoutMode = isTimeout

        let reliability = skynetCore.deepTracker.averageReliability
        var recommendedZoom = skynetCore.deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 1.3)
        if isTimeout || players.isEmpty { recommendedZoom = 1.0 }

        let smoothedZoom = skynetCore.smoothZoomController.update(target: Double(recommendedZoom), confidence: reliability)

        if skynetCore.frameCount % 30 == 0 {
            let status = isTimeout ? "⌛️ TIMEOUT" : "✅ TRACKING"
            debugPrint("🤖 [Skynet] \(status) | Players: \(players.count) | Reliability: \(String(format: "%.0f%%", reliability * 100)) | Zoom: \(String(format: "%.2f", smoothedZoom))x")
        }

        return SkynetResult(
            newActionCenter: newActionCenter,
            newTargetZoom: CGFloat(smoothedZoom),
            playerCount: skynetCore.deepTracker.playerTrackCount,
            trackingReliability: reliability,
            confirmedTracks: skynetCore.deepTracker.confirmedTrackCount,
            isTimeout: isTimeout,
            debugActionZone: skynetCore.deepTracker.getGroupBoundingBox(filterPlayers: true),
            noPlayers: players.isEmpty
        )
    }

    /// Apply background-computed results on MainActor — only @Published writes happen here.
    @MainActor
    private func applySkynetResult(_ result: SkynetResult) {
        if let newCenter = result.newActionCenter {
            actionZoneCenter = newCenter
            GimbalTrackingManager.shared.updateTrackingROI(center: newCenter)
        }

        isTimeoutMode = result.isTimeout
        trackingReliability = result.trackingReliability
        confirmedTracks = result.confirmedTracks
        detectedPlayerCount = result.playerCount
        debugActionZone = result.debugActionZone

        if result.noPlayers && !result.isTimeout {
            if recentZoomTargets.count > 3 {
                updateTargetZoom(max(minZoom, currentZoom - 0.1))
            }
        } else {
            updateTargetZoom(result.newTargetZoom)
        }
    }

    // MARK: - Helpers

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
