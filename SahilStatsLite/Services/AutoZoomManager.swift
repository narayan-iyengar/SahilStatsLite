//
//  AutoZoomManager.swift
//  SahilStatsLite
//
//  PURPOSE: AI-powered auto-zoom orchestrator (Skynet v5.1). Receives SD frames
//           from RecordingManager, runs Vision detection, calculates optimal zoom.
//  KEY TYPES: AutoZoomManager (@MainActor, UI state), SkynetProcessor (actor, tracking)
//  DEPENDS ON: PersonClassifier, DeepTracker, RecordingManager
//
//  ARCHITECTURE:
//  - SkynetProcessor (Swift actor, file scope) owns all background tracking state.
//    Actor isolation guarantees no data races and no Swift concurrency warnings.
//  - AutoZoomManager (@MainActor) owns @Published UI state and coordinates handoff.
//  - processFrame() dispatches Task { await skynetProcessor.tryCompute() }.
//  - tryCompute() runs on the actor's executor — off the main thread, zero warnings.
//  - applySkynetResult() runs on @MainActor — only @Published writes here.
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import AVFoundation
import Vision
import Combine

// MARK: - Ultra-Smooth Zoom Controller

class UltraSmoothZoomController {

    // nonisolated(unsafe) on mutable stored vars because this class is defined in the same
    // file as @MainActor AutoZoomManager, causing Swift to infer @MainActor for the class.
    // The nonisolated methods need to read/write these without isolation warnings.
    private nonisolated(unsafe) var smoothZoom: Double = 1.0
    private nonisolated(unsafe) var zoomVelocity: Double = 0
    private nonisolated(unsafe) var targetZoom: Double = 1.0

    private let zoomSmoothing: Double = 0.005
    private let velocityDamping: Double = 0.9
    private let deadZone: Double = 0.04
    private let maxZoomSpeed: Double = 0.004

    let minZoom: Double
    let maxZoom: Double

    private nonisolated(unsafe) var highConfidenceStreak: Int = 0
    private let minStreakForUpdate: Int = 6

    nonisolated(unsafe) var isTimeoutMode: Bool = false

    nonisolated init(minZoom: Double = 1.0, maxZoom: Double = 1.5) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.smoothZoom = minZoom
    }

    nonisolated func update(target: Double, confidence: Float) -> Double {
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

    nonisolated func reset() {
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

// MARK: - Sendable Pixel Buffer Wrapper (file scope — visible to actor and class)

/// Wraps CVPixelBuffer (non-Sendable) for safe passage across actor boundaries.
private struct UnsafeSendableBuffer: @unchecked Sendable {
    nonisolated(unsafe) let buffer: CVPixelBuffer
}

// MARK: - Skynet Processor (Actor)

/// Swift actor that owns all Skynet tracking state.
/// Actor isolation guarantees exclusive access — no data races, no nonisolated(unsafe),
/// no Swift concurrency warnings. Runs on Swift's cooperative thread pool (off main thread).
private actor SkynetProcessor {

    private let personClassifier = PersonClassifier()
    private let deepTracker = DeepTracker()
    private let smoothZoomController = UltraSmoothZoomController(minZoom: 1.0, maxZoom: 1.3)
    private let ballDetector = BallDetector()

    /// Match RecordingManager's aiFrameInterval (0.067 = 15fps).
    /// Raise to 0.1 (10fps) if thermals are an issue during a full game.
    private let processInterval: CFAbsoluteTime = 0.067

    private var bgActionCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var frameCount: Int = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var lastProcessTime: CFAbsoluteTime = 0
    private var isProcessing: Bool = false

    /// Entry point for each camera frame. Returns nil if throttled or already processing.
    /// Takes UnsafeSendableBuffer so CVPixelBuffer never crosses the actor boundary directly.
    func tryCompute(_ wrapper: UnsafeSendableBuffer) -> SkynetResult? {
        let now = CFAbsoluteTimeGetCurrent()
        guard !isProcessing, now - lastProcessTime >= processInterval else { return nil }
        isProcessing = true
        lastProcessTime = now
        defer { isProcessing = false }
        return compute(wrapper.buffer, now: now)
    }

    /// Finalizes team colors and resets tracking state (called at game start).
    func prepareForGameStart() {
        personClassifier.finalizeTeamColors()
        resetState()
    }

    /// Full reset (called at stop).
    func resetState() {
        deepTracker.reset()
        smoothZoomController.reset()
        personClassifier.resetTrackingState()
        bgActionCenter = CGPoint(x: 0.5, y: 0.5)
        frameCount = 0
        lastFrameTime = 0
        isProcessing = false
    }

    // MARK: - Core Computation

    private func compute(_ pixelBuffer: CVPixelBuffer, now: CFAbsoluteTime) -> SkynetResult {
        frameCount += 1
        let dt = lastFrameTime > 0 ? now - lastFrameTime : 1.0/15.0
        lastFrameTime = now

        let currentCenter = bgActionCenter
        personClassifier.currentFocusHint = currentCenter

        let classifiedPeople = personClassifier.classifyPeople(in: pixelBuffer)
        // Pattern match instead of == to avoid @MainActor Equatable conformance warning
        let players = classifiedPeople.filter { if case .player = $0.classification { return true }; return false }
        let ballDetection = ballDetector.detectBall(in: pixelBuffer, dt: dt)
        let activeTracks = deepTracker.update(detections: classifiedPeople, dt: dt)

        // Player cluster is always the primary tracking signal.
        // YOLO + DeepTracker over 5-10 players is orders of magnitude more reliable than
        // color-threshold ball detection at gym distances (ball = 8-15px in AI frame).
        let playerCenter = personClassifier.calculateActionCenter(from: activeTracks)
        var rawActionCenter = playerCenter

        // Ball is used ONLY as a fast-break early-warning system.
        // Conditions that must ALL be true before the ball influences the camera:
        //   1. High confidence (0.85) — reject false positives from skin, equipment, floor
        //   2. Ball moving fast (>0.25 norm units/s) — genuine pass or fast break
        //   3. Ball significantly ahead of players (>15% frame width) — players haven't
        //      caught up yet, ball is actually leading the action
        // Effect: a gentle 20% nudge toward where the ball is HEADING (not where it is),
        // so the camera drifts ahead of a fast break rather than snapping to a noise signal.
        if let ball = ballDetection,
           ball.confidence > 0.85,
           hypot(ball.velocity.x, ball.velocity.y) > 0.25,
           abs(ball.position.x - playerCenter.x) > 0.15 {
            // Predict where ball will be in 0.2s — pan ahead, not at current position
            let predictedX = max(0.1, min(0.9, ball.position.x + ball.velocity.x * 0.2))
            rawActionCenter.x = playerCenter.x * 0.8 + predictedX * 0.2
            // Y stays on player cluster — we're pan-only and players define the vertical framing
        }

        let distance = hypot(rawActionCenter.x - currentCenter.x, rawActionCenter.y - currentCenter.y)
        var newActionCenter: CGPoint? = nil
        if distance > 0.03 {
            newActionCenter = rawActionCenter
            bgActionCenter = rawActionCenter
        }

        let edgePlayers = players.filter { $0.boundingBox.midX < 0.15 || $0.boundingBox.midX > 0.85 }
        let isTimeout = players.count >= 3 && Float(edgePlayers.count) / Float(players.count) > 0.6
        smoothZoomController.isTimeoutMode = isTimeout

        let reliability = deepTracker.averageReliability
        var recommendedZoom = deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 1.3)
        if isTimeout || players.isEmpty { recommendedZoom = 1.0 }

        let smoothedZoom = smoothZoomController.update(target: Double(recommendedZoom), confidence: reliability)

        if frameCount % 30 == 0 {
            let status = isTimeout ? "⌛️ TIMEOUT" : "✅ TRACKING"
            debugPrint("🤖 [Skynet] \(status) | Players: \(players.count) | Reliability: \(String(format: "%.0f%%", reliability * 100)) | Zoom: \(String(format: "%.2f", smoothedZoom))x")
        }

        return SkynetResult(
            newActionCenter: newActionCenter,
            newTargetZoom: CGFloat(smoothedZoom),
            playerCount: deepTracker.playerTrackCount,
            trackingReliability: reliability,
            confirmedTracks: deepTracker.confirmedTrackCount,
            isTimeout: isTimeout,
            debugActionZone: deepTracker.getGroupBoundingBox(filterPlayers: true),
            noPlayers: players.isEmpty
        )
    }
}

/// Shared processor — file scope, actor-isolated (not @MainActor).
private let skynetProcessor = SkynetProcessor()

// MARK: - Skynet Result

private struct SkynetResult: Sendable {
    let newActionCenter: CGPoint?
    let newTargetZoom: CGFloat
    let playerCount: Int
    let trackingReliability: Float
    let confirmedTracks: Int
    let isTimeout: Bool
    let debugActionZone: CGRect
    let noPlayers: Bool
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
    @Published var trackingReliability: Float = 0
    @Published var confirmedTracks: Int = 0
    @Published var debugActionZone: CGRect = .zero
    @Published var showDebugOverlay: Bool = false

    // MARK: - Zoom Limits

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    // MARK: - UI-only State

    private var smoothZoomTimer: Timer?
    private var recentZoomTargets: [CGFloat] = []
    private let rollingAverageCount = 5

    private init() {}

    // MARK: - Control

    func start() {
        guard mode != .off else { return }
        isProcessing = true
        currentZoom = RecordingManager.shared.getCurrentZoom()
        targetZoom = currentZoom
        recentZoomTargets = []
        Task { await skynetProcessor.resetState() }
        startSmoothZoomLoop()
        debugPrint("🔍 [AutoZoom] Started v5.1 (actor-based, zero concurrency warnings)")
    }

    func stop() {
        isProcessing = false
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = nil
        Task { await skynetProcessor.resetState() }
        trackingReliability = 0
        confirmedTracks = 0
        actionZoneCenter = CGPoint(x: 0.5, y: 0.5)
        debugPrint("🔍 [AutoZoom] Stopped")
    }

    /// Reset tracking state for game start. Keeps learned court bounds + team colors from warmup.
    func resetTrackingState() {
        Task { await skynetProcessor.prepareForGameStart() }
        trackingReliability = 0
        confirmedTracks = 0
        isTimeoutMode = false
        currentZoom = 1.0
        targetZoom = 1.0
        recentZoomTargets = []
        actionZoneCenter = CGPoint(x: 0.5, y: 0.5)
        debugPrint("🔍 [AutoZoom] Tracking reset for game start")
    }

    // MARK: - Frame Processing

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let sendable = UnsafeSendableBuffer(buffer: pixelBuffer)
        Task {
            guard let result = await skynetProcessor.tryCompute(sendable) else { return }
            await MainActor.run { [weak self] in
                self?.applySkynetResult(result)
            }
        }
    }

    // MARK: - Apply Results

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
            // No players found — apply gravity drift (tilt down slowly after 5s)
            GimbalTrackingManager.shared.applyGravityDrift()
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
        if recentZoomTargets.count > rollingAverageCount { recentZoomTargets.removeFirst() }
        let smoothedTarget = recentZoomTargets.reduce(0, +) / CGFloat(recentZoomTargets.count)
        guard abs(smoothedTarget - targetZoom) > mode.hysteresis else { return }
        targetZoom = smoothedTarget
    }

    private func startSmoothZoomLoop() {
        smoothZoomTimer?.invalidate()
        smoothZoomTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.updateZoomSmooth() }
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
