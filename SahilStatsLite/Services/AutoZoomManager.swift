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

    @Published var mode: AutoZoomMode = .smooth
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

    // Skynet tracking stats
    @Published var trackingReliability: Float = 0
    @Published var isInRecoveryMode: Bool = false
    @Published var confirmedTracks: Int = 0

    // Frame timing for Kalman dt
    private nonisolated(unsafe) var lastFrameTime: CFAbsoluteTime = 0

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

        // Reset DeepTracker for next session
        deepTracker.reset()
        trackingReliability = 0
        isInRecoveryMode = false
        confirmedTracks = 0

        debugPrint("🔍 [AutoZoom] Stopped")
    }

    // MARK: - Frame Processing

    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Throttle processing
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessTime >= processInterval else { return }
        lastProcessTime = now

        // Always use Skynet (DeepTracker with Kalman filtering)
        Task { @MainActor in
            self.processFrameWithSkynet(pixelBuffer)
        }
    }

    /// Skynet: Deep Track 4.0-inspired tracking with Kalman filtering
    private func processFrameWithSkynet(_ pixelBuffer: CVPixelBuffer) {
        // Calculate dt for Kalman filter
        let now = CFAbsoluteTimeGetCurrent()
        let dt = lastFrameTime > 0 ? now - lastFrameTime : 1.0/30.0
        lastFrameTime = now

        // Run classification and tracking on background thread
        Task.detached { [weak self] in
            guard let self = self else { return }

            // 1. Classify all people in frame (PersonClassifier)
            let classifiedPeople = self.personClassifier.classifyPeople(in: pixelBuffer)

            // 2. Update DeepTracker with new detections (SORT-style tracking)
            let activeTracks = self.deepTracker.update(detections: classifiedPeople, dt: dt)

            // 3. Get Kalman-filtered action center (much smoother than raw detection)
            let actionCenter = self.deepTracker.getActionCenter(filterPlayers: true)

            // 4. Get group bounding box for debug visualization
            let groupBox = self.deepTracker.getGroupBoundingBox(filterPlayers: true)

            // 5. Calculate zoom with recovery awareness (zoom out if lost)
            let recommendedZoom = self.deepTracker.calculateZoom(minZoom: 1.0, maxZoom: 2.0)

            // Count by classification
            let players = classifiedPeople.filter { $0.classification == .player && $0.isOnCourt }
            let refs = classifiedPeople.filter { $0.classification == .referee }
            let adults = classifiedPeople.filter {
                $0.classification == .coach || $0.classification == .spectator
            }

            // Get tracking stats
            let reliability = self.deepTracker.averageReliability
            let inRecovery = self.deepTracker.isInRecoveryMode
            let confirmed = self.deepTracker.confirmedTrackCount

            await MainActor.run {
                // Update detection counts
                self.detectedPlayerCount = self.deepTracker.playerTrackCount
                self.filteredRefCount = self.deepTracker.refTrackCount
                self.filteredAdultCount = adults.count

                // Update tracking stats
                self.trackingReliability = reliability
                self.isInRecoveryMode = inRecovery
                self.confirmedTracks = confirmed

                // Update action center (Kalman-smoothed)
                self.actionZoneCenter = actionCenter

                // Update debug visualization
                self.debugActionZone = groupBox

                if activeTracks.isEmpty {
                    self.handleNoPlayers()
                } else {
                    // Use DeepTracker's Kalman-filtered zoom
                    self.updateTargetZoom(recommendedZoom)

                    // Log with tracking info
                    let status = inRecovery ? "🔍 RECOVERY" : "✅ TRACKING"
                    debugPrint("🤖 [Skynet] \(status) | Tracks: \(confirmed) | Players: \(players.count) Refs: \(refs.count) | Reliability: \(String(format: "%.0f%%", reliability * 100)) | Zoom: \(String(format: "%.1f", recommendedZoom))x")
                }
            }
        }
    }

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
