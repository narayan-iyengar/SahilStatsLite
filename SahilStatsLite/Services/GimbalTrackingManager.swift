//
//  GimbalTrackingManager.swift
//  SahilStatsLite
//
//  PURPOSE: DockKit gimbal integration for Insta360 Flow Pro 2. Controls
//           physical pan/tilt as a 2-axis stabilizer guided by Skynet.
//           DockKit system tracking AI is DISABLED. Skynet is the sole tracking brain.
//           Skynet calls updateTrackingROI(center:) each frame to steer the physical gimbal.
//  KEY TYPES: GimbalTrackingManager (singleton), GimbalMode (off/stabilize/track)
//  DEPENDS ON: DockKit (iOS 18+), AVFoundation
//
//  NOTE: Keep this header updated when modifying this file.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI
#if canImport(DockKit)
import DockKit
#endif

// MARK: - Gimbal Mode

enum GimbalMode: String, CaseIterable {
    case off = "Off"
    case stabilize = "Stabilize"
    case track = "Auto-Track"

    var icon: String {
        switch self {
        case .off: return "iphone"
        case .stabilize: return "gyroscope"
        case .track: return "person.fill.viewfinder"
        }
    }

    var description: String {
        switch self {
        case .off: return "Handheld, no gimbal"
        case .stabilize: return "Gimbal smoothing, manual aim"
        case .track: return "Auto-follow subjects"
        }
    }
}

@MainActor
final class GimbalTrackingManager: ObservableObject {
    static let shared = GimbalTrackingManager()

    // MARK: - Published Properties

    @Published var gimbalMode: GimbalMode = .track
    @Published var isTrackingActive: Bool = false
    @Published var isDockKitAvailable: Bool = false
    @Published var lastError: String?
    @Published var trackedSubjectCount: Int = 0

    // MARK: - DockKit Properties

    #if canImport(DockKit)
    @available(iOS 18.0, *)
    private var dockAccessory: DockAccessory?
    #endif

    private var trackingTask: Task<Void, Never>?
    private var roiUpdateTask: Task<Void, Never>?

    // Minimum movement (normalized) before we bother updating the ROI
    private let roiDeadband: CGFloat = 0.08
    private var lastROICenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    // ROI box size sent to DockKit (30% of frame). Smaller = less DockKit hunting.
    private let roiSize: CGFloat = 0.30

    // MARK: - Initialization

    private init() {
        checkDockKitAvailability()
    }

    // MARK: - DockKit Availability

    private func checkDockKitAvailability() {
        #if canImport(DockKit)
        if #available(iOS 18.0, *) {
            debugPrint("[DockKit] iOS 18+ detected, starting accessory scan...")
            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    debugPrint("[DockKit] Got DockAccessoryManager, waiting for accessoryStateChanges...")
                    let stateChanges = try manager.accessoryStateChanges

                    for await stateChange in stateChanges {
                        debugPrint("[DockKit] State change received!")
                        if let accessory = stateChange.accessory {
                            // Immediately disable Insta360's own tracking AI the moment the
                            // gimbal connects. This is the DockKit equivalent of Lock mode —
                            // the gimbal stabilizes but does not track on its own.
                            // Skynet will steer it via updateTrackingROI(center:).
                            try? await manager.setSystemTrackingEnabled(false)
                            debugPrint("[DockKit] ✅ Gimbal connected: \(accessory.identifier.name) — Lock mode engaged")
                            await MainActor.run {
                                self.dockAccessory = accessory
                                self.isDockKitAvailable = true
                            }
                        } else {
                            await MainActor.run {
                                self.dockAccessory = nil
                                self.isDockKitAvailable = false
                                debugPrint("[DockKit] ❌ Gimbal disconnected")
                            }
                        }
                    }
                } catch {
                    debugPrint("[DockKit] ❌ Error: \(error.localizedDescription)")
                    await MainActor.run {
                        self.isDockKitAvailable = false
                        self.lastError = error.localizedDescription
                    }
                }
            }
        } else {
            debugPrint("[DockKit] ❌ iOS version < 18, DockKit not available")
            isDockKitAvailable = false
        }
        #else
        debugPrint("[DockKit] ❌ DockKit framework not available (not imported)")
        isDockKitAvailable = false
        #endif
    }

    // MARK: - Tracking Control

    func startTracking() {
        // If mode is off, don't do anything
        guard gimbalMode != .off else {
            debugPrint("[Gimbal] Mode is OFF, skipping gimbal")
            return
        }

        #if canImport(DockKit)
        guard let _ = dockAccessory else {
            lastError = "No gimbal connected"
            return
        }

        if #available(iOS 18.0, *) {
            isTrackingActive = true
            lastError = nil
            lastROICenter = CGPoint(x: 0.5, y: 0.5)

            Task {
                do {
                    let manager = DockAccessoryManager.shared
                    // CRITICAL: Disable DockKit's own tracking AI entirely.
                    // The Insta360 Flow Pro 2 is used as a pure 2-axis physical stabilizer.
                    // Skynet (AutoZoomManager) is the sole tracking brain. It calls
                    // updateTrackingROI(center:) each frame to steer where the gimbal points.
                    try await manager.setSystemTrackingEnabled(false)
                    debugPrint("[Gimbal] System tracking DISABLED — Skynet is in command")
                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.isTrackingActive = false
                    }
                }
            }
        }
        #endif
    }

    func stopTracking() {
        guard isTrackingActive else { return }

        trackingTask?.cancel()
        trackingTask = nil
        roiUpdateTask?.cancel()
        roiUpdateTask = nil

        isTrackingActive = false
        trackedSubjectCount = 0
    }

    // MARK: - Skynet-Driven Physical Gimbal Steering

    /// Called by AutoZoomManager each frame with Skynet's computed action center (normalized 0–1).
    /// Translates that center into a DockKit region of interest so the gimbal physically pans/tilts
    /// toward the action. Only updates DockKit if the center has moved past the deadband.
    func updateTrackingROI(center: CGPoint) {
        guard gimbalMode == .track, isDockKitAvailable, isTrackingActive else { return }

        let movement = hypot(center.x - lastROICenter.x, center.y - lastROICenter.y)
        guard movement > roiDeadband else { return }
        lastROICenter = center

        roiUpdateTask?.cancel()
        roiUpdateTask = Task {
            #if canImport(DockKit)
            if #available(iOS 18.0, *) {
                guard let accessory = dockAccessory else { return }
                let half = roiSize / 2
                let roi = CGRect(
                    x: max(0, center.x - half),
                    y: max(0, center.y - half),
                    width: roiSize,
                    height: roiSize
                )
                do {
                    try await accessory.setRegionOfInterest(roi)
                    debugPrint("[Gimbal] ROI → (\(String(format: "%.2f", center.x)), \(String(format: "%.2f", center.y)))")
                } catch {
                    // Non-fatal — Skynet keeps running even if gimbal ROI update fails
                    debugPrint("[Gimbal] ROI update failed: \(error.localizedDescription)")
                }
            }
            #endif
        }
    }

    // MARK: - Status

    func getStatusText() -> String {
        if !isDockKitAvailable {
            return "No gimbal"
        }
        if isTrackingActive {
            return trackedSubjectCount > 0 ? "Tracking \(trackedSubjectCount)" : "Tracking"
        }
        return "Ready"
    }
}
